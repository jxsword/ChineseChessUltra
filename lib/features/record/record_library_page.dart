import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../board/model/board_state.dart';
import 'record_battle_launcher.dart';
import 'board_view_replay.dart';
import 'clipboard_guard.dart';
import 'game_record.dart';
import 'pgn_writer.dart';
import 'record_repository.dart';

/// 棋谱库：全部棋谱的列表、筛选、删除与导出。
class RecordLibraryPage extends ConsumerStatefulWidget {
  const RecordLibraryPage({super.key});

  @override
  ConsumerState<RecordLibraryPage> createState() => _RecordLibraryPageState();
}

class _RecordLibraryPageState extends ConsumerState<RecordLibraryPage> {
  List<GameRecord>? _records;
  SolveStatus? _filter;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final repo = await ref.read(recordRepositoryProvider.future);
      if (!mounted) return;
      setState(() => _records = repo.listAll());
    } on Object {
      if (mounted) setState(() => _records = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final records = _records;
    return Scaffold(
      appBar: AppBar(title: const Text('棋谱库')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Wrap(
              spacing: 8,
              children: [
                for (final status in SolveStatus.values)
                  ChoiceChip(
                    label: Text(status.label),
                    selected: _filter == status,
                    onSelected: (selected) => setState(() {
                      _filter = selected ? status : null;
                    }),
                  ),
              ],
            ),
          ),
          Expanded(
            child: records == null
                ? const Center(child: CircularProgressIndicator())
                : _buildList(records),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<GameRecord> records) {
    final filtered = _filter == null
        ? records
        : records.where((r) => r.solveStatus == _filter).toList();
    if (filtered.isEmpty) {
      return const Center(child: Text('暂无棋谱。可在对局中保存，'
          '或在残局工作室求解后自动入库。'));
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.separated(
        itemCount: filtered.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final record = filtered[index];
          return ListTile(
            leading: _statusIcon(record),
            title: Text(record.title, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${record.modeLabel} · ${_dateText(record)} · '
              '${record.moves.isEmpty ? '残局' : '${record.moves.length} 着'}'
              '${record.solutions.isEmpty
                  ? ''
                  : ' · ${record.solutions.length} 条解法'}',
              overflow: TextOverflow.ellipsis,
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (value) => _onMenu(value, record),
              itemBuilder: (context) => [
                if (canLaunchBattle(record))
                  const PopupMenuItem(
                    value: 'battle',
                    child: Text('进入对战'),
                  ),
                const PopupMenuItem(
                    value: 'pgn', child: Text('导出 PGN（复制）')),
                const PopupMenuItem(
                    value: 'share', child: Text('分享文本（复制）')),
                const PopupMenuItem(
                    value: 'file', child: Text('导出 PGN 文件')),
                const PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => RecordDetailPage(record: record),
                ),
              );
              _reload();
            },
          );
        },
      ),
    );
  }

  Widget _statusIcon(GameRecord record) => switch (record.solveStatus) {
        SolveStatus.none => const Icon(Icons.menu_book),
        SolveStatus.solved => const Icon(Icons.emoji_events, color: Colors.amber),
        SolveStatus.noSolution => const Icon(Icons.block, color: Colors.red),
        SolveStatus.timeout => const Icon(Icons.hourglass_bottom,
            color: Colors.orange),
      };

  String _dateText(GameRecord record) {
    final date = record.createdAt;
    if (date == null) return '';
    final pad = (int v) => v.toString().padLeft(2, '0');
    return '${date.year}-${pad(date.month)}-${pad(date.day)}';
  }

  Future<void> _onMenu(String value, GameRecord record) async {
    final messenger = ScaffoldMessenger.of(context);
    switch (value) {
      case 'battle':
        await launchBattle(context, record);
      case 'pgn':
        await ClipboardGuard.copy(PgnWriter.write(record));
        messenger.showSnackBar(const SnackBar(content: Text('PGN 已复制')));
      case 'share':
        await ClipboardGuard.copy(PgnWriter.writeShareText(record));
        messenger.showSnackBar(const SnackBar(content: Text('棋谱文本已复制')));
      case 'file':
        try {
          await FilePicker.platform.saveFile(
            fileName:
                'chess-record-${record.id ?? DateTime.now().millisecondsSinceEpoch}.pgn',
            bytes: utf8.encode(PgnWriter.write(record)),
          );
          messenger.showSnackBar(const SnackBar(content: Text('PGN 文件已导出')));
        } on Object catch (e) {
          messenger.showSnackBar(SnackBar(content: Text('导出失败：$e')));
        }
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('删除棋谱'),
            content: Text('确定删除「${record.title}」？不可恢复。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('删除'),
              ),
            ],
          ),
        );
        if (confirmed == true && record.id != null) {
          try {
            final repo = await ref.read(recordRepositoryProvider.future);
            repo.delete(record.id!);
          } on Object {
            // ignore: 静默失败，列表刷新会反映真实状态
          }
          _reload();
        }
    }
  }
}

/// 棋谱详情：局面重放、走法列表、解法演示、导出。
class RecordDetailPage extends StatelessWidget {
  const RecordDetailPage({super.key, required this.record});

  final GameRecord record;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(record.title, overflow: TextOverflow.ellipsis),
        actions: [
          if (canLaunchBattle(record))
            IconButton(
              icon: const Icon(Icons.sports_esports),
              tooltip: '进入对战',
              onPressed: () => launchBattle(context, record),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 5,
            child: ReplayBoardView(record: record),
          ),
          Expanded(
            flex: 3,
            child: _RecordMeta(record: record),
          ),
        ],
      ),
    );
  }
}

class _RecordMeta extends StatelessWidget {
  const _RecordMeta({required this.record});

  final GameRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.all(8),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(
            '${record.modeLabel} · ${record.solveStatus.label}'
            '${record.solutions.isEmpty ? '' : '（${record.solutions.length} 条解法'
                '${record.hasUniqueSolution ? '，唯一' : ''}）'}',
            style: theme.textTheme.titleSmall,
          ),
          if (record.result != null)
            Text(
              '结果: ${switch (record.result!) {
                GameResult.redWins => '红方胜',
                GameResult.blackWins => '黑方胜',
                GameResult.draw => '和棋',
              }}',
            ),
          if (record.initialFen != fenOfInitialStandard)
            Text('起始 FEN: ${record.initialFen}',
                style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis),
          if (record.note != null && record.note!.isNotEmpty)
            Text('备注: ${record.note}'),
          if (record.llmNote != null && record.llmNote!.isNotEmpty)
            Text('大模型注释: ${record.llmNote}'),
          const Divider(height: 24),
          for (var i = 0; i < record.solutions.length; i++) ...[
            Text('破解之法 ${i + 1}:', style: theme.textTheme.titleSmall),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(record.solutions[i].join('  ')),
            ),
          ],
          if (record.solveStatus == SolveStatus.noSolution)
            const Text('求解结论: 无解（深度上界内已证明）'),
          if (record.solveStatus == SolveStatus.timeout)
            const Text('求解结论: 限时内未找到解法'),
        ],
      ),
    );
  }

  static final String fenOfInitialStandard =
      'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR';
}
