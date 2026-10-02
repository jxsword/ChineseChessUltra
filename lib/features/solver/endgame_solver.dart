import 'dart:isolate';

import '../board/model/board.dart';
import '../board/model/move.dart';
import '../board/model/piece.dart';

/// 求解结论状态。
///
/// 落库为棋谱标记时与 record 模块的 [SolveStatus]（game_record.dart）
/// 一一对应：solved/noSolution/timeout。
enum EndgameSolveStatus { solved, noSolution, timeout }

/// 一条强制线路（自初始局面起，求解方先行）。
///
/// 每个分支点来自应对方的不同防着；着法为裸坐标，落库前经
/// [fillMovePieces] 补齐棋子信息。
class SolverSolution {
  SolverSolution(this.moves);
  final List<Move> moves;
}

/// 求解结果。
class SolveResult {
  const SolveResult({
    required this.status,
    required this.solutions,
    required this.elapsed,
    required this.searchedPlies,
  });

  final EndgameSolveStatus status;
  final List<SolverSolution> solutions;
  final Duration elapsed;

  /// 实际搜索到的深度（半着数）。
  final int searchedPlies;

  /// 解是否唯一。
  bool get unique => status == EndgameSolveStatus.solved && solutions.length == 1;
}

/// 中国象棋残局求解器：迭代加深 AND/OR 杀棋搜索。
///
/// 语义（调研文档 docs/phase4/01 §2.2）：
/// - 目标：求解方在深度上界内**强制将死/困毙**对方；
/// - OR 节点（求解方行棋）：存在一路必胜着法即胜；
/// - AND 节点（应对方行棋）：所有防着皆败才胜——防着分叉即"多条破解走法"；
/// - 限时内未决返回 [EndgameSolveStatus.timeout]；深度树闭合返回
///   [EndgameSolveStatus.noSolution]。
///
/// 已知限制：长将判负规则未完整实现，以"搜索路径内局面重复即剪枝"近似
/// （求解线路含重复局面不视为必胜）。
class EndgameSolver {
  EndgameSolver._(
    this._initialFen, {
    required Duration timeLimit,
    required this.maxPlies,
  }) : _deadline =
            DateTime.now().add(timeLimit <= Duration.zero ? const Duration(hours: 1) : timeLimit);

  /// 初始局面 FEN（轮走方即求解方）。
  final String _initialFen;

  /// 搜索深度上限（半着数，奇数：求解方最后收官）。
  final int maxPlies;

  /// 最多枚举的解数量（防组合爆炸）。
  static const int maxSolutions = 64;

  final DateTime _deadline;

  late Board _board;
  final Map<String, int> _winAt = {};
  final Map<String, int> _failAt = {};
  final List<String> _path = [];
  int _nodes = 0;

  /// 入口：在独立 Isolate 中求解。
  ///
  /// [maxPlies] 为半着数上限（默认 9 = 求解方最多 5 着）。
  static Future<SolveResult> solve(
    String fen, {
    Duration timeLimit = const Duration(seconds: 30),
    int maxPlies = 9,
  }) {
    return Isolate.run(() async {
      final sw = Stopwatch()..start();
      final solver = EndgameSolver._(fen, timeLimit: timeLimit, maxPlies: maxPlies);
      final result = solver._run();
      return SolveResult(
        status: result.status,
        solutions: result.solutions,
        elapsed: sw.elapsed,
        searchedPlies: result.searchedPlies,
      );
    });
  }

  /// 验证某条"首着"是否属于必胜着法集合（供大模型 Hybrid 提议验证）。
  ///
  /// 仅当 [EndgameSolver.solve] 得出 solved 结论后调用才有证明意义。
  static bool isWinningFirstMove({
    required String fen,
    required Move firstMove,
    int plies = 9,
    Duration timeLimit = const Duration(seconds: 30),
  }) {
    final solver = EndgameSolver._(fen, timeLimit: timeLimit, maxPlies: plies);
    return solver._isWinningFirstMove(firstMove, plies);
  }

  // ---------------------------------------------------------------------------
  // 主流程
  // ---------------------------------------------------------------------------

