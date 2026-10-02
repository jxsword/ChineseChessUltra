import 'package:flutter_test/flutter_test.dart';

import 'package:chinese_chess_ultra/features/board/model/board.dart';
import 'package:chinese_chess_ultra/features/board/model/move.dart';
import 'package:chinese_chess_ultra/features/shared/engine/move_annotation.dart';

/// 黑王 (3,0)、红车 (0,6) 与黑车 (0,4) 同列相隔、红帅 (4,9)：
/// 红可 R×r（吃车），黑王与红帅不同列（避免照面）。
const captureFen = '3k5/9/9/9/r8/9/R8/9/9/4K4 w';

void main() {
  final board = Board.fromFen(captureFen);

  group('MoveAnnotation.annotate', () {
    test('吃车着法：坐标+中文记法+吃子标注', () {
      final move = const Move(from: Position(0, 6), to: Position(0, 4));
      final text = MoveAnnotation.annotate(board, move);
      expect(text, startsWith('a6-a4('));
      expect(text, contains('车九进二'));
      expect(text, contains('吃车'));
    });

    test('将军着法带将军标注', () {
      // 红车 (0,6)->(0,1)：沉底后沿 0 列……黑王在 (3,0) 不在 0 列。
      // 用另一将军：红车 (0,6)->(3,6)? 不将军。构造：红车平 3 列 (3,6)
      // 沿 3 列向下将军黑王 (3,0)，中间 (3,1..5) 为空 → 将军。
      final check = const Move(from: Position(0, 6), to: Position(3, 6));
      final text = MoveAnnotation.annotate(board, check);
      expect(text, contains('将军'));
      expect(text, contains('车九平六'));
    });

    test('普通着法无吃子/将军标注', () {
      final move = const Move(from: Position(0, 6), to: Position(1, 6));
      final text = MoveAnnotation.annotate(board, move);
      expect(text, 'a6-b6(车九平八)');
    });

    test('起点无棋子退化为纯坐标', () {
      final move = const Move(from: Position(4, 4), to: Position(4, 5));
      expect(MoveAnnotation.annotate(board, move), 'e4-e5');
    });
  });

  group('MoveAnnotation.scoreBucket', () {
    test('五档分桶与边界', () {
      expect(MoveAnnotation.scoreBucket(0), '最佳/均势');
      expect(MoveAnnotation.scoreBucket(30), '最佳/均势');
      expect(MoveAnnotation.scoreBucket(31), '略亏');
      expect(MoveAnnotation.scoreBucket(100), '略亏');
      expect(MoveAnnotation.scoreBucket(101), '明显亏（约半子）');
      expect(MoveAnnotation.scoreBucket(250), '明显亏（约半子）');
      expect(MoveAnnotation.scoreBucket(251), '大亏（丢一马/一炮级）');
      expect(MoveAnnotation.scoreBucket(600), '大亏（丢一马/一炮级）');
      expect(MoveAnnotation.scoreBucket(601), '致命（丢车/被将杀级）');
      expect(MoveAnnotation.scoreBucket(30000), '致命（丢车/被将杀级）');
    });

    test('带分桶的候选行文本', () {
      final move = const Move(from: Position(0, 6), to: Position(0, 4));
      final line = MoveAnnotation.annotatedWithBucket(board, move, 20);
      expect(line, startsWith('a6-a4('));
      expect(line, endsWith('— 最佳/均势'));
    });
  });
}
