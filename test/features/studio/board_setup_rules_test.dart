import 'package:flutter_test/flutter_test.dart';

import 'package:chinese_chess_ultra/features/board/model/piece.dart';
import 'package:chinese_chess_ultra/features/studio/board_setup_rules.dart';

void main() {
  Piece red(PieceKind kind) => Piece(kind: kind, side: Side.red);
  Piece black(PieceKind kind) => Piece(kind: kind, side: Side.black);

  group('BoardSetupRules.placementIssue（位置限制）', () {
    test('帅/将只能放九宫', () {
      // 黑方九宫：col 3~5、row 0~2；红方九宫：col 3~5、row 7~9。
      expect(BoardSetupRules.placementIssue(black(PieceKind.king), 4, 0), isNull);
      expect(BoardSetupRules.placementIssue(black(PieceKind.king), 3, 2), isNull);
      expect(BoardSetupRules.placementIssue(red(PieceKind.king), 4, 9), isNull);
      expect(BoardSetupRules.placementIssue(red(PieceKind.king), 4, 0), isNotNull);
      expect(BoardSetupRules.placementIssue(black(PieceKind.king), 0, 0), isNotNull);
      expect(BoardSetupRules.placementIssue(black(PieceKind.king), 8, 1), isNotNull);
      expect(BoardSetupRules.placementIssue(black(PieceKind.king), 4, 3), isNotNull);
    });

    test('士/仕限九宫 5 个斜线点', () {
      // 黑方斜线点：(3,0),(5,0),(4,1),(3,2),(5,2)。
      expect(BoardSetupRules.placementIssue(black(PieceKind.advisor), 4, 1), isNull);
      expect(BoardSetupRules.placementIssue(black(PieceKind.advisor), 3, 0), isNull);
      expect(BoardSetupRules.placementIssue(black(PieceKind.advisor), 4, 0), isNotNull);
      // 红方斜线点：(3,7),(5,7),(4,8),(3,9),(5,9)。
      expect(BoardSetupRules.placementIssue(red(PieceKind.advisor), 4, 8), isNull);
      expect(BoardSetupRules.placementIssue(red(PieceKind.advisor), 5, 9), isNull);
      expect(BoardSetupRules.placementIssue(red(PieceKind.advisor), 4, 7), isNotNull);
      // 不能进对方九宫。
      expect(BoardSetupRules.placementIssue(red(PieceKind.advisor), 4, 1), isNotNull);
      expect(BoardSetupRules.placementIssue(black(PieceKind.advisor), 4, 8), isNotNull);
    });

    test('相/象限己方半场田字点（偶数列 × 固定奇偶行），不能过河', () {
      // 红相（奇数行 5/7/9 × 偶数列）：起点 (2,9),(6,9)。
      expect(BoardSetupRules.placementIssue(red(PieceKind.minister), 2, 9), isNull);
      expect(BoardSetupRules.placementIssue(red(PieceKind.minister), 8, 7), isNull);
      expect(BoardSetupRules.placementIssue(red(PieceKind.minister), 0, 5), isNull);
      expect(BoardSetupRules.placementIssue(red(PieceKind.minister), 4, 9), isNull);
      // 非法：奇数列 / 偶数行 / 对方半场。
      expect(BoardSetupRules.placementIssue(red(PieceKind.minister), 1, 9), isNotNull);
      expect(BoardSetupRules.placementIssue(red(PieceKind.minister), 0, 6), isNotNull);
      expect(BoardSetupRules.placementIssue(red(PieceKind.minister), 2, 8), isNotNull);
      expect(BoardSetupRules.placementIssue(red(PieceKind.minister), 6, 6), isNotNull);
      expect(BoardSetupRules.placementIssue(red(PieceKind.minister), 2, 4), isNotNull);
      // 黑象（偶数行 0/2/4 × 偶数列）：起点 (2,0),(6,0)。
      expect(BoardSetupRules.placementIssue(black(PieceKind.minister), 4, 2), isNull);
      expect(BoardSetupRules.placementIssue(black(PieceKind.minister), 6, 0), isNull);
      expect(BoardSetupRules.placementIssue(black(PieceKind.minister), 8, 4), isNull);
      // 非法：奇数行（如 (4,1),(6,3)）。
      expect(BoardSetupRules.placementIssue(black(PieceKind.minister), 4, 1), isNotNull);
      expect(BoardSetupRules.placementIssue(black(PieceKind.minister), 6, 3), isNotNull);
      expect(BoardSetupRules.placementIssue(black(PieceKind.minister), 4, 5), isNotNull);
    });

    test('兵/卒不能放本方底线三排', () {
      expect(BoardSetupRules.placementIssue(red(PieceKind.pawn), 0, 6), isNull);
      expect(BoardSetupRules.placementIssue(red(PieceKind.pawn), 4, 0), isNull);
      expect(BoardSetupRules.placementIssue(red(PieceKind.pawn), 4, 7), isNotNull);
      expect(BoardSetupRules.placementIssue(red(PieceKind.pawn), 4, 9), isNotNull);
      expect(BoardSetupRules.placementIssue(black(PieceKind.pawn), 4, 3), isNull);
      expect(BoardSetupRules.placementIssue(black(PieceKind.pawn), 4, 9), isNull);
      expect(BoardSetupRules.placementIssue(black(PieceKind.pawn), 4, 2), isNotNull);
      expect(BoardSetupRules.placementIssue(black(PieceKind.pawn), 4, 0), isNotNull);
    });

    test('车马炮无位置限制', () {
      expect(BoardSetupRules.placementIssue(red(PieceKind.rook), 0, 0), isNull);
      expect(BoardSetupRules.placementIssue(black(PieceKind.knight), 8, 9), isNull);
      expect(BoardSetupRules.placementIssue(red(PieceKind.cannon), 4, 4), isNull);
    });
  });

  group('BoardSetupRules 数量限制', () {
    test('countIssueForPlacement：同格替换不计数，超限拒绝', () {
      const king = Piece(kind: PieceKind.king, side: Side.red);
      // 已有 0 枚：可放。
      expect(BoardSetupRules.countIssueForPlacement(king, 0), isNull);
      // 已有 1 枚：再放被拒。
      expect(
        BoardSetupRules.countIssueForPlacement(king, 1),
        contains('最多 1 枚'),
      );
      // 目标格已是同种棋子（替换）：不新增，允许。
      expect(
        BoardSetupRules.countIssueForPlacement(king, 1, occupant: king),
        isNull,
      );
    });

    test('countIssue：全盘统计超限', () {
      const pawn = Piece(kind: PieceKind.pawn, side: Side.red);
      expect(
        BoardSetupRules.countIssue({pawn: 5}),
        isNull,
      );
      expect(
        BoardSetupRules.countIssue({pawn: 6}),
        contains('最多 5 枚'),
      );
    });
  });
}