  ({EndgameSolveStatus status, List<SolverSolution> solutions, int searchedPlies})
      _run() {
    _board = Board.fromFen(_initialFen);
    _winAt.clear();
    _failAt.clear();
    _path.clear();
    _nodes = 0;

    // 对方已被将死（处于被将军且无着可走）：0 步解。
    // 注意：对方"暂无着"但未被将军时不构成胜势——此刻轮走方是己方，
    // 己方一手后对方可能重新获得着法。
    final opponent = _board.turn.opponent;
    if (_board.isCheck(opponent) && !_board.hasAnyLegalMoveFor(opponent)) {
      return (
        status: EndgameSolveStatus.solved,
        solutions: <SolverSolution>[],
        searchedPlies: 0,
      );
    }

    for (var plies = 1; plies <= maxPlies; plies += 2) {
      try {
        if (_attackWin(plies)) {
          final solutions = _enumerate(plies);
          return (
            status: EndgameSolveStatus.solved,
            solutions: solutions,
            searchedPlies: plies,
          );
        }
      } on _SearchTimeout {
        return (
          status: EndgameSolveStatus.timeout,
          solutions: <SolverSolution>[],
          searchedPlies: plies,
        );
      }
    }
    return (
      status: EndgameSolveStatus.noSolution,
      solutions: <SolverSolution>[],
      searchedPlies: maxPlies,
    );
  }

  // ---------------------------------------------------------------------------
  // AND/OR 搜索
  // ---------------------------------------------------------------------------

  /// OR 节点：求解方行棋，能否在 [r] 半着内强制获胜。
  bool _attackWin(int r) {
    if (r <= 0) return false;
    _tick();
    final key = _board.toFen();
    if (_path.contains(key)) return false; // 重复局面：不视为必胜（近似长将判负）
    final win = _winAt[key];
    if (win != null && win <= r) return true;
    final fail = _failAt[key];
    if (fail != null && fail >= r) return false;

    final moves = _orderedMoves();
    _path.add(key);
    var won = false;
    for (final m in moves) {
      _board.applyMove(m);
      final opponent = _board.turn;
      if (!_board.hasAnyLegalMoveFor(opponent)) {
        // 将死或困毙：应对方无着可走即判负（中国象棋无逼和）。
        won = true;
      } else if (r >= 2 && _defendLose(r - 1)) {
        won = true;
      }
      _board.undoMove(m);
      if (won) break;
    }
    _path.removeLast();
    if (won) {
      _winAt[key] = win == null ? r : (win < r ? win : r);
      return true;
    }
    _failAt[key] = fail == null ? r : (fail > r ? fail : r);
    return false;
  }

  /// AND 节点：应对方行棋，是否所有防着都在 [r] 半着内被制服。
  bool _defendLose(int r) {
    _tick();
    final key = _board.toFen();
    if (_path.contains(key)) return false;
    final win = _winAt[key];
    if (win != null && win <= r) return true;
    final fail = _failAt[key];
    if (fail != null && fail >= r) return false;

    // 应对方无着可走 = 被将死/困毙 = 求解方胜。
    if (!_board.hasAnyLegalMoveFor(_board.turn)) return true;

    final moves = _orderedMoves();
    _path.add(key);
    var allLose = moves.isNotEmpty;
    for (final d in moves) {
      _board.applyMove(d);
      final lose = r >= 1 ? _attackWin(r - 1) : false;
      _board.undoMove(d);
      if (!lose) {
        allLose = false;
        break;
      }
    }
    _path.removeLast();
    if (allLose) {
      _winAt[key] = win == null ? r : (win < r ? win : r);
      return true;
    }
    _failAt[key] = fail == null ? r : (fail > r ? fail : r);
    return false;
  }

  // ---------------------------------------------------------------------------
  // 多解枚举：根节点所有必胜首着 × 应对方每种防着的分支线路
  // ---------------------------------------------------------------------------

