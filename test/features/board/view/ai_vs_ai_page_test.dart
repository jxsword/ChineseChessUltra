import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chinese_chess_ultra/features/board/model/board_state.dart';
import 'package:chinese_chess_ultra/features/board/view/ai_vs_ai_page.dart';
import 'package:chinese_chess_ultra/features/board/viewmodel/board_vm.dart';
import 'package:chinese_chess_ultra/features/storage/game_dao.dart';
import 'package:chinese_chess_ultra/features/storage/repository.dart';

void main() {
  // 页面进入时会读存档（恢复棋局），用内存库替换文件数据库，
  // 避免测试环境依赖 path_provider 平台通道。
  late GameDao dao;
  late GameRepository repo;

  setUp(() {
    dao = GameDao.inMemory();
    repo = GameRepository(dao);
  });
  tearDown(() => dao.dispose());

  // 闭包在 Provider 首次读取时才执行，届时 repo 已由 setUp 赋值。
  final overrides = <Override>[
    gameRepositoryProvider.overrideWith((ref) => repo),
  ];

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
        overrides: overrides,
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

  testWidgets('AI对战：运行中退出页面，全局输入锁必须被释放（P0-1）', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AiVsAiPage()),
      ),
    );
    await tester.pumpAndSettle();

    // 开始对战（应用栏播放按钮，避免侧栏按钮在测试视口被遮挡）→ lockInput。
    await tester.tap(find.byTooltip('开始'));
    await tester.pump();
    // AI（红方）已先行一步，轮到黑方；锁定时点黑车 (0,0) 应被吞。
    container.read(boardViewModelProvider.notifier).onTap(0, 0);
    expect(container.read(boardViewModelProvider).selected, isNull,
        reason: '对战期间输入应被锁定');

    // 运行态直接退出页面（AI isolate 仍在计算）。
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SizedBox()),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 800)),
    );

    container.read(boardViewModelProvider.notifier).onTap(0, 0);
    expect(container.read(boardViewModelProvider).selected, isNotNull,
        reason: '运行态退出页面必须解锁全局输入');
  });
}
