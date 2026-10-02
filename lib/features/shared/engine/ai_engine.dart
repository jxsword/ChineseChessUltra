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

  /// 引擎参谋报告（五期 P1）：以固定深度、无随机性搜索一次，
  /// 返回最佳着法与按分数降序的 Top-K 候选。
  ///
  /// 与 [findBestMove] 的区别：不引入难度随机窗口（保证分数是真实分差、
  /// 名单稳定可复现），并把根节点各着法的评分暴露给调用方
  /// （复用根节点循环，不增加搜索成本）。剪枝模式下非最佳分支返回的
  /// 是边界值——Top-K 内的排序仍可信，但 K 之后的分数仅供参考。
  ///
  /// [topK] 最小为 1；无合法走法（被将死/困毙）返回 null。
  static EngineReport? findBestMoveEx(
    Board board, {
    int depth = 6,
    int topK = 5,
    Duration timeLimit = const Duration(seconds: 5),
  }) {
    final search = _Search(
      board: board.copy(),
      maxDepth: depth.clamp(1, 8),
      deadline: DateTime.now().add(timeLimit),
      randomness: 0,
    );
    final scored = search.runScored();
    if (scored.isEmpty) return null;
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    final k = topK.clamp(1, scored.length);
    return EngineReport(
      best: scored.first.$1,
      bestCp: scored.first.$2,
      topK: scored.sublist(0, k),
    );
  }

  /// 单着法评估（护航否决用）：走 [move] 后以浅搜索取对手最佳分，
  /// 返回从当前走子方视角的评分（厘兵）。毫秒级。
  ///
  /// [move] 必须是 [board] 当前方的一步合法走法；非法（起点无己方子/
  /// 走完自将）返回 null。
  static int? evaluateMove(Board board, Move move, {int depth = 4}) {
    final probe = board.copy();
    final mover = probe.pieceAtP(move.from);
    if (mover == null || mover.side != probe.turn) return null;
    probe.applyMove(move);
    if (probe.isCheck(mover.side)) return null; // 走完自将，非法
    final scored = _Search(
      board: probe,
      maxDepth: depth.clamp(1, 6),
      deadline: DateTime.now().add(const Duration(seconds: 2)),
      randomness: 0,
    ).runScored();
    if (scored.isEmpty) return ChessAi._mateScore; // 走完后对手被将死/困毙
    var bestOpp = -ChessAi._infinity;
    for (final (_, score) in scored) {
      if (score > bestOpp) bestOpp = score;
    }
    return -bestOpp;
  }
}

/// 引擎搜索报告：最佳着法、最佳评分（厘兵，正数=当前方占优）
/// 与 Top-K 候选（已按分数降序）。
class EngineReport {
  const EngineReport({
    required this.best,
    required this.bestCp,
    required this.topK,
  });

  final Move best;
  final int bestCp;

  /// Top-K 候选（move, cp），按 cp 降序；cp 为从当前走子方视角的评分。
  final List<(Move, int)> topK;
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

  /// 最后一层完整搜索的根节点评分表（未排序）。
  List<(Move, int)> _lastScored = const [];

  /// 最佳着法（迭代加深逐层覆盖）。
  Move? _best;

  /// 迭代加深主入口：返回最佳走法。
  /// 超时时返回上一深度已得到的最佳走法，
  /// 此时 [_board] 停留在搜索树中部的临时状态，随本对象一起废弃。
  Move? run() {
    _iterate();
    return _best;
  }

  /// 迭代加深并返回最后一层完整搜索的根节点评分表（按分数降序）。
  ///
  /// 强制根节点全窗口（不剪枝）：保证表中每个着法的分数是真实分差
  /// （供参谋制否决阈值计算使用）。深度节点的剪枝不受影响；
  /// 超时时返回上一深度完整结果。空表 = 无合法走法。
  List<(Move, int)> runScored() {
    _iterate(forceFullRootWindow: true);
    final sorted = List.of(_lastScored)
      ..sort((a, b) => b.$2.compareTo(a.$2));
    return sorted;
  }

  void _iterate({bool forceFullRootWindow = false}) {
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
    if (rootMoves.isEmpty) return; // 被将死或困毙

    // 根节点是否全窗口：低难度需要真实分差做随机挑选；
    // runScored 强制全窗口（分数即真实分差）。
    final fullRootWindow = forceFullRootWindow || _randomness > 0;

    // 根节点走法排序：上层最佳走法放最前（浅层结果指导深层剪枝）。
    _best ??= rootMoves.first;

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
          score = fullRootWindow
              // 全窗口：根节点不剪枝，每个着法的分数都是真实分差。
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

      _lastScored = scored;
      bestThisDepth =
          _randomness > 0 ? _pickRootMove(scored) : bestThisDepth;
      if (bestThisDepth != null) _best = bestThisDepth;

      // 已找到确定的将杀路线，无需更深搜索。
      if (alpha >= ChessAi._mateScore - 100) break;
    }
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
