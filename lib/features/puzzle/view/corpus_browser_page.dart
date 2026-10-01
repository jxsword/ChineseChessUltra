/// 本地棋谱库浏览页。
///
/// 一级为分类（XQF 子目录 / PGN 大文件），二级为棋局列表，
/// 支持搜索、难度筛选与按步数/难度排序；点开棋局进入演示页。
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/corpus_downloader.dart';
import '../model/corpus_paths.dart';
import '../model/corpus_scanner.dart';
import '../viewmodel/corpus_browser_vm.dart';
import 'corpus_pgn_browser_page.dart';
import 'puzzle_detail_page.dart';

/// 本地棋谱库页面。
class CorpusBrowserPage extends ConsumerStatefulWidget {
  const CorpusBrowserPage({super.key});

  @override
  ConsumerState<CorpusBrowserPage> createState() => _CorpusBrowserPageState();
}

class _CorpusBrowserPageState extends ConsumerState<CorpusBrowserPage> {
  /// 下载取消标志（进度框"取消"按钮置位，下载器各阶段间轮询）。
  bool _downloadCancelled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(corpusBrowserProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(corpusBrowserProvider);
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;
    return Scaffold(
      appBar: AppBar(
        title: const Text('本地棋谱库'),
        actions: [
          if (isDesktop)
            IconButton(
              icon: const Icon(Icons.folder_open),
              tooltip: '设置棋谱目录',
              onPressed: () => _pickCorpusDirectory(state),
            ),
        ],
      ),
      body: !state.corpusExists
          ? _CorpusMissingGuide(
              corpusPath: state.corpusPath,
              isDesktop: isDesktop,
              onDownload: _downloadCorpus,
              onPickDirectory: () => _pickCorpusDirectory(state),
            )
          : Column(
              children: [
                _buildCategoryBar(state),
                if (_isXqfSelected(state)) ...[
                  _buildControlBar(state),
                  if (state.isLoading) _buildProgressBar(state),
                ],
                Expanded(child: _buildBody(state)),
              ],
            ),
    );
  }

  bool _isXqfSelected(CorpusBrowserState state) =>
      state.selectedCategory != null &&
      state.categories[state.selectedCategory!].kind ==
          CorpusKind.xqfDirectory;

