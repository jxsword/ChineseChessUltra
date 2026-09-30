/// PGN 大文件浏览页（多局合一 .pgns）。
///
/// 打开时在后台 isolate 建立按局偏移索引，列表分页展示
/// （Event/红黑双方摘要），点开按需解析单局并进入演示页。

import 'package:flutter/material.dart';

import '../model/corpus_scanner.dart';
import '../model/parsers/pgn_parser.dart';
import 'puzzle_detail_page.dart';

/// PGN 大文件棋局列表页。
class CorpusPgnBrowserPage extends StatefulWidget {
  final CorpusCategory category;

  const CorpusPgnBrowserPage({super.key, required this.category});

  @override
  State<CorpusPgnBrowserPage> createState() => _CorpusPgnBrowserPageState();
}

class _CorpusPgnBrowserPageState extends State<CorpusPgnBrowserPage> {
  static const _pageSize = 50;

  List<PgnGameIndex>? _index;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _index = null;
      _error = null;
    });
    try {
      final index = await CorpusRepository.scanPgnIndex(widget.category.path);
      if (!mounted) return;
      setState(() => _index = index);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  List<PgnGameIndex> get _filtered {
    final index = _index;
    if (index == null) return const [];
    final q = _query.trim();
    if (q.isEmpty) return index;
    return index
        .where((g) =>
            (g.event?.contains(q) ?? false) ||
            (g.red?.contains(q) ?? false) ||
            (g.black?.contains(q) ?? false))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.category.name;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 8),
            Text('索引扫描失败：$_error'),
          ],
        ),
      );
    }
    final index = _index;
    if (index == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final filtered = _filtered;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '搜索赛事 / 棋手（共 ${index.length} 局）',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: PagedListView(
            total: filtered.length,
            pageSize: _pageSize,
            itemBuilder: (context, i) {
              final game = filtered[i];
              final subtitle = [
                if (game.red != null) game.red!,
                if (game.black != null) game.black!,
              ].join(' vs ');
              return ListTile(
                leading: Text('${i + 1}'),
                title: Text(
                  game.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: subtitle.isEmpty
                    ? null
                    : Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openGame(game),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _openGame(PgnGameIndex game) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(content: Text('正在解析棋局…'), duration: Duration(minutes: 1)),
    );
    final puzzle = await CorpusRepository.parsePgnGameAt(
      widget.category.path,
      game,
      widget.category.source,
    );
    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    if (puzzle == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('该局解析失败（可能包含非法着法）')),
      );
      return;
    }
    await navigator.push(
      MaterialPageRoute(builder: (_) => PuzzleDetailPage(puzzle: puzzle)),
    );
  }
}

/// 简单分页列表：先展示一页，滚动到底或点击"加载更多"追加。
class PagedListView extends StatefulWidget {
  final int total;
  final int pageSize;
  final IndexedWidgetBuilder itemBuilder;

  const PagedListView({
    super.key,
    required this.total,
    required this.pageSize,
    required this.itemBuilder,
  });

  @override
  State<PagedListView> createState() => _PagedListViewState();
}

class _PagedListViewState extends State<PagedListView> {
  int _shown = 0;

  @override
  void initState() {
    super.initState();
    _shown = widget.pageSize;
  }

  @override
  void didUpdateWidget(covariant PagedListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.total != widget.total) {
      _shown = widget.pageSize;
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _shown.clamp(0, widget.total);
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: count + (count < widget.total ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= count) {
          return TextButton(
            onPressed: () =>
                setState(() => _shown = (_shown + widget.pageSize)),
            child: Text('加载更多（已显示 $count / ${widget.total}）'),
          );
        }
        return widget.itemBuilder(context, index);
      },
    );
  }
}
