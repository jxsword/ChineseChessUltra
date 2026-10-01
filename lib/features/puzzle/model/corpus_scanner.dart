/// 本地棋谱语料扫描。
///
/// 语料真实保存位置为 `E:\ssy_proj\qp`（见 docs/qp_parse.md），本地开发时
/// 通过项目根下的目录联接 `corpus` 引用（`mklink /J corpus E:\ssy_proj\qp`），
/// 不把棋谱复制进项目。联接不存在时 [CorpusRepository.exists] 为 false，
/// 浏览页显示引导说明。
///
/// 结构：
/// - `XQF-象棋谱大全/<分类>/.../*.xqf` —— 按一级子目录分类，逐文件懒解析；
/// - `ChessQ-gamebooks/gamebooks/**/*.xqf` —— 残局杀势；
/// - `CGLemon-PGN/{wxf,dpxq}/ICCS/*.pgns` —— 多局合一 PGN 大文件，
///   用 [PgnParser.scanGameOffsets] 建立按局索引后分页浏览。

library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:logging/logging.dart';

import 'parsers/pgn_parser.dart';
import 'puzzle_data.dart';
import 'puzzle_parser.dart';

/// 语料条目种类。
enum CorpusKind {
  /// XQF 文件目录（逐文件懒解析）。
  xqfDirectory,

  /// 多局合一 PGN 大文件（按局偏移索引、分页浏览）。
  pgnFile,
}

/// 语料分类（浏览页的一级入口）。
class CorpusCategory {
  final String name;
  final CorpusKind kind;

  /// 目录或 PGN 文件的绝对路径。
  final String path;

  /// 来源标注（相对语料根的前两级路径），传入解析器。
  final String source;

  const CorpusCategory({
    required this.name,
    required this.kind,
    required this.path,
    this.source = '',
  });
}

/// XQF 分类下的一个文件条目（解析前的轻量描述）。
class CorpusEntry {
  final String path;
  final String category;

  /// 相对语料根的来源路径（作为 ParsedPuzzle.source）。
  final String source;

  const CorpusEntry({
    required this.path,
    required this.category,
    required this.source,
  });

  String get displayName {
    final base = path.split(Platform.pathSeparator).last;
    final dot = base.lastIndexOf('.');
    return dot > 0 ? base.substring(0, dot) : base;
  }
}

/// 语料扫描与棋局加载。
class CorpusRepository {
  static final _log = Logger('CorpusRepository');

  /// 项目根下指向 E:\ssy_proj\qp 的目录联接名。
  static const corpusDirName = 'corpus';

  final Directory root;

  /// [root] 缺省为项目根下的 `corpus`；测试可注入临时目录。
  CorpusRepository({Directory? root})
      : root = root ?? Directory(corpusDirName);

  bool get exists => root.existsSync();

  /// 扫描语料分类。XQF 按一级子目录聚合；PGN 大文件每个文件一个分类。
  List<CorpusCategory> scanCategories() {
    if (!exists) return const [];
    final categories = <CorpusCategory>[];
    for (final entity in root.listSync(followLinks: true)) {
      if (entity is! Directory) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      if (name.startsWith('_')) continue; // 忽略 _ref 等辅助目录
      if (name == 'CGLemon-PGN') {
        // PGN 大文件：递归找 .pgn / .pgns。
        for (final f in entity
            .listSync(recursive: true, followLinks: true)
            .whereType<File>()) {
          final ext = f.path.toLowerCase().split('.').last;
          if (ext != 'pgn' && ext != 'pgns') continue;
          final rel = f.path.substring(root.path.length);
          final parts = rel.split(Platform.pathSeparator)..removeAt(0);
          final source = parts.take(2).join('/');
          categories.add(CorpusCategory(
            name: 'PGN · ${parts.last}（多局合一）',
            kind: CorpusKind.pgnFile,
            path: f.path,
            source: source,
          ));
        }
      } else {
        categories.add(CorpusCategory(
          name: name,
          kind: CorpusKind.xqfDirectory,
          path: entity.path,
          source: name,
        ));
      }
    }
    categories.sort((a, b) => a.name.compareTo(b.name));
    return categories;
  }

