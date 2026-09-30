import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_chess_ultra/features/board/model/move.dart';
import 'package:chinese_chess_ultra/features/puzzle/model/iccs.dart';

void main() {
  group('Iccs', () {
    test('解析紧凑小写形式 h3e3', () {
      final r = Iccs.parse('h3e3');
      expect(r, isNotNull);
      expect(r!.from, const Position(7, 6));
      expect(r.to, const Position(4, 6));
    });

    test('解析带分隔的大写形式 H3-E3', () {
      final r = Iccs.parse('H3-E3');
      expect(r, isNotNull);
      expect(r!.from, const Position(7, 6));
      expect(r.to, const Position(4, 6));
    });

    test('行 0 为红方底线（a0 → (0,9)），行 9 为黑方底线（a9 → (0,0)）', () {
      expect(Iccs.parse('a0a9')!.from, const Position(0, 9));
      expect(Iccs.parse('a0a9')!.to, const Position(0, 0));
    });

    test('兼容黑方底线写成 10 的情况（a10a0 → from (0,0)）', () {
      expect(Iccs.parse('a10a0')!.from, const Position(0, 0));
      expect(Iccs.parse('h10g8')!.from, const Position(7, 0));
      expect(Iccs.parse('h10g8')!.to, const Position(6, 1));
    });

    test('非法输入返回 null', () {
      expect(Iccs.parse(''), isNull);
      expect(Iccs.parse('h3'), isNull);
      expect(Iccs.parse('z3e3'), isNull);
      expect(Iccs.parse('炮二平五'), isNull);
      expect(Iccs.parse('h30e3'), isNull);
    });

    test('format 与 parse 互逆', () {
      const from = Position(7, 6);
      const to = Position(4, 6);
      expect(Iccs.format(from, to), 'h3e3');
      expect(Iccs.parse(Iccs.format(from, to)!)!
          , (from: from, to: to));
    });

    test('format 越界返回 null', () {
      expect(Iccs.format(const Position(-1, 0), const Position(0, 0)), isNull);
      expect(Iccs.format(const Position(0, 0), const Position(9, 0)), isNull);
    });
  });
}
