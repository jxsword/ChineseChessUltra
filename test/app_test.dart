import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chinese_chess_ultra/app/app.dart';
import 'package:chinese_chess_ultra/features/board/model/board.dart';
import 'package:chinese_chess_ultra/features/board/model/move.dart';
import 'package:chinese_chess_ultra/features/board/viewmodel/board_vm.dart';
import 'package:chinese_chess_ultra/features/storage/game_dao.dart';
import 'package:chinese_chess_ultra/features/storage/game_mode.dart';
import 'package:chinese_chess_ultra/features/storage/repository.dart';

void main() {
  testWidgets('应用启动后显示标题与主导航入口', (tester) async {
    // 用内存 SQLite 替代文件数据库，避免测试环境依赖 path_provider。
    final dao = GameDao.inMemory();
    final repo = GameRepository(dao);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gameRepositoryProvider.overrideWith((ref) => repo),
        ],
        child: const ChineseChessApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    // 标题
    expect(find.text('中国象棋 Ultra'), findsOneWidget);
    // 主导航入口（二期主导航页 + 三三大模型入口）
    expect(find.text('残局选关'), findsOneWidget);
    expect(find.text('人机对战'), findsOneWidget);
    expect(find.text('人机对战（大模型）'), findsOneWidget);
    expect(find.text('大模型对战'), findsOneWidget);
    expect(find.text('双人对弈'), findsOneWidget);

    dao.dispose();
  });

  testWidgets('双人对弈页进入时自动恢复存档', (tester) async {
    final dao = GameDao.inMemory();
    final repo = GameRepository(dao);
    // 预置一份双人对弈存档：红炮平中（炮二平五）后的局面。
    final board = Board.initial();
    board.applyMove(Move(from: Position(7, 7), to: Position(7, 4)));
    final savedFen = board.toFen();
    repo.saveGame(
      mode: GameMode.humanVsHuman,
      fen: savedFen,
      moves: [Move(from: Position(7, 7), to: Position(7, 4))],
    );

    final container = ProviderContainer(
      overrides: [gameRepositoryProvider.overrideWith((ref) => repo)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ChineseChessApp(),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('双人对弈'));
    // 推入路由 + initState 的 postFrameCallback + 异步恢复。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(container.read(boardViewModelProvider).fen, savedFen);
  });

  testWidgets('大模型对战页无存档进入时重置全局棋盘（消除内存残留）', (tester) async {
    final dao = GameDao.inMemory();
    final repo = GameRepository(dao);

    final container = ProviderContainer(
      overrides: [gameRepositoryProvider.overrideWith((ref) => repo)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ChineseChessApp(),
      ),
    );
    await tester.pump();

    // 污染全局棋盘（模拟上一局残留）。
    container
        .read(boardViewModelProvider.notifier)
        .playMove(Position(7, 7), Position(7, 4));
    final initialFen = Board.initial().toFen();
    expect(
      container.read(boardViewModelProvider).fen,
      isNot(initialFen),
    );

    await tester.tap(find.text('大模型对战'));
    // 等待路由动画与页面 initState（postFrame 新局）完成。
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // 无存档进入后应重置为初始局面，而不是残留上一局。
    expect(container.read(boardViewModelProvider).fen, initialFen);
  });
}
