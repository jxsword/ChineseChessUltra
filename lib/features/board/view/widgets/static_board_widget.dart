import 'package:flutter/material.dart';

import '../../model/board.dart';
import '../../model/board_state.dart';
import '../../model/move.dart';
import 'board_layout.dart';
import 'board_painter.dart';

/// 只读/可点选的静态棋盘（四期）。
///
/// 供残局摆盘、FEN 导入预览、识图校正、棋谱库重放等场景复用：
/// 与 BoardWidget（绑定全局对弈 ViewModel）不同，本组件直接持有
/// [Board] 数据，点击通过 [onCellTap] 回调交由调用方处理。
class StaticBoardWidget extends StatelessWidget {
  const StaticBoardWidget({
    super.key,
    required this.board,
    this.lastMove,
    this.onCellTap,
  });

  final Board board;

  /// 高亮最近一手（from/to 圈记）。
  final Move? lastMove;

  /// 格位点击回调（col, row，内部坐标：row 0 为黑方底线）。
  final void Function(int col, int row)? onCellTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 600,
          constraints.maxHeight.isFinite ? constraints.maxHeight : 600,
        );
        final state = BoardState(
          fen: board.toFen(),
          moveHistory: const [],
          isRedTurn: board.isRedTurn,
          isCheck: board.isCheck(board.turn),
          result: null,
          lastMove: lastMove,
        );
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: onCellTap == null
              ? null
              : (details) {
                  final layout = BoardLayout.fromSize(size);
                  final col =
                      ((details.localPosition.dx - layout.originX) /
                              layout.cell)
                          .round();
                  final row =
                      ((details.localPosition.dy - layout.originY) /
                              layout.cell)
                          .round();
                  if (col >= 0 && col <= 8 && row >= 0 && row <= 9) {
                    onCellTap!(col, row);
                  }
                },
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: CustomPaint(
              painter: BoardPainter(
                state: state,
                board: board,
                animatingMove: null,
              ),
            ),
          ),
        );
      },
    );
  }
}
