import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../board/model/board_state.dart';
import '../../../board/view/widgets/board_painter.dart';
import '../../viewmodel/puzzle_vm.dart';

/// 残局演示专用只读棋盘。
///
/// 渲染 [PuzzleViewModel] 播放出的局面（含最近一步高亮），
/// 不与对局 BoardViewModel 交互，也不处理点击。
class DemoBoardWidget extends ConsumerWidget {
  const DemoBoardWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(puzzleViewModelProvider);
    final board = ref.watch(puzzleViewModelProvider.notifier).board;

    if (board == null) {
      return const Center(child: Text('点击播放开始演示'));
    }

    final boardState = BoardState(
      fen: state.fen ?? board.toFen(),
      moveHistory: const [],
      isRedTurn: board.isRedTurn,
      isCheck: false,
      result: null,
      lastMove: state.lastMove,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 600,
          constraints.maxHeight.isFinite ? constraints.maxHeight : 600,
        );
        return CustomPaint(
          size: size,
          painter: BoardPainter(
            state: boardState,
            board: board,
            animatingMove: null,
          ),
        );
      },
    );
  }
}
