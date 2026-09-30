import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_chess_ultra/features/puzzle/model/corpus_scanner.dart';
import 'package:chinese_chess_ultra/features/puzzle/model/puzzle_data.dart';

/// 语料联接根目录（mklink /J corpus E:\ssy_proj\qp）。
const corpusRoot = 'corpus';

void main() {
  group('难度分档', () {
    test('按步数分档边界', () {
      expect(ParsedPuzzle.difficultyFromMoveCount(0), 1);
      expect(ParsedPuzzle.difficultyFromMoveCount(20), 1);
      expect(ParsedPuzzle.difficultyFromMoveCount(21), 2);
      expect(ParsedPuzzle.difficultyFromMoveCount(40), 2);
      expect(ParsedPuzzle.difficultyFromMoveCount(41), 3);
      expect(ParsedPuzzle.difficultyFromMoveCount(80), 3);
      expect(ParsedPuzzle.difficultyFromMoveCount(81), 4);
      expect(ParsedPuzzle.difficultyFromMoveCount(150), 4);
      expect(ParsedPuzzle.difficultyFromMoveCount(151), 5);
    });
  });

  group('语料扫描（临时目录）', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('corpus_test');
      // 构造: XQF测试谱/残局/a.xqf, XQF测试谱/残局/子/b.xqf, _ref/c.xqf
      final d1 = Directory('${tmp.path}${Platform.pathSeparator}XQF测试谱'
          '${Platform.pathSeparator}残局')
        ..createSync(recursive: true);
      File('${d1.path}${Platform.pathSeparator}a.xqf').writeAsBytesSync(
          List.filled(1100, 0));
      Directory('${d1.path}${Platform.pathSeparator}子').createSync();
      File('${d1.path}${Platform.pathSeparator}子'
          '${Platform.pathSeparator}b.XQF').writeAsBytesSync([]);
      Directory('${tmp.path}${Platform.pathSeparator}_ref').createSync();
      File('${tmp.path}${Platform.pathSeparator}_ref'
          '${Platform.pathSeparator}c.xqf').writeAsBytesSync([]);
    });

    tearDown(() {
      tmp.deleteSync(recursive: true);
    });

    test('scanCategories 忽略 _ref、按一级子目录聚合', () {
      final repo = CorpusRepository(root: tmp);
      final categories = repo.scanCategories();
      expect(categories.map((c) => c.name), ['XQF测试谱']);
      expect(categories.single.kind, CorpusKind.xqfDirectory);
      expect(categories.single.source, 'XQF测试谱');
    });

    test('listXqfEntries 递归列出并按名称排序', () {
      final repo = CorpusRepository(root: tmp);
      final entries = repo.listXqfEntries(repo.scanCategories().single);
      expect(entries.map((e) => e.displayName), ['a', 'b']);
    });

    test('空目录 / 不存在的目录返回空', () {
      final repo = CorpusRepository(
          root: Directory('${tmp.path}${Platform.pathSeparator}不存在'));
      expect(repo.exists, isFalse);
      expect(repo.scanCategories(), isEmpty);
    });
  });

  group('真实语料（corpus 联接）', () {
    final corpusExists = Directory(corpusRoot).existsSync();

    test('分类扫描：XQF 分类与 PGN 大文件均被发现', () async {
      final repo = CorpusRepository();
      final categories = repo.scanCategories();
      // ignore: avoid_print
      print('分类: ${categories.map((c) => c.name).toList()}');
      expect(
          categories.where((c) => c.kind == CorpusKind.xqfDirectory).length,
          greaterThanOrEqualTo(2));
      expect(
          categories.where((c) => c.kind == CorpusKind.pgnFile).length,
          greaterThanOrEqualTo(1));
    }, skip: !corpusExists);

    test('随机抽取一局并完整解析（含重放校验）', () async {
      final repo = CorpusRepository();
      final categories = repo.scanCategories();
      final xqf = categories
          .firstWhere((c) => c.name == 'XQF-象棋谱大全');
      final entries = repo.listXqfEntries(xqf);
      expect(entries, isNotEmpty);

      // 随机抽一条解析。
      final entry = entries[DateTime.now().millisecondsSinceEpoch %
          entries.length];
      final puzzle = repo.parseXqfEntry(entry);
      // ignore: avoid_print
      print('随机样本: ${entry.displayName} → '
          '${puzzle == null ? "解析失败" : "${puzzle.moves.length} 着"}');
      expect(puzzle, isNotNull);
      expect(puzzle!.source, 'XQF-象棋谱大全');
      expect(puzzle.difficulty, greaterThanOrEqualTo(1));
      expect(puzzle.difficulty, lessThanOrEqualTo(5));
    }, skip: !corpusExists);

    test('PGN 大文件：索引扫描 + 抽样解析单局', () async {
      final repo = CorpusRepository();
      final categories = repo.scanCategories();
      final pgn = categories
          .firstWhere((c) => c.kind == CorpusKind.pgnFile);
      final index = await CorpusRepository.scanPgnIndex(pgn.path);
      expect(index.length, greaterThan(1000));
      final sample = index[DateTime.now().millisecondsSinceEpoch % 100];
      final puzzle = await CorpusRepository.parsePgnGameAt(
          pgn.path, sample, pgn.source);
      expect(puzzle, isNotNull);
      // ignore: avoid_print
      print('PGN 随机样本: ${sample.title} → ${puzzle!.moves.length} 着');
    }, skip: !corpusExists, timeout: const Timeout(Duration(minutes: 3)));
  });
}
