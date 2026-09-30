import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/puzzle_data.dart';
import '../viewmodel/puzzle_vm.dart';
import '../../board/model/board.dart';
import '../../board/model/fen.dart';
import '../../board/view/widgets/board_widget.dart';
import '../../board/viewmodel/board_vm.dart';

/// 残局详情页面
class PuzzleDetailPage extends ConsumerStatefulWidget {
  const PuzzleDetailPage({
    super.key,
    required this.puzzle,
  });

  final ParsedPuzzle puzzle;

  @override
  ConsumerState<PuzzleDetailPage> createState() => _PuzzleDetailPageState();
}

class _PuzzleDetailPageState extends ConsumerState<PuzzleDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.puzzle.title ?? '残局详情'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '残局信息'),
            Tab(text: '残局演示'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPuzzleInfo(),
          _buildPuzzleDemo(),
        ],
      ),
    );
  }

  Widget _buildPuzzleInfo() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.puzzle.title ?? '残局${widget.puzzle.id}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      _buildDifficultyBadge(),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildInfoRow('来源', widget.puzzle.source ?? '未知'),
                  _buildInfoRow('格式', widget.puzzle.format.toUpperCase()),
                  _buildInfoRow('难度', '${'★' * widget.puzzle.difficulty}${'☆' * (5 - widget.puzzle.difficulty)}'),
                  _buildInfoRow('走法数量', '${widget.puzzle.moveCount} 步'),
                  if (widget.puzzle.description != null) ...[
                    const SizedBox(height: 16),
                    const Text(
                      '残局描述',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.puzzle.description!,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '初始局面',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    widget.puzzle.initialFen,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '破解走法',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (widget.puzzle.solutionMoves != null &&
                      widget.puzzle.solutionMoves!.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: widget.puzzle.solutionMoves!.map((move) {
                        return Chip(
                          label: Text(move),
                          backgroundColor: Colors.blue.withOpacity(0.1),
                          labelStyle: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      }).toList(),
                    )
                  else
                    const Text(
                      '暂无破解走法',
                      style: TextStyle(color: Colors.grey),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPuzzleDemo() {
    final state = ref.watch(puzzleViewModelProvider);
    return Column(
      children: [
        _buildDemoControls(state),
        const SizedBox(height: 16),
        Expanded(
          child: _buildBoardArea(),
        ),
        const SizedBox(height: 16),
        _buildMoveList(),
      ],
    );
  }

  Widget _buildDemoControls(PuzzleState state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.play_arrow),
              onPressed: _startDemo,
              style: IconButton.styleFrom(
                backgroundColor: Colors.green,
                disabledForegroundColor: Colors.grey,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.pause),
              onPressed: _pauseDemo,
              style: IconButton.styleFrom(
                backgroundColor: Colors.orange,
                disabledForegroundColor: Colors.grey,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.stop),
              onPressed: _stopDemo,
              style: IconButton.styleFrom(
                backgroundColor: Colors.red,
                disabledForegroundColor: Colors.grey,
              ),
            ),
            const SizedBox(width: 16),
            const Text('速度:'),
            const SizedBox(width: 8),
            DropdownButton<PuzzleDemoParams>(
              value: PuzzleDemoParams.normal,
              items: [
                const DropdownMenuItem(
                  value: PuzzleDemoParams.slow,
                  child: Text('慢速'),
                ),
                const DropdownMenuItem(
                  value: PuzzleDemoParams.normal,
                  child: Text('正常'),
                ),
                const DropdownMenuItem(
                  value: PuzzleDemoParams.fast,
                  child: Text('快速'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  ref.read(puzzleViewModelProvider.notifier).setDemoSpeed(value);
                }
              },
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.loop),
              onPressed: () {
                ref.read(puzzleViewModelProvider.notifier).setDemoMode(true);
              },
              style: IconButton.styleFrom(
                backgroundColor: Colors.green.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBoardArea() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 400,
          constraints.maxHeight.isFinite ? constraints.maxHeight : 400,
        );
        return Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: BoardWidget(onMoved: () {}),
          ),
        );
      },
    );
  }

  Widget _buildMoveList() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '走法序列',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (widget.puzzle.moves.isEmpty)
              const Text('暂无走法')
            else
              SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.puzzle.moves.length,
                  itemBuilder: (context, index) {
                    final move = widget.puzzle.moves[index];
                    final isCurrent = ref.read(puzzleViewModelProvider).currentMoveIndex == index;
                    return Container(
                      width: 80,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? Colors.blue.withOpacity(0.2)
                            : Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isCurrent ? Colors.blue : Colors.grey,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '${index + 1}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            move,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDifficultyBadge() {
    Color color;
    switch (widget.puzzle.difficulty) {
      case 1:
        color = Colors.green;
        break;
      case 2:
        color = Colors.blue;
        break;
      case 3:
        color = Colors.orange;
        break;
      case 4:
        color = Colors.red;
        break;
      case 5:
        color = Colors.purple;
        break;
      default:
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color),
      ),
      child: Text(
        '${'★' * widget.puzzle.difficulty}${'☆' * (5 - widget.puzzle.difficulty)}',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _startDemo() {
    ref.read(puzzleViewModelProvider.notifier).initializePuzzle(widget.puzzle);
    ref.read(puzzleViewModelProvider.notifier).startDemo();
  }

  void _pauseDemo() {
    ref.read(puzzleViewModelProvider.notifier).pauseDemo();
  }

  void _stopDemo() {
    ref.read(puzzleViewModelProvider.notifier).stopDemo();
  }
}