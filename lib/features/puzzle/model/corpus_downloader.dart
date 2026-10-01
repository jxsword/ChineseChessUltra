/// 棋谱语料包下载器：HTTPS 下载 + zip 解压到语料目录。
///
/// 安全约束：
/// - 下载前用 [CorpusPaths.isDownloadUrlAllowed] 校验 URL（仅 https 公网地址）；
/// - 重定向手动跟随，每一跳都重新校验；
/// - zip 解压防路径穿越：条目名规范化后必须仍在目标目录内（zip-slip 防护）；
/// - zip 魔数与大小校验 + Windows 保留名条目跳过（防炸弹/异常中断）。
///
/// 健壮性约束：
/// - 连接 15s 超时 + 响应流 30s 块间超时，支持用户取消；
/// - 临时 zip 写系统临时目录；解压先落 `corpus.tmp-<ts>` 临时目录，
///   全部成功后原子替换目标目录，失败整体清理，不残留半成品。

library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:logging/logging.dart';

import 'corpus_paths.dart';

/// 用户取消下载时抛出。
class CorpusDownloadCancelled implements Exception {
  const CorpusDownloadCancelled();

  @override
  String toString() => '下载已取消';
}

/// 下载解压结果：解压成功的文件数与跳过的条目数。
class CorpusDownloadResult {
  final int extracted;
  final int skipped;

  const CorpusDownloadResult({required this.extracted, required this.skipped});
}

/// 棋谱语料下载器。
class CorpusDownloader {
  CorpusDownloader._();

  static final _log = Logger('CorpusDownloader');

  /// TCP 连接与响应头等待超时。
  static const _connectTimeout = Duration(seconds: 15);

  /// 响应流块间超时：超过该时长无新数据即判定下载停滞。
  static const _chunkTimeout = Duration(seconds: 30);

  /// 语料 zip 合法大小下限/上限（当前包约 45.8MB，留足余量防炸弹/空文件）。
  static const _minZipBytes = 1 << 20; // 1MB
  static const _maxZipBytes = 512 << 20; // 512MB