  List<SolverSolution> _enumerate(int plies) {
    final out = <SolverSolution>[];
    for (final m in _orderedMoves()) {
      _board.applyMove(m);
      var win = false;
      if (!_board.hasAnyLegalMoveFor(_board.turn)) {
        win = true; // 一着制胜
      } else if (plies >= 2 && _defendLose(plies - 1)) {
        win = true;
      }
      if (win) {
        final line = <Move>[m];
        if (_board.hasAnyLegalMoveFor(_board.turn)) {
          _extendLine(line, plies - 1, out);
        }
        out.add(SolverSolution(List.of(line)));
      }
      _board.undoMove(m);
      if (out.length >= maxSolutions) break;
    }
    return out;
  }

  /// 从"应对方行棋、已被证明必败"的局面继续，把每种防着展开成一条线路。
  void _extendLine(List<Move> prefix, int r, List<SolverSolution> out) {
    if (out.length >= maxSolutions || r <= 0) return;
    for (final d in _orderedMoves()) {
      if (out.length >= maxSolutions) return;
      _board.applyMove(d);
      if (r >= 1 && _attackWin(r - 1)) {
        final reply = _findWinningReply(r - 1);
        if (reply != null) {
          final line = <Move>[...prefix, d, reply];
          _board.applyMove(reply);
          final finished = !_board.hasAnyLegalMoveFor(_board.turn);
          _board.undoMove(reply);
          if (finished) {
            out.add(SolverSolution(line));
          } else {
            _extendLine(line, r - 2, out);
          }
        }
      }
      _board.undoMove(d);
      // 该防着在当前预算下未被证明必败（理论不应发生）：跳过该分支。
    }
  }

  /// OR 节点（求解方行棋）找一个必胜应手；无则 null。
  Move? _findWinningReply(int r) {
    for (final m in _orderedMoves()) {
      _board.applyMove(m);
      var win = false;
      if (!_board.hasAnyLegalMoveFor(_board.turn)) {
        win = true;
      } else if (r >= 2 && _defendLose(r - 1)) {
        win = true;
      }
      _board.undoMove(m);
      if (win) return m;
    }
    return null;
  }

  /// 验证首着：走下后 OR/AND 链路在预算内闭合。
  bool _isWinningFirstMove(Move firstMove, int plies) {
    _board = Board.fromFen(_initialFen);
    _winAt.clear();
    _failAt.clear();
    _path.clear();
    _nodes = 0;
    final legal = _board
        .legalMovesFor(firstMove.from)
        .any((m) => m.to == firstMove.to);
    if (!legal) return false;
    _board.applyMove(firstMove);
    try {
      if (!_board.hasAnyLegalMoveFor(_board.turn)) return true;
      return plies >= 2 && _defendLose(plies - 1);
    } on _SearchTimeout {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // 辅助
  // ---------------------------------------------------------------------------

  /// 着法排序：将军 > 吃子（按子力价值）> 其他，显著改善剪枝效率。
  List<Move> _orderedMoves() {
    final scored = <(int, Move)>[];
    for (var row = 0; row < 10; row++) {
      for (var col = 0; col < 9; col++) {
        final piece = _board.pieceAt(col, row);
        if (piece == null || piece.side != _board.turn) continue;
        // legalMovesFor 已过滤自将，且每条 Move 带被吃子信息。
        for (final m in _board.legalMovesFor(Position(col, row))) {
          scored.add((_score(m), m));
        }
      }
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    return scored.map((e) => e.$2).toList();
  }

  int _score(Move m) {
    var score = 0;
    final captured = m.captured;
    if (captured != null) {
      score += switch (captured.kind) {
        PieceKind.rook => 90,
        PieceKind.cannon => 45,
        PieceKind.knight => 40,
        PieceKind.minister || PieceKind.advisor => 20,
        PieceKind.pawn => 10,
        PieceKind.king => 1000,
      };
    }
    // 将军加成：走完后对方王被将。
    _board.applyMove(m);
    if (_board.isCheck(_board.turn)) score += 500;
    _board.undoMove(m);
    return score;
  }

  void _tick() {
    _nodes++;
    if (_nodes % 512 == 0 && DateTime.now().isAfter(_deadline)) {
      throw const _SearchTimeout();
    }
  }
}

class _SearchTimeout implements Exception {
  const _SearchTimeout();
}
