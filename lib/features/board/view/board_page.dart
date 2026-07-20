import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/constants.dart';
import '../../storage/repository.dart';
import '../viewmodel/board_vm.dart';
import 'widgets/board_widget.dart';
import 'widgets/side_panel.dart';

/// 棋盘主页面。
class BoardPage extends ConsumerStatefulWidget {
  const BoardPage({super.key});

  @override
  ConsumerState<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends ConsumerState<BoardPage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 启动时尝试恢复（异步，不阻塞 UI）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(boardLifecycleProvider.notifier).onStarted();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    // App 进入 paused/inactive 时强制保存当前局面。
    if (lifecycleState == AppLifecycleState.paused ||
        lifecycleState == AppLifecycleState.inactive) {
      ref.read(boardLifecycleProvider.notifier).onPaused();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '手动保存',
            icon: const Icon(Icons.save_outlined),
            onPressed: () async {
              await ref.read(boardLifecycleProvider.notifier).saveNow();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('棋局已保存')),
              );
            },
          ),
        ],
      ),
      body: OrientationBuilder(
        builder: (context, orientation) {
          final isPortrait = orientation == Orientation.portrait;
          if (isPortrait) {
            // 竖屏：棋盘居中，面板在底部可展开。
            return Column(
              children: [
                Expanded(
                  flex: 7,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: _BoardArea(onMoved: _onMoved),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: SidePanel(onNewGame: _onNewGame),
                  ),
                ),
              ],
            );
          }
          // 横屏：左棋盘，右面板。
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: _BoardArea(onMoved: _onMoved),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 1,
                  child: SidePanel(onNewGame: _onNewGame),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _onMoved() {
    ref.read(boardLifecycleProvider.notifier).onMoveFinished();
  }

  void _onNewGame() {
    ref.read(boardViewModelProvider.notifier).newGame();
    ref.read(boardLifecycleProvider.notifier).forgetCurrentGame();
  }
}

class _BoardArea extends StatelessWidget {
  const _BoardArea({required this.onMoved});

  final VoidCallback onMoved;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 棋盘为正方形（边长 = min(width, height)）。
        final side = constraints.maxWidth < constraints.maxHeight
            ? constraints.maxWidth
            : constraints.maxHeight;
        return Center(
          child: SizedBox(
            width: side,
            height: side,
            child: BoardWidget(onMoved: onMoved),
          ),
        );
      },
    );
  }
}

/// 处理棋局保存/恢复生命周期的 Notifier。
///
/// 用一个独立 Notifier 把存储与 UI 解耦，UI 只需在合适时机调用其方法。
class BoardLifecycleNotifier extends Notifier<bool> {
  int? _currentGameId;
  bool _restored = false;

  @override
  bool build() => false;

  Future<GameRepository> _repo() async {
    return ref.read(gameRepositoryProvider.future);
  }

  /// 启动时调用：从存储恢复最近一局（若无则保持初始局面）。
  ///
  /// 异步执行，避免阻塞 UI；限制最多恢复 50 步。
  Future<void> onStarted() async {
    if (_restored) return;
    _restored = true;
    try {
      final repo = await _repo();
      final latest = repo.loadLatest();
      if (latest != null) {
        _currentGameId = latest.id;

        // 限制恢复步数，避免长局导致阻塞。
        final moves = latest.moves.length > 50
            ? latest.moves.sublist(0, 50)
            : latest.moves;

        ref.read(boardViewModelProvider.notifier).restore(
              fen: latest.fen,
              moves: moves,
            );
      }
    } on Object catch (e) {
      // ignore: avoid_print
      print('Restore failed: $e');
    }
  }

  /// 走子完成后调用：写入数据库。
  Future<void> onMoveFinished() async {
    await _persist();
  }

  /// 手动保存。
  Future<void> saveNow() async {
    await _persist();
  }

  /// App 进入后台时调用。
  Future<void> onPaused() async {
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final vm = ref.read(boardViewModelProvider.notifier);
      final snapshot = vm.serialize();
      final repo = await _repo();
      _currentGameId = repo.saveGame(
        existingId: _currentGameId,
        fen: snapshot.fen,
        moves: snapshot.moves,
      );
    } on Object catch (e) {
      // ignore: avoid_print
      print('Persist failed: $e');
    }
  }

  /// 新游戏：清空当前 id，使下一次走子写入新条。
  void forgetCurrentGame() {
    _currentGameId = null;
  }
}

final boardLifecycleProvider =
    NotifierProvider<BoardLifecycleNotifier, bool>(
  BoardLifecycleNotifier.new,
);