  Widget _buildCategoryBar(CorpusBrowserState state) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        itemCount: state.categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = state.categories[index];
          final selected = state.selectedCategory == index;
          return ChoiceChip(
            label: Text(category.name),
            selected: selected,
            onSelected: (_) async {
              if (category.kind == CorpusKind.pgnFile) {
                await ref
                    .read(corpusBrowserProvider.notifier)
                    .selectCategory(index);
                if (!mounted) return;
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CorpusPgnBrowserPage(category: category),
                  ),
                );
              } else {
                ref.read(corpusBrowserProvider.notifier).selectCategory(index);
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildControlBar(CorpusBrowserState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              decoration: const InputDecoration(
                isDense: true,
                hintText: '搜索棋局名称',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged:
                  ref.read(corpusBrowserProvider.notifier).setQuery,
            ),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('仅看残局'),
            selected: state.onlyEndgame,
            onSelected: (v) =>
                ref.read(corpusBrowserProvider.notifier).setOnlyEndgame(v),
          ),
          const SizedBox(width: 8),
          DropdownButton<int?>(
            value: state.difficultyFilter,
            hint: const Text('等级'),
            items: const [
              DropdownMenuItem(value: null, child: Text('全部')),
              DropdownMenuItem(value: 1, child: Text('入门')),
              DropdownMenuItem(value: 2, child: Text('初级')),
              DropdownMenuItem(value: 3, child: Text('中级')),
              DropdownMenuItem(value: 4, child: Text('高级')),
              DropdownMenuItem(value: 5, child: Text('职业')),
            ],
            onChanged: (v) =>
                ref.read(corpusBrowserProvider.notifier).setDifficultyFilter(v),
          ),
          const SizedBox(width: 8),
          DropdownButton<CorpusSortMode>(
            value: state.sortMode,
            items: const [
              DropdownMenuItem(value: CorpusSortMode.name, child: Text('按名称')),
              DropdownMenuItem(
                  value: CorpusSortMode.moves, child: Text('按步数'),),
              DropdownMenuItem(
                  value: CorpusSortMode.difficulty, child: Text('按难度'),),
            ],
            onChanged: (v) {
              if (v != null) {
                ref.read(corpusBrowserProvider.notifier).setSortMode(v);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(CorpusBrowserState state) {
    final progress = state.progress ?? 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: LinearProgressIndicator(value: progress),
          ),
          const SizedBox(width: 8),
          Text(
            '${state.parsedCount}/${state.entries.length}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  /// 下载语料包并解压到当前语料目录，带可取消进度对话框。
  ///
  /// 失败时用常驻对话框展示原因并提供"重试"入口（SnackBar 一闪而过
  /// 会引导用户走向空目录死胡同）。
  Future<void> _downloadCorpus() async {
    final targetPath = ref.read(corpusBrowserProvider).corpusPath;
    if (targetPath == null) return;
    _downloadCancelled = false;
    final status = ValueNotifier<String>('正在下载语料包…');
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              ValueListenableBuilder<String>(
                valueListenable: status,
                builder: (_, text, __) => Text(text),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  _downloadCancelled = true;
                  status.value = '正在取消…';
                },
                child: const Text('取消'),
              ),
            ],
          ),
        ),
      ),
    );
    try {
      final result = await CorpusDownloader.downloadAndExtract(
        url: CorpusPaths.downloadUrl,
        targetDir: Directory(targetPath),
        onProgress: (received, total) {
          final text = total > 0
              ? '正在下载语料包… '
                  '${(received / 1024 / 1024).toStringAsFixed(1)} / '
                  '${(total / 1024 / 1024).toStringAsFixed(1)} MB'
              : '正在下载语料包… '
                  '${(received / 1024 / 1024).toStringAsFixed(1)} MB';
          if (status.value != text) status.value = text;
        },
        isCancelled: () => _downloadCancelled,
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // 关进度框
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.skipped > 0
              ? '棋谱下载完成（${result.extracted} 个文件，'
                  '跳过 ${result.skipped} 个异常条目）'
              : '棋谱下载完成',),
          backgroundColor: Colors.green,
        ),
      );
      await ref.read(corpusBrowserProvider.notifier).load();
    } on CorpusDownloadCancelled {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // 关进度框
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已取消下载')),
      );
    } on Object catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // 关进度框
      _showDownloadFailureDialog(e);
    }
  }

  /// 常驻失败对话框：含失败原因与重试入口。
  void _showDownloadFailureDialog(Object error) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.error_outline, color: Colors.red, size: 40),
        title: const Text('语料下载失败'),
        content: Text(
          '$error\n\n请检查网络或代理设置后重试。',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _downloadCorpus(); // 重试
            },
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }

  /// 桌面端：选择自定义棋谱目录。
  Future<void> _pickCorpusDirectory(CorpusBrowserState state) async {
    final selected = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择棋谱目录',
      initialDirectory: state.corpusPath,
    );
    if (selected == null || !mounted) return;
    await ref.read(corpusBrowserProvider.notifier).pickCustomDirectory(selected);
  }

  Widget _buildBody(CorpusBrowserState state) {
    if (state.selectedCategory == null) {
      return const Center(child: Text('请选择分类'));
    }
    final items = state.visibleItems;
    if (items.isEmpty && !state.isLoading) {
      return const Center(child: Text('该分类暂无棋谱（或均解析失败）'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final (entry, puzzle) = items[index];
        return ListTile(
          leading: _difficultyBadge(puzzle.difficulty),
          title: Text(
            puzzle.title ?? entry.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${entry.source} · ${puzzle.kindLabel} · '
            '${puzzle.moves.length} 着 · ${puzzle.difficultyText}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PuzzleDetailPage(puzzle: puzzle),
            ),
          ),
        );
      },
    );
  }

  Widget _difficultyBadge(int difficulty) {
    final color = switch (difficulty) {
      1 => Colors.green,
      2 => Colors.lightGreen,
      3 => Colors.orange,
      4 => Colors.deepOrange,
      _ => Colors.red,
    };
    return CircleAvatar(
      radius: 14,
      backgroundColor: color.withValues(alpha: 0.15),
      child: Text(
        '$difficulty',
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
      ),
    );
  }
}

/// 语料目录缺失时的引导：展示当前路径，提供下载 / 选择其他目录。
class _CorpusMissingGuide extends StatelessWidget {
  const _CorpusMissingGuide({
    required this.corpusPath,
    required this.isDesktop,
    required this.onDownload,
    required this.onPickDirectory,
  });

  final String? corpusPath;
  final bool isDesktop;
  final Future<void> Function() onDownload;
  final Future<void> Function() onPickDirectory;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('未找到棋谱语料'),
            const SizedBox(height: 8),
            Text(
              '棋谱目录：${corpusPath ?? "（未解析）"}\n'
              '可从网络下载语料包，'
              '${isDesktop ? "或将已下载的语料目录放到该位置/选择其他目录" : "稍后可重新进入此页"}。',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onDownload,
              icon: const Icon(Icons.download),
              label: const Text('下载棋谱库（约 45MB，解压后约 245MB）'),
            ),
            if (isDesktop) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onPickDirectory,
                icon: const Icon(Icons.folder_open),
                label: const Text('选择其他棋谱目录'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
