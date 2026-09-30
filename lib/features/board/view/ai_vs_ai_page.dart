import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/board_state.dart';
import '../viewmodel/board_vm.dart';
import '../view/widgets/board_widget.dart';
import '../view/widgets/side_panel.dart';

/// AI对战页面
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI对战'),
        actions: [
          IconButton(
            icon: Icon(_isRunning ? Icons.pause : Icons.play_arrow),
            onPressed: _togglePlayPause,
            tooltip: _isRunning ? '暂停' : '开始',
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
          value: 3,
          items: const [
            DropdownMenuItem(value: 1, child: Text('初级')),
            DropdownMenuItem(value: 2, child: Text('中级')),
            DropdownMenuItem(value: 3, child: Text('高级')),
            DropdownMenuItem(value: 4, child: Text('专家')),
            DropdownMenuItem(value: 5, child: Text('大师')),
          ],
          onChanged: (value) {
            // TODO: 实现红方AI难度设置
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
          value: 3,
          items: const [
            DropdownMenuItem(value: 1, child: Text('初级')),
            DropdownMenuItem(value: 2, child: Text('中级')),
            DropdownMenuItem(value: 3, child: Text('高级')),
            DropdownMenuItem(value: 4, child: Text('专家')),
            DropdownMenuItem(value: 5, child: Text('大师')),
          ],
          onChanged: (value) {
            // TODO: 实现黑方AI难度设置
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
          value: true,
          onChanged: (value) {
            // TODO: 实现自动开始设置
          },
        ),
        SwitchListTile(
          title: const Text('显示思考过程'),
          value: true,
          onChanged: (value) {
            // TODO: 实现思考过程显示
          },
        ),
        ListTile(
          title: const Text('走棋间隔'),
          trailing: DropdownButton<int>(
            value: 2,
            items: const [
              DropdownMenuItem(value: 1, child: Text('1秒')),
              DropdownMenuItem(value: 2, child: Text('2秒')),
              DropdownMenuItem(value: 3, child: Text('3秒')),
              DropdownMenuItem(value: 5, child: Text('5秒')),
            ],
            onChanged: (value) {
              // TODO: 实现走棋间隔设置
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
          onPressed: _startBattle,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 40),
            backgroundColor: Colors.green,
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          icon: const Icon(Icons.pause),
          label: const Text('暂停'),
          onPressed: _pauseBattle,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 40),
            backgroundColor: Colors.orange,
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          icon: const Icon(Icons.stop),
          label: const Text('停止'),
          onPressed: _stopBattle,
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
            _isRunning
                ? (IconData(0xe8f5, fontFamily: 'MaterialIcons'))
                : Icons.check_circle,
            color: _isRunning ? Colors.blue : Colors.green,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentStatus,
                  style: TextStyle(
                    color: _isRunning ? Colors.blue : Colors.green,
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
              ],
            ),
          ),
          if (_isRunning)
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

  void _startBattle() {
    setState(() {
      _isRunning = true;
      _isPaused = false;
      _currentStatus = '红方 AI 思考中...';
    });

    // 模拟AI思考时间
    _simulateAiMove();
  }

  void _pauseBattle() {
    setState(() {
      _isPaused = true;
      _currentStatus = '已暂停';
    });
  }

  void _stopBattle() {
    setState(() {
      _isRunning = false;
      _isPaused = false;
      _currentStatus = '已停止';
      _lastMove = '';
    });
  }

  void _newGame() {
    ref.read(boardViewModelProvider.notifier).newGame();
    setState(() {
      _isRunning = false;
      _isPaused = false;
      _currentStatus = '等待开始';
      _lastMove = '';
    });
  }

  void _togglePlayPause() {
    if (_isRunning) {
      _pauseBattle();
    } else {
      _startBattle();
    }
  }

  void _onMoveFinished() {
    if (_isRunning && !_isPaused) {
      // 继续下一步
      _simulateAiMove();
    }
  }

  void _simulateAiMove() {
    if (!mounted || _isPaused) return;

    // 模拟AI思考
    setState(() {
      _currentStatus = 'AI 正在分析局面...';
    });

    Future.delayed(const Duration(milliseconds: 1000), () {
      if (!mounted || _isPaused) return;

      // 模拟生成走法
      final moves = ['h3e3', 'h9g7', 'c3e3', 'h10g8', 'a3a5', 'h10g8'];
      final randomMove = moves[DateTime.now().millisecond % moves.length];
      _lastMove = randomMove;

      // 判断当前是谁的回合
      final isRedTurn = _lastMove.isNotEmpty;
      setState(() {
        _currentStatus = isRedTurn ? '黑方 AI 思考中...' : '红方 AI 思考中...';
      });

      // 继续下一步
      if (_isRunning && !_isPaused) {
        Future.delayed(const Duration(seconds: 2), () {
          _simulateAiMove();
        });
      }
    });
  }
}