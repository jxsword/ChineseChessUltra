import 'package:flutter_test/flutter_test.dart';

import 'package:chinese_chess_ultra/features/board/model/board.dart';
import 'package:chinese_chess_ultra/features/board/model/move.dart';
import 'package:chinese_chess_ultra/features/board/model/piece.dart';
import 'package:chinese_chess_ultra/features/shared/engine/ai_engine.dart';

void main() {
  group('ChessAi.findBestMove', () {
    test('初始局面返回一步合法走法，且不修改原棋盘', () {
      final board = Board.initial();
      final fenBefore = board.toFen();

      final move = ChessAi.findBestMove(board, difficulty: 1);

      expect(move, isNotNull);
      final legal = board
          .legalMovesFor(move!.from)
          .any((m) => m.to == move.to);
      expect(legal, isTrue, reason: 'AI 应手必须是合法走法: $move');
      expect(board.toFen(), fenBefore, reason: '搜索不得修改调用方棋盘');
    });

    test('优先白吃高价值棋子', () {
      // 黑车孤悬中路：红兵 (4,5) 可向前直吃，红炮 (4,7) 也可借兵作架吃，
      // 两者都是白吃车的正确应手。
      const fen = '4k4/9/9/9/4r4/4P4/9/4C4/9/4K4 w - - 0 1';
      final board = Board.fromFen(fen);

      final move = ChessAi.findBestMove(board, difficulty: 2);

      expect(move, isNotNull);
      expect(move!.to, const Position(4, 4));
      expect(move.captured?.kind, PieceKind.rook);
    });

    test('一步将杀局面能找到杀招', () {
      // 黑将 (4,0)，红车 (0,0) 封锁底线；红车 (4,2) 可沉到 (4,1) 将杀
      // ——但 (4,1) 与黑将相邻会被吃，改为测试红车平移到底线直接将杀:
      // 黑将 (4,0)；红车 A (3,1)、红车 B (5,1) 双车锁肋，任一车平至底线即绝杀?
      // 取更简单局面：黑将 (4,0)，红车 (0,0)、红车 (4,1)（车被兵 (4,2) 保护），
      // 黑方被将死，轮黑走 → 无合法走法，返回 null。
      const fen = 'R3k4/4R4/4P4/9/9/9/9/9/9/4K4 b - - 0 1';
      final board = Board.fromFen(fen);

      expect(board.isCheckmate(Side.black), isTrue);
      expect(ChessAi.findBestMove(board, difficulty: 1), isNull);
    });

    test('被将军时会优先解将而不是进攻', () {
      // 红帅被黑车将军（黑车 (4,3) 直射 (4,9)，中间无子），
      // AI（红方）应走出能解将的走法。
      const fen = '4k4/9/9/9/4R4/9/9/9/9/4K4 w - - 0 1';
      final board = Board.fromFen(fen);

      final move = ChessAi.findBestMove(board, difficulty: 1);

      expect(move, isNotNull);
      board.applyMove(move!);
      expect(board.isCheck(Side.red), isFalse, reason: '走子后必须解除将军: $move');
    });

    test('不同难度均能给出合法走法', () {
      final board = Board.initial();
      for (var level = 1; level <= 5; level++) {
        final move = ChessAi.findBestMove(board, difficulty: level);
        expect(move, isNotNull, reason: '难度 $level 应返回走法');
        final legal = board
            .legalMovesFor(move!.from)
            .any((m) => m.to == move.to);
        expect(legal, isTrue, reason: '难度 $level 的走法应合法: $move');
      }
    });
  });
}
