/// ICCS 坐标走法工具。
///
/// ICCS（International Chinese Chess Standard）记谱：列 a-i（红方视角从左到右），
/// 行 0-9（0 为红方底线、9 为黑方底线），一着写作起止两格，如 `h3e3` / `H3-E3`。
///
/// 本项目内部坐标为 [Position]（col 0-8、row 0-9，row 0 为黑方底线），
/// 因此与 ICCS 的换算关系是 `row = 9 - rank`。
///
/// 解析器（XQF/PGN）与演示 VM 共用本文件，避免两处实现漂移。
library;

import '../../board/model/move.dart';

/// 单条 ICCS 走法工具。
class Iccs {
  Iccs._();

  /// 宽松匹配一着 ICCS：大小写不敏感，允许 `h3e3`、`H3-E3`、`h3 e3` 等分隔形式。
  static final RegExp _pattern =
      RegExp(r'^\s*([a-iA-I])(\d{1,2})\s*-?\s*([a-iA-I])(\d{1,2})\s*$');

  /// 解析 ICCS 走法字符串为起止坐标；格式非法或坐标越界返回 null。
  ///
  /// 行号兼容个别记谱把黑方底线写成 10 的情况（此时按 0 处理）。
  static ({Position from, Position to})? parse(String iccs) {
    final match = _pattern.firstMatch(iccs);
    if (match == null) return null;

    Position? parseSquare(String file, String rankStr) {
      final rank = int.tryParse(rankStr);
      if (rank == null || rank > 10) return null;
      final col = file.toLowerCase().codeUnitAt(0) - 'a'.codeUnitAt(0);
      if (col < 0 || col > 8) return null;
      final row = rank >= 10 ? 0 : 9 - rank;
      if (row < 0 || row > 9) return null;
      return Position(col, row);
    }

    final from = parseSquare(match.group(1)!, match.group(2)!);
    final to = parseSquare(match.group(3)!, match.group(4)!);
    if (from == null || to == null) return null;
    return (from: from, to: to);
  }

  /// 把起止坐标编码为小写紧凑 ICCS（`h3e3`），坐标越界返回 null。
  static String? format(Position from, Position to) {
    String? square(Position p) {
      if (!p.isValid) return null;
      final file = 'a'.codeUnitAt(0) + p.col;
      final rank = 9 - p.row;
      return '${String.fromCharCode(file)}$rank';
    }

    final f = square(from);
    final t = square(to);
    if (f == null || t == null) return null;
    return '$f$t';
  }
}
