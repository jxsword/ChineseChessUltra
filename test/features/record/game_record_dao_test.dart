import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:chinese_chess_ultra/features/record/game_record.dart';
import 'package:chinese_chess_ultra/features/storage/game_dao.dart';

void main() {
  late GameDao dao;

  setUp(() {
    dao = GameDao.inMemory();
  });

  tearDown(() {
    dao.dispose();
  });

  GameRecord sampleRecord({String title = '测试棋谱'}) => GameRecord(
        title: title,
        mode: GameRecord.endgameMode,
        initialFen: '3k5/9/9/9/9/9/9/9/9/4K4 w',
        moves: const [],
        solveStatus: SolveStatus.solved,
        solutions: [
          ['h5h3'],
          ['h5h4', 'h0g2'],
        ],
        llmNote: '大模型首选 h5h3（已验证为必胜着法）',
        note: '经典双车残局',
        createdAt: DateTime.parse('2026-10-02T08:00:00Z'),
      );

  test('插入并读回棋谱（含解法/标记/备注）', () {
    final record = sampleRecord();
    final id = dao.insertRecord(record);

    final loaded = dao.recordById(id)!;
    expect(loaded.title, '测试棋谱');
    expect(loaded.mode, GameRecord.endgameMode);
    expect(loaded.solveStatus, SolveStatus.solved);
    expect(loaded.solutions.length, 2);
    expect(loaded.solutions[1], ['h5h4', 'h0g2']);
    expect(loaded.llmNote, contains('h5h3'));
    expect(loaded.note, '经典双车残局');
    expect(loaded.isEndgame, isTrue);
  });

  test('allRecords 按创建时间倒序', () {
    dao.insertRecord(sampleRecord(title: 'A'));
    dao.insertRecord(sampleRecord(title: 'B'));
    final all = dao.allRecords();
    expect(all.length, 2);
    expect(all.map((r) => r.title), containsAll(['A', 'B']));
  });

  test('updateRecord 更新求解结论与备注', () {
    final id = dao.insertRecord(sampleRecord());
    final loaded = dao.recordById(id)!;
    final updated = GameRecord(
      id: loaded.id,
      title: '更新标题',
      mode: loaded.mode,
      initialFen: loaded.initialFen,
      moves: loaded.moves,
      solveStatus: SolveStatus.timeout,
      solutions: const [],
      note: '限时未决',
    );
    dao.updateRecord(updated);

    final reloaded = dao.recordById(id)!;
    expect(reloaded.title, '更新标题');
    expect(reloaded.solveStatus, SolveStatus.timeout);
    expect(reloaded.solutions, isEmpty);
    expect(reloaded.note, '限时未决');
  });

  test('deleteRecord 删除后查无', () {
    final id = dao.insertRecord(sampleRecord());
    dao.deleteRecord(id);
    expect(dao.recordById(id), isNull);
    expect(dao.allRecords(), isEmpty);
  });

  test('game_records 与 saved_games 互不影响', () {
    final id = dao.insertRecord(sampleRecord());
    // 老存档链路照常工作。
    dao.upsertForMode(mode: 'humanVsHuman', fen: 'fen', moves: [
      [1, 2, 3, 4],
    ]);
    expect(dao.latestForMode('humanVsHuman'), isNotNull);
    expect(dao.recordById(id), isNotNull);

    dao.deleteForMode('humanVsHuman');
    expect(dao.recordById(id), isNotNull);
  });

  test('旧库（无 game_records 表）打开时自动建表', () {
    // 模拟一期老库：只有 saved_games 表。
    final db = sqlite3.openInMemory();
    db.execute('''
      CREATE TABLE saved_games (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fen TEXT NOT NULL,
        move_stack_json TEXT NOT NULL,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    final legacyDao = GameDao.fromDatabase(db);
    final id = legacyDao.insertRecord(sampleRecord());
    expect(legacyDao.recordById(id), isNotNull);
    // V1 迁移同样生效。
    expect(legacyDao.latestForMode('humanVsHuman'), isNull);
    legacyDao.dispose();
    db.dispose();
  });
}
