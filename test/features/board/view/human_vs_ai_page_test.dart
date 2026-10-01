import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chinese_chess_ultra/features/board/model/board_state.dart';
import 'package:chinese_chess_ultra/features/board/view/human_vs_ai_page.dart';
import 'package:chinese_chess_ultra/features/board/model/piece.dart';
import 'package:chinese_chess_ultra/features/board/viewmodel/board_vm.dart';

/// 残局始盘（红先）FEN：双炮对黑孤将。
const puzzleFenRed = '4k4/9/9/9/9/9/4C4/9/4C4/4K4 w - - 0 1';

/// 黑先 FEN：用于验证开局即触发 AI（黑方）应手。
const puzzleFenBlack = '4k4/9/9/9/9/9/4C4/9/4C4/4K4 b - - 0 1';

void main() {
  testWidgets('人机对战：以残局 FEN 开局且玩家红先', (tester) async {
    BoardState captured = const BoardState(
      fen: '',
      moveHistory: [],
      isRedTurn: true,
      isCheck: false,
      result: null,
    );

    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(
          builder: (context, ref, _) {
            captured = ref.watch(boardViewModelProvider);
            return const MaterialApp(
              home: HumanVsAiPage(initialFen: puzzleFenRed),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(captured.fen, puzzleFenRed);
    expect(captured.isRedTurn, isTrue);
    expect(captured.moveHistory, isEmpty);

    // 页面标题体现残局模式与执子方。
    expect(find.textContaining('残局人机对战'), findsOneWidget);
    expect(find.textContaining('玩家执红'), findsOneWidget);
  });

  testWidgets('人机对战：残局模式下"新游戏"回到残局始盘而非标准开局',
      (tester) async {
    BoardState captured = const BoardState(
      fen: '',
      moveHistory: [],
      isRedTurn: true,
      isCheck: false,
      result: null,
    );

    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(
          builder: (context, ref, _) {
            captured = ref.watch(boardViewModelProvider);
            return const MaterialApp(
              home: HumanVsAiPage(initialFen: puzzleFenRed),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('新游戏'));
    await tester.pumpAndSettle();

    expect(captured.fen, puzzleFenRed,
        reason: '残局模式下重开应回到残局始盘');
    expect(captured.isRedTurn, isTrue);
  });

  testWidgets('人机对战：黑先残局由 AI 先行落子', (tester) async {
    BoardState captured = const BoardState(
      fen: '',
      moveHistory: [],
      isRedTurn: true,
      isCheck: false,
      result: null,
    );

    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(
          builder: (context, ref, _) {
            captured = ref.watch(boardViewModelProvider);
            return const MaterialApp(
              home: HumanVsAiPage(initialFen: puzzleFenBlack),
            );
          },
        ),
      ),
    );
    await tester.pump();

    // AI 应手在独立 Isolate 中计算（真实异步），用 runAsync 等待其完成。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 6)),
    );
    await tester.pumpAndSettle();

    expect(captured.isRedTurn, isTrue, reason: 'AI（黑方）落子后轮到玩家');
    expect(captured.moveHistory, hasLength(1), reason: 'AI 已先行一步');
  });

  testWidgets('人机对战：玩家执黑时 AI（红方）先行', (tester) async {
    BoardState captured = const BoardState(
      fen: '',
      moveHistory: [],
      isRedTurn: true,
      isCheck: false,
      result: null,
    );

    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(
          builder: (context, ref, _) {
            captured = ref.watch(boardViewModelProvider);
            return const MaterialApp(
              home: HumanVsAiPage(
                initialFen: puzzleFenRed,
                playerSide: Side.black,
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 6)),
    );
    await tester.pumpAndSettle();

    expect(captured.isRedTurn, isFalse, reason: 'AI（红方）先行后轮到黑方玩家');
    expect(captured.moveHistory, hasLength(1), reason: 'AI（红方）已先行一步');
  });
}
