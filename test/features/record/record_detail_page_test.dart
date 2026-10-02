import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chinese_chess_ultra/features/board/model/fen.dart';
import 'package:chinese_chess_ultra/features/board/model/move.dart';
import 'package:chinese_chess_ultra/features/record/game_record.dart';
import 'package:chinese_chess_ultra/features/record/record_library_page.dart';
import 'package:chinese_chess_ultra/features/record/record_repository.dart';
import 'package:chinese_chess_ultra/features/storage/game_dao.dart';

/// TC-DET-001~005：棋谱详情逐手重放、解法切换、无解/超时文案。
void main() {
  late GameDao dao;

  setUp(() {
    dao = GameDao.inMemory();
  });

  tearDown(() {
    dao.dispose();
  });

  Future<void> pumpDetail(WidgetTester tester, GameRecord record) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recordRepositoryProvider.overrideWith(
            (ref) => RecordRepository(dao),
          ),
        ],
        child: MaterialApp(home: RecordDetailPage(record: record)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('TC-DET-001/002 逐手前进、首末跳转', (tester) async {
    await pumpDetail(tester, _sessionRecord());

    expect(find.text('0 / 2 着'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(find.text('1 / 2 着'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2 着'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.first_page));
    await tester.pumpAndSettle();
    expect(find.text('0 / 2 着'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.last_page));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2 着'), findsOneWidget);
  });

  testWidgets('TC-DET-003 点击中文记谱芯片跳转到对应局面', (tester) async {
    await pumpDetail(tester, _sessionRecord());
    await tester.tap(find.text('1. 炮二平五'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 2 着'), findsOneWidget);
  });

  testWidgets('TC-DET-004 多解残局：线路切换独立重放', (tester) async {
    await pumpDetail(tester, _solvedEndgameRecord());

    // 无对局走法的残局自动定位到第一条解法。
    expect(find.text('0 / 1 着'), findsOneWidget);

    // 打开线路下拉，切到解法 2。
    await tester.tap(find.text('解法 1（1 着）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('解法 2（1 着）').last);
    await tester.pumpAndSettle();
    expect(find.text('0 / 1 着'), findsOneWidget);

    // 切回主变：无着法。
    await tester.tap(find.text('解法 2（1 着）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('主变（无着法）').last);
    await tester.pumpAndSettle();
    expect(find.text('0 / 0 着'), findsOneWidget);
  });

  testWidgets('TC-DET-005 无解/超时棋谱显示求解结论文案', (tester) async {
    await pumpDetail(tester, GameRecord(
      title: '无解谱',
      mode: GameRecord.endgameMode,
      initialFen: '3k5/9/9/9/9/9/9/9/9/4K4 w',
      moves: const [],
      solveStatus: SolveStatus.noSolution,
      createdAt: DateTime.now(),
    ));
    expect(
      find.text('求解结论: 无解（深度上界内已证明）'),
      findsOneWidget,
    );

    await pumpDetail(tester, GameRecord(
      title: '未决谱',
      mode: GameRecord.endgameMode,
      initialFen: '3k5/9/9/9/9/9/9/9/9/4K4 w',
      moves: const [],
      solveStatus: SolveStatus.timeout,
      createdAt: DateTime.now(),
    ));
    expect(find.text('求解结论: 限时内未找到解法'), findsOneWidget);
  });
}

/// 两着对局记录（炮二平五 / 马8进7，含棋子信息）。
GameRecord _sessionRecord() {
  return GameRecord(
    title: '对局',
    mode: 'humanVsHuman',
    initialFen: Fen.initial,
    moves: fillMovePieces(
      Fen.initial,
      const [
        Move(from: Position(7, 7), to: Position(4, 7)),
        Move(from: Position(7, 0), to: Position(6, 2)),
      ],
    ),
    createdAt: DateTime.parse('2026-10-02T08:00:00Z'),
  );
}

/// 多解残局记录（解法一：车一平三 a5d5；解法二：车二平三 i4d4）。
GameRecord _solvedEndgameRecord() {
  return GameRecord(
    title: '多解残局',
    mode: GameRecord.endgameMode,
    initialFen: '3k5/9/9/9/R8/8R/9/9/9/4K4 w',
    moves: const [],
    solveStatus: SolveStatus.solved,
    solutions: const [
      ['a5d5'],
      ['i4d4'],
    ],
    createdAt: DateTime.parse('2026-10-02T08:00:00Z'),
  );
}
