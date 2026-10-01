import 'package:shared_preferences/shared_preferences.dart';

import 'llm_move_source.dart';

/// 对局设置（非敏感项，存 shared_preferences 即可）。
class LlmGameSettings {
  const LlmGameSettings({
    this.timeoutSeconds = 60,
    this.maxAttempts = 3,
    this.fallback = LlmFallback.builtinAi,
    this.intervalSeconds = 1,
  });

  /// 空闲超时（秒）。
  final int timeoutSeconds;

  /// 无效回复最大请求次数。
  final int maxAttempts;

  /// 模型持续失败时的降级策略。
  final LlmFallback fallback;

  /// 大模型对战每手之间的等待秒数。
  final int intervalSeconds;

  LlmGameSettings copyWith({
    int? timeoutSeconds,
    int? maxAttempts,
    LlmFallback? fallback,
    int? intervalSeconds,
  }) =>
      LlmGameSettings(
        timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
        maxAttempts: maxAttempts ?? this.maxAttempts,
        fallback: fallback ?? this.fallback,
        intervalSeconds: intervalSeconds ?? this.intervalSeconds,
      );

  Map<String, Object> toMap() => {
        'timeoutSeconds': timeoutSeconds,
        'maxAttempts': maxAttempts,
        'fallbackIndex': fallback.index,
        'intervalSeconds': intervalSeconds,
      };

  /// 从持久化字段还原：缺省/越界均回落默认值。
  factory LlmGameSettings.fromMapChecked({
    required int? timeoutSeconds,
    required int? maxAttempts,
    required int? fallbackIndex,
    required int? intervalSeconds,
  }) {
    final fallback = LlmFallback.values.length > (fallbackIndex ?? 0) &&
            (fallbackIndex ?? 0) >= 0
        ? LlmFallback.values[fallbackIndex!]
        : LlmFallback.builtinAi;
    return LlmGameSettings(
      timeoutSeconds: timeoutSeconds ?? 60,
      maxAttempts: maxAttempts ?? 3,
      fallback: fallback,
      intervalSeconds: intervalSeconds ?? 1,
    );
  }
}

/// 对局设置的持久化。
class LlmSettingsStore {
  LlmSettingsStore();

  static const _prefix = 'llm_settings_';

  Future<LlmGameSettings> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return LlmGameSettings.fromMapChecked(
        timeoutSeconds: prefs.getInt('${_prefix}timeoutSeconds'),
        maxAttempts: prefs.getInt('${_prefix}maxAttempts'),
        fallbackIndex: prefs.getInt('${_prefix}fallbackIndex'),
        intervalSeconds: prefs.getInt('${_prefix}intervalSeconds'),
      );
    } on Object {
      // 测试环境/存储不可用：返回默认值。
      return const LlmGameSettings();
    }
  }

  Future<void> save(LlmGameSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
          '${_prefix}timeoutSeconds', settings.timeoutSeconds);
      await prefs.setInt('${_prefix}maxAttempts', settings.maxAttempts);
      await prefs.setInt('${_prefix}fallbackIndex', settings.fallback.index);
      await prefs.setInt(
          '${_prefix}intervalSeconds', settings.intervalSeconds);
    } on Object {
      // 写失败不中断对局；下次修改会再尝试。
    }
  }
}
