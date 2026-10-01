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
    final m = _ipv4Pattern.firstMatch(host);
    if (m != null) {
      final groups = m.groups([1, 2, 3, 4]).map((g) => g!).toList();
      // 八进制分段（多段前导 0，如 0177.0.0.1）语义有歧义，一律拒绝。
      if (groups.any((g) => g.length > 1 && g.startsWith('0'))) return true;
      final octets = groups.map(int.parse).toList();
      if (octets.any((o) => o < 0 || o > 255)) return true;
      return _isBlockedV4(octets);
    }
    // 纯十进制 / 0x 十六进制整数形式的 IPv4（如 2130706433 / 0x7f000001）。
    final asInt = _parseIntegerHost(host);
    if (asInt != null) {
      if (asInt > 0xFFFFFFFF) return true;
      return _isBlockedV4([
        (asInt >> 24) & 0xFF,
        (asInt >> 16) & 0xFF,
        (asInt >> 8) & 0xFF,
        asInt & 0xFF,
      ]);
    }
    // IPv6 字面量：拒绝环回、链路本地（fe80::/10）、唯一本地（fc00::/7）。
    if (host.contains(':')) {
      final h = host.replaceFirst('[', '').replaceFirst(']', '');
      if (h == '::' || h == '::1') return true;
      // IPv4-mapped IPv6（::ffff:0:0/96）：还原成 v4 判段。
      if (h.toLowerCase().startsWith('::ffff:')) {
        final mapped = _parseMappedV4(h.substring('::ffff:'.length));
        if (mapped == null) return true; // 形式存疑的 mapped 段一律拒绝
        return _isBlockedV4(mapped);
      }
      if (h.startsWith('fe8') || h.startsWith('fe9') || h.startsWith('fea') ||
          h.startsWith('feb')) {
        return true;
      }
      if (h.startsWith('fc') || h.startsWith('fd')) return true;
    }
    return false;
  }

  // 段长不设 1-3 上限：让 0177.0.0.1 之类八进制歧义形式先命中本模式，
  // 再由前导零规则拒绝，而不是落空后被放行。
  static final _ipv4Pattern = RegExp(r'^(\d+)\.(\d+)\.(\d+)\.(\d+)$');

  /// IPv4 段判定（环回/私有/链路本地/组播与保留段）。
  static bool _isBlockedV4(List<int> octets) {
    final a = octets[0], b = octets[1];
    if (a == 0 || a == 10 || a == 127) return true;
    if (a == 169 && b == 254) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 192 && b == 168) return true;
    if (a >= 224) return true;
    return false;
  }

  /// 解析十进制/十六进制整数形式的 host；非整数形式返回 null。
  static int? _parseIntegerHost(String host) {
    if (RegExp(r'^\d+$').hasMatch(host)) {
      return int.tryParse(host);
    }
    final lower = host.toLowerCase();
    if (lower.length > 2 &&
        lower.startsWith('0x') &&
        RegExp(r'^0x[0-9a-f]+$').hasMatch(lower)) {
      return int.tryParse(lower.substring(2), radix: 16);
    }
    return null;
  }

  /// 解析 `::ffff:` 后的 IPv4 部分（点分十进制或两组十六进制）。
  static List<int>? _parseMappedV4(String rest) {
    final m = _ipv4Pattern.firstMatch(rest);
    if (m != null) {
      final octets =
          m.groups([1, 2, 3, 4]).map((g) => int.parse(g!)).toList();
      if (octets.any((o) => o > 255)) return null;
      return octets;
    }
    final hex =
        RegExp(r'^([0-9a-fA-F]{1,4}):([0-9a-fA-F]{1,4})$').firstMatch(rest);
    if (hex != null) {
      final hi = int.parse(hex.group(1)!, radix: 16);
      final lo = int.parse(hex.group(2)!, radix: 16);
      return [(hi >> 8) & 0xFF, hi & 0xFF, (lo >> 8) & 0xFF, lo & 0xFF];
    }
    return null;
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
