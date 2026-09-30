import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chinese_chess_ultra/features/board/model/board_state.dart';
import 'package:chinese_chess_ultra/features/board/view/ai_vs_ai_page.dart';
import 'package:chinese_chess_ultra/features/board/viewmodel/board_vm.dart';

void main() {
  testWidgets('AI对战：开始后 AI 应手应真正落子并更新棋盘状态', (tester) async {
    BoardState captured = const BoardState(
      fen: '',
      moveHistory: [],
      isRedTurn: true,
      isCheck: false,
      result: null,
    );

    // 放大测试窗口，保证侧栏中的操作按钮可见可点。
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(
          builder: (context, ref, _) {
            captured = ref.watch(boardViewModelProvider);
            return const MaterialApp(home: AiVsAiPage());
          },
        ),
      ),
    );
    await tester.pump();

    final initialFen = captured.fen;
    expect(captured.moveHistory, isEmpty);

    await tester.tap(find.byTooltip('开始'));
    await tester.pump();

    // AI 应手在独立 Isolate 中计算（真实异步），用 runAsync 等待其完成。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 6)),
    );
    await tester.pump();

    expect(
      captured.moveHistory,
      isNotEmpty,
      reason: 'AI 应手应写入走法记录',
    );
    expect(
      captured.fen,
      isNot(equals(initialFen)),
      reason: 'AI 走子后棋盘局面应从开局状态更新',
    );

    // 暂停对战，取消走子循环中挂起的定时器，保证测试干净收尾。
    await tester.tap(find.byTooltip('暂停'));
    await tester.pump();
  });
}
