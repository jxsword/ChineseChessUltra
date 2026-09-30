import '../../board/model/board.dart';
import '../../board/model/move.dart';
import '../../board/model/piece.dart';

/// 内置中国象棋 AI 引擎（纯 Dart 实现，无外部依赖、无需引擎二进制）。
///
/// 算法：
/// - Negamax 框架 + Alpha-Beta 剪枝，配合吃子优先（MVV-LVA）的走法排序；
/// - 迭代加深：由浅入深搜索，超过时间上限即返回上一层完整结果，
///   保证任何难度下 UI 都能在可预期的时长内拿到应手；
/// - 叶子节点做只吃子的静态搜索（Quiescence），缓解水平线效应；
/// - 静态评估 = 子力价值 + 位置修正（兵过河、中路控制、沉底车）；
/// - 低难度在根节点引入随机性，避免每局走法完全相同。
///
/// 无任何 Flutter 依赖，可在 Isolate 中运行（[Board]/[Piece] 均为可发送对象）。
class ChessAi {
  ChessAi._();

  /// 将杀评分（区分被杀步数，越早被杀越差）。
  static const int _mateScore = 30000;
  static const int _infinity = 100000;

  /// 静态搜索（吃子延伸）最大层数。
  static const int _maxQuiescencePly = 8;

  /// 各难度的搜索参数：最大深度 / 时间上限 / 根节点随机窗口（厘兵）。
  static const Map<int, ({int depth, Duration time, int randomness})>
      _levelParams = {
    1: (depth: 2, time: Duration(milliseconds: 300), randomness: 120),
    2: (depth: 3, time: Duration(milliseconds: 800), randomness: 50),
    3: (depth: 4, time: Duration(milliseconds: 1600), randomness: 0),
    4: (depth: 5, time: Duration(milliseconds: 3000), randomness: 0),
    5: (depth: 6, time: Duration(milliseconds: 5000), randomness: 0),
  };

  /// 为 [board] 的当前走子方寻找最佳走法。
  ///
  /// [difficulty] 取 1-5（初级-大师）。内部对棋盘深拷贝后搜索，
  /// 不会修改调用方传入的棋盘。
  /// 若当前方无任何合法走法（被将死/困毙）返回 null。
  static Move? findBestMove(Board board, {int difficulty = 3}) {
    final params = _levelParams[difficulty.clamp(1, 5)] ?? _levelParams[3]!;
    final search = _Search(
      board: board.copy(),
      maxDepth: params.depth,
      deadline: DateTime.now().add(params.time),
      randomness: params.randomness,
    );
    return search.run();
  }
}

/// 单次搜索任务（持有自己的棋盘副本，用完即弃）。
class _Search {
  _Search({
    required Board board,
    required int maxDepth,
    required DateTime deadline,
    required int randomness,
  })  : _board = board,
        _maxDepth = maxDepth,
        _deadline = deadline,
        _randomness = randomness;

  final Board _board;
  final int _maxDepth;
  final DateTime _deadline;
  final int _randomness;

  int _nodes = 0;

