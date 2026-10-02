import 'package:flutter_test/flutter_test.dart';

import 'package:chinese_chess_ultra/features/board/model/move.dart';
import 'package:chinese_chess_ultra/features/puzzle/model/iccs.dart';
import 'package:chinese_chess_ultra/features/record/game_record.dart';
import 'package:chinese_chess_ultra/features/record/pgn_writer.dart';

void main() {
  /// 残局求解记录（无对局走法，只有解法）。
  GameRecord endgameRecord(SolveStatus status, List<List<String>> solutions) =>
      GameRecord(
        title: '残局测试',
        mode: GameRecord.endgameMode,
        initialFen: '3k5/9/9/9/9/9/9/9/9/4K4 w',
        moves: const [],
        solveStatus: status,
        solutions: solutions,
        createdAt: DateTime.parse('2026-10-02T08:00:00Z'),
      );

  /// 标准开局两步的对局记录。
  GameRecord sessionRecord() {
    final moves = [
      const Move(from: Position(7, 7), to: Position(4, 7)),
      const Move(from: Position(7, 0), to: Position(6, 2)),
    ];
    return GameRecord.fromSession(
      title: '对局测试',
      mode: 'humanVsHuman',
      finalFen: finalFenOf(moves),
      moves: moves,
      redName: '玩家甲',
      blackName: '玩家乙',
      createdAt: DateTime.parse('2026-10-02T08:00:00Z'),
    );
  }

  group('PgnWriter.write', () {
    test('标准七标签 + ICCS 着法', () {
      final pgn = PgnWriter.write(sessionRecord());
      expect(pgn, contains('[Event "中国象棋 Ultra"]'));
      expect(pgn, contains('[Red "玩家甲"]'));
      expect(pgn, contains('[Black "玩家乙"]'));
      expect(pgn, contains('[Result "*"]'));
      expect(pgn, contains('1. h2e2 h9g7'));
      // 标准开局不写 SetFen。
      expect(pgn, isNot(contains('[SetFen')));
    });

    test('残局记录带 SetFen/FEN 与结果标记', () {
      final pgn = PgnWriter.write(
        endgameRecord(SolveStatus.solved, [
          ['h5h3'],
        ]),
      );
      expect(pgn, contains('[SetFen "3k5/9/9/9/9/9/9/9/9/4K4 w"]'));
      expect(pgn, contains('[Result "1-0"]'));
      expect(pgn, contains('[Annotator "已破解"]'));
    });

    test('无解残局结果标记为 0-1', () {
      final pgn = PgnWriter.write(
        endgameRecord(SolveStatus.noSolution, const []),
      );
      expect(pgn, contains('[Result "0-1"]'));
    });
  });

  group('PgnWriter.writeShareText', () {
    test('对局：中文记谱', () {
      final text = PgnWriter.writeShareText(sessionRecord());
      expect(text, contains('【中国象棋 Ultra 棋谱】对局测试'));
      expect(text, contains('双人对弈'));
      expect(text, contains('1. 炮二平五  马8进7'));
    });

    test('多解残局列出全部解法并标注数量', () {
      final text = PgnWriter.writeShareText(
        endgameRecord(SolveStatus.solved, [
          ['h5h3'],
          ['h5h4'],
          ['h5g5'],
        ]),
      );
      expect(text, contains('破解之法（3 条'));
      expect(text, contains('解法1: h5h3'));
      expect(text, contains('解法3: h5g5'));
    });

    test('无解与超时标记', () {
      expect(
        PgnWriter.writeShareText(
          endgameRecord(SolveStatus.noSolution, const []),
        ),
        contains('无解'),
      );
      expect(
        PgnWriter.writeShareText(endgameRecord(SolveStatus.timeout, const [])),
        contains('限时内未找到解法'),
      );
    });

    test('ICCS 着法可被 Iccs 解析还原（导出可往返）', () {
      final record = sessionRecord();
      final pgn = PgnWriter.write(record);
      final body = pgn.split('\n\n').last.trim();
      final tokens = body
          .replaceAll('*', '')
          .replaceAll(RegExp(r'\d+\.'), '')
          .trim()
          .split(RegExp(r'\s+'))
          .where((t) => t.isNotEmpty)
          .toList();
      expect(tokens, isNotEmpty);
      for (final token in tokens) {
        expect(Iccs.parse(token), isNotNull, reason: 'token=$token');
      }
    });
  });
}

/// 从初始局面重放 moves 得到终局 FEN（测试辅助，不复用业务代码）。
String finalFenOf(List<Move> moves) {
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
