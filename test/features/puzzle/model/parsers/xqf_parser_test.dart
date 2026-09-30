import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_chess_ultra/features/board/model/board.dart';
import 'package:chinese_chess_ultra/features/board/model/fen.dart';
import 'package:chinese_chess_ultra/features/board/model/move.dart';
import 'package:chinese_chess_ultra/features/puzzle/model/iccs.dart';
import 'package:chinese_chess_ultra/features/puzzle/model/parsers/xqf_parser.dart';

/// 语料联接根目录（mklink /J corpus E:\ssy_proj\qp）。
const corpusRoot = 'corpus';
final corpusExists = Directory(corpusRoot).existsSync();

/// 构造一个仅含魔数的假 XQF。
Uint8List bytesOf(List<int> head) => Uint8List.fromList(head);

void main() {
  test('坏魔数抛 FormatException', () {
    final bad = bytesOf([0x58, 0x58, 0x0A, ...List.filled(1100, 0)]);
    expect(() => XqfParser.parse(bad), throwsFormatException);
  });

  test('文件过短抛 FormatException', () {
    expect(() => XqfParser.parse(bytesOf([0x58, 0x51, 0x0A, 1, 2, 3])),
        throwsFormatException);
  });

  test('真语料：低版本（0x0A，无加密）基准对照', () {
    final f = File(
        '$corpusRoot\\XQF-象棋谱大全\\布局\\列手炮布局\\中炮对后补列炮(二)红士角炮 黑进右正马局(1).xqf');
    if (corpusRoot != 'corpus' || !f.existsSync()) { /* skip 标记在下方 */ }
    // 使用 skip 语义：语料缺失时跳过
    if (!f.existsSync()) return;
    final puzzle = XqfParser.parse(f.readAsBytesSync(), source: '布局');
    expect(puzzle.initialFen,
        'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1');
    expect(puzzle.moves.length, 40);
    expect(puzzle.moves.first, 'h2e2');
    expect(puzzle.moves[1], 'h9g7');
    expect(puzzle.moves.last, 'f3g3');
    expect(puzzle.format, 'xqf');
  }, skip: !Directory(corpusRoot).existsSync());

  test('真语料：加密版本（0x0C）基准对照', () {
    final f = File(
        '$corpusRoot\\XQF-象棋谱大全\\布局\\后手布局应对方略\\顺炮横车对直车（红进正马）.XQF');
    if (!f.existsSync()) return;
    final puzzle = XqfParser.parse(f.readAsBytesSync(), source: '布局');
    expect(puzzle.initialFen,
        'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1');
    expect(puzzle.moves.length, 33);
    expect(puzzle.moves.take(5).toList(),
        ['h2e2', 'h7e7', 'i0i1', 'h9g7', 'i1d1']);
    expect(puzzle.moves.last, 'd4d5');
    expect(puzzle.title, '顺炮横车对直车（红进正马）');
  }, skip: !Directory(corpusRoot).existsSync());

  test('真语料：高版本（0x12，位置置换加密）基准对照', () {
    final f = File('$corpusRoot\\XQF-象棋谱大全\\布局\\其他布局\\角包.xqf');
    if (!f.existsSync()) return;
    final puzzle = XqfParser.parse(f.readAsBytesSync(), source: '布局');
    expect(puzzle.moves.length, 188);
    expect(puzzle.moves.take(5).toList(),
        ['h2f2', 'b7e7', 'b0c2', 'b9c7', 'a0b0']);
    expect(puzzle.title, '仕角炮开局');
  }, skip: !Directory(corpusRoot).existsSync());

  test('真语料：全部走法在项目棋盘上重放合法（角包前 170 着；'
      '源谱第 171 着本身未解将，属数据错误）', () {
    final f = File('$corpusRoot\\XQF-象棋谱大全\\布局\\其他布局\\角包.xqf');
    if (!f.existsSync()) return;
    final puzzle = XqfParser.parse(f.readAsBytesSync());
    final board = Board.fromFen(puzzle.initialFen);
    var applied = 0;
    for (final iccs in puzzle.moves) {
      final pos = Iccs.parse(iccs)!;
      final legal = board
          .legalMovesFor(pos.from)
          .any((m) => m.from == pos.from && m.to == pos.to);
      if (!legal) break;
      board.applyMove(Move(from: pos.from, to: pos.to));
      applied += 1;
    }
    expect(applied, 170);
  }, skip: !Directory(corpusRoot).existsSync());

  test('真语料：随机抽取一局——解析成功、FEN 合法、走法可重放', () {
    final dir = Directory('$corpusRoot\\XQF-象棋谱大全');
    if (!dir.existsSync()) return;
    final files = <File>[];
    for (final f in dir.listSync(recursive: true, followLinks: true)) {
      if (f is File && f.path.toLowerCase().endsWith('.xqf')) files.add(f);
    }
    expect(files, isNotEmpty);

    // 每次运行随机抽一个（最多重试 5 次，跳过个别坏文件）。
    final random = Random(DateTime.now().millisecondsSinceEpoch);
    for (var attempt = 0; attempt < 5; attempt++) {
      final file = files[random.nextInt(files.length)];
      final bytes = file.readAsBytesSync();
      if (bytes.length < XqfParser.headerSize + 8) continue;
      if (bytes[0] != 0x58 || bytes[1] != 0x51) continue;
      try {
        final puzzle = XqfParser.parse(bytes);
        // FEN 粗校验。
        expect(Fen.isValid(puzzle.initialFen), isTrue,
            reason: '文件: ${file.path}');
        // 走法重放（项目棋盘、将军感知）。
        final board = Board.fromFen(puzzle.initialFen);
        var applied = 0;
        for (final iccs in puzzle.moves) {
          final pos = Iccs.parse(iccs);
          if (pos == null) break;
          final legal = board
              .legalMovesFor(pos.from)
              .any((m) => m.from == pos.from && m.to == pos.to);
          if (!legal) break;
          board.applyMove(Move(from: pos.from, to: pos.to));
          applied += 1;
        }
        // ignore: avoid_print
        print('随机样本: ${file.path.split('\\').last} '
            '(${puzzle.moves.length} 着，重放合法 $applied 着)');
        expect(applied, greaterThan(0), reason: '文件: ${file.path}');
        return;
      } on FormatException {
        continue; // 个别损坏文件，重试
      }
    }
    fail('连续 5 次随机抽样均解析失败');
  }, skip: !Directory(corpusRoot).existsSync());
}
