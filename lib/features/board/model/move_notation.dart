import 'move.dart';
import 'piece.dart';

/// 走法记录工具：把 (from,to,piece) 序列化为带颜色与中文坐标的字符串。
///
/// 自 board_vm.dart 抽出，供走法记录展示与 LLM Prompt 组装共用。
extension MoveNotation on Move {
  /// 形如 "炮二平五" 风格的简易记法（红方使用汉字数字一二三...九，黑方用阿拉伯数字）。
  String chineseNotation(Piece piece) {
    String col(int c, bool red) {
      const han = ['九', '八', '七', '六', '五', '四', '三', '二', '一'];
      if (red) return han[c];
      return '${c + 1}';
    }

    final red = piece.side.isRed;
    final fromCol = col(from.col, red);
    final toCol = col(to.col, red);
    final sameCol = from.col == to.col;
    final forward = to.row - from.row;
    String action;
    String target;
    if (sameCol) {
      final ahead = red ? forward < 0 : forward > 0;
      action = ahead ? '进' : '退';
      final steps = forward.abs();
      target = red
          ? const ['九', '八', '七', '六', '五', '四', '三', '二', '一'][9 - steps]
          : '$steps';
    } else if (from.row == to.row) {
      action = '平';
      target = toCol;
    } else {
      final ahead = red ? forward < 0 : forward > 0;
      action = ahead ? '进' : '退';
      target = toCol;
    }
    return '${piece.label}$fromCol$action$target';
  }
}
