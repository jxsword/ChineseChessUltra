import 'package:flutter/material.dart';

import '../../../shared/engine/llm_config.dart';
import '../../../shared/engine/llm_config_store.dart';
import '../../../shared/engine/llm_move_source.dart';

/// 单侧大模型配置编辑卡（人机·大模型页与大模型对战页共用）。
///
/// 只负责编辑与连通性测试；持久化由页面经 [LlmConfigStore] 完成。
class LlmConfigEditor extends StatefulWidget {
  const LlmConfigEditor({
    super.key,
    required this.title,
    required this.titleColor,
    required this.config,
    required this.onChanged,
  });

  final String title;
  final Color titleColor;
  final LlmConfig config;

  /// 任意字段变化时回调（页面据此更新内存中的配置，保存时机由页面控制）。
  final ValueChanged<LlmConfig> onChanged;

  @override
  State<LlmConfigEditor> createState() => _LlmConfigEditorState();
}

class _LlmConfigEditorState extends State<LlmConfigEditor> {
  late final TextEditingController _baseUrl;
  late final TextEditingController _apiKey;
  late final TextEditingController _model;

  bool _obscureKey = true;
  bool _testing = false;
  String _testResult = '';

  @override
  void initState() {
    super.initState();
    _baseUrl = TextEditingController(text: widget.config.baseUrl);
    _apiKey = TextEditingController(text: widget.config.apiKey);
    _model = TextEditingController(text: widget.config.model);
  }

  @override
  void didUpdateWidget(covariant LlmConfigEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 页面加载持久化配置是异步的：配置从空变为已加载时同步到输入框。
    if (widget.config.baseUrl != oldWidget.config.baseUrl &&
        widget.config.baseUrl != _baseUrl.text) {
      _baseUrl.text = widget.config.baseUrl;
    }
    if (widget.config.apiKey != oldWidget.config.apiKey &&
        widget.config.apiKey != _apiKey.text) {
      _apiKey.text = widget.config.apiKey;
    }
    if (widget.config.model != oldWidget.config.model &&
        widget.config.model != _model.text) {
      _model.text = widget.config.model;
    }
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _apiKey.dispose();
    _model.dispose();
    super.dispose();
  }

  void _notify({
    String? baseUrl,
    String? apiKey,
    String? model,
    bool? disableThinking,
  }) {
    widget.onChanged(widget.config.copyWith(
      baseUrl: baseUrl ?? _baseUrl.text,
      apiKey: apiKey ?? _apiKey.text,
      model: model ?? _model.text,
      disableThinking: disableThinking ?? widget.config.disableThinking,
    ));
  }

  Future<void> _testConnection() async {
    final config = widget.config.copyWith(
      baseUrl: _baseUrl.text,
      apiKey: _apiKey.text,
      model: _model.text,
    );
    if (!config.isConfigured) {
      setState(() => _testResult = '请先填写端点地址与模型 ID');
      return;
    }
    setState(() {
      _testing = true;
      _testResult = '正在测试…';
    });
    final (ok, message) = await LlmMoveSource.testConnection(config);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: widget.titleColor,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<LlmPreset>(
          value: _matchedPreset,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: '端点预设',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            for (final preset in LlmPreset.all)
              DropdownMenuItem(value: preset, child: Text(preset.name)),
          ],
          onChanged: (preset) {
            if (preset == null) return;
            if (preset == LlmPreset.custom) return;
            _baseUrl.text = preset.baseUrl;
            if (_model.text.trim().isEmpty) {
              _model.text = preset.exampleModel;
            }
            _notify(baseUrl: preset.baseUrl, model: _model.text);
          },
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _baseUrl,
          decoration: const InputDecoration(
            labelText: '端点地址（Base URL）',
            hintText: 'https://…/v4 或 https://…/v1',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (_) => _notify(),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _apiKey,
          obscureText: _obscureKey,
          decoration: InputDecoration(
            labelText: 'API Key',
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: IconButton(
              icon: Icon(_obscureKey ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscureKey = !_obscureKey),
            ),
          ),
          onChanged: (_) => _notify(),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _model,
          decoration: const InputDecoration(
            labelText: '模型 ID',
            hintText: '如 glm-4-flash / deepseek-chat',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (_) => _notify(),
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          title: const Text('禁用思维链（推荐）', style: TextStyle(fontSize: 13)),
          subtitle: const Text(
            '下棋只需一个着法，思维链会拖慢每手响应（思考型模型可达数十秒）。'
            '默认禁用；仅当想观察模型推理过程时才关闭本开关。',
            style: TextStyle(fontSize: 11),
          ),
          value: widget.config.disableThinking,
          contentPadding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          onChanged: (value) => _notify(disableThinking: value),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              icon: _testing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_tethering, size: 18),
              label: const Text('测试连接'),
              onPressed: _testing ? null : _testConnection,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _testResult,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: _testResult.startsWith('连接成功')
                      ? Colors.green.shade700
                      : Colors.red.shade700,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 根据当前 baseUrl 匹配预设（自定义端点回落到"自定义"）。
  LlmPreset get _matchedPreset {
    for (final preset in LlmPreset.all) {
      if (preset != LlmPreset.custom && preset.baseUrl == widget.config.baseUrl) {
        return preset;
      }
    }
    return LlmPreset.custom;
  }
}
