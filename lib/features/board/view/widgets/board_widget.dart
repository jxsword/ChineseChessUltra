import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../model/board.dart';
import '../../model/board_state.dart';
import '../../model/move.dart';
import '../../model/piece.dart';
import '../../viewmodel/board_vm.dart';
import 'board_painter.dart';

/// 棋盘交互层：负责点击命中检测 + 走子动画。
///
/// 内部用 [CustomPaint] 绘制底层，叠加一个 [Listener] 处理鼠标/触控点击；
/// 走子时使用 [AnimationController] 驱动 [Positioned] 中飞行的棋子。
class BoardWidget extends ConsumerStatefulWidget {
  const BoardWidget({super.key, this.onMoved});

  /// 走子完成回调（用于触发持久化）。
  final VoidCallback? onMoved;

  @override
  ConsumerState<BoardWidget> createState() => _BoardWidgetState();
}

class _BoardWidgetState extends ConsumerState<BoardWidget>
    with TickerProviderStateMixin {
  /// 动画期间的飞行棋子。
  ///
  /// (piece, from, to, controller, animation)
  _FlyingPiece? _flying;

  @override
  void dispose() {
    _flying?.controller.dispose();
    super.dispose();
  }

  void _onTap(Offset localPosition, Size size, BoardState state) {
    final viewModel = ref.read(boardViewModelProvider.notifier);
    final board = viewModel.board;

    final cell = _cellSize(size);
    final originX = (size.width - cell * 8) / 2;
    final originY = (size.height - cell * 9) / 2;

    final col = ((localPosition.dx - originX) / cell).round();
    final row = ((localPosition.dy - originY) / cell).round();
    if (col < 0 || col > 8 || row < 0 || row > 9) return;

    // 若点击为合法走法目标，先触发动画再真正应用走子。
    final selected = state.selected;
    final isLegalTarget =
        selected != null && state.legalTargets.any((p) {
      return p.col == col && p.row == row;
    });

    if (isLegalTarget) {
      final mover = board.pieceAtP(selected!)!;
      _animateMove(mover, selected, Position(col, row), size);
    } else {
      viewModel.onTap(col, row);
    }
  }

  void _animateMove(
    Piece mover,
    Position from,
    Position to,
    Size size,
  ) {
    final cell = _cellSize(size);
    final originX = (size.width - cell * 8) / 2;
    final originY = (size.height - cell * 9) / 2;

    Offset posOf(int col, int row) => Offset(
          originX + col * cell,
          originY + row * cell,
        );

    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    final animation = CurvedAnimation(
      parent: controller,
      curve: Curves.easeOutCubic,
    );
    final flying = _FlyingPiece(
      piece: mover,
      from: from,
      to: to,
      controller: controller,
      animation: animation,
    );
    setState(() => _flying = flying);

    // 把 from 处棋子先从底层 board 视图中"隐藏"：
    // 通过让 painter 在 animatingMove 非空时不绘制 from 处棋子来实现，
    // 而 board 实际 applyMove 在动画结束后再调用。
    controller.forward().whenComplete(() {
      final viewModel = ref.read(boardViewModelProvider.notifier);
      viewModel.onTap(to.col, to.row);
      setState(() => _flying = null);
      flying.controller.dispose();
      widget.onMoved?.call();
    });
  }

  double _cellSize(Size size) {
    const padding = 24.0;
    final innerWidth = size.width - padding * 2;
    final innerHeight = size.height - padding * 2;
    final cellW = innerWidth / 8;
    final cellH = innerHeight / 9;
    return cellW < cellH ? cellW : cellH;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(boardViewModelProvider);
    final board = ref.read(boardViewModelProvider.notifier).board;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 600,
          constraints.maxHeight.isFinite ? constraints.maxHeight : 600,
        );
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => _onTap(details.localPosition, size, state),
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: BoardPainter(
                        state: state,
                        board: board,
                        animatingMove: _flying?.toMove(),
                      ),
                    ),
                  ),
                ),
                if (_flying != null)
                  _buildFlyingLayer(size, _flying!, state, board),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFlyingLayer(
    Size size,
    _FlyingPiece flying,
    BoardState state,
    Board board,
  ) {
    final cell = _cellSize(size);
    final originX = (size.width - cell * 8) / 2;
    final originY = (size.height - cell * 9) / 2;

    Offset posOf(int col, int row) => Offset(
          originX + col * cell,
          originY + row * cell,
        );

    final radius = cell * 0.86 / 2;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: flying.animation,
        builder: (context, _) {
          final from = posOf(flying.from.col, flying.from.row);
          final to = posOf(flying.to.col, flying.to.row);
          final offset = Offset(
            from.dx + (to.dx - from.dx) * flying.animation.value,
            from.dy + (to.dy - from.dy) * flying.animation.value,
          );
          return CustomPaint(
            painter: _FlyingPiecePainter(
              center: offset,
              radius: radius,
              piece: flying.piece,
            ),
          );
        },
      ),
    );
  }
}

class _FlyingPiece {
  _FlyingPiece({
    required this.piece,
    required this.from,
    required this.to,
    required this.controller,
    required this.animation,
  });

  final Piece piece;
  final Position from;
  final Position to;
  final AnimationController controller;
  final Animation<double> animation;

  Move toMove() => Move(from: from, to: to);
}

class _FlyingPiecePainter extends CustomPainter {
  const _FlyingPiecePainter({
    required this.center,
    required this.radius,
    required this.piece,
  });

  final Offset center;
  final double radius;
  final Piece piece;

  @override
  void paint(Canvas canvas, Size size) {
    BoardPainter.drawPiece(canvas, piece, center, radius);
  }

  @override
  bool shouldRepaint(covariant _FlyingPiecePainter old) {
    return old.center != center || old.piece != piece;
  }
}
