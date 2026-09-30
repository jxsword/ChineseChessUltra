import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/board/view/board_page.dart';
import '../features/puzzle/view/puzzle_list_page.dart';
import '../features/board/view/human_vs_ai_page.dart';
import '../features/board/view/ai_vs_ai_page.dart';
import '../features/board/model/board.dart';
import '../features/board/model/board_state.dart';
import '../features/board/viewmodel/board_vm.dart';
import '../features/board/view/widgets/board_widget.dart';
import '../features/board/view/widgets/side_panel.dart';

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

/// 主导航页面（二期）。
///
/// 功能：
/// - 提供主要功能入口
/// - 残局选关
/// - 人机对战
/// - 机器对战
/// - 双人对弈
class MainNavigationPage extends StatelessWidget {
  const MainNavigationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('中国象棋 Ultra'),
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
              '机器对战',
              const Icon(Icons.auto_mode),
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AiVsAiPage(),
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

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _gameTimer?.cancel();
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

  void _saveGame() {
    // TODO: 实现保存棋局功能
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('棋局已保存'),
        backgroundColor: Colors.green,
      ),
    );
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