  /// 迭代加深主入口。超时时直接返回上一深度已得到的最佳走法，
  /// 此时 [_board] 停留在搜索树中部的临时状态，随本对象一起废弃。
  Move? run() {
    // 根节点走法必须做合法性过滤（深层节点在递归内过滤）：
    // 否则被将军时 AI 可能"吃掉将军的子"而不真正解将。
    final rootMoves = <Move>[];
    for (final move in _orderedMoves()) {
      final mover = _board.pieceAtP(move.from)!;
      final applied = _board.applyMove(move);
      final leavesSelfInCheck = _board.isCheck(mover.side);
      _board.undoMove(applied);
      if (!leavesSelfInCheck) rootMoves.add(move);
    }
    if (rootMoves.isEmpty) return null; // 被将死或困毙

    // 根节点走法排序：上层最佳走法放最前（浅层结果指导深层剪枝）。
    Move best = rootMoves.first;

    for (var depth = 1; depth <= _maxDepth; depth++) {
      var alpha = -ChessAi._infinity;
      var bestScore = -ChessAi._infinity;
      Move? bestThisDepth;
      final scored = <(Move, int)>[];
      var timedOut = false;

      for (final move in rootMoves) {
        final applied = _board.applyMove(move);
        int score;
        try {
          score = _randomness > 0
              // 低难度需要真实分差做随机挑选，根节点不剪枝（全窗口）。
              ? -_negamax(depth - 1, -ChessAi._infinity, ChessAi._infinity, 1)
              // 剪枝模式下，未超过 alpha 的走法会返回边界值，
              // 因此只在严格更优时更新 best。
              : -_negamax(depth - 1, -ChessAi._infinity, -alpha, 1);
        } on _TimeUp {
          timedOut = true;
          break;
        } finally {
          if (!timedOut) _board.undoMove(applied);
        }
        scored.add((move, score));
        if (score > bestScore) {
          bestScore = score;
          bestThisDepth = move;
        }
        if (score > alpha) alpha = score;
      }

      if (timedOut) break;

      bestThisDepth = _randomness > 0 ? _pickRootMove(scored) : bestThisDepth;
      if (bestThisDepth != null) best = bestThisDepth;

      // 已找到确定的将杀路线，无需更深搜索。
      if (alpha >= ChessAi._mateScore - 100) break;
    }
    return best;
  }

  /// 按分数挑选根节点走法；带随机窗口时在接近最佳的走法中随机取一。
  Move? _pickRootMove(List<(Move, int)> scored) {
    if (scored.isEmpty) return null;
    if (_randomness <= 0) {
      scored.sort((a, b) => b.$2.compareTo(a.$2));
      return scored.first.$1;
    }
    var bestScore = -ChessAi._infinity;
    for (final (_, score) in scored) {
      if (score > bestScore) bestScore = score;
    }
    final candidates = scored
        .where((e) => e.$2 >= bestScore - _randomness)
        .map((e) => e.$1)
        .toList();
    if (candidates.isEmpty) return scored.first.$1;
    candidates.shuffle();
    return candidates.first;
  }

  // ---------------------------------------------------------------------------
  // Negamax + Alpha-Beta
  // ---------------------------------------------------------------------------

  int _negamax(int depth, int alpha, int beta, int ply) {
    _bumpNode();
    if (depth <= 0) return _quiescence(alpha, beta, ply);

    var anyLegal = false;
    for (final move in _orderedMoves()) {
      final mover = _board.pieceAtP(move.from)!;
      final applied = _board.applyMove(move);
      // 伪合法走法：走完自将则跳过。
      if (_board.isCheck(mover.side)) {
        _board.undoMove(applied);
        continue;
      }
      anyLegal = true;
      final score = -_negamax(depth - 1, -beta, -alpha, ply + 1);
      _board.undoMove(applied);
      if (score >= beta) return beta;
      if (score > alpha) alpha = score;
    }

    if (!anyLegal) {
      // 无合法走法：被将死或困毙，按中国象棋规则均判负；越早被杀分越差。
      return -ChessAi._mateScore + ply;
    }
    return alpha;
  }

  /// 静态搜索：只延伸吃子走法，避免在叶子节点因"刚好吃亏"误判。
  int _quiescence(int alpha, int beta, int ply) {
    _bumpNode();

    // 被将军时必须搜索全部应将走法，否则评估失真。
    if (_board.isCheck(_board.turn) && ply < ChessAi._maxQuiescencePly * 2) {
      return _searchEvasions(alpha, beta, ply);
    }

    final standPat = _evaluate();
    if (standPat >= beta) return beta;
    if (standPat > alpha) alpha = standPat;
    if (ply >= ChessAi._maxQuiescencePly) return alpha;

    for (final move in _orderedMoves(capturesOnly: true)) {
      final mover = _board.pieceAtP(move.from)!;
      final applied = _board.applyMove(move);
      if (_board.isCheck(mover.side)) {
        _board.undoMove(applied);
        continue;
      }
      final score = -_quiescence(-beta, -alpha, ply + 1);
      _board.undoMove(applied);
      if (score >= beta) return beta;
      if (score > alpha) alpha = score;
    }
    return alpha;
  }

