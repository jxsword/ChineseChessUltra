import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_chess_ultra/features/board/model/move.dart';
import 'package:chinese_chess_ultra/features/board/viewmodel/board_vm.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  group('BoardViewModel', () {
    test('初始局面：红方先行，无选中，无走法历史', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final state = container.read(boardViewModelProvider);
      expect(state.isRedTurn, isTrue);
      expect(state.selected, isNull);
      expect(state.legalTargets, isEmpty);
      expect(state.moveHistory, isEmpty);
      expect(state.result, isNull);
    });

    test('点击红车（col=0,row=9）能选中并产生合法走法', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final vm = container.read(boardViewModelProvider.notifier);
      vm.onTap(0, 9);
      final state = container.read(boardViewModelProvider);
      expect(state.selected, isNotNull);
      expect(state.legalTargets.length, greaterThan(0));
    });

    test('走子后切换轮走方，记录走法历史', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final vm = container.read(boardViewModelProvider.notifier);
      // 选中红车 (0,9) → 走到 (0,8)
      vm.onTap(0, 9);
      vm.onTap(0, 8);
      final state = container.read(boardViewModelProvider);
      expect(state.isRedTurn, isFalse);
      expect(state.moveHistory.length, 1);
      expect(state.lastMove, isNotNull);
    });

    test('悔棋后走法历史减少，轮走方回退', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final vm = container.read(boardViewModelProvider.notifier);
      vm.onTap(0, 9);
      vm.onTap(0, 8);
      vm.undo();
      final state = container.read(boardViewModelProvider);
      expect(state.moveHistory, isEmpty);
      expect(state.isRedTurn, isTrue);
    });

    test('新游戏后恢复初始局面', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final vm = container.read(boardViewModelProvider.notifier);
      vm.onTap(0, 9);
      vm.onTap(0, 8);
      vm.newGame();
      final state = container.read(boardViewModelProvider);
      expect(state.moveHistory, isEmpty);
      expect(state.isRedTurn, isTrue);
    });
  });

    test('newGameFromFen：以残局 FEN 开局，轮走方随 FEN', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final vm = container.read(boardViewModelProvider.notifier);
      const fen = '4k4/9/9/9/9/9/4C4/9/4C4/4K4 w - - 0 1';
      vm.newGameFromFen(fen);
      final state = container.read(boardViewModelProvider);
      expect(state.fen, fen);
      expect(state.isRedTurn, isTrue);
      expect(state.moveHistory, isEmpty);
      expect(state.result, isNull);
    });

    test('newGameFromFen：黑先 FEN 时轮走方为黑', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final vm = container.read(boardViewModelProvider.notifier);
      vm.newGameFromFen('4k4/9/9/9/9/9/4C4/9/4C4/4K4 b - - 0 1');
      expect(container.read(boardViewModelProvider).isRedTurn, isFalse);
    });

    test('newGameFromFen：无效 FEN 回退标准初始局面', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final vm = container.read(boardViewModelProvider.notifier);
      vm.newGameFromFen('不是 FEN 的字符串');
      final state = container.read(boardViewModelProvider);
      expect(state.fen,
          'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1');
      expect(state.isRedTurn, isTrue);
    });

    test('newGameFromFen 后走子正常：红炮进一更新局面', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final vm = container.read(boardViewModelProvider.notifier);
      vm.newGameFromFen('4k4/9/9/9/9/9/4C4/9/4C4/4K4 w - - 0 1');
      final applied = vm.playMove(const Position(4, 6), const Position(4, 5));
      expect(applied, isTrue);
      expect(container.read(boardViewModelProvider).isRedTurn, isFalse);
      expect(container.read(boardViewModelProvider).moveHistory, hasLength(1));
    });
}
