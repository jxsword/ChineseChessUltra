import 'package:flutter_test/flutter_test.dart';
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
}
