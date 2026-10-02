import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../board/viewmodel/board_vm.dart';
import '../storage/game_mode.dart';
import 'clipboard_guard.dart';
import 'game_record.dart';
import 'pgn_writer.dart';
import 'record_repository.dart';

/// "保存为棋谱"的公共入口（四期 T2）。
///
/// 所有对战模式页面共用：弹出标题/备注输入 → 组装 [GameRecord] 落库。
/// 与自动存档（saved_games，每模式一局）互不影响，棋谱库保留全部历史。
class RecordSaver {
  RecordSaver._();

  /// 弹出保存对话框并保存当前对局为棋谱。
  ///
  /// [redName]/[blackName] 供大模型对战页传入模型名等署名信息。
  static Future<void> saveCurrentGame(
    BuildContext context,
    WidgetRef ref, {
    required GameMode mode,
    String? redName,
    String? blackName,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final titleController = TextEditingController();
    final noteController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('保存为棋谱'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: '棋谱标题（留空自动生成）',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              maxLines: 2,
              decoration: const InputDecoration(labelText: '备注（可选）'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final viewModel = ref.read(boardViewModelProvider.notifier);
      final data = viewModel.serialize();
      final record = GameRecord.fromSession(
        title: titleController.text.trim().isEmpty
            ? null
            : titleController.text.trim(),
        mode: mode.name,
        finalFen: data.fen,
        moves: data.moves,
        result: ref.read(boardViewModelProvider).result,
        redName: redName,
        blackName: blackName,
        note: noteController.text.trim().isEmpty
            ? null
            : noteController.text.trim(),
      );
      final repo = await ref.read(recordRepositoryProvider.future);
      repo.save(record);
      messenger.showSnackBar(
        SnackBar(content: Text('棋谱已保存（共 ${record.moves.length} 着）')),
      );
    } on Object {
      messenger.showSnackBar(
        const SnackBar(content: Text('保存失败：本地存储不可用')),
      );
    }
  }

  /// 快捷棋谱栏按钮（对局页 AppBar / 控制区共用）。
  static Widget button(
    BuildContext context,
    WidgetRef ref, {
    required GameMode mode,
    String? redName,
    String? blackName,
  }) =>
      IconButton(
        icon: const Icon(Icons.bookmark_add_outlined),
        tooltip: '保存为棋谱',
        onPressed: () => saveCurrentGame(
          context,
          ref,
          mode: mode,
          redName: redName,
          blackName: blackName,
        ),
      );
}

/// 分享当前对局：把棋谱文本复制到剪贴板（替换三期的 TODO 占位）。
Future<void> shareCurrentGame(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final viewModel = ref.read(boardViewModelProvider.notifier);
    final data = viewModel.serialize();
    final state = ref.read(boardViewModelProvider);
    final record = GameRecord.fromSession(
      mode: GameMode.humanVsHuman.name,
      finalFen: data.fen,
      moves: data.moves,
      result: state.result,
    );
    await ClipboardGuard.copy(PgnWriter.writeShareText(record));
    messenger.showSnackBar(const SnackBar(content: Text('棋谱文本已复制到剪贴板')));
  } on Object {
    messenger.showSnackBar(const SnackBar(content: Text('分享失败：棋谱生成异常')));
  }
}
