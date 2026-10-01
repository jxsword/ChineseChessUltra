/// 棋谱语料路径解析与下载源配置。
///
/// 各平台棋谱目录的解析优先级：
/// 1. 用户设置目录（桌面端可在棋谱库页选择，持久化到 SharedPreferences）；
/// 2. 旧版相对路径 `corpus`（Windows 开发期目录联接，存在则沿用）；
/// 3. 平台默认目录：
///    - 桌面（Windows/macOS/Linux）：`<文档>/ChineseChessUltra/corpus`
///    - Android：应用专属外置目录 `<外置存储>/Android/data/<包名>/files/corpus`
///      （外置存储、文件管理器可见、无需权限、卸载自清、不打入 APK）
///
/// Android 首次启动检测目录为空时，由棋谱库页引导从 [downloadUrl]
/// 下载语料包并解压到该目录。

library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 棋谱路径与下载源配置。
class CorpusPaths {
  CorpusPaths._();

  /// SharedPreferences 中保存用户自定义棋谱目录的键。
  static const userPathPrefKey = 'corpus.userPath';

  /// 旧版相对路径（Windows 开发期目录联接）。
  static const legacyDirName = 'corpus';

  /// 语料包下载地址（GitHub Release 附件，qp-corpus 语料仓库打 zip）。
  ///
  /// 发布语料时：在 qp-corpus 仓库打 tag 并上传 qp-corpus.zip 附件即可，
  /// `releases/latest/download/...` 永远指向最新一版。
  static const downloadUrl =
      'https://github.com/jxsword/qp-corpus/releases/latest/download/qp-corpus.zip';

  /// 校验下载 URL 是否允许。
  ///
  /// 安全约束：仅允许 https；拒绝 localhost、环回、私有与保留地址、
  /// mDNS 域名（防止 SSRF 把请求打向内网）。
  static bool isDownloadUrlAllowed(String url) {
    final Uri uri;
    try {
      uri = Uri.parse(url);
    } on FormatException {
      return false;
    }
    if (uri.scheme.toLowerCase() != 'https') return false;
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return false;
    if (_isBlockedHost(host)) return false;
    return true;
  }

  static bool _isBlockedHost(String host) {
    if (host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        host.endsWith('.internal')) {
      return true;
    }
    // IPv4 字面量：拒绝环回/私有/链路本地/保留段。
    final v4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');
    final m = v4.firstMatch(host);
    if (m != null) {
      final octets =
          m.groups([1, 2, 3, 4]).map((g) => int.parse(g!)).toList();
      if (octets.any((o) => o < 0 || o > 255)) return true;
      final a = octets[0], b = octets[1];
      if (a == 0 || a == 10 || a == 127) return true; // 环回/私有/保留
      if (a == 169 && b == 254) return true; // 链路本地
      if (a == 172 && b >= 16 && b <= 31) return true; // 私有
      if (a == 192 && b == 168) return true; // 私有
      if (a >= 224) return true; // 组播/保留
      return false;
    }
    // IPv6 字面量：拒绝环回、链路本地（fe80::/10）、唯一本地（fc00::/7）。
    if (host.contains(':')) {
      final h = host.replaceFirst('[', '').replaceFirst(']', '');
      if (h == '::' || h == '::1') return true;
      if (h.startsWith('fe8') || h.startsWith('fe9') || h.startsWith('fea') ||
          h.startsWith('feb')) {
        return true;
      }
      if (h.startsWith('fc') || h.startsWith('fd')) return true;
    }
    return false;
  }

  /// 按优先级解析棋谱目录（见类注释）。
  static Future<Directory> resolveDirectory({String? userSetting}) async {
    if (userSetting != null && userSetting.trim().isNotEmpty) {
      return Directory(userSetting.trim());
    }
    final legacy = Directory(legacyDirName);
    if (legacy.existsSync()) return legacy; // Windows 开发期联接
    return defaultDirectory();
  }

  /// 平台默认棋谱目录（可能尚不存在，由引导下载/手动放置创建）。
  static Future<Directory> defaultDirectory() async {
    if (Platform.isAndroid) {
      final ext = await getExternalStorageDirectory();
      final base = ext?.path ??
          (await getApplicationDocumentsDirectory()).path; // 兜底
      return Directory('$base${Platform.pathSeparator}$legacyDirName');
    }
    final docs = await getApplicationDocumentsDirectory();
    return Directory(
        '${docs.path}${Platform.pathSeparator}ChineseChessUltra'
        '${Platform.pathSeparator}$legacyDirName');
  }
}
