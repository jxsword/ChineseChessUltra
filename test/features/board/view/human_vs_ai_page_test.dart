import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chinese_chess_ultra/features/board/model/board_state.dart';
import 'package:chinese_chess_ultra/features/board/model/fen.dart';
import 'package:chinese_chess_ultra/features/board/view/human_vs_ai_page.dart';
import 'package:chinese_chess_ultra/features/board/model/piece.dart';
import 'package:chinese_chess_ultra/features/board/viewmodel/board_vm.dart';
import 'package:chinese_chess_ultra/features/storage/game_dao.dart';
import 'package:chinese_chess_ultra/features/storage/repository.dart';

/// 残局始盘（红先）FEN：双炮对黑孤将。
const puzzleFenRed = '4k4/9/9/9/9/9/4C4/9/4C4/4K4 w - - 0 1';

/// 黑先 FEN：用于验证开局即触发 AI（黑方）应手。
const puzzleFenBlack = '4k4/9/9/9/9/9/4C4/9/4C4/4K4 b - - 0 1';

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
        overrides: overrides,
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
        overrides: overrides,
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
        overrides: overrides,
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
        overrides: overrides,
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

  testWidgets('人机对战：页面退出时兜底释放全局输入锁（P0-1）', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HumanVsAiPage(initialFen: puzzleFenRed)),
      ),
    );
    await tester.pumpAndSettle();

    // 模拟 AI 思考中的锁状态（_triggerAiMove 已 lockInput、尚未 unlock 时
    // 用户退出页面）。测试环境 Isolate 不可用走同步退化，无法制造真实
    // 思考窗口，故直接注入锁状态验证 dispose 兜底。
    container.read(boardViewModelProvider.notifier).lockInput();
    // (4,6) 是红炮：未锁时可选中；锁定时点击被吞。
    container.read(boardViewModelProvider.notifier).onTap(4, 6);
    expect(container.read(boardViewModelProvider).selected, isNull,
        reason: '锁定期内棋盘点击应被吞掉');

    // 退出页面：dispose 必须兜底解锁，否则全局棋盘永久冻结。
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SizedBox()),
      ),
    );
    await tester.pump();

    container.read(boardViewModelProvider.notifier).onTap(4, 6);
    expect(container.read(boardViewModelProvider).selected, isNotNull,
        reason: '页面退出后全局输入锁必须已释放');
  });

  testWidgets('人机对战：残局对局后无参进入应重置为标准开局（P1-2）', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);

    // 先进入残局对局（写入全局残局局面）。
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HumanVsAiPage(initialFen: puzzleFenRed)),
      ),
    );
    await tester.pumpAndSettle();
    expect(container.read(boardViewModelProvider).fen, puzzleFenRed);

    // 返回主页后再无参进入人机对战：必须重置为标准开局。
    // UniqueKey 强制新建 State（模拟真实导航进入新 route），
    // 否则 Flutter 复用旧 State、initState 不重跑。
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: HumanVsAiPage(key: UniqueKey()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final state = container.read(boardViewModelProvider);
    expect(state.fen, Fen.initial, reason: '不应残留残局局面');
    expect(state.result, isNull, reason: '不应残留胜负横幅');
    expect(state.moveHistory, isEmpty);
  });
}
