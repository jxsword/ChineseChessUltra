import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_chess_ultra/features/puzzle/model/corpus_downloader.dart';
import 'package:chinese_chess_ultra/features/puzzle/model/corpus_paths.dart';

void main() {
  group('CorpusPaths 下载 URL 安全校验', () {
    test('允许 https 公网地址', () {
      expect(CorpusPaths.isDownloadUrlAllowed(CorpusPaths.downloadUrl), isTrue);
      expect(
          CorpusPaths.isDownloadUrlAllowed(
              'https://github.com/jxsword/qp-corpus/releases/download/v1/x.zip',),
          isTrue,);
    });

    test('拒绝非 https 与非法 URL', () {
      expect(
          CorpusPaths.isDownloadUrlAllowed(
              'http://github.com/jxsword/qp-corpus/releases/download/v1/x.zip',),
          isFalse,);
      expect(CorpusPaths.isDownloadUrlAllowed('ftp://example.com/x.zip'),
          isFalse,);
      expect(CorpusPaths.isDownloadUrlAllowed('not a url'), isFalse);
      expect(CorpusPaths.isDownloadUrlAllowed(''), isFalse);
    });

    test('拒绝 localhost / 环回 / 私有 / 保留地址 / mDNS', () {
      expect(CorpusPaths.isDownloadUrlAllowed('https://localhost/x.zip'),
          isFalse,);
      expect(CorpusPaths.isDownloadUrlAllowed('https://127.0.0.1/x.zip'),
          isFalse,);
      expect(CorpusPaths.isDownloadUrlAllowed('https://10.0.0.1/x.zip'),
          isFalse,);
      expect(CorpusPaths.isDownloadUrlAllowed('https://192.168.1.1/x.zip'),
          isFalse,);
      expect(CorpusPaths.isDownloadUrlAllowed('https://172.16.0.1/x.zip'),
          isFalse,);
      expect(CorpusPaths.isDownloadUrlAllowed('https://169.254.1.1/x.zip'),
          isFalse,);
      expect(CorpusPaths.isDownloadUrlAllowed('https://0.0.0.0/x.zip'),
          isFalse,);
      expect(CorpusPaths.isDownloadUrlAllowed('https://224.0.0.1/x.zip'),
          isFalse,);
      expect(CorpusPaths.isDownloadUrlAllowed('https://[::1]/x.zip'), isFalse);
      expect(CorpusPaths.isDownloadUrlAllowed('https://[fe80::1]/x.zip'),
          isFalse,);
      expect(CorpusPaths.isDownloadUrlAllowed('https://[fd00::1]/x.zip'),
          isFalse,);
      expect(CorpusPaths.isDownloadUrlAllowed('https://nas.local/x.zip'),
          isFalse);
    });

    test('拒绝 IPv4-mapped IPv6 / 整数 IP / 八进制分段等绕过形式（P2-1）', () {
      // IPv4-mapped IPv6（::ffff:0:0/96）还原成 v4 判段。
      expect(CorpusPaths.isDownloadUrlAllowed('https://[::ffff:127.0.0.1]/x.zip'),
          isFalse);
      expect(CorpusPaths.isDownloadUrlAllowed('https://[::ffff:7f00:1]/x.zip'),
          isFalse);
      expect(CorpusPaths.isDownloadUrlAllowed('https://[::ffff:10.0.0.1]/x.zip'),
          isFalse);
      // 纯十进制 / 十六进制整数 IP。
      expect(CorpusPaths.isDownloadUrlAllowed('https://2130706433/x.zip'),
          isFalse);
      expect(CorpusPaths.isDownloadUrlAllowed('https://0x7f000001/x.zip'),
          isFalse);
      // 超出 v4 范围的整数 host。
      expect(CorpusPaths.isDownloadUrlAllowed('https://2887685888/x.zip'),
          isFalse);
      // 八进制分段（前导 0 歧义）。
      expect(CorpusPaths.isDownloadUrlAllowed('https://0177.0.0.1/x.zip'),
          isFalse);
      // mapped 公网地址仍放行（行为对齐：校验的是内网/保留段）。
      expect(CorpusPaths.isDownloadUrlAllowed('https://[::ffff:8.8.8.8]/x.zip'),
          isTrue);
    });
  });

  group('CorpusDownloader.extractZip（本地构造包，不走网络）', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('corpus_dl_test');
    });

    tearDown(() {
      tmp.deleteSync(recursive: true);
    });

    File buildZip(Map<String, List<int>> entries, String name) {
      final archive = Archive();
      entries.forEach((path, content) {
        archive.addFile(ArchiveFile(path, content.length, content));
      });
      final zip = File('${tmp.path}${Platform.pathSeparator}$name');
      zip.writeAsBytesSync(ZipEncoder().encode(archive)!);
      return zip;
    }

    test('正常解压：文件与子目录落位，返回文件数', () {
      final zip = buildZip({
        'XQF-象棋谱大全/残局/适情雅趣/a.xqf': utf8.encode('data-a'),
        'XQF-象棋谱大全/全局/b.xqf': utf8.encode('data-b'),
        'README.md': utf8.encode('readme'),
      }, 'ok.zip',);
      final target = Directory('${tmp.path}${Platform.pathSeparator}corpus');

      final count = CorpusDownloader.extractZip(zip, target);

      expect(count.extracted, 3);
      expect(
          File('${target.path}${Platform.pathSeparator}XQF-象棋谱大全'
              '${Platform.pathSeparator}残局${Platform.pathSeparator}适情雅趣'
              '${Platform.pathSeparator}a.xqf'
              ).readAsStringSync(),
          'data-a',);
      expect(
          File('${target.path}${Platform.pathSeparator}README.md',
              ).readAsStringSync(),
          'readme',);
    });

    test('zip-slip 防护：.. 越界、绝对路径、盘符条目被跳过', () {
      final zip = buildZip({
        '../escape.txt': utf8.encode('evil'),
        '/abs/evil.txt': utf8.encode('evil'),
        'C:/evil.txt': utf8.encode('evil'),
        'XQF-象棋谱大全/安全.xqf': utf8.encode('safe'),
      }, 'evil.zip',);
      final target = Directory('${tmp.path}${Platform.pathSeparator}corpus');

      final count = CorpusDownloader.extractZip(zip, target);

      expect(count.extracted, 1, reason: '只有安全条目被解压');
      expect(
          File('${target.path}${Platform.pathSeparator}XQF-象棋谱大全'
              '${Platform.pathSeparator}安全.xqf').existsSync(),
          isTrue,);
      // 越界文件不存在于临时目录。
      expect(
          File('${tmp.path}${Platform.pathSeparator}escape.txt').existsSync(),
          isFalse,);
    });

    test('zip-slip 探针：反斜杠归一、嵌套 ..、UNC、符号链接全拦截', () {
      final symlink = ArchiveFile('link/evil.xqf', 4, utf8.encode('evil'))
        ..mode = 0xA1FF
        ..nameOfLinkedFile = '../../../outside.txt';
      final archive = Archive()
        ..addFile(ArchiveFile('..\\escape.txt', 4, utf8.encode('evil')))
        ..addFile(ArchiveFile('a/../../escape2.txt', 5, utf8.encode('evil2')))
        ..addFile(
            ArchiveFile(r'\\evil\share\f.txt', 5, utf8.encode('evil3')),)
        ..addFile(symlink)
        ..addFile(ArchiveFile('ok.txt', 2, utf8.encode('hi')));

      final zip =
          File('${tmp.path}${Platform.pathSeparator}probes.zip');
      zip.writeAsBytesSync(ZipEncoder().encode(archive)!);
      final target = Directory('${tmp.path}${Platform.pathSeparator}corpus');

      final count = CorpusDownloader.extractZip(zip, target);

      expect(count.extracted, 1, reason: '只允许 ok.txt 落地');
      expect(
          File('${target.path}${Platform.pathSeparator}ok.txt')
              .readAsStringSync(),
          'hi',);
      // 逃逸向量均未产生目标目录之外的文件。
      expect(
          File('${tmp.path}${Platform.pathSeparator}escape.txt').existsSync(),
          isFalse,);
      expect(
          File('${tmp.path}${Platform.pathSeparator}escape2.txt').existsSync(),
          isFalse,);
      expect(Directory('${tmp.path}${Platform.pathSeparator}evil').existsSync(),
          isFalse,);
      expect(
          File('${target.path}${Platform.pathSeparator}link').existsSync(),
          isFalse,);
    });

    test('Windows 保留名（含扩展名形式）与尾随点/空格条目被跳过', () {
      final zip = buildZip({
        'CON': utf8.encode('x'),
        'NUL.txt': utf8.encode('x'),
        'com1': utf8.encode('x'),
        'aux/inner.txt': utf8.encode('x'),
        'LPT2': utf8.encode('x'),
        'bad.': utf8.encode('x'),
        'bad. ': utf8.encode('x'),
        'good.txt': utf8.encode('ok'),
      }, 'reserved.zip',);
      final target = Directory('${tmp.path}${Platform.pathSeparator}corpus');

      final result = CorpusDownloader.extractZip(zip, target);

      expect(result.extracted, 1, reason: '只有 good.txt 落地');
      expect(result.skipped, 7);
      expect(
          File('${target.path}${Platform.pathSeparator}good.txt')
              .readAsStringSync(),
          'ok',);
    });

    test('同名冲突（先文件后目录）跳过冲突条目，不中断整体解压', () {
      final zip = buildZip({
        'conflict': utf8.encode('file'),
        'conflict/inner.txt': utf8.encode('dir-entry'),
        'ok.txt': utf8.encode('ok'),
      }, 'conflict.zip',);
      final target = Directory('${tmp.path}${Platform.pathSeparator}corpus');

      final result = CorpusDownloader.extractZip(zip, target);

      expect(result.extracted, 2, reason: 'conflict 文件与 ok.txt 落地');
      expect(result.skipped, 1, reason: 'conflict/inner.txt 因同名冲突被跳过');
      expect(
          File('${target.path}${Platform.pathSeparator}ok.txt').existsSync(),
          isTrue,);
      // 解压过程未抛异常（整体未中断）——走到这里即为通过。
    });

    test('extractZipAtomic：失败时清理临时目录且旧目录不被破坏', () async {
      final parent = tmp;
      final target = Directory('${parent.path}${Platform.pathSeparator}corpus')
        ..createSync();
      final sentinel =
          File('${target.path}${Platform.pathSeparator}old.txt')
            ..writeAsStringSync('old');

      // 非 zip 垃圾字节：解压必然抛异常。
      final corrupt = File('${tmp.path}${Platform.pathSeparator}corrupt.zip')
        ..writeAsBytesSync([0x00, 0x01, 0x02, 0x03, 0x04]);

      await expectLater(
        CorpusDownloader.extractZipAtomic(corrupt, target),
        throwsA(isA<Object>()),
      );

      // 旧目录内容完好，临时目录已清理。
      expect(sentinel.readAsStringSync(), 'old');
      final leftovers = parent
          .listSync()
          .whereType<Directory>()
          .where((d) =>
              d.path.split(Platform.pathSeparator).last.startsWith('corpus.tmp'),)
          .toList();
      expect(leftovers, isEmpty, reason: '失败的临时解压目录应被整体删除');
    });

    test('extractZipAtomic：成功后原子替换旧目录', () async {
      final parent = tmp;
      final target = Directory('${parent.path}${Platform.pathSeparator}corpus')
        ..createSync();
      File('${target.path}${Platform.pathSeparator}old.txt')
          .writeAsStringSync('old');

      final zip = buildZip({
        'new.txt': utf8.encode('new'),
      }, 'replace.zip',);

      final result = await CorpusDownloader.extractZipAtomic(zip, target);

      expect(result.extracted, 1);
      expect(result.skipped, 0);
      expect(
          File('${target.path}${Platform.pathSeparator}new.txt')
              .readAsStringSync(),
          'new',);
      expect(
          File('${target.path}${Platform.pathSeparator}old.txt').existsSync(),
          isFalse,
          reason: '旧目录被整体替换',);
      final leftovers = parent
          .listSync()
          .whereType<Directory>()
          .where((d) =>
              d.path.split(Platform.pathSeparator).last.startsWith('corpus.tmp'),)
          .toList();
      expect(leftovers, isEmpty);
    });
  });
}
