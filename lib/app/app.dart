import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/board/view/board_page.dart';
import '../features/puzzle/view/puzzle_list_page.dart';
import '../features/board/view/human_vs_ai_page.dart';
import '../features/board/view/human_vs_llm_page.dart';
import '../features/board/view/llm_vs_llm_page.dart';
import '../features/board/model/board.dart';
import '../features/board/model/board_state.dart';
import '../features/board/viewmodel/board_vm.dart';
import '../features/board/viewmodel/game_auto_save.dart';
import '../features/board/viewmodel/game_restore.dart';
import '../features/board/view/widgets/board_widget.dart';
import '../features/board/view/widgets/side_panel.dart';
import '../features/storage/game_mode.dart';
import '../features/storage/repository.dart';
import '../features/settings/global_settings.dart';

/// 应用根 Widget。
class ChineseChessApp extends StatelessWidget {
  const ChineseChessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '中国象棋 Ultra',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF8D6E63),
        fontFamilyFallback: const ['Microsoft YaHei', 'PingFang SC', 'serif'],
      ),
      home: const MainNavigationPage(),
    );
  }
}

/// 主导航页面（二期 + 三三全局设置入口）。
///
/// 功能：
/// - 提供主要功能入口
/// - 残局选关
/// - 人机对战（内置 AI / 大模型）
/// - 大模型对战
/// - 双人对弈
/// - 全局设置（自动保存棋局开关）
class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  @override
  void initState() {
    super.initState();
    // 启动即加载持久化设置，棋盘页退出触发保存时读到的是真实开关值。
    GlobalSettings.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('中国象棋 Ultra'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _showGlobalSettings(context),
            tooltip: '全局设置',
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildNavigationButton(
              context,
              '残局选关',
              const Icon(Icons.grid_on),
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const PuzzleListPage(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildNavigationButton(
              context,
              '人机对战',
              const Icon(Icons.computer),
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const HumanVsAiPage(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildNavigationButton(
              context,
              '人机对战（大模型）',
              const Icon(Icons.psychology),
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const HumanVsLlmPage(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildNavigationButton(
              context,
              '大模型对战',
              const Icon(Icons.smart_toy),
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const LlmVsLlmPage(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildNavigationButton(
              context,
              '双人对弈',
              const Icon(Icons.people),
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const HumanVsHumanGamePage(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 全局设置弹窗：自动保存开关（改动即持久化）。
  Future<void> _showGlobalSettings(BuildContext context) async {
    // 打开前加载持久化值，避免展示进程内过期缓存。
    await GlobalSettings.instance.load();
    if (!context.mounted) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '全局设置',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SwitchListTile(
                      title: const Text('自动保存棋局'),
                      subtitle: const Text(
                        '离开棋盘或应用切后台时自动保存当前棋局；'
                        '关闭后仅点击棋盘页"保存棋局"按钮才保存。',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: GlobalSettings.instance.autoSave,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (value) {
                        GlobalSettings.instance.setAutoSave(value);
                        setSheetState(() {});
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 构建导航按钮。
  Widget _buildNavigationButton(
    BuildContext context,
    String title,
    Icon icon,
    VoidCallback onPressed,
  ) {
    return SizedBox(
      width: 200,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: icon,
        label: Text(title),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}

/// 双人对弈页面
class HumanVsHumanGamePage extends ConsumerStatefulWidget {
  const HumanVsHumanGamePage({super.key});

  @override
  ConsumerState<HumanVsHumanGamePage> createState() => _HumanVsHumanGamePageState();
}

class _HumanVsHumanGamePageState extends ConsumerState<HumanVsHumanGamePage> {
  /// 是否显示走法记录。
  bool _showMoveRecords = false;

  /// 对局计时器与已用秒数。
  Timer? _gameTimer;
  int _elapsedSeconds = 0;

  /// 对局自动保存：离开页面/应用切后台时按全局开关落存档。
  GameAutoSave? _autoSave;

  @override
  void initState() {
    super.initState();
    _startTimer();
    // 进入页面即恢复双人对弈存档（无存档则重开新局），消除全局棋盘
    // 内存残留的歧义：进入后看到的要么是存档局面，要么是新局。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _restoreOrNewGame();
    });
  }

  /// 恢复双人对弈模式存档；无存档则开新局。
  Future<void> _restoreOrNewGame() async {
    final viewModel = ref.read(boardViewModelProvider.notifier);
    final GameRepository repo;
    try {
      repo = await ref.read(gameRepositoryProvider.future);
    } on Object {
      // 存储不可用（如 path_provider 异常）：退化为新局。
      if (mounted) viewModel.newGame();
      return;
    }
    if (!mounted) return;
    _autoSave = GameAutoSave(
      mode: GameMode.humanVsHuman,
      viewModel: viewModel,
    )..adopt(repo);
    await restoreOrNewGame(
      repo: repo,
      viewModel: viewModel,
      mode: GameMode.humanVsHuman,
    );
  }

  @override
  void dispose() {
    _gameTimer?.cancel();
    _autoSave?.dispose(); // 离开页面：按全局"自动保存"开关触发棋局保存
    super.dispose();
  }

  /// 启动计时：每秒累计一次；对局结束（胜负已分）后自动暂停累计。
  void _startTimer() {
    _gameTimer?.cancel();
    _elapsedSeconds = 0;
    _gameTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (ref.read(boardViewModelProvider).isFinished) return;
      setState(() {
        _elapsedSeconds++;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('双人对弈'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _newGame,
            tooltip: '新游戏',
          ),
          IconButton(
            icon: const Icon(Icons.undo),
            onPressed: _undoMove,
            tooltip: '悔棋',
          ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveGame,
            tooltip: '保存棋局',
          ),
        ],
      ),
      body: OrientationBuilder(
        builder: (context, orientation) {
          final isPortrait = orientation == Orientation.portrait;
          if (isPortrait) {
            return Column(
              children: [
                Expanded(
                  flex: 7,
                  child: _buildBoardArea(),
                ),
                Expanded(
                  flex: 3,
                  child: _buildSidePanel(),
                ),
              ],
            );
          }
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: _buildBoardArea(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 1,
                  child: _buildSidePanel(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBoardArea() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 600,
          constraints.maxHeight.isFinite ? constraints.maxHeight : 600,
        );
        return Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: BoardWidget(onMoved: _onMoveFinished),
          ),
        );
      },
    );
  }

  Widget _buildSidePanel() {
    final state = ref.watch(boardViewModelProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 胜负结果横幅（对局结束时显示）。
            ResultBanner(state: state),
            const SizedBox(height: 8),
            const Text(
              '游戏信息',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildGameInfo(state),
            const SizedBox(height: 16),
            _buildGameControls(),
            if (_showMoveRecords) ...[
              const SizedBox(height: 8),
              const Text(
                '走法记录',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Expanded(child: MoveRecordsList(state: state)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGameInfo(BoardState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '当前回合: ',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              state.isRedTurn ? '红方' : '黑方',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: state.isRedTurn ? Colors.red : Colors.black,
              ),
            ),
            // 将军提示。
            if (state.isCheck && !state.isFinished) ...[
              const SizedBox(width: 12),
              Text(
                '将军！',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade700,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '步数: ${state.moveHistory.length}',
          style: const TextStyle(
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '用时: ${_formatTime(_elapsedSeconds)}',
          style: const TextStyle(
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '游戏模式',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('显示走法记录'),
          value: _showMoveRecords,
          contentPadding: EdgeInsets.zero,
          onChanged: (value) {
            setState(() {
              _showMoveRecords = value;
            });
          },
        ),
      ],
    );
  }

  Widget _buildGameControls() {
    return Column(
      children: [
        ElevatedButton.icon(
          icon: const Icon(Icons.refresh),
          label: const Text('新游戏'),
          onPressed: _newGame,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 40),
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          icon: const Icon(Icons.undo),
          label: const Text('悔棋'),
          onPressed: _undoMove,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 40),
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          icon: const Icon(Icons.save),
          label: const Text('保存棋局'),
          onPressed: _saveGame,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 40),
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          icon: const Icon(Icons.share),
          label: const Text('分享棋局'),
          onPressed: _shareGame,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 40),
          ),
        ),
      ],
    );
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  void _newGame() {
    ref.read(boardViewModelProvider.notifier).newGame();
    _startTimer();
  }

  void _undoMove() {
    ref.read(boardViewModelProvider.notifier).undo();
  }

  /// 保存当前棋局到双人对弈存档（覆盖上一份）。
  Future<void> _saveGame() async {
    try {
      final repo = await ref.read(gameRepositoryProvider.future);
      final data = ref.read(boardViewModelProvider.notifier).serialize();
      repo.saveGame(
        mode: GameMode.humanVsHuman,
        fen: data.fen,
        moves: data.moves,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('棋局已保存')),
      );
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存失败：本地存储不可用')),
      );
    }
  }

  void _shareGame() {
    // TODO: 实现分享棋局功能
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('分享功能开发中'),
      ),
    );
  }

  void _onMoveFinished() {
    // 走子动画完成后的回调，当前无需额外处理。
  }
}