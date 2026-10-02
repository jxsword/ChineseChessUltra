import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chinese_chess_ultra/features/board/model/fen.dart';
import 'package:chinese_chess_ultra/features/board/model/move.dart';
import 'package:chinese_chess_ultra/features/record/game_record.dart';
import 'package:chinese_chess_ultra/features/record/record_library_page.dart';
import 'package:chinese_chess_ultra/features/record/record_repository.dart';
import 'package:chinese_chess_ultra/features/storage/game_dao.dart';

/// TC-LIB-001~007：棋谱库列表、筛选、导出复制、删除（record_library_page.dart）。
void main() {
  late GameDao dao;

  setUp(() {
    dao = GameDao.inMemory();
    dao.insertRecord(_gameRecord('对局甲'));
    dao.insertRecord(_endgameRecord(
      '残局乙',
      SolveStatus.solved,
      [
        ['a5d5'],
        ['i4d4'],
      ],
    ));
    dao.insertRecord(
      _endgameRecord('残局丙', SolveStatus.noSolution, const []),
    );
  });

  tearDown(() {
    dao.dispose();
  });

  Future<void> pumpLibrary(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recordRepositoryProvider.overrideWith(
            (ref) => RecordRepository(dao),
          ),
        ],
        child: const MaterialApp(home: RecordLibraryPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('TC-LIB-001 列表展示全部棋谱', (tester) async {
    await pumpLibrary(tester);
    expect(find.text('对局甲'), findsOneWidget);
    expect(find.text('残局乙'), findsOneWidget);
    expect(find.text('残局丙'), findsOneWidget);
  });

  testWidgets('TC-LIB-002 状态筛选', (tester) async {
    await pumpLibrary(tester);

    await tester.tap(find.text('对局'));
    await tester.pumpAndSettle();
    expect(find.text('对局甲'), findsOneWidget);
    expect(find.text('残局乙'), findsNothing);

    await tester.tap(find.text('已破解'));
    await tester.pumpAndSettle();
    expect(find.text('残局乙'), findsOneWidget);
    expect(find.text('对局甲'), findsNothing);

    await tester.tap(find.text('无解'));
    await tester.pumpAndSettle();
    expect(find.text('残局丙'), findsOneWidget);
    expect(find.text('残局乙'), findsNothing);
  });

  testWidgets('TC-LIB-003/004 导出 PGN 与分享文本复制', (tester) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = call.arguments['text'] as String;
        }
        return null;
      },
    );
    await pumpLibrary(tester);

    // 列表按 id 倒序：丙、乙、甲 → .at(1) 是残局乙（多解残局）。
    await tester.tap(find.byIcon(Icons.more_vert).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导出 PGN（复制）'));
    await tester.pumpAndSettle();
    expect(clipboard, contains('[Event "中国象棋 Ultra"]'));
    expect(clipboard, contains('[SetFen'));
    expect(clipboard, contains('[Result "1-0"]'));

    clipboard = null;
    await tester.tap(find.byIcon(Icons.more_vert).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分享文本（复制）'));
    await tester.pumpAndSettle();
    expect(clipboard, contains('破解之法（2 条'));
    expect(clipboard, contains('解法1: a5d5'));
  });

  testWidgets('TC-LIB-007 删除确认框取消后棋谱保留', (tester) async {
    await pumpLibrary(tester);
    await tester.tap(find.byIcon(Icons.more_vert).at(0)); // 残局丙
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(dao.allRecords().length, 3);
    expect(find.text('残局丙'), findsOneWidget);
  });

  testWidgets('TC-LIB-006 删除确认后棋谱移除且持久化生效', (tester) async {
    await pumpLibrary(tester);
    await tester.tap(find.byIcon(Icons.more_vert).at(0)); // 残局丙
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(dao.allRecords().length, 2);
    expect(find.text('残局丙'), findsNothing);
    expect(find.text('残局乙'), findsOneWidget);
  });
}

/// 一条普通对局棋谱（两着：炮二平五 / 马8进7，标准开局）。
GameRecord _gameRecord(String title) {
  return GameRecord(
    title: title,
    mode: 'humanVsHuman',
    initialFen: Fen.initial,
    moves: fillMovePieces(
      Fen.initial,
      const [
        Move(from: Position(7, 7), to: Position(4, 7)),
        Move(from: Position(7, 0), to: Position(6, 2)),
      ],
    ),
    solveStatus: SolveStatus.none,
    createdAt: DateTime.parse('2026-10-02T08:00:00Z'),
  );
}

/// 一条残局棋谱（无对局走法，只有求解结论与解法）。
GameRecord _endgameRecord(
  String title,
  SolveStatus status,
  List<List<String>> solutions,
) {
  return GameRecord(
    title: title,
    mode: GameRecord.endgameMode,
    initialFen: '3k5/9/9/9/R8/8R/9/9/9/4K4 w',
    moves: const [],
    solveStatus: status,
    solutions: solutions,
    createdAt: DateTime.parse('2026-10-02T08:00:00Z'),
  );
}
