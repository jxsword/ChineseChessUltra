import 'package:flutter/material.dart';

import '../../model/board.dart';
import '../../model/board_state.dart';
import '../../model/move.dart';
import '../../model/piece.dart';
import '../../../../shared/constants.dart';

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
    // 计算 cell 大小：纵向有 9 个间隔（10 条线），横向有 8 个间隔（9 条线）。
    // 留出 padding 用于绘制外框。

    // print('BoardPainter size: $size');

    const padding = 24.0;
    final innerWidth = size.width - padding * 2;
    final innerHeight = size.height - padding * 2;
    final cellW = innerWidth / 8;
    final cellH = innerHeight / 9;
    final cell = cellW < cellH ? cellW : cellH;
    final originX = (size.width - cell * 8) / 2;
    final originY = (size.height - cell * 9) / 2;

    final offsetOf = (int col, int row) => Offset(
          originX + col * cell,
          originY + row * cell,
        );

    _drawBackground(canvas, size);
    _drawGrid(canvas, originX, originY, cell, offsetOf);
    _drawLastMove(canvas, cell, offsetOf);
    _drawSelectedAndHints(canvas, cell, offsetOf);
    _drawPieces(canvas, cell, offsetOf);
  }

  void _drawBackground(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(AppColors.boardBackground);
    canvas.drawRect(Offset.zero & size, paint);
  }

  void _drawGrid(
    Canvas canvas,
    double originX,
    double originY,
    double cell,
    Offset Function(int, int) offsetOf,
  ) {
    final linePaint = Paint()
      ..color = const Color(AppColors.boardLine)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    final borderPaint = Paint()
      ..color = const Color(AppColors.boardLine)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;

    // 外边框（双层）。
    final outer = Rect.fromPoints(
      Offset(originX - cell * 0.18, originY - cell * 0.18),
      Offset(originX + 8 * cell + cell * 0.18,
          originY + 9 * cell + cell * 0.18),
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
