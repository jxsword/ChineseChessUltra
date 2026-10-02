import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../record/record_saver.dart';
import '../model/board_state.dart';
import '../viewmodel/board_vm.dart';
import '../viewmodel/game_auto_save.dart';
import '../viewmodel/game_restore.dart';
import '../view/widgets/board_widget.dart';
import '../view/widgets/side_panel.dart';
import '../../storage/game_mode.dart';
import '../../storage/repository.dart';

/// 双人对弈页面。
///
/// 传入 [initialFen]（棋谱库"进入对战"）时以该局面开局：轮走方由 FEN
/// 决定，且不写自动存档（残局/棋谱来源不污染每模式一局的存档桶）。
class HumanVsHumanGamePage extends ConsumerStatefulWidget {
  const HumanVsHumanGamePage({super.key, this.initialFen});

  final String? initialFen;

  @override
  ConsumerState<HumanVsHumanGamePage> createState() =>
      _HumanVsHumanGamePageState();
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _restoreOrNewGame();
    });
  }

  /// 棋谱来源：以 initialFen 开局并禁用自动存档；否则恢复双人对弈存档。
  Future<void> _restoreOrNewGame() async {
    final viewModel = ref.read(boardViewModelProvider.notifier);
    if (widget.initialFen != null) {
      viewModel.newGameFromFen(widget.initialFen!);
      return;
    }
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
        title: Text(widget.initialFen == null ? '双人对弈' : '双人对弈（棋谱续战）'),
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
          RecordSaver.button(
            context,
            ref,
            mode: GameMode.humanVsHuman,
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
    // 可滚动侧栏：内容固定高度随按钮数量增长，短窗口下不再溢出。
    return Card(
      child: SingleChildScrollView(
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
                SizedBox(height: 260, child: MoveRecordsList(state: state)),
              ],
            ],
          ),
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
    final viewModel = ref.read(boardViewModelProvider.notifier);
    if (widget.initialFen != null) {
      viewModel.newGameFromFen(widget.initialFen!);
    } else {
      viewModel.newGame();
    }
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

  Future<void> _shareGame() async {
    await shareCurrentGame(context, ref);
  }

  void _onMoveFinished() {
    // 走子动画完成后的回调，当前无需额外处理。
  }
}
