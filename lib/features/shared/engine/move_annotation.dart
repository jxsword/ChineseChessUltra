import '../../board/model/board.dart';
import '../../board/model/move.dart';
import '../../board/model/move_notation.dart';
import 'move_source.dart' show encodeMove;

/// 着法注解与引擎分数分桶（五期 P0/P1，纯函数）。
///
/// 所有标注信息（棋子/中文记法/吃子/将军/分数分桶）均由本地规则引擎
/// 与搜索结果生成，零成本、零幻觉——给 LLM 的"战术眼镜"。
class MoveAnnotation {
  MoveAnnotation._();

  /// 生成带注解的着法文本：`b2-e2(炮二平五,吃卒,将军)`。
  ///
  /// [board] 为走子前的局面（[move] 的起点须有棋子）；
  /// 起点无棋子时退化为纯坐标。
  static String annotate(Board board, Move move) {
    final piece = board.pieceAtP(move.from);
    if (piece == null) return encodeMove(move);

    final parts = <String>[move.chineseNotation(piece)];
    // 优先用棋盘实际局面取被吃子（手工构造的 Move 不带 captured）。
    final captured = move.captured ?? board.pieceAtP(move.to);
    if (captured != null) parts.add('吃${captured.label}');

    final probe = board.copy();
    probe.applyMove(Move(from: move.from, to: move.to));
    if (probe.isCheck(probe.turn)) parts.add('将军');

    return '${encodeMove(move)}(${parts.join(',')})';
  }

  /// 相对最佳分的损失 → 分桶文字（给 LLM 的可读评估）。
  ///
  /// [cpDiff] 为厘兵（正数越大亏损越多）。
  static String scoreBucket(int cpDiff) {
    if (cpDiff <= 30) return '最佳/均势';
    if (cpDiff <= 100) return '略亏';
    if (cpDiff <= 250) return '明显亏（约半子）';
    if (cpDiff <= 600) return '大亏（丢一马/一炮级）';
    return '致命（丢车/被将杀级）';
  }

  /// 候选清单的一行文本：`b2-e2(炮二平五,吃卒,将军) — 均势`。
  static String annotatedWithBucket(Board board, Move move, int cpDiff) =>
      '${annotate(board, move)} — ${scoreBucket(cpDiff)}';

  /// 棋盘 ASCII 图（原 llm_solve_assist._asciiBoard，提升为共享工具）：
  /// 10 行文本，大写红方/小写黑方，行号 0-9（0 为黑方底线）、列标 a-i。
  static String asciiBoard(Board board) {
    final buf = StringBuffer();
    buf.writeln('    a b c d e f g h i');
    for (var row = 0; row < 10; row++) {
      final cells = <String>[];
      for (var col = 0; col < 9; col++) {
        final piece = board.pieceAt(col, row);
        cells.add(piece?.fen ?? '.');
      }
      buf.writeln('$row  ${cells.join(' ')}');
    }
    return buf.toString();
  }
}
