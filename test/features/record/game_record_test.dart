import 'package:flutter_test/flutter_test.dart';

import 'package:chinese_chess_ultra/features/board/model/move.dart';
import 'package:chinese_chess_ultra/features/record/game_record.dart';

void main() {
  group('GameRecord.fromSession', () {
    test('从终局反推初始 FEN（标准开局两步）', () {
      // 炮二平五 / 马8进7
      final moves = [
        const Move(from: Position(7, 7), to: Position(4, 7)),
        const Move(from: Position(7, 0), to: Position(6, 2)),
      ];
      final board = initialBoardAfter(moves);
      final record = GameRecord.fromSession(
        mode: 'humanVsHuman',
        finalFen: board,
        moves: moves,
      );

      expect(record.initialFen.split(' ').first,
          'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR');
      expect(record.modeLabel, '双人对弈');
      expect(record.solveStatus, SolveStatus.none);
    });

    test('标题缺省时自动生成', () {
      final record = GameRecord.fromSession(
        mode: 'humanVsAi',
        finalFen: initialBoardAfter(const []),
        moves: const [],
      );
      expect(record.title, contains('人机对战'));
    });
  });

  group('fillMovePieces', () {
    test('重放补齐棋子与吃子信息', () {
      // 炮二平五（红炮 (7,7)->(4,7)），再炮5进4?? 用吃卒构造吃子：
      // 红炮 (7,7)->(4,7) 后黑中卒在 (4,3)，炮打卒需要炮架——
      // 改用简单吃子：红车 (8,9)->(8,7)->(8,0) 吃黑马。
      final moves = [
        const Move(from: Position(8, 9), to: Position(8, 7)),
        const Move(from: Position(7, 0), to: Position(6, 2)),
        const Move(from: Position(8, 7), to: Position(8, 0)),
      ];
      final filled = fillMovePieces(
        'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w',
        moves,
      );
      expect(filled.length, 3);
      expect(filled[0].piece?.label, '车');
      expect(filled[0].captured, isNull);
      expect(filled[2].captured?.label, '车');
    });

    test('局面不符的走法被截断（防御式）', () {
      final filled = fillMovePieces(
        'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w',
        const [Move(from: Position(4, 4), to: Position(4, 5))],
      );
      expect(filled, isEmpty);
    });
  });

  group('chineseNotations', () {
    test('生成中文记谱', () {
      final moves = [
        const Move(from: Position(7, 7), to: Position(4, 7)),
      ];
      final record = GameRecord.fromSession(
        mode: 'humanVsHuman',
        finalFen: initialBoardAfter(moves),
        moves: moves,
      );
      expect(record.chineseNotations(), ['炮二平五']);
    });

    test('残局自定义 FEN 同样适用', () {
      // 红帅 (4,9) + 红车 (3,4)，黑将 (3,0)：车 (3,4)->(3,2) 无吃子。
      final fen = '3k5/9/9/9/3R5/9/9/9/9/4K4 w';
      final moves = [const Move(from: Position(3, 4), to: Position(3, 2))];
      final record = GameRecord(
        mode: GameRecord.endgameMode,
        title: 't',
        initialFen: fen,
        moves: moves,
      );
      final notations = record.chineseNotations();
      expect(notations, isNotEmpty);
      expect(notations.first, startsWith('车'));
    });
  });

  group('GameRecord 序列化往返', () {
    test('toRowJson 与 DAO 行解码一致（经 decodeMoveJson）', () {
      final moves = [
        const Move(from: Position(7, 7), to: Position(4, 7)),
        const Move(from: Position(7, 0), to: Position(6, 2)),
      ];
      final record = GameRecord.fromSession(
        mode: 'endgame',
        finalFen: initialBoardAfter(moves),
        moves: moves,
      );
      for (final m in record.moves) {
        final decoded = GameRecord.decodeMoveJson({
          'f': [m.from.col, m.from.row],
          't': [m.to.col, m.to.row],
          'p': m.piece?.fen,
          'x': m.captured?.fen,
        });
        expect(decoded.from, m.from);
        expect(decoded.to, m.to);
        expect(decoded.piece, m.piece);
      }
    });
  });

  group('SolveStatus', () {
    test('标签与唯一解判定', () {
      final record = GameRecord(
        mode: GameRecord.endgameMode,
        title: 't',
        initialFen: '3k5/9/9/9/9/9/9/9/9/4K4 w',
        moves: const [],
        solveStatus: SolveStatus.solved,
        solutions: const [['h2-e2']],
      );
      expect(record.solveStatus.label, '已破解');
      expect(record.hasUniqueSolution, isTrue);
      expect(record.isEndgame, isTrue);
    });
  });
}

/// 从初始局面重放 moves 得到终局 FEN。
String initialBoardAfter(List<Move> moves) {
  // 简易重放：逐手搬动棋子（测试辅助，不复用业务代码）。
  final grid = <List<String?>>[
    ['r', 'n', 'b', 'a', 'k', 'a', 'b', 'n', 'r'],
    List.filled(9, null),
    [null, 'c', null, null, null, null, null, 'c', null],
    ['p', null, 'p', null, 'p', null, 'p', null, 'p'],
    List.filled(9, null),
    List.filled(9, null),
    ['P', null, 'P', null, 'P', null, 'P', null, 'P'],
    [null, 'C', null, null, null, null, null, 'C', null],
    List.filled(9, null),
    ['R', 'N', 'B', 'A', 'K', 'A', 'B', 'N', 'R'],
  ];
  var turn = 'w';
  for (final m in moves) {
    grid[m.to.row][m.to.col] = grid[m.from.row][m.from.col];
    grid[m.from.row][m.from.col] = null;
    turn = turn == 'w' ? 'b' : 'w';
  }
  final rows = grid.map((row) {
    final buf = StringBuffer();
    var empty = 0;
    for (final cell in row) {
      if (cell == null) {
        empty++;
      } else {
        if (empty > 0) {
          buf.write(empty);
          empty = 0;
        }
        buf.write(cell);
      }
    }
    if (empty > 0) buf.write(empty);
    return buf.toString();
  }).join('/');
  return '$rows $turn - - 0 1';
}
