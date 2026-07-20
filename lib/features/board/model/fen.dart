import 'piece.dart';

/// 中国象棋标准局面 FEN 编解码（参考 XQFEN）。
///
/// 一行棋盘从红方底线（rank 9）写到顶线（rank 0），每行 9 列从左到右，
/// 用数字表示连续空格，红方大写、黑方小写。
class Fen {
  const Fen._();

  /// 初始局面。
  static const String initial =
      'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1';

  /// 校验是否为合法 FEN（粗校：行数、列数、字段数）。
  static bool isValid(String fen) {
    final parts = fen.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return false;
    final rows = parts[0].split('/');
    if (rows.length != 10) return false;
    for (final r in rows) {
      int sum = 0;
      for (final ch in r.split('')) {
        if (RegExp(r'\d').hasMatch(ch)) {
          sum += int.parse(ch);
        } else if (pieceFromFenChar(ch) != null) {
          sum += 1;
        } else {
          return false;
        }
      }
      if (sum != 9) return false;
    }
    return true;
  }

  /// 解析 FEN 棋盘部分，返回 10 行 × 9 列矩阵，空格为 null。
  /// 矩阵下标为 [row][col]，row 0 为黑方底线（FEN 第一行），row 9 为红方底线。
  static List<List<Piece?>> parseBoard(String fen) {
    final rows = fen.trim().split(RegExp(r'\s+'))[0].split('/');
    if (rows.length != 10) {
      throw FormatException('Invalid FEN board rows: ${rows.length}');
    }
    final result = List<List<Piece?>>.generate(
      10,
      (_) => List<Piece?>.filled(9, null),
    );
    for (var r = 0; r < 10; r++) {
      final rowStr = rows[r];
      var col = 0;
      for (final ch in rowStr.split('')) {
        if (RegExp(r'\d').hasMatch(ch)) {
          col += int.parse(ch);
        } else {
          final piece = pieceFromFenChar(ch);
          if (piece == null) {
            throw FormatException('Invalid FEN char: $ch');
          }
          result[r][col] = piece;
          col += 1;
        }
      }
      if (col != 9) {
        throw FormatException(
            'Invalid FEN row length at $r: expected 9 got $col');
      }
    }
    return result;
  }

  /// 解析 FEN 中"轮走方"字段，true=红方。
  static bool parseTurn(String fen) {
    final parts = fen.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return true;
    return parts[1].toLowerCase() == 'w' || parts[1].toLowerCase() == 'r';
  }

  /// 将棋盘矩阵序列化为 FEN 棋盘部分。
  static String boardToFen(List<List<Piece?>> board) {
    final rows = <String>[];
    for (var r = 0; r < 10; r++) {
      final buf = StringBuffer();
      var empty = 0;
      for (var c = 0; c < 9; c++) {
        final p = board[r][c];
        if (p == null) {
          empty += 1;
        } else {
          if (empty > 0) {
            buf.write(empty);
            empty = 0;
          }
          buf.write(p.fen);
        }
      }
      if (empty > 0) buf.write(empty);
      rows.add(buf.toString());
    }
    return rows.join('/');
  }

  /// 拼装完整 FEN（含走子方/回合数等扩展字段）。
  static String build({
    required List<List<Piece?>> board,
    required bool isRedTurn,
    int halfMove = 0,
    int fullMove = 1,
  }) {
    return '${boardToFen(board)} ${isRedTurn ? 'w' : 'b'} - - $halfMove $fullMove';
  }
}
