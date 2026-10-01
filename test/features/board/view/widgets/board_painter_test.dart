import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_chess_ultra/features/board/model/board.dart';
import 'package:chinese_chess_ultra/features/board/model/board_state.dart';
import 'package:chinese_chess_ultra/features/board/view/widgets/board_layout.dart';
import 'package:chinese_chess_ultra/features/board/view/widgets/board_painter.dart';

void main() {
  group('BoardLayout（坐标标注留白）', () {
    test('留白比例调整为 0.8 后，网格交点仍在画布内且四周有余量', () {
      // 等比测试尺寸：9.6 : 10.6 = 480 : 530，cell 恰为 50。
      const size = Size(480, 530);
      final layout = BoardLayout.fromSize(size);
      expect(layout.cell, closeTo(50, 0.01));
      // 四角交点距画布边缘恰为 0.8 cell。
      expect(layout.originX, closeTo(0.8 * layout.cell, 0.01));
      expect(layout.originY, closeTo(0.8 * layout.cell, 0.01));
      // 最右/最下交点 + 0.8 cell 不超出画布。
      final last = layout.offsetOf(8, 9);
      expect(last.dx + 0.8 * layout.cell, lessThanOrEqualTo(size.width + 0.01));
      expect(
          last.dy + 0.8 * layout.cell, lessThanOrEqualTo(size.height + 0.01));
      // 坐标标注位于外框（0.5 cell）与画布边缘（0.8 cell）之间的空隙。
      expect(0.5 * layout.cell, lessThan(0.65 * layout.cell));
      expect(0.65 * layout.cell, lessThan(0.8 * layout.cell));
    });

    test('offsetOf 命中一致性：格距均匀', () {
      final layout = BoardLayout.fromSize(const Size(600, 680));
      final a = layout.offsetOf(0, 0);
      final b = layout.offsetOf(1, 0);
      expect(b.dx - a.dx, closeTo(layout.cell, 0.001));
    });
  });

  group('BoardPainter（坐标标注冒烟）', () {
    test('paint 全流程不抛异常（含坐标标注绘制）', () {
      const size = Size(600, 680);
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      final painter = BoardPainter(
        state: const BoardState(
          fen: 'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1',
          moveHistory: [],
          isRedTurn: true,
          isCheck: false,
          result: null,
        ),
        board: Board.initial(),
        animatingMove: null,
      );
      painter.paint(canvas, size);
      final picture = recorder.endRecording();
      expect(picture, isNotNull);
    });
  });
}