  /// 列出 XQF 分类下的全部棋谱文件（不做解析）。
  ///
  /// 条目的 [CorpusEntry.source] 取相对分类目录的前两级子目录
  /// （如"残局/适情雅趣"），供解析结果标注来源与区分全局对局/残局题。
  List<CorpusEntry> listXqfEntries(CorpusCategory category) {
    assert(category.kind == CorpusKind.xqfDirectory);
    final dir = Directory(category.path);
    if (!dir.existsSync()) return const [];
    final entries = <CorpusEntry>[];
    for (final f in dir
        .listSync(recursive: true, followLinks: true)
        .whereType<File>()) {
      if (!f.path.toLowerCase().endsWith('.xqf')) continue;
      entries.add(CorpusEntry(
        path: f.path,
        category: category.name,
        source: _sourceOf(category, f.path),
      ));
    }
    entries.sort((a, b) => a.displayName.compareTo(b.displayName));
    return entries;
  }

  /// 从文件相对路径推导来源标注（前两级子目录）。
  String _sourceOf(CorpusCategory category, String filePath) {
    final rel = filePath.substring(category.path.length);
    final parts = rel
        .split(Platform.pathSeparator)
        .where((p) => p.isNotEmpty)
        .toList();
    parts.removeLast(); // 文件名
    parts.removeWhere((p) => p == 'gamebooks'); // ChessQ 的通用目录层
    return parts.take(2).join('/');
  }

  /// 解析单个 XQF 文件（含门面重放校验）。
  ///
  /// 返回 null 表示文件损坏或无可演示走法。
  ParsedPuzzle? parseXqfEntry(CorpusEntry entry) => parseXqfFile(
        entry.path,
        source: entry.source,
      );

  /// 批量解析 XQF 文件（后台 isolate 中执行，避免阻塞 UI）。
  ///
  /// 返回与 [entries] 等长的结果列表，失败位为 null；来源标注逐条目携带
  /// （同分类下不同子目录的来源不同）。
  static Future<List<ParsedPuzzle?>> parseXqfBatch(
    List<CorpusEntry> entries,
  ) {
    return Isolate.run(() => [
          for (final e in entries)
            parseXqfFile(e.path, source: e.source),
        ]);
  }

  /// 解析单个 XQF 文件；损坏或无可演示走法返回 null。
  static ParsedPuzzle? parseXqfFile(String path, {required String source}) {
    try {
      final bytes = File(path).readAsBytesSync();
      final parsed = PuzzleParser.parse(
        fileName: path,
        bytes: bytes,
        source: source,
      );
      return parsed.isEmpty ? null : parsed.first;
    } on FormatException catch (e) {
      _log.warning('XQF 解析失败 $path: ${e.message}');
      return null;
    } on FileSystemException catch (e) {
      _log.warning('XQF 读取失败 $path: ${e.message}');
      return null;
    }
  }

  /// 扫描 PGN 大文件的按局索引（后台 isolate）。
  static Future<List<PgnGameIndex>> scanPgnIndex(String path,
      {int maxGames = -1}) {
    return Isolate.run(
        () => PgnParser.scanGameOffsets(path, maxGames: maxGames));
  }

  /// 读取并解析 PGN 大文件中 [index] 指向的棋局（后台 isolate）。
  static Future<ParsedPuzzle?> parsePgnGameAt(
    String path,
    PgnGameIndex index,
    String source,
  ) {
    return Isolate.run(() {
      try {
        final text = PgnParser.readGameAt(path, index);
        final parsed = PuzzleParser.parse(
          fileName: path,
          bytes: utf8.encode(text),
          source: source,
        );
        return parsed.isEmpty ? null : parsed.first;
      } catch (e) {
        _log.warning('PGN 局解析失败: $e');
        return null;
      }
    });
  }
}
