import 'package:shared_preferences/shared_preferences.dart';

import 'hybrid_llm_move_source.dart';
import 'llm_move_source.dart';

export 'hybrid_llm_move_source.dart' show AdvisorMode;

/// 对局设置（非敏感项，存 shared_preferences 即可）。
class LlmGameSettings {
  const LlmGameSettings({
    this.timeoutSeconds = 60,
    this.maxAttempts = 3,
    this.fallback = LlmFallback.builtinAi,
    this.intervalSeconds = 1,
    this.advisorMode = AdvisorMode.candidate,
    this.strengthBlend = 50,
    this.advisorDifficulty = 5,
    this.redStrengthBlend = 50,
    this.blackStrengthBlend = 50,
  });

  /// 空闲超时（秒）。
  final int timeoutSeconds;

  /// 无效回复最大请求次数。
  final int maxAttempts;

  /// 模型持续失败时的降级策略。
  final LlmFallback fallback;

  /// 大模型对战每手之间的等待秒数。
  final int intervalSeconds;

  /// 引擎参谋模式。
  final AdvisorMode advisorMode;

  /// 棋力旋钮 0~100：调节候选名单宽度 / 否决阈值。
  final int strengthBlend;

  /// 参谋引擎搜索深度档（1~5，映射迭代深度 = 档 + 1）。
  final int advisorDifficulty;

  /// 大模型对战中红方的参谋强度（仅 llm_vs_llm 使用，默认同 strengthBlend）。
  final int redStrengthBlend;

  /// 大模型对战中黑方的参谋强度。
  final int blackStrengthBlend;

  LlmGameSettings copyWith({
    int? timeoutSeconds,
    int? maxAttempts,
    LlmFallback? fallback,
    int? intervalSeconds,
    AdvisorMode? advisorMode,
    int? strengthBlend,
    int? advisorDifficulty,
    int? redStrengthBlend,
    int? blackStrengthBlend,
  }) =>
      LlmGameSettings(
        timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
        maxAttempts: maxAttempts ?? this.maxAttempts,
        fallback: fallback ?? this.fallback,
        intervalSeconds: intervalSeconds ?? this.intervalSeconds,
        advisorMode: advisorMode ?? this.advisorMode,
        strengthBlend: strengthBlend ?? this.strengthBlend,
        advisorDifficulty: advisorDifficulty ?? this.advisorDifficulty,
        redStrengthBlend: redStrengthBlend ?? this.redStrengthBlend,
        blackStrengthBlend: blackStrengthBlend ?? this.blackStrengthBlend,
      );

  Map<String, Object> toMap() => {
        'timeoutSeconds': timeoutSeconds,
        'maxAttempts': maxAttempts,
        'fallbackIndex': fallback.index,
        'intervalSeconds': intervalSeconds,
        'advisorModeIndex': advisorMode.index,
        'strengthBlend': strengthBlend,
        'advisorDifficulty': advisorDifficulty,
        'redStrengthBlend': redStrengthBlend,
        'blackStrengthBlend': blackStrengthBlend,
      };

  /// 从持久化字段还原：缺省/越界均回落默认值。
  factory LlmGameSettings.fromMapChecked({
    required int? timeoutSeconds,
    required int? maxAttempts,
    required int? fallbackIndex,
    required int? intervalSeconds,
    required int? advisorModeIndex,
    required int? strengthBlend,
    required int? advisorDifficulty,
    required int? redStrengthBlend,
    required int? blackStrengthBlend,
  }) {
    final fallback = LlmFallback.values.length > (fallbackIndex ?? 0) &&
            (fallbackIndex ?? 0) >= 0
        ? LlmFallback.values[fallbackIndex!]
        : LlmFallback.builtinAi;
    final advisor = AdvisorMode.values.length > (advisorModeIndex ?? 0) &&
            (advisorModeIndex ?? 0) >= 0
        ? AdvisorMode.values[advisorModeIndex!]
        : AdvisorMode.candidate;
    return LlmGameSettings(
      // 数值越界一律 clamp：timeout 0 会让每次调用秒失败、
      // maxAttempts 0 会跳过全部重试。
      timeoutSeconds: (timeoutSeconds ?? 60).clamp(5, 600),
      maxAttempts: (maxAttempts ?? 3).clamp(1, 10),
      fallback: fallback,
      intervalSeconds: (intervalSeconds ?? 1).clamp(0, 60),
      advisorMode: advisor,
      strengthBlend: (strengthBlend ?? 50).clamp(0, 100),
      advisorDifficulty: (advisorDifficulty ?? 5).clamp(1, 5),
      redStrengthBlend: (redStrengthBlend ?? strengthBlend ?? 50).clamp(0, 100),
      blackStrengthBlend:
          (blackStrengthBlend ?? strengthBlend ?? 50).clamp(0, 100),
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
        advisorModeIndex: prefs.getInt('${_prefix}advisorModeIndex'),
        strengthBlend: prefs.getInt('${_prefix}strengthBlend'),
        advisorDifficulty: prefs.getInt('${_prefix}advisorDifficulty'),
        redStrengthBlend: prefs.getInt('${_prefix}redStrengthBlend'),
        blackStrengthBlend: prefs.getInt('${_prefix}blackStrengthBlend'),
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
      await prefs.setInt(
          '${_prefix}advisorModeIndex', settings.advisorMode.index);
      await prefs.setInt('${_prefix}strengthBlend', settings.strengthBlend);
      await prefs.setInt(
          '${_prefix}advisorDifficulty', settings.advisorDifficulty);
      await prefs.setInt(
          '${_prefix}redStrengthBlend', settings.redStrengthBlend);
      await prefs.setInt(
          '${_prefix}blackStrengthBlend', settings.blackStrengthBlend);
    } on Object {
      // 写失败不中断对局；下次修改会再尝试。
    }
  }
}
