import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_chess_ultra/features/board/model/fen.dart';

void main() {
  group('Fen', () {
    test('initial FEN 应通过校验', () {
      expect(Fen.isValid(Fen.initial), isTrue);
    });

    test('空字符串、错误列数、错误字符均不通过校验', () {
      expect(Fen.isValid(''), isFalse);
      expect(Fen.isValid('9/9/9/9/9/9/9/9/9/9 w - - 0 1'), isTrue);
      expect(Fen.isValid('9/9/9/9/9/9/9/9/9/8 w - - 0 1'), isFalse);
      expect(Fen.isValid('xxxxxxxxx/9/9/9/9/9/9/9/9/9 w - - 0 1'), isFalse);
      // 行数不对（只有 9 行）。
      expect(Fen.isValid('rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/9/9/9 w - - 0 1'),
          isFalse);
    });

    test('parseBoard 与 boardToFen 互逆', () {
      final grid = Fen.parseBoard(Fen.initial);
      final fen = Fen.boardToFen(grid);
      expect(fen, Fen.initial.split(' ').first);
    });

    test('parseBoard 解析初始局面：红车在右下角（row=9, col=0/8）', () {
      final grid = Fen.parseBoard(Fen.initial);
      expect(grid[9][0]?.label, '车'); // 红车
      expect(grid[9][0]?.side.isRed, isTrue);
      expect(grid[0][0]?.label, '车'); // 黑车
      expect(grid[0][0]?.side.isRed, isFalse);
    });

    test('parseTurn 红方先行', () {
      expect(Fen.parseTurn(Fen.initial), isTrue);
      expect(Fen.parseTurn('9/9/9/9/9/9/9/9/9/9 b - - 0 1'), isFalse);
    });
  });
}
