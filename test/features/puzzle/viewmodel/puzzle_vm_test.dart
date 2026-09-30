import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_chess_ultra/features/puzzle/model/puzzle_data.dart';
import 'package:chinese_chess_ultra/features/puzzle/viewmodel/puzzle_vm.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fake_async/fake_async.dart';

void main() {
  group('PuzzleViewModel.parseIccs', () {
    test('标准 ICCS：h2e2 → 红炮起点(7,7)、终点(4,7)', () {
      final move = PuzzleViewModel.parseIccs('h2e2');
      expect(move, isNotNull);
      expect(move!.from.col, 7);
      expect(move.from.row, 7);
      expect(move.to.col, 4);
      expect(move.to.row, 7);
    });

    test('兼容 10 行号记法：h10g8 → 黑马起点(7,0)、终点(6,1)', () {
      final move = PuzzleViewModel.parseIccs('h10g8');
      expect(move, isNotNull);
      expect(move!.from.col, 7);
      expect(move.from.row, 0);
      expect(move.to.col, 6);
      expect(move.to.row, 1);
    });

    test('非法输入返回 null', () {
      expect(PuzzleViewModel.parseIccs('xyz'), isNull);
      expect(PuzzleViewModel.parseIccs('z2e2'), isNull);
      expect(PuzzleViewModel.parseIccs('h99g8'), isNull);
    });
  });

  group('PuzzleViewModel 演示播放', () {
    final puzzle = ParsedPuzzle(
      id: 'test',
      initialFen:
          'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1',
      solutionMoves: const ['h2e2', 'h9g7', 'e3e4'],
      source: '测试',
      format: 'pgn',
      difficulty: 1,
    );

    test('初始化后棋盘为残局初始局面', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final vm = container.read(puzzleViewModelProvider.notifier);
      vm.initializePuzzle(puzzle);

      final state = container.read(puzzleViewModelProvider);
      expect(state.demoState, PuzzleDemoState.idle);
      expect(state.fen, puzzle.initialFen);
      expect(state.lastMove, isNull);
      expect(vm.board, isNotNull);
      // h2 处应为红炮。
      expect(vm.board!.pieceAt(7, 7)?.label, '炮');
    });

    test('播放推进时走法被应用到棋盘并高亮 lastMove', () {
      fakeAsync((async) {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final vm = container.read(puzzleViewModelProvider.notifier);
        vm.initializePuzzle(puzzle);
        vm.startDemo();

        // 第 1 步：h2e2 红炮平中（默认间隔 800ms）。
        async.elapse(const Duration(milliseconds: 850));
        var state = container.read(puzzleViewModelProvider);
        expect(state.currentMoveIndex, 0);
        expect(state.lastMove, isNotNull);
        expect(state.lastMove!.from.col, 7);
        expect(state.lastMove!.to.col, 4);
        // 起点已空，终点为红炮。
        expect(vm.board!.pieceAt(7, 7), isNull);
        expect(vm.board!.pieceAt(4, 7)?.label, '炮');

        // 播完所有步后进入 completed。
        async.elapse(const Duration(milliseconds: 4000));
        state = container.read(puzzleViewModelProvider);
        expect(state.demoState, PuzzleDemoState.completed);
        expect(state.currentMoveIndex, puzzle.moves.length - 1);
      });
    });

    test('慢速档位按倍率放慢走子间隔', () {
      fakeAsync((async) {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final vm = container.read(puzzleViewModelProvider.notifier);
        vm.initializePuzzle(puzzle);
        vm.setDemoSpeed(PuzzleDemoParams.slow);
        vm.startDemo();

        // 慢速间隔为 800/0.5 = 1600ms：850ms 时应还未走子。
        async.elapse(const Duration(milliseconds: 850));
        var state = container.read(puzzleViewModelProvider);
        expect(state.currentMoveIndex, -1);

        // 到 1600ms 才走第 1 步。
        async.elapse(const Duration(milliseconds: 800));
        state = container.read(puzzleViewModelProvider);
        expect(state.currentMoveIndex, 0);
        expect(state.lastMove, isNotNull);
      });
    });

    test('自定义间隔（滑块）按设定毫秒数走子', () {
      fakeAsync((async) {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final vm = container.read(puzzleViewModelProvider.notifier);
        vm.initializePuzzle(puzzle);
        vm.setCustomInterval(3000);
        vm.startDemo();

        // 3000ms 间隔：1600ms 时不应走子。
        async.elapse(const Duration(milliseconds: 1600));
        var state = container.read(puzzleViewModelProvider);
        expect(state.currentMoveIndex, -1);

        // 到 3000ms 走第 1 步。
        async.elapse(const Duration(milliseconds: 1500));
        state = container.read(puzzleViewModelProvider);
        expect(state.currentMoveIndex, 0);
        expect(state.demoParams.interval, 3000);
      });
    });

    test('点播放重新初始化后保留用户已设的速度', () {
      fakeAsync((async) {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final vm = container.read(puzzleViewModelProvider.notifier);
        vm.initializePuzzle(puzzle);
        // 用户通过滑块设为 4 秒/步。
        vm.setCustomInterval(4000);

        // 再次点播放（页面会先 initializePuzzle 再 startDemo）。
        vm.initializePuzzle(puzzle);
        vm.startDemo();
        expect(container.read(puzzleViewModelProvider).demoParams.interval, 4000);

        // 1600ms 时不应走子（若被重置为 800ms，这里已经走完两步）。
        async.elapse(const Duration(milliseconds: 1600));
        final state = container.read(puzzleViewModelProvider);
        expect(state.currentMoveIndex, -1);

        // 4000ms 时才走第 1 步。
        async.elapse(const Duration(milliseconds: 2500));
        expect(container.read(puzzleViewModelProvider).currentMoveIndex, 0);
      });
    });

    test('停止演示后棋盘重置到初始局面', () {
      fakeAsync((async) {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final vm = container.read(puzzleViewModelProvider.notifier);
        vm.initializePuzzle(puzzle);
        vm.startDemo();
        async.elapse(const Duration(milliseconds: 850));

        vm.stopDemo();
        final state = container.read(puzzleViewModelProvider);
        expect(state.demoState, PuzzleDemoState.idle);
        expect(state.currentMoveIndex, -1);
        expect(state.lastMove, isNull);
        expect(state.fen, puzzle.initialFen);
      });
    });
  });
}
