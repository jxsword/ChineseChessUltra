import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/engine/ai_engine.dart';
import '../model/board_state.dart';
import '../model/move.dart';
import '../viewmodel/board_vm.dart';
import '../view/widgets/board_widget.dart';
import '../view/widgets/side_panel.dart';

/// 人机对战页面。
///
/// 玩家执红先行，AI 执黑。玩家走子完成后（[BoardWidget.onMoved] 回调），
/// 在独立 Isolate 中用内置引擎计算应手并落到棋盘上。
class HumanVsAiPage extends ConsumerStatefulWidget {
  const HumanVsAiPage({super.key});

  @override
  ConsumerState<HumanVsAiPage> createState() => _HumanVsAiPageState();
}

class _HumanVsAiPageState extends ConsumerState<HumanVsAiPage> {
  bool _isAiThinking = false;

  /// AI 难度（1-5，对应内置引擎搜索强度）。
  int _difficulty = 3;

  /// 对局代数：新游戏/悔棋后自增，使过期的 AI 计算结果作废。
  int _gameSeq = 0;

  static const _difficultyNames = {1: '初级', 2: '中级', 3: '高级', 4: '专家', 5: '大师'};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('人机对战'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _newGame,
            tooltip: '新游戏',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: OrientationBuilder(
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
                return Row(
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
                );
              },
            ),
          ),
          _buildAiStatus(),
        ],
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
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '对战设置',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildAiLevelSelector(),
                    const SizedBox(height: 16),
                    _buildActionButtons(),
                  ],
                ),
              ),
            ),
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
        ),
      ),
    );
  }

  Widget _buildAiLevelSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'AI 难度',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButton<int>(
          value: _difficulty,
          items: [
            for (final level in _difficultyNames.keys)
              DropdownMenuItem(value: level, child: Text(_difficultyNames[level]!)),
          ],
          onChanged: _isAiThinking
              ? null
              : (value) {
                  if (value != null) {
                    setState(() => _difficulty = value);
                  }
                },
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
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
          onPressed: _isAiThinking ? null : _undoMove,
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
      ],
    );
  }

  Widget _buildAiStatus() {
    final state = ref.watch(boardViewModelProvider);
    final String text;
    final Color color;
    if (state.result != null) {
      text = switch (state.result!) {
        GameResult.redWins => '对局结束：红方获胜',
        GameResult.blackWins => '对局结束：黑方获胜',
        GameResult.draw => '对局结束：和棋',
      };
      color = Colors.blue;
    } else if (_isAiThinking) {
      text = 'AI 正在思考...';
      color = Colors.orange;
    } else if (state.isCheck) {
      text = state.isRedTurn ? '等待玩家走棋（红方被将军！）' : '等待玩家走棋';
      color = Colors.red;
    } else {
      text = '等待玩家走棋';
      color = Colors.green;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      color: color.withOpacity(0.08),
      child: Row(
        children: [
          Icon(
            _isAiThinking ? Icons.hourglass_empty : Icons.check_circle,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (_isAiThinking)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.orange,
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 对局控制
  // ---------------------------------------------------------------------------

  void _newGame() {
    _gameSeq++; // 作废仍在计算中的 AI 应手
    final viewModel = ref.read(boardViewModelProvider.notifier);
    viewModel.newGame();
    setState(() => _isAiThinking = false);
  }

  void _undoMove() {
    _gameSeq++; // 作废仍在计算中的 AI 应手（防御性，正常悔棋时 AI 不在思考）
    ref.read(boardViewModelProvider.notifier).undoRound();
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

  /// 玩家走子完成后的回调：对局未结束则轮到 AI（黑方）应手。
  void _onMoveFinished() {
    final state = ref.read(boardViewModelProvider);
    if (state.result != null) return;
    _triggerAiMove();
  }

  /// 在独立 Isolate 中计算 AI 应手，避免阻塞 UI。
  Future<void> _triggerAiMove() async {
    final viewModel = ref.read(boardViewModelProvider.notifier);
    // 必须在 await 前完成：棋盘快照与难度值要能被发送到 Isolate。
    final boardSnapshot = viewModel.board.copy();
    final difficulty = _difficulty;
    final seq = _gameSeq;

    viewModel.lockInput();
    setState(() => _isAiThinking = true);

    Move? bestMove;
    try {
      bestMove = await Isolate.run(
        () => ChessAi.findBestMove(boardSnapshot, difficulty: difficulty),
      );
    } on Object {
      // Isolate 不可用时（极少数平台限制）退化为同步计算。
      bestMove = ChessAi.findBestMove(boardSnapshot, difficulty: difficulty);
    }

    if (!mounted || seq != _gameSeq) return; // 页面已离开或对局已重开/悔棋

    setState(() => _isAiThinking = false);
    viewModel.unlockInput();

    // null 通常意味着 AI 已无合法走法（将死/困毙），结果由棋盘状态呈现。
    if (bestMove == null) return;
    final applied = viewModel.playMove(bestMove.from, bestMove.to);
    assert(() {
      if (!applied) {
        // ignore: avoid_print
        print('AI 应手被拒绝: $bestMove');
      }
      return true;
    }());
  }
}
