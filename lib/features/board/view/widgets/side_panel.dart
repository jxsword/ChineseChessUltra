import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../model/board_state.dart';
import '../../model/move.dart';
import '../../model/piece.dart';
import '../../viewmodel/board_vm.dart';

/// 右侧操作面板：回合指示 / 走法记录 / 悔棋 / 新游戏。
class SidePanel extends ConsumerWidget {
  const SidePanel({super.key, this.onNewGame});

  /// 新游戏回调（由外部注入，用于触发 LifecycleNotifier.forgetCurrentGame）。
  final VoidCallback? onNewGame;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(boardViewModelProvider);
    final vm = ref.read(boardViewModelProvider.notifier);
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TurnIndicator(state: state),
            const SizedBox(height: 12),
            _ResultBanner(state: state),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: state.moveHistory.isEmpty
                        ? null
                        : () => vm.undo(),
                    icon: const Icon(Icons.undo),
                    label: const Text('悔棋'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onNewGame != null
                        ? () => _confirmNewGame(context, onNewGame!)
                        : () => _confirmNewGame(context, vm.newGame),
                    icon: const Icon(Icons.refresh),
                    label: const Text('新游戏'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('走法记录', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Expanded(
              child: _MoveList(state: state),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmNewGame(BuildContext context, VoidCallback onConfirm) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('开始新游戏'),
        content: const Text('当前棋局将被清空，确定要开始新游戏吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

class _TurnIndicator extends StatelessWidget {
  const _TurnIndicator({required this.state});

  final BoardState state;

  @override
  Widget build(BuildContext context) {
    final isRed = state.isRedTurn;
    final color = isRed
        ? const Color(0xFFB71C1C)
        : const Color(0xFF212121);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.circle, color: color, size: 14),
          const SizedBox(width: 8),
          Text(
            isRed ? '红方走棋' : '黑方走棋',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const Spacer(),
          if (state.isCheck && !state.isFinished)
            Text(
              '将军！',
              style: TextStyle(
                color: Colors.red.shade700,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }
}

class _ResultBanner extends StatelessWidget {
  const _ResultBanner({required this.state});

  final BoardState state;

  @override
  Widget build(BuildContext context) {
    final result = state.result;
    if (result == null) {
      return const SizedBox.shrink();
    }
    final (text, color) = switch (result) {
      GameResult.redWins => ('红方胜！', Colors.red.shade700),
      GameResult.blackWins => ('黑方胜！', Colors.black87),
      GameResult.draw => ('和棋', Colors.blueGrey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 22,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _MoveList extends StatelessWidget {
  const _MoveList({required this.state});

  final BoardState state;

  @override
  Widget build(BuildContext context) {
    final moves = state.moveHistory;
    if (moves.isEmpty) {
      return const Center(
        child: Text('暂无走法', style: TextStyle(color: Colors.grey)),
      );
    }
    // 双列：奇数（红）偶数（黑）。
    final rows = <Widget>[];
    for (var i = 0; i < moves.length; i += 2) {
      final round = (i ~/ 2) + 1;
      final redMove = moves[i];
      final blackMove = i + 1 < moves.length ? moves[i + 1] : null;
      rows.add(_MoveRow(
        round: round,
        redMove: redMove,
        blackMove: blackMove,
      ));
    }
    return ListView(
      children: rows,
    );
  }
}

/// 走法格式化：优先使用 move 自带的 piece 信息生成中文记法。
String _formatMove(Move m) {
  if (m.piece != null) return m.chineseNotation(m.piece!);
  // 回退：简易记法。
  const han = ['九', '八', '七', '六', '五', '四', '三', '二', '一'];
  final side = m.from.row >= 5 ? Side.red : Side.black;
  final fc = side.isRed ? han[m.from.col] : '${m.from.col + 1}';
  final tc = side.isRed ? han[m.to.col] : '${m.to.col + 1}';
  if (m.from.row == m.to.row) return '?$fc 平 $tc';
  final ahead = side.isRed ? m.to.row < m.from.row : m.to.row > m.from.row;
  final steps = (m.to.row - m.from.row).abs();
  final target = side.isRed ? han[9 - steps] : '$steps';
  return '?$fc ${ahead ? '进' : '退'} $target';
}

class _MoveRow extends StatelessWidget {
  const _MoveRow({
    required this.round,
    required this.redMove,
    this.blackMove,
  });

  final int round;
  final Move redMove;
  final Move? blackMove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '$round.',
              style: const TextStyle(color: Colors.grey),
            ),
          ),
            Expanded(
              child: Text(
                _formatMove(redMove),
                style: const TextStyle(color: Color(0xFFB71C1C)),
              ),
            ),
            Expanded(
              child: blackMove == null
                  ? const SizedBox.shrink()
                  : Text(
                      _formatMove(blackMove!),
                      style: const TextStyle(color: Colors.black87),
                    ),
            ),
        ],
      ),
    );
  }
}
