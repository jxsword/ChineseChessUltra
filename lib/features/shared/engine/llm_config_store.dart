import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'llm_config.dart';

/// 模型配置的持久化（按红/黑双槽位 + 研究助手槽位）。
///
/// 配置整体（含 Key）走 flutter_secure_storage（Windows 为 DPAPI 加密），
/// 不落明文偏好存储。
class LlmConfigStore {
  LlmConfigStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _redSlot = 'llm_config_red';
  static const _blackSlot = 'llm_config_black';

  /// 四期"研究助手模型"槽位：残局求解辅助与棋盘图片识图共用
  /// （需支持视觉的模型才可识图，纯文本模型仅可做求解辅助）。
  static const _assistantSlot = 'llm_config_assistant';

  Future<LlmConfig> loadRed() => _load(_redSlot);
  Future<LlmConfig> loadBlack() => _load(_blackSlot);

  Future<LlmConfig> loadAssistant() => _load(_assistantSlot);

  Future<void> saveRed(LlmConfig config) => _storage.write(
        key: _redSlot,
        value: config.serialize(),
      );

  Future<void> saveBlack(LlmConfig config) => _storage.write(
        key: _blackSlot,
        value: config.serialize(),
      );

  Future<void> saveAssistant(LlmConfig config) => _storage.write(
        key: _assistantSlot,
        value: config.serialize(),
      );

  Future<LlmConfig> _load(String slot) async {
    try {
      final raw = await _storage.read(key: slot);
      if (raw == null || raw.isEmpty) return const LlmConfig();
      return LlmConfig.deserialize(raw);
    } on Object {
      // 安全存储不可用时按未配置处理，页面会引导用户重新填写。
      return const LlmConfig();
    }
  }
}
