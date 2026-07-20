import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_chess_ultra/features/storage/game_dao.dart';

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
}
