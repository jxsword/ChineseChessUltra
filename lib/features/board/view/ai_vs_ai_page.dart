import 'dart:async';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/engine/ai_engine.dart';
import '../model/board_state.dart';
import '../model/move.dart';
import '../viewmodel/board_vm.dart';
import '../view/widgets/board_widget.dart';
import '../view/widgets/side_panel.dart';

/// AI对战页面：红黑双方均由内置引擎驱动，棋盘实时反映每一步应手。
class AiVsAiPage extends ConsumerStatefulWidget {
  const AiVsAiPage({super.key});

  @override
  ConsumerState<AiVsAiPage> createState() => _AiVsAiPageState();
}

class _AiVsAiPageState extends ConsumerState<AiVsAiPage> {
  bool _isRunning = false;
  bool _isPaused = false;
  String _currentStatus = '等待开始';
  String _lastMove = '';

  /// 双方 AI 难度（1-5，对应内置引擎搜索强度）。
  int _redLevel = 3;
  int _blackLevel = 3;

  /// 走棋间隔（秒）。
  int _intervalSeconds = 2;

  /// 新对局结束后自动开始。
  bool _autoStart = false;

  /// 对局代数：暂停/停止/新游戏后自增，使过期的 AI 计算与延时续走作废。
  int _seq = 0;

  Timer? _nextMoveTimer;

  static const _difficultyNames = {1: '初级', 2: '中级', 3: '高级', 4: '专家', 5: '大师'};

  @override
  void dispose() {
    _seq++; // 作废仍在计算中的 AI 应手
    _nextMoveTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI对战'),
        actions: [
          IconButton(
            icon: Icon(_isRunning && !_isPaused ? Icons.pause : Icons.play_arrow),
            onPressed: _togglePlayPause,
            tooltip: _isRunning && !_isPaused ? '暂停' : '开始',
          ),
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
          _buildStatusPanel(),
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
            child: const BoardWidget(),
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
                      'AI 设置',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildAiSettings(),
                    const SizedBox(height: 16),
                    _buildGameSettings(),
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

  Widget _buildAiSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '红方 AI',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.red,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButton<int>(
          value: _redLevel,
          items: [
            for (final level in _difficultyNames.keys)
              DropdownMenuItem(value: level, child: Text(_difficultyNames[level]!)),
          ],
          onChanged: _isRunning
              ? null
              : (value) {
                  if (value != null) {
                    setState(() => _redLevel = value);
                  }
                },
        ),
        const SizedBox(height: 16),
        const Text(
          '黑方 AI',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButton<int>(
          value: _blackLevel,
          items: [
            for (final level in _difficultyNames.keys)
              DropdownMenuItem(value: level, child: Text(_difficultyNames[level]!)),
          ],
          onChanged: _isRunning
              ? null
              : (value) {
                  if (value != null) {
                    setState(() => _blackLevel = value);
                  }
                },
        ),
      ],
    );
  }

