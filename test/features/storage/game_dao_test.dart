import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_chess_ultra/features/storage/game_dao.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late GameDao dao;

  setUp(() {
    dao = GameDao.inMemory();
  });

  tearDown(() {
    dao.dispose();
  });

  test('upsert 后 latest 应返回相同数据', () {
    final id = dao.upsert(
      fen: 'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w',
      moves: [
        [0, 9, 0, 8],
      ],
    );
    expect(id, greaterThan(0));

    final latest = dao.latest();
    expect(latest, isNotNull);
    expect(latest!.id, id);
    expect(
      latest.fen,
      'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w',
    );
    expect(latest.moves, [
      [0, 9, 0, 8],
    ]);
  });

  test('upsert 已有 id 时为更新而非新增', () {
    final id = dao.upsert(
      fen: 'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w',
      moves: [],
    );
    dao.upsert(id: id, fen: 'changed', moves: [
      [1, 2, 3, 4],
    ]);
    final all = dao.all();
    expect(all.length, 1);
    expect(all.first.fen, 'changed');
  });

  test('latest 按 updatedAt 倒序取最新', () async {
    dao.upsert(fen: 'first', moves: []);
    // 确保时间戳不同。
    await Future<void>.delayed(const Duration(seconds: 1));
    dao.upsert(fen: 'second', moves: []);
    final latest = dao.latest();
    expect(latest, isNotNull);
    expect(latest!.fen, 'second');
  });

  test('delete 后 latest 不返回该条', () {
    final id = dao.upsert(fen: 'first', moves: []);
    dao.delete(id);
    expect(dao.latest(), isNull);
  });

  test('clear 后所有记录被清空', () {
    dao.upsert(fen: 'a', moves: []);
    dao.upsert(fen: 'b', moves: []);
    dao.clear();
    expect(dao.all(), isEmpty);
  });

  group('按模式分存', () {
    test('不同模式各存一份，互不覆盖', () {
      dao.upsertForMode(mode: 'humanVsAi', fen: 'fen-a', moves: [
        [0, 9, 0, 8],
      ]);
      dao.upsertForMode(mode: 'humanVsHuman', fen: 'fen-b', moves: []);
      dao.upsertForMode(mode: 'aiVsAi', fen: 'fen-c', moves: []);

      expect(dao.latestForMode('humanVsAi')!.fen, 'fen-a');
      expect(dao.latestForMode('humanVsHuman')!.fen, 'fen-b');
      expect(dao.latestForMode('aiVsAi')!.fen, 'fen-c');
      expect(dao.all().length, 3);
    });

    test('同模式重复保存覆盖为一条', () {
      dao.upsertForMode(mode: 'humanVsAi', fen: 'old', moves: []);
      dao.upsertForMode(mode: 'humanVsAi', fen: 'new', moves: [
        [1, 1, 1, 2],
      ]);

      final saved = dao.latestForMode('humanVsAi');
      expect(saved!.fen, 'new');
      expect(saved.moves, [
        [1, 1, 1, 2],
      ]);
      expect(dao.all().length, 1);
    });

    test('无存档的模式返回 null，legacy 数据不属于任何模式', () {
      dao.upsert(fen: 'legacy-row', moves: []);
      expect(dao.latestForMode('humanVsAi'), isNull);
      expect(dao.latestForMode('legacy'), isNull);
      expect(dao.latest()!.fen, 'legacy-row');
    });

    test('deleteForMode 只删除该模式', () {
      dao.upsertForMode(mode: 'humanVsAi', fen: 'a', moves: []);
      dao.upsertForMode(mode: 'aiVsAi', fen: 'b', moves: []);

      dao.deleteForMode('humanVsAi');

      expect(dao.latestForMode('humanVsAi'), isNull);
      expect(dao.latestForMode('aiVsAi')!.fen, 'b');
    });
  });

  group('旧库迁移（一期无 mode 列）', () {
    test('补齐 mode 列，老数据标记 legacy 且按模式查不到', () {
      final db = sqlite3.openInMemory();
      // 模拟一期建表结构与数据。
      db.execute('''
        CREATE TABLE saved_games (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          fen TEXT NOT NULL,
          move_stack_json TEXT NOT NULL,
          created_at TEXT DEFAULT CURRENT_TIMESTAMP,
          updated_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
      ''');
      db.execute(
        "INSERT INTO saved_games(fen, move_stack_json) VALUES ('old-fen', '[]')",
      );

      final migrated = GameDao.fromDatabase(db);
      addTearDown(migrated.dispose);

      // 迁移后新写入按模式分存正常。
      migrated.upsertForMode(mode: 'humanVsAi', fen: 'new-fen', moves: []);
      expect(migrated.latestForMode('humanVsAi')!.fen, 'new-fen');
      // 老数据仍在库里，但不属于任何正式模式。
      final legacy = migrated
          .all()
          .where((g) => g.fen == 'old-fen')
          .toList();
      expect(legacy.length, 1);
      expect(legacy.first.mode, 'legacy');
      expect(migrated.latestForMode('legacy')!.fen, 'old-fen');
      // 正式模式（GameMode.name）读不到 legacy 数据。
      expect(migrated.latestForMode('humanVsHuman'), isNull);
    });
  });
}
