import 'dart:isolate';

import '../../board/model/board.dart';
import '../../board/model/move.dart';
import 'ai_engine.dart';

/// 坐标编码：列 a-i（对应 col 0-8），行 0-9（0 为黑方底线/棋盘顶部，9 为红方底线）。
///
/// 这是与 LLM 交互的着法文本格式，例如 "h7-e7"。
String encodeCell(Position p) =>
    '${String.fromCharCode(97 + p.col)}${p.row}';

/// 解析单格坐标（如 "b2"）；格式非法返回 null。
Position? decodeCell(String cell) {
  if (cell.length != 2) return null;
  final col = cell.codeUnitAt(0) - 97;
  final row = cell.codeUnitAt(1) - 48;
  if (col < 0 || col > 8 || row < 0 || row > 9) return null;
  return Position(col, row);
}

/// 把走法编码为 "起点-终点" 文本。
String encodeMove(Move move) => '${encodeCell(move.from)}-${encodeCell(move.to)}';

/// 当前走子方的全部合法走法。
List<Move> allLegalMoves(Board board) {
  final moves = <Move>[];
  for (var r = 0; r < 10; r++) {
    for (var c = 0; c < 9; c++) {
      final piece = board.pieceAt(c, r);
      if (piece == null || piece.side != board.turn) continue;
      moves.addAll(board.legalMovesFor(Position(c, r)));
    }
  }
  return moves;
}

/// 棋手一步棋的结果。
class MoveSourceResult {
  const MoveSourceResult({
    required this.status,
    this.move,
    this.note,
    this.fromFallback = false,
  });

  /// 成功给出着法。
  factory MoveSourceResult.ok(Move move, {String? note}) =>
      MoveSourceResult(status: MoveSourceStatus.ok, move: move, note: note);

  /// 当前走子方已无合法着法（将死/困毙，由棋盘状态判定胜负）。
  factory MoveSourceResult.noLegalMove() =>
      const MoveSourceResult(status: MoveSourceStatus.noLegalMove);

  /// 该方走子失败（如模型连续输出无效、网络不可用）。
  factory MoveSourceResult.failed(String reason) =>
      MoveSourceResult(status: MoveSourceStatus.failed, note: reason);

  final MoveSourceStatus status;
  final Move? move;

  /// 思路 / 解说 / 失败原因，供状态栏展示。
  final String? note;

  /// true 表示着法来自内置 AI 兜底而非模型本身。
  final bool fromFallback;
}

enum MoveSourceStatus { ok, noLegalMove, failed }

/// "棋手"抽象：内置引擎与大模型是两个可互换的实现。
///
/// 实现必须自行保证返回的 [MoveSourceResult.move] 是合法着法
/// （页面侧的 `playMove` 仍会做最终校验）。
abstract class MoveSource {
  /// 展示名，用于状态栏，如 "glm-4-flash"。
  String get displayName;

  /// 为 [board] 的当前走子方寻求一步棋。
  ///
  /// [history] 为对局走法记录（含棋子信息），可用于组装上下文。
  Future<MoveSourceResult> nextMove(
    Board board, {
    List<Move> history = const [],
  });
}

/// 内置 AI 棋手（包装 ChessAi，在独立 Isolate 中搜索）。
class ChessAiMoveSource implements MoveSource {
  ChessAiMoveSource({this.difficulty = 3});

  final int difficulty;

  static const _difficultyNames = {1: '初级', 2: '中级', 3: '高级', 4: '专家', 5: '大师'};

  @override
  String get displayName => '内置 AI（${_difficultyNames[difficulty] ?? difficulty}）';

  @override
  Future<MoveSourceResult> nextMove(
    Board board, {
    List<Move> history = const [],
  }) async {
    final snapshot = board.copy();
    Move? best;
    try {
      best = await Isolate.run(
        () => ChessAi.findBestMove(snapshot, difficulty: difficulty),
      );
    } on Object {
      // Isolate 不可用时退化为同步计算。
      best = ChessAi.findBestMove(snapshot, difficulty: difficulty);
    }
    if (best == null) return MoveSourceResult.noLegalMove();
    return MoveSourceResult.ok(best);
  }
}
