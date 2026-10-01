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
              'https://github.com/jxsword/qp-corpus/releases/download/v1/x.zip'),
          isTrue);
    });

    test('拒绝非 https 与非法 URL', () {
      expect(
          CorpusPaths.isDownloadUrlAllowed(
              'http://github.com/jxsword/qp-corpus/releases/download/v1/x.zip'),
          isFalse);
      expect(CorpusPaths.isDownloadUrlAllowed('ftp://example.com/x.zip'),
          isFalse);
      expect(CorpusPaths.isDownloadUrlAllowed('not a url'), isFalse);
      expect(CorpusPaths.isDownloadUrlAllowed(''), isFalse);
    });

    test('拒绝 localhost / 环回 / 私有 / 保留地址 / mDNS', () {
      expect(CorpusPaths.isDownloadUrlAllowed('https://localhost/x.zip'),
          isFalse);
      expect(CorpusPaths.isDownloadUrlAllowed('https://127.0.0.1/x.zip'),
          isFalse);
      expect(CorpusPaths.isDownloadUrlAllowed('https://10.0.0.1/x.zip'),
          isFalse);
      expect(CorpusPaths.isDownloadUrlAllowed('https://192.168.1.1/x.zip'),
          isFalse);
      expect(CorpusPaths.isDownloadUrlAllowed('https://172.16.0.1/x.zip'),
          isFalse);
      expect(CorpusPaths.isDownloadUrlAllowed('https://169.254.1.1/x.zip'),
          isFalse);
      expect(CorpusPaths.isDownloadUrlAllowed('https://0.0.0.0/x.zip'),
          isFalse);
      expect(CorpusPaths.isDownloadUrlAllowed('https://224.0.0.1/x.zip'),
          isFalse);
      expect(CorpusPaths.isDownloadUrlAllowed('https://[::1]/x.zip'), isFalse);
      expect(CorpusPaths.isDownloadUrlAllowed('https://[fe80::1]/x.zip'),
          isFalse);
      expect(CorpusPaths.isDownloadUrlAllowed('https://[fd00::1]/x.zip'),
          isFalse);
      expect(CorpusPaths.isDownloadUrlAllowed('https://nas.local/x.zip'),
          isFalse);
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
      }, 'ok.zip');
      final target = Directory('${tmp.path}${Platform.pathSeparator}corpus');

      final count = CorpusDownloader.extractZip(zip, target);

      expect(count, 3);
      expect(
          File('${target.path}${Platform.pathSeparator}XQF-象棋谱大全'
              '${Platform.pathSeparator}残局${Platform.pathSeparator}适情雅趣'
              '${Platform.pathSeparator}a.xqf'
              ).readAsStringSync(),
          'data-a');
      expect(
          File('${target.path}${Platform.pathSeparator}README.md'
              ).readAsStringSync(),
          'readme');
    });

    test('zip-slip 防护：.. 越界、绝对路径、盘符条目被跳过', () {
      final zip = buildZip({
        '../escape.txt': utf8.encode('evil'),
        '/abs/evil.txt': utf8.encode('evil'),
        'C:/evil.txt': utf8.encode('evil'),
        'XQF-象棋谱大全/安全.xqf': utf8.encode('safe'),
      }, 'evil.zip');
      final target = Directory('${tmp.path}${Platform.pathSeparator}corpus');

      final count = CorpusDownloader.extractZip(zip, target);

      expect(count, 1, reason: '只有安全条目被解压');
      expect(
          File('${target.path}${Platform.pathSeparator}XQF-象棋谱大全'
              '${Platform.pathSeparator}安全.xqf').existsSync(),
          isTrue);
      // 越界文件不存在于临时目录。
      expect(
          File('${tmp.path}${Platform.pathSeparator}escape.txt').existsSync(),
          isFalse);
    });

    test('zip-slip 探针：反斜杠归一、嵌套 ..、UNC、符号链接全拦截', () {
      final symlink = ArchiveFile('link/evil.xqf', 4, utf8.encode('evil'))
        ..mode = 0xA1FF
        ..nameOfLinkedFile = '../../../outside.txt';
      final archive = Archive()
        ..addFile(ArchiveFile('..\\escape.txt', 4, utf8.encode('evil')))
        ..addFile(ArchiveFile('a/../../escape2.txt', 5, utf8.encode('evil2')))
        ..addFile(
            ArchiveFile(r'\\evil\share\f.txt', 5, utf8.encode('evil3')))
        ..addFile(symlink)
        ..addFile(ArchiveFile('ok.txt', 2, utf8.encode('hi')));

      final zip =
          File('${tmp.path}${Platform.pathSeparator}probes.zip');
      zip.writeAsBytesSync(ZipEncoder().encode(archive)!);
      final target = Directory('${tmp.path}${Platform.pathSeparator}corpus');

      final count = CorpusDownloader.extractZip(zip, target);

      expect(count, 1, reason: '只允许 ok.txt 落地');
      expect(
          File('${target.path}${Platform.pathSeparator}ok.txt')
              .readAsStringSync(),
          'hi');
      // 逃逸向量均未产生目标目录之外的文件。
      expect(
          File('${tmp.path}${Platform.pathSeparator}escape.txt').existsSync(),
          isFalse);
      expect(
          File('${tmp.path}${Platform.pathSeparator}escape2.txt').existsSync(),
          isFalse);
      expect(Directory('${tmp.path}${Platform.pathSeparator}evil').existsSync(),
          isFalse);
      expect(
          File('${target.path}${Platform.pathSeparator}link').existsSync(),
          isFalse);
    });
  });
}
