import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../board/model/piece.dart';
import '../../board/view/human_vs_ai_page.dart';
import '../model/puzzle_data.dart';
import '../viewmodel/puzzle_vm.dart';
import 'widgets/demo_board_widget.dart';

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
        actions: [
          IconButton(
            icon: const Icon(Icons.sports_esports),
            tooltip: '从残局始盘开始人机对战',
            onPressed: _startPuzzleGame,
          ),
        ],
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

  /// 以残局始盘为初始局面进入人机对战：先让玩家选择执子方。
  void _startPuzzleGame() {
    showModalBottomSheet<Side>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '选择执子方',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.circle, color: Colors.red),
              title: const Text('执红先行'),
              subtitle: const Text('红方先走（多数残局的攻杀方）'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(sheetContext).pop(Side.red),
            ),
            ListTile(
              leading:
                  const Icon(Icons.circle_outlined, color: Colors.black87),
              title: const Text('执黑后行'),
              subtitle: const Text('黑方后走，由 AI 先行动子'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(sheetContext).pop(Side.black),
            ),
          ],
        ),
      ),
    ).then((side) {
      if (side is! Side) return;
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => HumanVsAiPage(
            initialFen: widget.puzzle.initialFen,
            playerSide: side,
          ),
        ),
      );
    });
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
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _startPuzzleGame,
                    icon: const Icon(Icons.sports_esports),
                    label: const Text('从残局始盘开始人机对战'),
                  ),
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
        child: Column(
          children: [
            Row(
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
                _buildSpeedDropdown(state),
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
            const SizedBox(height: 8),
            _buildSpeedSlider(state),
          ],
        ),
      ),
    );
  }

  /// 速度下拉框：预设三档；当前为自定义间隔时追加"自定义"项以正确回显。
  Widget _buildSpeedDropdown(PuzzleState state) {
    final presets = [
      PuzzleDemoParams.slow,
      PuzzleDemoParams.normal,
      PuzzleDemoParams.fast,
    ];
    final isPreset =
        presets.any((p) => identical(p, state.demoParams) || p == state.demoParams);
    return DropdownButton<PuzzleDemoParams>(
      value: state.demoParams,
      items: [
        DropdownMenuItem(
          value: PuzzleDemoParams.slow,
          child: Text(_speedLabel(PuzzleDemoParams.slow)),
        ),
        DropdownMenuItem(
          value: PuzzleDemoParams.normal,
          child: Text(_speedLabel(PuzzleDemoParams.normal)),
        ),
        DropdownMenuItem(
          value: PuzzleDemoParams.fast,
          child: Text(_speedLabel(PuzzleDemoParams.fast)),
        ),
        if (!isPreset)
          DropdownMenuItem(
            value: state.demoParams,
            child: Text('自定义 ${_speedLabel(state.demoParams)}'),
          ),
      ],
      onChanged: (value) {
        if (value != null) {
          ref.read(puzzleViewModelProvider.notifier).setDemoSpeed(value);
        }
      },
    );
  }

  /// 速度滑块：按走子间隔（毫秒/步）自由调节，范围 200ms–4000ms。
  Widget _buildSpeedSlider(PuzzleState state) {
    const minMs = 200.0;
    const maxMs = 4000.0;
    final value = state.demoParams.interval.toDouble().clamp(minMs, maxMs);
    return Row(
      children: [
        const Icon(Icons.speed, size: 20),
        Expanded(
          child: Slider(
            value: value,
            min: minMs,
            max: maxMs,
            divisions: ((maxMs - minMs) / 100).round(),
            label: _speedLabel(state.demoParams),
            onChanged: (v) {
              ref
                  .read(puzzleViewModelProvider.notifier)
                  .setCustomInterval((v / 100).round() * 100);
            },
          ),
        ),
        SizedBox(
          width: 72,
          child: Text(
            _speedLabel(state.demoParams),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  /// 速度文案：以"秒/步"展示走子间隔。
  String _speedLabel(PuzzleDemoParams params) {
    final seconds = params.interval / 1000;
    return '${seconds.toStringAsFixed(1)} 秒/步';
  }

  Widget _buildBoardArea() {
    // 演示专用只读棋盘：由 PuzzleViewModel 播放的局面驱动。
    return const DemoBoardWidget();
  }

  Widget _buildMoveList() {
    final currentMoveIndex = ref.watch(puzzleViewModelProvider).currentMoveIndex;
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
                    final isCurrent = currentMoveIndex == index;
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
    final state = ref.read(puzzleViewModelProvider);
    final notifier = ref.read(puzzleViewModelProvider.notifier);
    if (state.demoState == PuzzleDemoState.paused) {
      // 暂停中再次点击播放 = 继续演示，不重置进度。
      notifier.resumeDemo();
    } else {
      notifier.initializePuzzle(widget.puzzle);
      notifier.startDemo();
    }
  }

  void _pauseDemo() {
    ref.read(puzzleViewModelProvider.notifier).pauseDemo();
  }

  void _stopDemo() {
    ref.read(puzzleViewModelProvider.notifier).stopDemo();
  }
}