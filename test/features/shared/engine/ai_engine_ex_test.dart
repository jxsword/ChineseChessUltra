import 'package:flutter_test/flutter_test.dart';

import 'package:chinese_chess_ultra/features/board/model/board.dart';
import 'package:chinese_chess_ultra/features/board/model/move.dart';
import 'package:chinese_chess_ultra/features/shared/engine/ai_engine.dart';

/// 白吃车局面：黑车 (0,4) 与红车 (0,6) 同在 0 列，中间 (0,5) 为空，
/// 黑王 (3,0) 与红帅 (4,9) 不同列（避免双王照面的非法局面），
/// 红先可直接 R×R。
const captureFen = '3k5/9/9/9/r8/9/R8/9/9/4K4 w';

/// 一步杀局面（endgame_solver_test 同款）：两车各平 3 列皆 1 着杀。
const mateFen = '3k5/9/9/9/R8/8R/9/9/9/4K4 w';

/// 黑方被将死局面：黑将 (4,0) 被红车 (4,5) 领将，红车 (0,0) 封 0 排
/// （(3,0)/(5,0) 出逃格被控），(4,1) 由领将车控制，黑方无子可挡——
/// 轮黑无合法着法。红帅 (4,9) 与黑将间的照面由 (4,5) 红车遮挡。
const deadFen = 'R3k4/9/9/9/9/4R4/9/9/9/4K4 b';

void main() {
  group('ChessAi.findBestMoveEx', () {
    test('Top-K 降序排列，最佳与首位一致', () {
      final board = Board.fromFen(captureFen);
      final report = ChessAi.findBestMoveEx(board, depth: 4, topK: 3)!;

      expect(report.topK, hasLength(3));
      for (var i = 1; i < report.topK.length; i++) {
        expect(report.topK[i].$2, lessThanOrEqualTo(report.topK[i - 1].$2));
      }
      expect(report.best, report.topK.first.$1);
      expect(report.bestCp, report.topK.first.$2);
    });

    test('吃车局面：吃车着法进入 Top-K 且大幅占优', () {
      final board = Board.fromFen(captureFen);
      final report = ChessAi.findBestMoveEx(board, depth: 4, topK: 8)!;
      final eatRook = report.topK.firstWhere(
        (m) =>
            m.$1.from == const Position(0, 6) &&
            m.$1.to == const Position(0, 4),
        orElse: () => throw StateError('吃车着法未入 Top-K'),
      );
      // 黑方损失一车：吃车后从红方视角应大幅占优（> 800 厘兵）。
      expect(eatRook.$2, greaterThan(800));
    });

    test('一步杀局面：bestCp 达到将杀分量级', () {
      final board = Board.fromFen(mateFen);
      final report = ChessAi.findBestMoveEx(board, depth: 4, topK: 3)!;
      expect(report.bestCp, greaterThan(25000));
    });

    test('黑方被将死（轮黑无合法着法）返回 null', () {
      final board = Board.fromFen(deadFen);
      expect(ChessAi.findBestMoveEx(board, depth: 2), isNull);
    });
  });

  group('ChessAi.evaluateMove', () {
    test('好着（吃车）大幅占优，消极着法分差明显', () {
      final board = Board.fromFen(captureFen);
      final eatRook = const Move(from: Position(0, 6), to: Position(0, 4));
      final goodCp = ChessAi.evaluateMove(board, eatRook, depth: 3)!;
      expect(goodCp, greaterThan(800));

      // 消极着法：车横移不吃车（帅平移会与黑王照面，非法）。
      final passive = const Move(from: Position(0, 6), to: Position(5, 6));
      final passiveCp = ChessAi.evaluateMove(board, passive, depth: 3)!;
      expect(passiveCp, lessThan(goodCp));
    });

    test('非法着法返回 null', () {
      final board = Board.fromFen(captureFen);
      // 起点无己方棋子。
      expect(
        ChessAi.evaluateMove(
            board, const Move(from: Position(0, 0), to: Position(0, 1))),
        isNull,
      );
      // 起点是对方棋子。
      expect(
        ChessAi.evaluateMove(
            board, const Move(from: Position(0, 4), to: Position(0, 6))),
        isNull,
      );
    });
  });
}
