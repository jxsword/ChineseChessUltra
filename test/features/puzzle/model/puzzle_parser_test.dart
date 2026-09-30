import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_chess_ultra/features/puzzle/model/puzzle_parser.dart';

void main() {
  group('PuzzleParser（门面）', () {
    test('按扩展名分发：.pgn 走 PGN 解析', () {
      const text = '1. 炮二平五 马8进7\n';
      final puzzles = PuzzleParser.parse(
        fileName: '对局.pgn',
        bytes: utf8.encode(text),
        source: '测试',
      );
      expect(puzzles, hasLength(1));
      expect(puzzles.first.moves, ['h2e2', 'h9g7']);
      expect(puzzles.first.format, 'pgn');
    });

    test('.pgns 扩展名同样分发到 PGN 解析', () {
      final puzzles = PuzzleParser.parse(
        fileName: '合集.pgns',
        bytes: utf8.encode('1. 兵七进一 卒7进1\n'),
        source: '测试',
      );
      expect(puzzles, hasLength(1));
      expect(puzzles.first.moves.first, 'c3c4');
    });

    test('不认识的扩展名抛 FormatException', () {
      expect(
        () => PuzzleParser.parse(
            fileName: '棋局.cbf', bytes: utf8.encode(''), source: '测试'),
        throwsFormatException,
      );
    });

    test('非法着被重放校验截断，保留合法前缀', () {
      // "炮二平五 马8进7 兵七进一 卒7进1 炮五进四 ..." 前四着合法；
      // 追加一着故意非法的 ICCS（起点无子）触发截断。
      const text = '1. 炮二平五 马8进7 h1h9\n';
      final puzzles = PuzzleParser.parse(
        fileName: '截断.pgn',
        bytes: utf8.encode(text),
        source: '测试',
      );
      expect(puzzles, hasLength(1));
      expect(puzzles.first.moves, ['h2e2', 'h9g7']);
    });

    test('全部着法非法时丢弃该局', () {
      const text = '1. 马九进九\n';
      final puzzles = PuzzleParser.parse(
        fileName: '空.pgn',
        bytes: utf8.encode(text),
        source: '测试',
      );
      expect(puzzles, isEmpty);
    });

    test('重复 id 自动去重', () {
      const one = '1. 炮二平五 马8进7\n';
      const multi = '[Event "同一标题"]\n\n$one[Event "同一标题"]\n\n$one';
      final puzzles = PuzzleParser.parse(
        fileName: '重复.pgn',
        bytes: utf8.encode(multi),
        source: '测试',
      );
      expect(puzzles, hasLength(2));
      expect(puzzles[0].id != puzzles[1].id, isTrue);
    });
  });

  group('大文件流式导入判定', () {
    test('多局 PGN 大文件走流式路径，其余走整读', () {
      const mb = 1024 * 1024;
      expect(PuzzleParser.shouldStreamImport('合集.pgns', 9 * mb), isTrue);
      expect(PuzzleParser.shouldStreamImport('对局.pgn', 9 * mb), isTrue);
      expect(PuzzleParser.shouldStreamImport('合集.pgns', 8 * mb), isFalse,
          reason: '等于阈值不流式');
      expect(PuzzleParser.shouldStreamImport('对局.pgn', 1024), isFalse);
      expect(PuzzleParser.shouldStreamImport('残局.xqf', 9 * mb), isFalse,
          reason: 'XQF 单文件不大，始终整读');
    });
  });
}