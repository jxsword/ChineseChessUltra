import 'package:flutter/material.dart';

import '../../../../shared/constants.dart';

/// 棋盘几何布局：由可用空间推导格子尺寸与网格原点。
///
/// 绘制（[BoardPainter]）、点击命中、飞子动画必须共用同一布局，
/// 否则三者对"格子/交点"的理解会错位。
///
/// 尺寸推导：边缘交点上的棋子半径为 `pieceRatio/2 × cell`，
/// 棋盘外框需外扩到能完整包住边缘棋子，因此画布四周留白
/// 按 `cell` 的比例计算而非固定像素，随窗口缩放保持一致。
class BoardLayout {
  factory BoardLayout.fromSize(Size size) {
    final cell = _cellFor(size);
    return BoardLayout._(
      cell: cell,
      originX: (size.width - 8 * cell) / 2,
      originY: (size.height - 9 * cell) / 2,
    );
  }

  BoardLayout._({
    required this.cell,
    required this.originX,
    required this.originY,
  });

  /// 棋盘外框距网格的外扩比例：需 ≥ 棋子半径比例(pieceRatio/2)
  /// 加少量呼吸空隙。
  static const double _borderMarginRatio = 0.5;

  /// 画布四周留白比例：外框外扩 + 边框线宽的余量。
  static const double _canvasPaddingRatio = _borderMarginRatio + 0.05;

  final double cell;
  final double originX;
  final double originY;

  /// 横向 8 格、纵向 9 格，四周各留 _canvasPaddingRatio × cell。
  static double _cellFor(Size size) {
    final byWidth = size.width / (8 + 2 * _canvasPaddingRatio);
    final byHeight = size.height / (9 + 2 * _canvasPaddingRatio);
    return byWidth < byHeight ? byWidth : byHeight;
  }

  /// 网格交点 (col,row) 的画布坐标。
  Offset offsetOf(int col, int row) => Offset(
        originX + col * cell,
        originY + row * cell,
      );

  /// 棋子半径。
  double get pieceRadius => cell * AppConstants.pieceRatio / 2;

  /// 棋盘外框相对网格的外扩距离。
  double get borderMargin => cell * _borderMarginRatio;
}
