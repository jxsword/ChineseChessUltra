/// 棋谱语料包下载器：HTTPS 下载 + zip 解压到语料目录。
///
/// 安全约束：
/// - 下载前用 [CorpusPaths.isDownloadUrlAllowed] 校验 URL（仅 https 公网地址）；
/// - 重定向手动跟随，每一跳都重新校验；
/// - zip 解压防路径穿越：条目名规范化后必须仍在目标目录内（zip-slip 防护）。

library;

import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:logging/logging.dart';

import 'corpus_paths.dart';

/// 棋谱语料下载器。
class CorpusDownloader {
  CorpusDownloader._();

  static final _log = Logger('CorpusDownloader');

  /// 下载 [url] 指向的语料 zip 并解压到 [targetDir]（自动创建）。
  ///
  /// [onProgress] 回调 (已接收字节, 总字节)；总字节未知时为 -1。
  /// 返回解压的文件数。
  static Future<int> downloadAndExtract({
    required String url,
    required Directory targetDir,
    void Function(int received, int total)? onProgress,
  }) async {
    if (!CorpusPaths.isDownloadUrlAllowed(url)) {
      throw const FormatException('下载地址不合法（仅允许 https 公网地址）');
    }
    await targetDir.create(recursive: true);
    final zipFile = await _download(url, targetDir, onProgress);
    try {
      // 解压放入独立 isolate：245MB 级解压在 UI isolate 会造成
      // Android ANR / 低内存设备 OOM（P0-2）。
      final count = await Isolate.run(
        () => _extractZipInIsolate(zipFile.path, targetDir.path),
      );
      _log.info('语料解压完成：$count 个文件 → ${targetDir.path}');
      return count;
    } finally {
      try {
        zipFile.deleteSync();
      } on FileSystemException catch (e) {
        _log.warning('临时 zip 清理失败: ${e.message}');
      }
    }
  }

  /// 下载 zip 到目标目录下的临时文件；手动跟随重定向并逐跳校验。
  static Future<File> _download(
    String url,
    Directory targetDir,
    void Function(int received, int total)? onProgress,
  ) async {
    var current = url;
    final client = HttpClient();
    try {
      for (var redirect = 0; redirect <= 5; redirect++) {
        if (!CorpusPaths.isDownloadUrlAllowed(current)) {
          throw const FormatException('重定向地址不合法（仅允许 https 公网地址）');
        }
        final request = await client.getUrl(Uri.parse(current))
          ..followRedirects = false
          ..maxRedirects = 0;
        final response = await request.close();
        if (response.isRedirect) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null) {
            throw const HttpException('重定向缺少 Location 头');
          }
          current = Uri.parse(current).resolve(location).toString();
          await response.drain<void>();
          continue;
        }
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException('下载失败：HTTP ${response.statusCode}');
        }
        final total = response.contentLength; // 未知时为 -1
        final tempFile = File(
            '${targetDir.parent.path}${Platform.pathSeparator}'
            'corpus-download-${DateTime.now().millisecondsSinceEpoch}.zip');
        final sink = tempFile.openWrite();
        var received = 0;
        try {
          await for (final chunk in response) {
            received += chunk.length;
            sink.add(chunk);
            onProgress?.call(received, total);
          }
          await sink.flush();
          await sink.close();
        } on Object {
          await sink.close();
          rethrow;
        }
        return tempFile;
      }
      throw const HttpException('重定向次数过多');
    } finally {
      client.close(force: true);
    }
  }

  /// 解压本地 zip 文件到 [targetDir]（含 zip-slip 防护），返回解压文件数。
  ///
  /// 用 [InputFileStream] 流式打开 + 条目内容按需惰性解码，
  /// 避免 readAsBytesSync 全量读入导致 zip + 解压内容同时驻留内存。
  /// 供 [_extractZipInIsolate] 在后台 isolate 中调用，也可直接单测。
  static int extractZip(File zipFile, Directory targetDir) {
    final input = InputFileStream(zipFile.path);
    try {
      final archive = ZipDecoder().decodeBuffer(input);
      var count = 0;
      for (final entry in archive) {
        final name = entry.name.replaceAll('\\', '/');
        // 符号链接条目一律拒绝（archive 用 mode 高位或 nameOfLinkedFile 表示）；
        // 绝对路径与 .. / 盘符段一律拒绝。
        final isSymlink = (entry.mode & 0xF000) == 0xA000 ||
            entry.nameOfLinkedFile.isNotEmpty;
        if (isSymlink ||
            name.startsWith('/') ||
            name.split('/').contains('..')) {
          _log.warning('跳过可疑 zip 条目: ${entry.name}');
          continue;
        }
        final segments = name.split('/').where((s) => s.isNotEmpty).toList();
        if (segments.isEmpty ||
            segments.any((s) => s.contains(':') || s == '.')) {
          _log.warning('跳过可疑 zip 条目: ${entry.name}');
          continue;
        }
        // 词法重组（已拒绝 .. / 盘符，不可能逃出目标目录）。
        final outPath =
            '${targetDir.path}${Platform.pathSeparator}${segments.join(Platform.pathSeparator)}';
        if (entry.isFile) {
          final outFile = File(outPath);
          outFile.parent.createSync(recursive: true);
          outFile.writeAsBytesSync(entry.content as List<int>);
          count += 1;
        } else {
          Directory(outPath).createSync(recursive: true);
        }
      }
      return count;
    } finally {
      input.closeSync();
    }
  }

  /// isolate 入口：仅传路径字符串，避免跨 isolate 传递文件句柄。
  static int _extractZipInIsolate(String zipPath, String targetPath) =>
      extractZip(File(zipPath), Directory(targetPath));
}
