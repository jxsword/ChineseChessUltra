import 'package:flutter/material.dart';

import '../../model/board.dart';
import '../../model/board_state.dart';
import '../../model/move.dart';
import '../../model/piece.dart';
import '../../../../shared/constants.dart';
import 'board_layout.dart';

/// 绘制 9×10 棋盘 + 棋子 + 选中/合法走法高亮。
///
/// 内部不持有任何可变状态，所有数据通过 [BoardState] 与 [Board] 传入。
class BoardPainter extends CustomPainter {
  const BoardPainter({
    required this.state,
    required this.board,
    required this.animatingMove,
  });

  final BoardState state;
  final Board board;
  final Move? animatingMove; // 当前正在动画中的走子（用于在 from 处隐藏棋子）

  @override
  void paint(Canvas canvas, Size size) {
    final layout = BoardLayout.fromSize(size);
    final cell = layout.cell;
    final originX = layout.originX;
    final originY = layout.originY;
    final offsetOf = layout.offsetOf;

    _drawBackground(canvas, size);
    _drawGrid(canvas, layout);
    _drawLastMove(canvas, cell, offsetOf);
    _drawSelectedAndHints(canvas, cell, offsetOf);
    _drawPieces(canvas, cell, offsetOf);
  }

  void _drawBackground(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(AppColors.boardBackground);
    canvas.drawRect(Offset.zero & size, paint);
  }

  void _drawGrid(Canvas canvas, BoardLayout layout) {
    final originX = layout.originX;
    final originY = layout.originY;
    final cell = layout.cell;
    final offsetOf = layout.offsetOf;
    final linePaint = Paint()
      ..color = const Color(AppColors.boardLine)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    final borderPaint = Paint()
      ..color = const Color(AppColors.boardLine)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;

    // 外边框（双层），外扩到能完整包住边缘交点上的棋子。
    final outer = Rect.fromPoints(
      offsetOf(0, 0) - Offset(layout.borderMargin, layout.borderMargin),
      offsetOf(8, 9) + Offset(layout.borderMargin, layout.borderMargin),
    );
    canvas.drawRect(outer, borderPaint);

    // 横线（10 条）。
    for (var r = 0; r < 10; r++) {
      canvas.drawLine(
        offsetOf(0, r),
        offsetOf(8, r),
        linePaint,
      );
    }
    // 竖线（9 条）：中间两段被楚河汉界打断。
    for (var c = 0; c < 9; c++) {
      if (c == 0 || c == 8) {
        canvas.drawLine(offsetOf(c, 0), offsetOf(c, 9), linePaint);
      } else {
        canvas.drawLine(offsetOf(c, 0), offsetOf(c, 4), linePaint);
        canvas.drawLine(offsetOf(c, 5), offsetOf(c, 9), linePaint);
      }
    }
    // 九宫格对角线（顶部）。
    canvas.drawLine(offsetOf(3, 0), offsetOf(5, 2), linePaint);
    canvas.drawLine(offsetOf(5, 0), offsetOf(3, 2), linePaint);
    // 九宫格对角线（底部）。
    canvas.drawLine(offsetOf(3, 7), offsetOf(5, 9), linePaint);
    canvas.drawLine(offsetOf(5, 7), offsetOf(3, 9), linePaint);

    // 楚河汉界文字。
    final textStyle = TextStyle(
      color: const Color(AppColors.riverText),
      fontSize: cell * 0.55,
      fontWeight: FontWeight.w500,
    );
    final riverY = originY + 4.5 * cell;
    final center = originX + 4 * cell;
    _drawTextCentered(
      canvas,
      '楚 河',
      Offset(center - cell * 2, riverY),
      textStyle,
    );
    _drawTextCentered(
      canvas,
      '漢 界',
      Offset(center + cell * 2, riverY),
      textStyle,
    );

    // 兵/炮位置十字标记（标准象棋棋盘装饰）。
    const marks = <(int, int)>[
      (1, 2), (7, 2),
      (0, 3), (2, 3), (4, 3), (6, 3), (8, 3),
      (0, 6), (2, 6), (4, 6), (6, 6), (8, 6),
      (1, 7), (7, 7),
    ];
    for (final (c, r) in marks) {
      _drawCrossMark(canvas, offsetOf(c, r), cell * 0.08, linePaint);
    }

    // 四周 ICCS 坐标标注（列 a-i、行 0-9，0 为红方底线）。
    _drawCoordinates(canvas, layout);
  }

  /// 在棋盘行列两端绘制 ICCS 坐标：列 a-i（画布上下两端）、
  /// 行 0-9（左右两端，rank 0 = 红方底线 = 内部 row 9）。
  ///
  /// 供玩家对照破解走法的 ICCS 步骤（如 h2e2）定位格子。
  void _drawCoordinates(Canvas canvas, BoardLayout layout) {
    final cell = layout.cell;
    final originX = layout.originX;
    final originY = layout.originY;
    final style = TextStyle(
      color: const Color(AppColors.riverText),
      fontSize: cell * 0.28,
      fontWeight: FontWeight.w600,
    );
    // 标注中心位于外框与画布边缘之间的空隙正中。
    const gapRatio = 0.65; // 相对 cell 的偏移量（介于 0.5 外框与 0.8 画布边之间）
    const files = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i'];
    for (var col = 0; col < 9; col++) {
      final x = originX + col * cell;
      _drawTextCentered(
        canvas,
        files[col],
        Offset(x, originY - gapRatio * cell),
        style,
      );
      _drawTextCentered(
        canvas,
        files[col],
        Offset(x, originY + 9 * cell + gapRatio * cell),
        style,
      );
    }
    for (var row = 0; row < 10; row++) {
      final rank = 9 - row; // ICCS 行号：0 = 红方底线
      final y = originY + row * cell;
      _drawTextCentered(
        canvas,
        '$rank',
        Offset(originX - gapRatio * cell, y),
        style,
      );
      _drawTextCentered(
        canvas,
        '$rank',
        Offset(originX + 8 * cell + gapRatio * cell, y),
        style,
      );
    }
  }

