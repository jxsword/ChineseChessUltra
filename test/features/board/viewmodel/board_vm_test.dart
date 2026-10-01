import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_chess_ultra/features/board/model/board_state.dart';
import 'package:chinese_chess_ultra/features/board/model/move.dart';
import 'package:chinese_chess_ultra/features/board/model/piece.dart';
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
          'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1',);
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

    test('undoRound：黑方玩家语义（先撤红方 AI 一手，再撤黑方玩家一手）', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final vm = container.read(boardViewModelProvider.notifier);
      // 红先残局：AI(红)先行 1 着，黑方玩家应手 1 着。
      vm.newGameFromFen('4k4/9/9/9/9/9/4C4/9/4C4/4K4 w - - 0 1');
      final aiApplied = vm.playMove(const Position(4, 9), const Position(5, 9));
      expect(aiApplied, isTrue, reason: '红帅 e0→f0 合法');
      final playerApplied =
          vm.playMove(const Position(4, 0), const Position(3, 0));
      expect(playerApplied, isTrue, reason: '黑将 e9→d9 合法（离开红炮纵线）');
      expect(container.read(boardViewModelProvider).moveHistory, hasLength(2));
      vm.undoRound(playerSide: Side.black);
      // 一轮 = 撤黑方玩家 + 撤红方 AI 各一手。
      expect(container.read(boardViewModelProvider).moveHistory, isEmpty);
      expect(container.read(boardViewModelProvider).isRedTurn, isTrue);
    });

    test('困毙判负：黑方无子可动且未被将军 → 红方胜（非和棋）', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final vm = container.read(boardViewModelProvider.notifier);
      // 黑将 e9 的全部出格（d9/f9/e8）均被过河兵攻击，
      // 黑方未被将军也无任何合法走法。
      vm.newGameFromFen('4k4/3P1P3/4P4/9/9/9/9/9/9/3K5 b - - 0 1');
      final state = container.read(boardViewModelProvider);
      expect(state.result, GameResult.redWins, reason: '困毙方判负');
    });

    test('困毙判负：红方无子可动且未被将军 → 黑方胜', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final vm = container.read(boardViewModelProvider.notifier);
      // 上一局面上下镜像：红帅的全部出格均被过河卒攻击。
      vm.newGameFromFen('4k4/9/9/9/9/9/9/4p4/3p1p3/4K4 w - - 0 1');
      final state = container.read(boardViewModelProvider);
      expect(state.result, GameResult.blackWins, reason: '困毙方判负');
    });
}
