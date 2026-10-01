import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chinese_chess_ultra/features/board/model/board.dart';
import 'package:chinese_chess_ultra/features/board/model/move.dart';
import 'package:chinese_chess_ultra/features/board/model/piece.dart';
import 'package:chinese_chess_ultra/features/board/view/human_vs_llm_page.dart';
import 'package:chinese_chess_ultra/features/board/viewmodel/board_vm.dart';
import 'package:chinese_chess_ultra/features/settings/global_settings.dart';
import 'package:chinese_chess_ultra/features/storage/game_dao.dart';
import 'package:chinese_chess_ultra/features/storage/game_mode.dart';
import 'package:chinese_chess_ultra/features/storage/repository.dart';

/// 构造"红黑各走一手、轮到红方"的存档局面（红炮二平五、黑马8进7），
/// 避免恢复后轮到黑方而触发模型思考（离线兜底会引入异步不确定性）。
({String fen, List<Move> moves}) presetRedToMove() {
  final board = Board.initial();
  final redMove = Move(
    from: const Position(7, 7),
    to: const Position(4, 7),
    piece: const Piece(kind: PieceKind.cannon, side: Side.red),
  );
  board.applyMove(redMove);
  final blackMove = Move(
    from: const Position(7, 9),
    to: const Position(6, 7),
    piece: const Piece(kind: PieceKind.knight, side: Side.black),
  );
  board.applyMove(blackMove);
  return (fen: board.toFen(), moves: [redMove, blackMove]);
}

void main() {
  // 页面进入时会读存档与安全存储，用内存库替换文件数据库，
  // 避免测试环境依赖 path_provider / 平台通道。
  late GameDao dao;
  late GameRepository repo;

  setUp(() {
    dao = GameDao.inMemory();
    repo = GameRepository(dao);
  });
  tearDown(() => dao.dispose());

  final overrides = <Override>[
    gameRepositoryProvider.overrideWith((ref) => repo),
  ];

  testWidgets('人机大模型：进入页面恢复上局存档', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final preset = presetRedToMove();
    repo.saveGame(
      mode: GameMode.humanVsLlm,
      fen: preset.fen,
      moves: preset.moves,
    );

    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HumanVsLlmPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final state = container.read(boardViewModelProvider);
    expect(state.fen, preset.fen, reason: '应恢复存档局面而非新局');
    expect(state.isRedTurn, isTrue, reason: '存档轮到红方，不应触发模型思考');

    // 结束前卸载页面：dispose 会落存档，须在 dao 关闭前完成。
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SizedBox()),
      ),
    );
    await tester.pump();
  });

  testWidgets('人机大模型：退出页面时自动保存当前棋局', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HumanVsLlmPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 无存档进入 → 新局；玩家走一手"炮二平五"。
    container
        .read(boardViewModelProvider.notifier)
        .playMove(const Position(7, 7), const Position(4, 7));
    final fenAfterMove = container.read(boardViewModelProvider).fen;

    // 退出页面：dispose 应自动落存档。
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SizedBox()),
      ),
    );
    await tester.pump();

    final saved = repo.loadLatest(GameMode.humanVsLlm);
    expect(saved, isNotNull, reason: '退出页面应自动保存');
    expect(saved!.fen, fenAfterMove);
  });

  testWidgets('人机大模型：新游戏覆盖旧存档', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final preset = presetRedToMove();
    repo.saveGame(
      mode: GameMode.humanVsLlm,
      fen: preset.fen,
      moves: preset.moves,
    );

    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HumanVsLlmPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 点击新游戏：应开新局；离开页面时自动保存覆盖旧档。
    await tester.tap(find.byTooltip('新游戏'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(boardViewModelProvider).fen,
      Board.initial().toFen(),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SizedBox()),
      ),
    );
    await tester.pump();

    final saved = repo.loadLatest(GameMode.humanVsLlm);
    expect(saved!.fen, Board.initial().toFen(), reason: '新局退出时应覆盖旧存档');
  });

  testWidgets('人机大模型：关闭自动保存后退出不保存', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    GlobalSettings.instance.autoSave = false;
    addTearDown(() => GlobalSettings.instance.autoSave = true);

    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HumanVsLlmPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    container
        .read(boardViewModelProvider.notifier)
        .playMove(const Position(7, 7), const Position(4, 7));

    // 自动保存已关闭：退出不落档。
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SizedBox()),
      ),
    );
    await tester.pump();
    expect(repo.loadLatest(GameMode.humanVsLlm), isNull,
        reason: '自动保存关闭时退出不应保存');
  });

  testWidgets('人机大模型：自动保存关闭时"保存棋局"按钮仍可手动落档',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    GlobalSettings.instance.autoSave = false;
    addTearDown(() => GlobalSettings.instance.autoSave = true);

    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HumanVsLlmPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    container
        .read(boardViewModelProvider.notifier)
        .playMove(const Position(7, 7), const Position(4, 7));
    final fenAfterMove = container.read(boardViewModelProvider).fen;

    await tester.ensureVisible(find.text('保存棋局'));
    await tester.pump();
    await tester.tap(find.text('保存棋局'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final saved = repo.loadLatest(GameMode.humanVsLlm);
    expect(saved, isNotNull, reason: '手动保存按钮应落档');
    expect(saved!.fen, fenAfterMove);

    // 退出（自动保存已关闭，不应覆盖手动保存的内容）。
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SizedBox()),
      ),
    );
    await tester.pump();
    expect(repo.loadLatest(GameMode.humanVsLlm)!.fen, fenAfterMove,
        reason: '关闭自动保存时退出不应改写存档');
  });
}
