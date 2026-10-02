import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chinese_chess_ultra/features/board/model/board_state.dart';
import 'package:chinese_chess_ultra/features/board/view/human_vs_llm_page.dart';
import 'package:chinese_chess_ultra/features/board/view/llm_vs_llm_page.dart';
import 'package:chinese_chess_ultra/features/board/viewmodel/board_vm.dart';
import 'package:chinese_chess_ultra/features/record/board_view_replay.dart';
import 'package:chinese_chess_ultra/features/record/game_record.dart';

/// 黑先残局 FEN（模型/黑方先行）。
const fenBlackToMove = '3k5/9/9/9/R8/8R/9/9/9/4K4 b - - 0 1';

GameRecord solvedEndgame() {
  return GameRecord(
    title: '演示残局',
    mode: GameRecord.endgameMode,
    initialFen: '3k5/9/9/9/R8/8R/9/9/9/4K4 w',
    moves: const [],
    solveStatus: SolveStatus.solved,
    solutions: const [
      ['a5d5', 'd5d1'],
      ['i4d4'],
    ],
    createdAt: DateTime.parse('2026-10-02T08:00:00Z'),
  );
}

void main() {
  group('ReplayBoardView 破解演示播放', () {
    Future<void> pumpView(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReplayBoardView(record: solvedEndgame()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('播放自动推进到线路尽头并自停', (tester) async {
      await pumpView(tester);
      // 残局默认进入第一条解法（2 着）。
      expect(find.text('0 / 2 着'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump(); // 触发播放状态
      expect(find.byIcon(Icons.pause), findsOneWidget);

      // 推进两个步进周期（基础 900ms/着）。
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.text('1 / 2 着'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.text('2 / 2 着'), findsOneWidget);
      // 到尽头自动停止：图标回到播放。
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      // 不再继续推进。
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.text('2 / 2 着'), findsOneWidget);
    });

    testWidgets('暂停后停在当前着，重置回起点', (tester) async {
      await pumpView(tester);
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.text('1 / 2 着'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump(const Duration(milliseconds: 2000));
      expect(find.text('1 / 2 着'), findsOneWidget, reason: '暂停后不再推进');

      await tester.tap(find.byIcon(Icons.replay));
      await tester.pumpAndSettle();
      expect(find.text('0 / 2 着'), findsOneWidget);
    });
  });

  group('HumanVsLlmPage initialFen 进入', () {
    testWidgets('黑先残局：载入局面并由模型方自动应手', (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      BoardState captured = const BoardState(
        fen: '',
        moveHistory: [],
        isRedTurn: true,
        isCheck: false,
        result: null,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: Consumer(
            builder: (context, ref, _) {
              captured = ref.watch(boardViewModelProvider);
              return const MaterialApp(
                home: HumanVsLlmPage(initialFen: fenBlackToMove),
              );
            },
          ),
        ),
      );
      await tester.pump();

      // 模型方（黑）走子走 Isolate 兜底链路，等待真实完成。
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 8)),
      );
      await tester.pumpAndSettle();

      expect(captured.isRedTurn, isTrue, reason: '黑方（模型）已自动应手');
      expect(captured.moveHistory, hasLength(1));
    });
  });

  group('LlmVsLlmPage initialFen 进入', () {
    testWidgets('载入起点局面且不自动开跑', (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      BoardState captured = const BoardState(
        fen: '',
        moveHistory: [],
        isRedTurn: true,
        isCheck: false,
        result: null,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: Consumer(
            builder: (context, ref, _) {
              captured = ref.watch(boardViewModelProvider);
              return const MaterialApp(
                home: LlmVsLlmPage(initialFen: fenBlackToMove),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(captured.fen.split(' ').first,
          '3k5/9/9/9/R8/8R/9/9/9/4K4');
      expect(captured.isRedTurn, isFalse, reason: '行棋方由 FEN 决定');
      expect(captured.moveHistory, isEmpty);
      // 未自动开跑（需用户点开始）。
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });
  });
}
