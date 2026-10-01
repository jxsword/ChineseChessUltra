import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_chess_ultra/features/puzzle/model/parsers/pgn_parser.dart';

const initialFen =
    'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1';

void main() {
  group('单局解析', () {
    test('标准初始局面 + 中文纵线记谱（无 FEN 标签）', () {
      const text = '''
[Event "测试局"]
[Red "红方"]
[Black "黑方"]

1. 炮二平五  马8进7
2. 马二进三  车9平8
*''';
      final puzzle = PgnParser.parseGame(text, source: '测试');
      expect(puzzle.initialFen, initialFen);
      expect(puzzle.moves, ['h2e2', 'h9g7', 'h0g2', 'i9h9']);
      expect(puzzle.title, '测试局');
      expect(puzzle.format, 'pgn');
      expect(puzzle.difficulty, 1);
    });

    test('ICCS 记谱 + FEN 标签', () {
      const text = '''
[FEN "$initialFen"]

1. C3-C4 C9-E7
2. B2-D2 G6-G5
''';
      final puzzle = PgnParser.parseGame(text);
      expect(puzzle.moves, ['c3c4', 'c9e7', 'b2d2', 'g6g5']);
    });

    test('注释、行注释、变着、NAG 与步数序号被跳过', () {
      const text = '''
1. 炮二平五 {好棋; 得中路} 马8进7 ; 行注释到行尾
2. 马二进三 (2. 卒3进1 3. 兵三进一) 车9平8 \$1
3. 车一平二
''';
      final puzzle = PgnParser.parseGame(text);
      expect(puzzle.moves, ['h2e2', 'h9g7', 'h0g2', 'i9h9', 'i0h0']);
    });

    test('全角数字（部分生成器黑方记谱）可解析', () {
      const text = '''
1. 兵七进一  象３进５
2. 炮八平六  卒７进１
''';
      final puzzle = PgnParser.parseGame(text);
      // 兵七进一 c3c4；象3进5 c9e7；炮八平六 b2d2；卒7进1 g6g5
      expect(puzzle.moves, ['c3c4', 'c9e7', 'b2d2', 'g6g5']);
    });

    test('前/后修饰消解同列多子', () {
      // 红方双炮同在五路（col 4），红方"前"为 row 较小者。
      const fen = '4k4/9/9/9/9/9/4C4/9/4C4/4K4 w - - 0 1';
      const text = '''
[FEN "$fen"]

1. 前炮进二
''';
      final puzzle = PgnParser.parseGame(text);
      // 前炮 (4,6)=e3，直进两格 → (4,4)=e5
      expect(puzzle.moves, ['e3e5']);
    });

    test('着法无法消解时抛 FormatException', () {
      // 兵不可以在同一路平移五格。
      const text = '1. 兵九平五\n';
      expect(() => PgnParser.parseGame(text), throwsFormatException);
    });

    test('无任何着法时抛 FormatException', () {
      expect(() => PgnParser.parseGame('[Event "空局"]\n*'),
          throwsFormatException);
    });
  });

  group('多局切分', () {
    test('两局文本切分为两局', () {
      const text = '''
[Event "第一局"]

1. 炮二平五 马8进7

[Event "第二局"]

1. 兵七进一 卒7进1
''';
      final games = PgnParser.parseGames(text);
      expect(games, hasLength(2));
      expect(games[0].title, '第一局');
      expect(games[1].title, '第二局');
      expect(games[1].moves.first, 'c3c4');
    });

    test('单局解析失败不影响其余棋局', () {
      const text = '''
[Event "坏局"]

1. 马九进九

[Event "好局"]

1. 炮二平五 马8进7
''';
      final games = PgnParser.parseGames(text);
      expect(games, hasLength(1));
      expect(games.first.title, '好局');
    });
  });

  group('大文件按局索引', () {
    late Directory tmp;
    late File pgnFile;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('pgn_index_test');
      pgnFile = File('${tmp.path}${Platform.pathSeparator}multi.pgn');
      pgnFile.writeAsStringSync('''
[Event "甲局"]
[Red "红甲"]
[Black "黑甲"]

1. 炮二平五 马8进7
2. 马二进三 车9平8

[Event "乙局"]
[Red "红乙"]
[Black "黑乙"]

1. 兵七进一 卒7进1
''', encoding: utf8);
    });

    tearDown(() {
      tmp.deleteSync(recursive: true);
    });

    test('扫描偏移索引并按需读取单局', () {
      final index = PgnParser.scanGameOffsets(pgnFile.path);
      expect(index, hasLength(2));
      expect(index[0].event, '甲局');
      expect(index[1].event, '乙局');
      expect(index[1].red, '红乙');

      final game1 = PgnParser.readGameAt(pgnFile.path, index[0]);
      expect(PgnParser.parseGame(game1).moves, hasLength(4));

      final game2 = PgnParser.readGameAt(pgnFile.path, index[1]);
      final parsed2 = PgnParser.parseGame(game2);
      expect(parsed2.moves.first, 'c3c4');
      expect(parsed2.title, '乙局');
    });

    test('maxGames 限制扫描数量', () {
      final index = PgnParser.scanGameOffsets(pgnFile.path, maxGames: 1);
      expect(index, hasLength(1));
    });

    test('超长行按 moves 行处理，pending 不再无限累积（P2-5）', () {
      // 9MB 无换行的单行畸形文件（超过 8MB 阈值）+ 一个正常局。
      final longFile = File('${tmp.path}${Platform.pathSeparator}long.pgn');
      longFile.writeAsStringSync(
        '${'a' * (9 << 20)}\n'
        '[Event "超长行后的一局"]\n'
        '[Red "红"]\n'
        '\n'
        '1. 炮二平五\n',
        encoding: utf8,
      );

      final index = PgnParser.scanGameOffsets(longFile.path);

      // 超长行被计为 moves 行（gameStart=0），随后标签行开启第二局。
      expect(index, hasLength(2));
      expect(index[0].offset, 0);
      expect(index[1].event, '超长行后的一局');
      expect(index[1].red, '红');
    });
  });
}
