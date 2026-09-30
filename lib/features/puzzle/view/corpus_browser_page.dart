/// 本地棋谱库浏览页。
///
/// 一级为分类（XQF 子目录 / PGN 大文件），二级为棋局列表，
/// 支持搜索、难度筛选与按步数/难度排序；点开棋局进入演示页。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('本地棋谱库')),
      body: !state.corpusExists
          ? const _CorpusMissingGuide()
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
                Navigator.push(
                  context,
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
                  value: CorpusSortMode.moves, child: Text('按步数')),
              DropdownMenuItem(
                  value: CorpusSortMode.difficulty, child: Text('按难度')),
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
            '${entry.category} · ${puzzle.moves.length} 着 · ${puzzle.difficultyText}',
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
      backgroundColor: color.withOpacity(0.15),
      child: Text(
        '$difficulty',
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
      ),
    );
  }
}

/// 语料目录缺失时的引导。
class _CorpusMissingGuide extends StatelessWidget {
  const _CorpusMissingGuide();

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
            const Text('未找到本地棋谱语料目录'),
            const SizedBox(height: 8),
            const Text(
              '语料保存在 E:\\ssy_proj\\qp，项目根需存在其目录联接：\n'
              'mklink /J corpus E:\\ssy_proj\\qp\n'
              '（详见 docs/qp_parse.md）',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
