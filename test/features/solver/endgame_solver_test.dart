import 'package:flutter_test/flutter_test.dart';

import 'package:chinese_chess_ultra/features/board/model/move.dart';
import 'package:chinese_chess_ultra/features/solver/endgame_solver.dart';

void main() {
  /// 双车闷杀残局（红先，多着皆可 1 着制胜）：
  /// - 黑将 (0,0)，黑卒 (1,1) 堵住 (1,1)；
  /// - 红马 (2,2) 永久盖住 (1,0)（马腿 (2,1) 为空）；
  /// - 红车一 (5,6)、红车二 (8,4)：任意一车平 0 列即沿 0 列将军成杀；
  /// - 红帅 (3,9)。初始黑方未被将军（合法）。
  const mateIn1Fen = 'k8/1p7/2N6/9/8R/9/5R3/9/9/3K5 w';

  group('mate-in-1 残局', () {
    test('解出多条破解走法（两车各平 0 列皆杀）', () async {
      final result = await EndgameSolver.solve(
        mateIn1Fen,
        timeLimit: const Duration(seconds: 10),
        maxPlies: 3,
      );
      expect(result.status, EndgameSolveStatus.solved);
      expect(result.solutions.length, greaterThanOrEqualTo(2));
      for (final solution in result.solutions) {
        expect(solution.moves.length, 1); // 一着制胜
      }
      final toSquares = result.solutions
          .map((s) => '${s.moves.first.to.col},${s.moves.first.to.row}')
          .toSet();
      expect(toSquares, contains('0,6')); // 车一 (5,6) 平 0 列
      expect(toSquares, contains('0,4')); // 车二 (8,4) 平 0 列
    });

    test('isWinningFirstMove：车一 (5,6)->(0,6) 为必胜首着', () {
      expect(
        EndgameSolver.isWinningFirstMove(
          fen: mateIn1Fen,
          firstMove: const Move(from: Position(5, 6), to: Position(0, 6)),
          plies: 1,
        ),
        isTrue,
      );
    });

    test('isWinningFirstMove：跳开马则 1 着内非必胜', () {
      expect(
        EndgameSolver.isWinningFirstMove(
          fen: mateIn1Fen,
          firstMove: const Move(from: Position(2, 2), to: Position(4, 1)),
          plies: 1,
        ),
        isFalse,
      );
    });
  });

  group('无解', () {
    test('裸王局面在深度上界内证明无解', () async {
      final result = await EndgameSolver.solve(
        '3k5/9/9/9/9/9/9/9/9/4K4 w',
        timeLimit: const Duration(seconds: 10),
        maxPlies: 5,
      );
      expect(result.status, EndgameSolveStatus.noSolution);
      expect(result.solutions, isEmpty);
    });
  });

  group('超时', () {
    test('初始局面 + 极短限时 → timeout', () async {
      final result = await EndgameSolver.solve(
        'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w',
        timeLimit: const Duration(milliseconds: 1),
        maxPlies: 9,
      );
      expect(result.status, EndgameSolveStatus.timeout);
    });
  });

  group('0 步解', () {
    test('对方已被将死/困毙时直接返回 solved', () async {
      // 黑将 (3,0) 已被三车围死（row0/row1/3 列），轮红方走。
      const mateAlreadyFen = 'R2k4R/R8/9/9/3R5/9/9/9/9/4K4 w';
      final result = await EndgameSolver.solve(
        mateAlreadyFen,
        timeLimit: const Duration(seconds: 5),
        maxPlies: 3,
      );
      expect(result.status, EndgameSolveStatus.solved);
      expect(result.solutions, isEmpty);
      expect(result.searchedPlies, 0);
    });
  });
}