  /// 被将军时的全部应将搜索（含解将失败即被将死的判定）。
  int _searchEvasions(int alpha, int beta, int ply) {
    var anyLegal = false;
    for (final move in _orderedMoves()) {
      final mover = _board.pieceAtP(move.from)!;
      final applied = _board.applyMove(move);
      if (_board.isCheck(mover.side)) {
        _board.undoMove(applied);
        continue;
      }
      anyLegal = true;
      final score = ply >= ChessAi._maxQuiescencePly * 2
          ? _evaluate()
          : -_quiescence(-beta, -alpha, ply + 1);
      _board.undoMove(applied);
      if (score >= beta) return beta;
      if (score > alpha) alpha = score;
    }
    if (!anyLegal) return -ChessAi._mateScore + ply;
    return alpha;
  }

  // ---------------------------------------------------------------------------
  // 走法生成与排序
  // ---------------------------------------------------------------------------

  /// 生成当前走子方全部伪合法走法，按 MVV-LVA（吃大子优先）排序。
  List<Move> _orderedMoves({bool capturesOnly = false}) {
    final scored = <(Move, int)>[];
    for (var r = 0; r < 10; r++) {
      for (var c = 0; c < 9; c++) {
        final piece = _board.pieceAt(c, r);
        if (piece == null || piece.side != _board.turn) continue;
        for (final move in _board.pseudoMovesFor(Position(c, r))) {
          if (capturesOnly && move.captured == null) continue;
          final order = move.captured == null
              ? 0
              : _pieceValue(move.captured!.kind) * 10 - _pieceValue(piece.kind);
          scored.add((move, order));
        }
      }
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final (move, _) in scored) move];
  }

  // ---------------------------------------------------------------------------
  // 静态评估（红方为正）
  // ---------------------------------------------------------------------------

  int _evaluate() {
    var score = 0;
    for (var r = 0; r < 10; r++) {
      for (var c = 0; c < 9; c++) {
        final piece = _board.pieceAt(c, r);
        if (piece == null) continue;
        final value = _pieceValue(piece.kind) + _pieceSquareBonus(piece, c, r);
        score += piece.side.isRed ? value : -value;
      }
    }
    return _board.isRedTurn ? score : -score;
  }

  static int _pieceValue(PieceKind kind) {
    return switch (kind) {
      PieceKind.king => 10000,
      PieceKind.rook => 900,
      PieceKind.cannon => 450,
      PieceKind.knight => 400,
      PieceKind.minister => 200,
      PieceKind.advisor => 200,
      PieceKind.pawn => 100,
    };
  }

  /// 位置修正：兵过河增值且贴近九宫加分，马炮居中加分，车沉底加分。
  static int _pieceSquareBonus(Piece piece, int col, int row) {
    final colCenter = 4 - (col - 4).abs();
    switch (piece.kind) {
      case PieceKind.pawn:
        final crossed = piece.side.isRed ? row <= 4 : row >= 5;
        if (!crossed) return 0;
        return 40 + colCenter * 8;
      case PieceKind.knight:
      case PieceKind.cannon:
        return colCenter * 4;
      case PieceKind.rook:
        final bottom = piece.side.isRed ? row == 0 : row == 9;
        return bottom ? 10 : 0;
      default:
        return 0;
    }
  }

  void _bumpNode() {
    _nodes++;
    if ((_nodes & 0x3F) == 0 && DateTime.now().isAfter(_deadline)) {
      throw _TimeUp();
    }
  }
}

/// 搜索超时信号（内部使用）。
class _TimeUp implements Exception {}
