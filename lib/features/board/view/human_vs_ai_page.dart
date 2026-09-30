import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/board_state.dart';
import '../viewmodel/board_vm.dart';
import '../view/widgets/board_widget.dart';
import '../view/widgets/side_panel.dart';

/// 人机对战页面
class HumanVsAiPage extends ConsumerStatefulWidget {
  const HumanVsAiPage({super.key});

  @override
  ConsumerState<HumanVsAiPage> createState() => _HumanVsAiPageState();
}

class _HumanVsAiPageState extends ConsumerState<HumanVsAiPage> {
  bool _isAiThinking = false;
  String _aiStatus = '';

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
                    _buildTimeControl(),
                    const SizedBox(height: 16),
                    _buildGameMode(),
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
          value: 3,
          items: const [
            DropdownMenuItem(value: 1, child: Text('初级')),
            DropdownMenuItem(value: 2, child: Text('中级')),
            DropdownMenuItem(value: 3, child: Text('高级')),
            DropdownMenuItem(value: 4, child: Text('专家')),
            DropdownMenuItem(value: 5, child: Text('大师')),
          ],
          onChanged: (value) {
            // TODO: 实现AI难度设置
          },
        ),
      ],
    );
  }

  Widget _buildTimeControl() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '时间控制',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('不限时'),
            Radio<int>(
              value: 0,
              groupValue: 0,
              onChanged: (value) {
                // TODO: 实现时间控制
              },
            ),
            const SizedBox(width: 16),
            const Text('限时'),
            Radio<int>(
              value: 1,
              groupValue: 0,
              onChanged: (value) {
                // TODO: 实现时间控制
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGameMode() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '游戏模式',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('显示AI思考过程'),
          value: true,
          onChanged: (value) {
            // TODO: 实现思考过程显示
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
      ],
    );
  }

  Widget _buildAiStatus() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: _isAiThinking ? Colors.yellow.withOpacity(0.1) : Colors.grey.withOpacity(0.05),
      child: Row(
        children: [
          Icon(
            _isAiThinking ? Icons.hourglass_empty : Icons.check_circle,
            color: _isAiThinking ? Colors.orange : Colors.green,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isAiThinking ? 'AI 正在思考... $_aiStatus' : '等待玩家走棋',
              style: TextStyle(
                color: _isAiThinking ? Colors.orange : Colors.green,
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

  void _newGame() {
    ref.read(boardViewModelProvider.notifier).newGame();
    setState(() {
      _isAiThinking = false;
      _aiStatus = '';
    });
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

  void _onMoveFinished() {
    // TODO: 实现AI走棋逻辑
    setState(() {
      _isAiThinking = true;
      _aiStatus = '分析局面中...';
    });

    // 模拟AI思考时间
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      
      setState(() {
        _isAiThinking = false;
        _aiStatus = '';
      });
      
      // TODO: 实际的AI走棋逻辑
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('AI 走棋完成'),
        ),
      );
    });
  }
}