  /// Windows 保留设备名（不区分大小写，含 `CON.txt` 扩展名形式）。
  static final _reservedSegment =
      RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$',
          caseSensitive: false,);

  /// 下载 [url] 指向的语料 zip 并解压到 [targetDir]。
  ///
  /// [onProgress] 回调 (已接收字节, 总字节)；总字节未知时为 -1。
  /// [isCancelled] 在下载/解压各阶段间轮询，返回 true 时抛出
  /// [CorpusDownloadCancelled] 并清理所有临时产物。
  /// 成功返回 [CorpusDownloadResult]。
  static Future<CorpusDownloadResult> downloadAndExtract({
    required String url,
    required Directory targetDir,
    void Function(int received, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (!CorpusPaths.isDownloadUrlAllowed(url)) {
      throw const FormatException('下载地址不合法（仅允许 https 公网地址）');
    }
    _throwIfCancelled(isCancelled);
    final zipFile = await _download(url, onProgress, isCancelled);
    try {
      _verifyZipIntegrity(zipFile);
      _throwIfCancelled(isCancelled);

      // Windows legacy 目录联接：不删除/替换联接本身（保留开发期行为），
      // 退化为直接解压。
      final isLink = FileSystemEntity.typeSync(targetDir.path,
              followLinks: false,) ==
          FileSystemEntityType.link;
      final CorpusDownloadResult result;
      if (isLink) {
        final counts =
            await Isolate.run(() => _extractZipInIsolate(zipFile.path,
                targetDir.path,),);
        result = CorpusDownloadResult(
            extracted: counts.extracted, skipped: counts.skipped,);
      } else {
        result = await extractZipAtomic(zipFile, targetDir,
            isCancelled: isCancelled,);
      }
      _log.info('语料解压完成：${result.extracted} 个文件 → ${targetDir.path}');
      return result;
    } finally {
      try {
        if (zipFile.existsSync()) zipFile.deleteSync();
      } on FileSystemException catch (e) {
        _log.warning('临时 zip 清理失败: ${e.message}');
      }
    }
  }

  /// 把 [zipFile] 解压并原子替换 [targetDir]。
  ///
  /// 先解压到目标目录旁的 `corpus.tmp-<ts>` 临时目录（同 parent，rename
  /// 不跨设备），全部成功后删除旧目标目录并 rename 替换；任何失败整体
  /// 删除临时目录，不污染旧目录（半成品残留防护）。
  /// [isCancelled] 在替换前后轮询，取消时清理临时目录并抛出取消异常。
  static Future<CorpusDownloadResult> extractZipAtomic(
    File zipFile,
    Directory targetDir, {
    bool Function()? isCancelled,
  }) async {
    final stagingDir = _createStagingDir(targetDir);
    try {
      final counts =
          await Isolate.run(() => _extractZipInIsolate(zipFile.path,
              stagingDir.path,),);
      _throwIfCancelled(isCancelled);
      if (targetDir.existsSync()) {
        targetDir.deleteSync(recursive: true);
      }
      stagingDir.renameSync(targetDir.path);
      return CorpusDownloadResult(
          extracted: counts.extracted, skipped: counts.skipped,);
    } on Object {
      try {
        if (stagingDir.existsSync()) stagingDir.deleteSync(recursive: true);
      } on FileSystemException catch (e) {
        _log.warning('临时解压目录清理失败: ${e.message}');
      }
      rethrow;
    }
  }

  /// 下载 zip 到系统临时目录；手动跟随重定向并逐跳校验。
  static Future<File> _download(
    String url,
    void Function(int received, int total)? onProgress,
    bool Function()? isCancelled,
  ) async {
    var current = url;
    final client = HttpClient()..connectionTimeout = _connectTimeout;
    try {
      for (var redirect = 0; redirect <= 5; redirect++) {
        _throwIfCancelled(isCancelled);
        if (!CorpusPaths.isDownloadUrlAllowed(current)) {
          throw const FormatException('重定向地址不合法（仅允许 https 公网地址）');
        }
        final request = await client.getUrl(Uri.parse(current))
          ..followRedirects = false
          ..maxRedirects = 0;
        final response = await request.close().timeout(
              _connectTimeout,
              onTimeout: () => throw TimeoutException('连接超时（15 秒无响应）'),
            );
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
            '${Directory.systemTemp.path}${Platform.pathSeparator}'
            'corpus-download-${DateTime.now().microsecondsSinceEpoch}.zip');
        final sink = tempFile.openWrite();
        var received = 0;
        try {
          // 块间超时：流中途停滞时抛 TimeoutException，避免永久挂起。
          await for (final chunk in response.timeout(_chunkTimeout,
              onTimeout: (sink) {
            sink.addError(TimeoutException('下载停滞（30 秒无新数据）'));
            sink.close();
          },)) {
            _throwIfCancelled(isCancelled);
            received += chunk.length;
            sink.add(chunk);
            onProgress?.call(received, total);
          }
          await sink.flush();
          await sink.close();
        } on Object {
          await sink.close();
          try {
            if (tempFile.existsSync()) tempFile.deleteSync();
          } on FileSystemException catch (e) {
            _log.warning('失败下载临时 zip 清理失败: ${e.message}');
          }
          rethrow;
        }
        return tempFile;
      }
      throw const HttpException('重定向次数过多');
    } finally {
      client.close(force: true);
    }
  }

  /// 校验下载产物完整性：zip 魔数 + 大小区间。
  // TODO(P2-2): 语料发布流程确定后，固化期望 SHA-256 随版本更新。
  static void _verifyZipIntegrity(File zipFile) {
    final size = zipFile.lengthSync();
    if (size < _minZipBytes || size > _maxZipBytes) {
      throw FormatException(
          '语料包大小异常（$size 字节，允许 $_minZipBytes-$_maxZipBytes），'
          '可能不是有效的语料包');
    }
    final raf = zipFile.openSync();
    try {
      final magic = raf.readSync(4);
      final isZip = magic.length == 4 &&
          magic[0] == 0x50 &&
          magic[1] == 0x4B &&
          magic[2] == 0x03 &&
          magic[3] == 0x04;
      if (!isZip) {
        throw const FormatException('语料包格式异常（缺少 zip 魔数 PK\x03\x04）');
      }
    } finally {
      raf.closeSync();
    }
  }

  /// 在目标目录旁创建 `corpus.tmp-<ts>` 临时解压目录。
  /// 与目标目录同 parent，保证 rename 原子替换不跨设备（Android 场景）。
  static Directory _createStagingDir(Directory targetDir) {
    return Directory(
      '${targetDir.parent.path}${Platform.pathSeparator}'
      'corpus.tmp-${DateTime.now().microsecondsSinceEpoch}',
    )..createSync(recursive: true);
  }

  /// 解压本地 zip 文件到 [targetDir]（含 zip-slip 防护）。
  ///
  /// 用 [InputFileStream] 流式打开 + 条目内容按需惰性解码，
  /// 避免 readAsBytesSync 全量读入导致 zip + 解压内容同时驻留内存。
  /// Windows 保留名/尾随点空格条目与写入异常条目跳过并计数，不中断整体。
  /// 供 [_extractZipInIsolate] 在后台 isolate 中调用，也可直接单测。
  static ({int extracted, int skipped}) extractZip(
      File zipFile, Directory targetDir,) {
    final input = InputFileStream(zipFile.path);
    try {
      final archive = ZipDecoder().decodeBuffer(input);
      var count = 0;
      var skipped = 0;
      void skip(String reason, String entryName) {
        skipped += 1;
        _log.warning('跳过 zip 条目（$reason）: $entryName');
      }

      for (final entry in archive) {
        final name = entry.name.replaceAll('\\', '/');
        // 符号链接条目一律拒绝（archive 用 mode 高位或 nameOfLinkedFile 表示）；
        // 绝对路径与 .. / 盘符段一律拒绝。
        final isSymlink = (entry.mode & 0xF000) == 0xA000 ||
            entry.nameOfLinkedFile.isNotEmpty;
        if (isSymlink ||
            name.startsWith('/') ||
            name.split('/').contains('..')) {
          skip('可疑路径', entry.name);
          continue;
        }
        final segments = name.split('/').where((s) => s.isNotEmpty).toList();
        if (segments.isEmpty ||
            segments.any((s) => s.contains(':') || s == '.')) {
          skip('可疑路径', entry.name);
          continue;
        }
        // Windows 保留设备名与尾随 `.`/空格：写入必失败，直接跳过。
        if (segments.any((s) =>
            s.endsWith('.') || s.endsWith(' ') || _reservedSegment.hasMatch(s),)) {
          skip('Windows 保留名或尾随点/空格', entry.name);
          continue;
        }
        // 词法重组（已拒绝 .. / 盘符，不可能逃出目标目录）。
        final outPath =
            '${targetDir.path}${Platform.pathSeparator}${segments.join(Platform.pathSeparator)}';
        try {
          if (entry.isFile) {
            final outFile = File(outPath);
            outFile.parent.createSync(recursive: true);
            outFile.writeAsBytesSync(entry.content as List<int>);
            count += 1;
          } else {
            Directory(outPath).createSync(recursive: true);
          }
        } on FileSystemException catch (e) {
          // 同名冲突（先文件后目录）、权限、磁盘满等单条目异常：
          // 跳过并计数，不中断整体解压。
          skip('写入失败: ${e.message}', entry.name);
        }
      }
      return (extracted: count, skipped: skipped);
    } finally {
      input.closeSync();
    }
  }

  /// isolate 入口：仅传路径字符串，避免跨 isolate 传递文件句柄。
  static ({int extracted, int skipped}) _extractZipInIsolate(
          String zipPath, String targetPath,) =>
      extractZip(File(zipPath), Directory(targetPath));

  static void _throwIfCancelled(bool Function()? isCancelled) {
    if (isCancelled != null && isCancelled()) {
      throw const CorpusDownloadCancelled();
    }
  }
}
