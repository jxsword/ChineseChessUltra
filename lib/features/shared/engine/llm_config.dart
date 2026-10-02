import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 一个大模型接入点配置（OpenAI 兼容）。
///
/// [apiKey] 属用户凭据：仅经 [LlmConfigStore] 存入安全存储，
/// 不得写入源码、示例或测试，日志输出也应回避。
class LlmConfig {
  const LlmConfig({
    this.baseUrl = '',
    this.apiKey = '',
    this.model = '',
    this.disableThinking = true,
  });

  final String baseUrl;
  final String apiKey;
  final String model;

  /// 是否禁用模型思维链（默认 true，发送 enable_thinking=false）。
  ///
  /// 下棋只需一个着法，思维链只会拖慢每手响应（思考型模型可达数十秒）；
  /// 仅当用户想观察模型推理时才应关闭本开关。仅对支持该参数的端点生效，
  /// 其他端点会忽略。
  final bool disableThinking;

  /// 端点与模型齐备即认为可调用（部分本地网关允许空 Key）。
  bool get isConfigured => baseUrl.trim().isNotEmpty && model.trim().isNotEmpty;

  /// 归一化后的 chat/completions 请求地址。
  ///
  /// 用户填根地址（推荐）或完整路径均可。
  String get requestUrl {
    var url = baseUrl.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.endsWith('/chat/completions')) return url;
    return '$url/chat/completions';
  }

  LlmConfig copyWith({
    String? baseUrl,
    String? apiKey,
    String? model,
    bool? disableThinking,
  }) =>
      LlmConfig(
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        disableThinking: disableThinking ?? this.disableThinking,
      );

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'disableThinking': disableThinking,
      };

  factory LlmConfig.fromJson(Map<String, dynamic> json) => LlmConfig(
        baseUrl: (json['baseUrl'] as String?) ?? '',
        apiKey: (json['apiKey'] as String?) ?? '',
        model: (json['model'] as String?) ?? '',
        // 旧版存档无此字段时按禁用思维链处理（下棋的合理默认）。
        disableThinking: (json['disableThinking'] as bool?) ?? true,
      );

  String serialize() => jsonEncode(toJson());

  static LlmConfig deserialize(String raw) {
    try {
      return LlmConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return const LlmConfig();
    }
  }

  /// Key 的掩码展示（配置卡片回显用，不暴露完整凭据）。
  String get maskedApiKey {
    if (apiKey.isEmpty) return '';
    if (apiKey.length <= 4) return '****';
    return '****${apiKey.substring(apiKey.length - 4)}';
  }
}

/// 常用 OpenAI 兼容端点预设（仅公开地址与示例模型 ID，不含任何凭据）。
class LlmPreset {
  const LlmPreset(this.name, this.baseUrl, this.exampleModel);

  final String name;
  final String baseUrl;
  final String exampleModel;

  static const custom = LlmPreset('自定义', '', '');

  static const List<LlmPreset> all = [
    LlmPreset('智谱 GLM', 'https://open.bigmodel.cn/api/paas/v4', 'glm-4-flash'),
    LlmPreset('DeepSeek', 'https://api.deepseek.com/v1', 'deepseek-chat'),
    LlmPreset('Kimi（Moonshot）', 'https://api.moonshot.cn/v1', 'moonshot-v1-8k'),
    LlmPreset('OpenRouter', 'https://openrouter.ai/api/v1', 'openai/gpt-4o-mini'),
    LlmPreset('OpenAI', 'https://api.openai.com/v1', 'gpt-4o-mini'),
    custom,
  ];

  /// 视觉理解模型预设（研究助手/识图专用）。
  ///
  /// 注意区分：qwen-image-*、各类"图片生成"模型走的是原生多模态生成接口，
  /// qwen-mt-* 是翻译模型，均不支持 OpenAI 兼容 chat/completions 识图用途。
  static const List<LlmPreset> visionAll = [
    LlmPreset(
      '通义千问 3.8-Max（旗舰视觉，阿里云百炼）',
      'https://dashscope.aliyuncs.com/compatible-mode/v1',
      'qwen3.8-max',
    ),
    LlmPreset(
      '通义千问 VL（阿里云百炼）',
      'https://dashscope.aliyuncs.com/compatible-mode/v1',
      'qwen-vl-max',
    ),
    LlmPreset(
      '智谱 GLM-4.5V（视觉）',
      'https://open.bigmodel.cn/api/paas/v4',
      'glm-4.5v',
    ),
    LlmPreset(
      'OpenAI GPT-4o mini（视觉）',
      'https://api.openai.com/v1',
      'gpt-4o-mini',
    ),
    LlmPreset(
      'OpenRouter（视觉）',
      'https://openrouter.ai/api/v1',
      'openai/gpt-4o-mini',
    ),
    custom,
  ];
}

/// 模型配置的持久化（按红/黑双槽位）。
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

  Future<void> saveAssistant(LlmConfig config) => _storage.write(
        key: _assistantSlot,
        value: config.serialize(),
      );

  Future<void> saveRed(LlmConfig config) => _storage.write(
        key: _redSlot,
        value: config.serialize(),
      );

  Future<void> saveBlack(LlmConfig config) => _storage.write(
        key: _blackSlot,
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
