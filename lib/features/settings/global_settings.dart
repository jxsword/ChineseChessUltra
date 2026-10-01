import 'package:shared_preferences/shared_preferences.dart';

/// 全局设置（shared_preferences 持久化 + 进程内缓存）。
///
/// 缓存的意义：棋盘页 dispose 时不能 await（ Riverpod 禁用 ref、
/// 同步退出路径），触发保存时直接读内存开关。
class GlobalSettings {
  GlobalSettings._();

  static final GlobalSettings instance = GlobalSettings._();

  static const _autoSaveKey = 'global_auto_save';

  /// 离开棋盘/应用切后台时自动保存当前棋局。默认开启。
  bool autoSave = true;

  /// 应用启动时调用一次；失败按默认值（开启）。
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      autoSave = prefs.getBool(_autoSaveKey) ?? true;
    } on Object {
      autoSave = true;
    }
  }

  Future<void> setAutoSave(bool value) async {
    autoSave = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_autoSaveKey, value);
    } on Object {
      // 写失败保留内存值；下次进入设置页会重新加载。
    }
  }
}
