import 'package:flutter/services.dart';

/// 剪贴板封装：隔离 Clipboard API，便于测试与扩展（分享/导出共用）。
class ClipboardGuard {
  ClipboardGuard._();

  static Future<void> copy(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}