  Widget _buildGameSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '游戏设置',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('自动开始'),
          value: _autoStart,
          onChanged: (value) {
            setState(() => _autoStart = value);
          },
        ),
        SwitchListTile(
          title: const Text('显示思考过程'),
          value: false,
          onChanged: (value) {
            // TODO: 实现思考过程显示
          },
        ),
        ListTile(
          title: const Text('走棋间隔'),
          trailing: DropdownButton<int>(
            value: _intervalSeconds,
            items: const [
              DropdownMenuItem(value: 1, child: Text('1秒')),
              DropdownMenuItem(value: 2, child: Text('2秒')),
              DropdownMenuItem(value: 3, child: Text('3秒')),
              DropdownMenuItem(value: 5, child: Text('5秒')),
            ],
            onChanged: _isRunning
                ? null
                : (value) {
                    if (value != null) {
                      setState(() => _intervalSeconds = value);
                    }
                  },
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        ElevatedButton.icon(
          icon: const Icon(Icons.play_arrow),
          label: const Text('开始对战'),
          onPressed: _isRunning ? null : _startBattle,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 40),
            backgroundColor: Colors.green,
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          icon: const Icon(Icons.pause),
          label: const Text('暂停'),
          onPressed: (_isRunning && !_isPaused) ? _pauseBattle : null,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 40),
            backgroundColor: Colors.orange,
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          icon: const Icon(Icons.stop),
          label: const Text('停止'),
          onPressed: _isRunning ? _stopBattle : null,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 40),
            backgroundColor: Colors.red,
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          icon: const Icon(Icons.refresh),
          label: const Text('新游戏'),
          onPressed: _newGame,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 40),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusPanel() {
    final state = ref.watch(boardViewModelProvider);
    final thinking = _isRunning && !_isPaused;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.05),
        border: Border(
          top: BorderSide(color: Colors.blue.withOpacity(0.2)),
        ),
      ),
      child: Row(
        children: [
          Icon(
            thinking ? Icons.hourglass_empty : Icons.check_circle,
            color: thinking ? Colors.blue : Colors.green,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentStatus,
                  style: TextStyle(
                    color: thinking ? Colors.blue : Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_lastMove.isNotEmpty)
                  Text(
                    '最后走法: $_lastMove',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                if (state.isCheck && !state.isFinished)
                  Text(
                    '将军！',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade700,
                    ),
                  ),
              ],
            ),
          ),
          if (thinking)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.blue,
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 对局控制
  // ---------------------------------------------------------------------------

  void _startBattle() {
    final viewModel = ref.read(boardViewModelProvider.notifier);
    viewModel.lockInput(); // 对战期间禁止人工干预棋盘
    _seq++;
    setState(() {
      _isRunning = true;
      _isPaused = false;
      _currentStatus = 'AI 正在分析局面...';
    });
    _runAiTurn();
  }

  void _pauseBattle() {
    _seq++; // 作废挂起的续走与计算结果
    _nextMoveTimer?.cancel();
    setState(() {
      _isPaused = true;
      _currentStatus = '已暂停';
    });
  }

  void _stopBattle() {
    _seq++;
    _nextMoveTimer?.cancel();
    ref.read(boardViewModelProvider.notifier).unlockInput();
    setState(() {
      _isRunning = false;
      _isPaused = false;
      _currentStatus = '已停止';
    });
  }

  void _newGame() {
    _seq++;
    _nextMoveTimer?.cancel();
    ref.read(boardViewModelProvider.notifier).newGame();
    setState(() {
      _isRunning = false;
      _isPaused = false;
      _currentStatus = '等待开始';
      _lastMove = '';
    });
    if (_autoStart) {
      _startBattle();
    }
  }

  void _togglePlayPause() {
    if (_isRunning && !_isPaused) {
      _pauseBattle();
    } else if (_isRunning && _isPaused) {
      // 从暂停恢复：重开输入锁并继续走子循环。
      ref.read(boardViewModelProvider.notifier).lockInput();
      setState(() {
        _isPaused = false;
        _currentStatus = 'AI 正在分析局面...';
      });
      _runAiTurn();
    } else {
      _startBattle();
    }
  }

  /// 执行一个 AI 回合：在独立 Isolate 中计算当前走子方（由棋盘状态决定红/黑）
  /// 的最佳应手，落子后按设定间隔调度下一回合。
  Future<void> _runAiTurn() async {
    if (!mounted) return;
    final seq = _seq;

    final viewModel = ref.read(boardViewModelProvider.notifier);
    final state = ref.read(boardViewModelProvider);
    if (state.isFinished) {
      _finishWithResult();
      return;
    }
    final redTurn = state.isRedTurn;
    setState(() {
      _currentStatus = redTurn ? '红方 AI 思考中...' : '黑方 AI 思考中...';
    });

    // 必须在 await 前完成：棋盘快照与难度值要能被发送到 Isolate。
    final boardSnapshot = viewModel.board.copy();
    final level = redTurn ? _redLevel : _blackLevel;

    Move? bestMove;
    try {
      bestMove = await Isolate.run(
        () => ChessAi.findBestMove(boardSnapshot, difficulty: level),
      );
    } on Object {
      // Isolate 不可用时（极少数平台限制）退化为同步计算。
      bestMove = ChessAi.findBestMove(boardSnapshot, difficulty: level);
    }

    if (!mounted || seq != _seq) return; // 页面已离开或已被暂停/停止/重开

    // null 意味着当前方无合法走法（将死/困毙），结果由棋盘状态呈现。
    if (bestMove == null) {
      _finishWithResult();
      return;
    }

    final applied = viewModel.playMove(bestMove.from, bestMove.to);
    if (!applied) {
      // 引擎给出的应手意外非法：终止对战，避免死循环。
      _seq++;
      ref.read(boardViewModelProvider.notifier).unlockInput();
      setState(() {
        _isRunning = false;
        _currentStatus = '对局异常终止';
      });
      return;
    }

    // 走法记录最后一手自带棋子信息，用于生成中文记法。
    final lastMove = ref.read(boardViewModelProvider).moveHistory.last;
    final notation = lastMove.chineseNotation(lastMove.piece!);
    setState(() {
      _lastMove = '${redTurn ? '红方' : '黑方'} $notation';
    });

    final newState = ref.read(boardViewModelProvider);
    if (newState.isFinished) {
      _finishWithResult();
      return;
    }

    _nextMoveTimer = Timer(Duration(seconds: _intervalSeconds), () {
      if (!mounted || seq != _seq) return;
      _runAiTurn();
    });
  }

  void _finishWithResult() {
    _seq++;
    _nextMoveTimer?.cancel();
    ref.read(boardViewModelProvider.notifier).unlockInput();
    final result = ref.read(boardViewModelProvider).result;
    setState(() {
      _isRunning = false;
      _isPaused = false;
      _currentStatus = switch (result) {
        GameResult.redWins => '对局结束：红方获胜',
        GameResult.blackWins => '对局结束：黑方获胜',
        GameResult.draw => '对局结束：和棋',
        null => '对局结束',
      };
    });
  }
}
