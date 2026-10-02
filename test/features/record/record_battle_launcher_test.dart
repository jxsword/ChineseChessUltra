import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chinese_chess_ultra/app/app.dart';
import 'package:chinese_chess_ultra/features/board/model/board_state.dart';
import 'package:chinese_chess_ultra/features/board/model/fen.dart';
import 'package:chinese_chess_ultra/features/board/model/move.dart';
import 'package:chinese_chess_ultra/features/board/view/human_vs_ai_page.dart';
import 'package:chinese_chess_ultra/features/board/view/human_vs_human_page.dart';
import 'package:chinese_chess_ultra/features/board/viewmodel/board_vm.dart';
import 'package:chinese_chess_ultra/features/record/game_record.dart';
import 'package:chinese_chess_ultra/features/record/record_battle_launcher.dart';
import 'package:chinese_chess_ultra/features/storage/game_dao.dart';
import 'package:chinese_chess_ultra/features/storage/repository.dart';

/// 对局类棋谱（两着：炮二平五 / 马8进7，未分胜负）。
GameRecord sessionRecord({GameResult? result}) {
  final moves = fillMovePieces(
    Fen.initial,
    const [
      Move(from: Position(7, 7), to: Position(4, 7)),
      Move(from: Position(7, 0), to: Position(6, 2)),
    ],
  );
  return GameRecord(
    title: '对局',
    mode: 'humanVsHuman',
    initialFen: Fen.initial,
    moves: moves,
    result: result,
    createdAt: DateTime.parse('2026-10-02T08:00:00Z'),
  );
}

/// 多解残局棋谱。
GameRecord endgameRecord({SolveStatus status = SolveStatus.solved}) {
  return GameRecord(
    title: '残局',
    mode: GameRecord.endgameMode,
    initialFen: '3k5/9/9/9/R8/8R/9/9/9/4K4 w',
    moves: const [],
    solveStatus: status,
    solutions: status == SolveStatus.solved
        ? const [
            ['a5d5'],
            ['i4d4'],
          ]
        : const [],
    createdAt: DateTime.parse('2026-10-02T08:00:00Z'),
  );
}

void main() {
  group('battleStartFen / canLaunchBattle（纯函数）', () {
    test('对局未分胜负 → 起点 = 终局 FEN', () {
      final record = sessionRecord();
      final fen = battleStartFen(record)!;
      expect(fen.split(' ').first,
          isNot('rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR'));
      expect(canLaunchBattle(record), isTrue);
    });

    test('对局已分胜负 → 无入口', () {
      final record = sessionRecord(result: GameResult.redWins);
      expect(battleStartFen(record), isNull);
      expect(canLaunchBattle(record), isFalse);
    });

    test('残局类（含无解/未决）→ 起点 = initialFen', () {
      for (final status in [
        SolveStatus.solved,
        SolveStatus.noSolution,
        SolveStatus.timeout,
        SolveStatus.none,
      ]) {
        final record = endgameRecord(status: status);
        expect(battleStartFen(record), record.initialFen, reason: '$status');
        expect(canLaunchBattle(record), isTrue);
      }
    });
  });

  group('launchBattle（widget 流程）', () {
    late GameDao dao;

    setUp(() {
      dao = GameDao.inMemory();
    });

    tearDown(() {
      dao.dispose();
    });

    Future<void> pumpHost(WidgetTester tester, GameRecord record) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            gameRepositoryProvider.overrideWith((ref) => GameRepository(dao)),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (sheetContext) => Center(
                  child: FilledButton(
                    onPressed: () => launchBattle(sheetContext, record),
                    child: const Text('GO'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('已分胜负的对局：无入口，不弹选择', (tester) async {
      await pumpHost(tester, sessionRecord(result: GameResult.redWins));
      await tester.tap(find.text('GO'));
      await tester.pumpAndSettle();
      expect(find.text('选择对战模式（从保存局面继续）'), findsNothing);
    });

    testWidgets('选择双人对弈：进入双人页并从保存局面继续', (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final record = sessionRecord();
      final startFen = battleStartFen(record)!;
      await pumpHost(tester, record);

      await tester.tap(find.text('GO'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('双人对弈'));
      await tester.pumpAndSettle();

      expect(find.byType(HumanVsHumanGamePage), findsOneWidget);
      expect(find.text('双人对弈（棋谱续战）'), findsOneWidget);
      // 全局棋盘已载入起点局面。
      final context = tester.element(find.byType(HumanVsHumanGamePage));
      final container = ProviderScope.containerOf(context);
      expect(container.read(boardViewModelProvider).fen, startFen);
    });

    testWidgets('选择人机 AI：先选执方再进入', (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final record = sessionRecord();
      await pumpHost(tester, record);

      await tester.tap(find.text('GO'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('人机对战（内置 AI）'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('玩家执红'));
      await tester.pumpAndSettle();

      expect(find.byType(HumanVsAiPage), findsOneWidget);
    });
  });

  group('双人页 initialFen 进入（残局来源不写自动存档）', () {
    testWidgets('以起点 FEN 开局，退出后存档桶为空', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final dao = GameDao.inMemory();
      addTearDown(dao.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            gameRepositoryProvider.overrideWith((ref) => GameRepository(dao)),
          ],
          child: const MaterialApp(
            home: HumanVsHumanGamePage(
              initialFen: '3k5/9/9/9/R8/8R/9/9/9/4K4 b - - 0 1',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(HumanVsHumanGamePage));
      final container = ProviderScope.containerOf(context);
      final state = container.read(boardViewModelProvider);
      expect(state.isRedTurn, isFalse, reason: '行棋方由 FEN 决定（黑先）');

      // 退出页面（触发 dispose/自动保存钩子）后，存档桶不被污染。
      // 页面直接作为 home 路由无返回按钮，编程式退出。
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(dao.latestForMode('humanVsHuman'), isNull);
    });
  });
}
