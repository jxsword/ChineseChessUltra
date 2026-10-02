import 'package:flutter/material.dart';

import '../shared/engine/llm_config.dart';
import '../shared/engine/llm_move_source.dart';

/// 研究助手模型配置弹窗（残局求解辅助 + 棋盘识图共用）。
///
/// Key 只写入 flutter_secure_storage（与对弈模型同一安全通道），
/// 回显时掩码处理，不出现在日志与源码。
Future<void> showAssistantConfigDialog(BuildContext context) async {
  final store = LlmConfigStore();
  final current = await store.loadAssistant();
  if (!context.mounted) return;

  final baseUrlController = TextEditingController(text: current.baseUrl);
  final modelController = TextEditingController(text: current.model);
  final keyController = TextEditingController(text: current.apiKey);

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('研究助手模型'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: baseUrlController,
                decoration: const InputDecoration(
                  labelText: 'API 端点（OpenAI 兼容根地址）',
                  hintText: 'https://open.bigmodel.cn/api/paas/v4',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: modelController,
                decoration: const InputDecoration(
                  labelText: '模型 ID（识图需视觉理解模型，如 glm-4.5v / qwen-vl-max）',
                  helperText: '注意：qwen-image-* 等图片生成模型不能用于识图',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: keyController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'API Key（仅存本机安全存储）',
                  hintText: current.maskedApiKey,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<LlmPreset>(
                initialValue: null,
                hint: const Text('选择视觉模型预设'),
                items: [
                  for (final preset in LlmPreset.visionAll)
                    DropdownMenuItem(
                      value: preset,
                      child: Text('${preset.name}  ${preset.exampleModel}'),
                    ),
                ],
                onChanged: (preset) {
                  if (preset == null || preset == LlmPreset.custom) return;
                  baseUrlController.text = preset.baseUrl;
                  modelController.text = preset.exampleModel;
                  setDialogState(() {});
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(dialogContext);
              final config = LlmConfig(
                baseUrl: baseUrlController.text.trim(),
                apiKey: keyController.text.trim(),
                model: modelController.text.trim(),
              );
              final (ok, message) =
                  await LlmMoveSource.testConnection(config);
              messenger.showSnackBar(SnackBar(content: Text(message)));
              if (!ok) return;
            },
            child: const Text('测试连接'),
          ),
          FilledButton(
            onPressed: () async {
              final config = LlmConfig(
                baseUrl: baseUrlController.text.trim(),
                apiKey: keyController.text.trim(),
                model: modelController.text.trim(),
              );
              await LlmConfigStore().saveAssistant(config);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
}