  void _drawCrossMark(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint,
  ) {
    final len = radius * 1.4;
    // 四个 L 形角标（外侧）。
    for (final dir in const [(-1, -1), (1, -1), (-1, 1), (1, 1)]) {
      final dx = dir.$1 * radius;
      final dy = dir.$2 * radius;
      canvas.drawLine(
        Offset(center.dx + dx, center.dy + dy),
        Offset(center.dx + dx, center.dy + dy + dir.$2 * len),
        paint,
      );
      canvas.drawLine(
        Offset(center.dx + dx, center.dy + dy),
        Offset(center.dx + dx + dir.$1 * len, center.dy + dy),
        paint,
      );
    }
  }

  void _drawLastMove(
    Canvas canvas,
    double cell,
    Offset Function(int, int) offsetOf,
  ) {
    final last = state.lastMove;
    if (last == null) return;
    final paint = Paint()
      ..color = const Color(AppColors.lastMove)
      ..style = PaintingStyle.fill;
    final radius = cell * AppConstants.pieceRatio / 2;
    canvas.drawCircle(offsetOf(last.from.col, last.from.row), radius, paint);
    canvas.drawCircle(offsetOf(last.to.col, last.to.row), radius, paint);
  }

  void _drawSelectedAndHints(
    Canvas canvas,
    double cell,
    Offset Function(int, int) offsetOf,
  ) {
    final selected = state.selected;
    if (selected != null) {
      final paint = Paint()
        ..color = const Color(AppColors.selected)
        ..style = PaintingStyle.fill;
      final radius = cell * AppConstants.pieceRatio / 2;
      canvas.drawCircle(
        offsetOf(selected.col, selected.row),
        radius,
        paint,
      );
    }
    final hintPaint = Paint()
      ..color = const Color(AppColors.legalHint)
      ..style = PaintingStyle.fill;
    final hintRadius = cell * 0.16;
    for (final target in state.legalTargets) {
      final center = offsetOf(target.col, target.row);
      // 若目标格有敌方棋子，则画外环高亮（吃子提示）。
      final piece = board.pieceAtP(target);
      if (piece != null) {
        final ringPaint = Paint()
          ..color = const Color(AppColors.legalHint)
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.08;
        canvas.drawCircle(
          center,
          cell * AppConstants.pieceRatio / 2 + cell * 0.05,
          ringPaint,
        );
      } else {
        canvas.drawCircle(center, hintRadius, hintPaint);
      }
    }
  }

  void _drawPieces(
    Canvas canvas,
    double cell,
    Offset Function(int, int) offsetOf,
  ) {
    final radius = cell * AppConstants.pieceRatio / 2;
    for (var r = 0; r < 10; r++) {
      for (var c = 0; c < 9; c++) {
        final piece = board.pieceAt(c, r);
        if (piece == null) continue;
        // 动画进行中：from 处的棋子由 PieceLayer 通过 Positioned 显示，
        // 这里跳过 from 格的棋子绘制，避免双重显示。
        if (animatingMove != null &&
            animatingMove!.from.col == c &&
            animatingMove!.from.row == r) {
          continue;
        }
        drawPiece(
          canvas,
          piece,
          offsetOf(c, r),
          radius,
        );
      }
    }
  }

  /// 公共绘制棋子方法（供动画层也复用）。
  static void drawPiece(
    Canvas canvas,
    Piece piece,
    Offset center,
    double radius,
  ) {
    // 棋子背景圆（含阴影）。
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      center + Offset(0, radius * 0.08),
      radius * 1.02,
      shadowPaint,
    );

    final facePaint = Paint()
      ..color = const Color(AppColors.pieceFaceRed)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, facePaint);

    final rimPaint = Paint()
      ..color = piece.side.isRed
          ? const Color(AppColors.pieceRed)
          : const Color(AppColors.pieceBlack)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.10;
    canvas.drawCircle(center, radius * 0.92, rimPaint);

    // 棋子文字。
    final textStyle = TextStyle(
      color: piece.side.isRed
          ? const Color(AppColors.pieceRed)
          : const Color(AppColors.pieceBlack),
      fontSize: radius * 1.05,
      fontWeight: FontWeight.bold,
      fontFamilyFallback: const ['KaiTi', 'STKaiti', '楷体', 'serif'],
    );
    _drawTextCentered(
      canvas,
      piece.label,
      center,
      textStyle,
    );
  }

  static void _drawTextCentered(
    Canvas canvas,
    String text,
    Offset center,
    TextStyle style,
  ) {
    final builder = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    builder.layout();
    builder.paint(
      canvas,
      Offset(
        center.dx - builder.width / 2,
        center.dy - builder.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant BoardPainter old) {
    return old.state != state ||
        old.board.toFen() != board.toFen() ||
        old.animatingMove != animatingMove;
  }
}
