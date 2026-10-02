import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/board.dart';
import '../model/board_state.dart';
import '../model/move.dart';
import '../model/move_notation.dart';
import '../model/piece.dart';

/// 棋盘对弈 ViewModel。
///
/// 通过 Riverpod Notifier 暴露 [BoardState]，UI 通过 ref.watch 即可订阅。
/// 同时承担：合法性校验、走子、悔棋、新游戏、自动判负等业务。
///
/// 走法历史 [Move] 列表由 ViewModel 内部维护（[_moveHistory]），
/// 每次产生新快照时一并写入 [BoardState]，避免丢失。
class BoardViewModel extends Notifier<BoardState> {
  late Board _board;
  late List<Move> _moveHistory;

  /// 输入锁：AI 思考期间禁止玩家点击棋盘（人机模式使用）。
  bool _inputLocked = false;

  @override
  BoardState build() {
    _board = Board.initial();
    _moveHistory = [];
    // 直接构造初始状态，避免在 `_snapshot()` 中访问 `this.state` 导致 "uninitialized provider"。
    final turn = _board.turn;
    final isCheck = _board.isCheck(turn);
    return BoardState(
      fen: _board.toFen(),
      moveHistory: const [],
      isRedTurn: _board.isRedTurn,
      isCheck: isCheck,
      result: null,
      selected: null,
      legalTargets: const [],
      lastMove: null,
    );
  }

  Board get board => _board;

  /// 当前状态快照（供存档恢复流程等外部读取，避免触碰 Notifier 的
  /// 受保护 state 成员）。
  BoardState get current => state;

  /// 当前是否轮到红方走。
  bool get isRedTurn => _board.isRedTurn;

  /// 用当前棋盘生成不可变快照。
  ///
  /// 可选参数：[selected]/[legalTargets]/[lastMove] 仅在走子/选中时传入；
  /// 若为 null 则保持空值（恢复棋局时由调用方显式传入）。
  BoardState _snapshot({
    Position? selected,
    List<Position>? legalTargets,
    Move? lastMove,
  }) {
    final turn = _board.turn;
    final isCheck = _board.isCheck(turn);
    GameResult? result;
    if (_board.isCheckmate(turn)) {
      result = turn.isRed ? GameResult.blackWins : GameResult.redWins;
    } else if (_board.isStalemate(turn)) {
      // 中国象棋规则：困毙（无子可动且未被将军）判困毙方负，不存在逼和。
      // 与引擎 ai_engine.dart 的 -mateScore 计分语义一致。
      result = turn.isRed ? GameResult.blackWins : GameResult.redWins;
    }
    return BoardState(
      fen: _board.toFen(),
      moveHistory: List.unmodifiable(_moveHistory),
      isRedTurn: _board.isRedTurn,
      isCheck: isCheck,
      result: result,
      selected: selected,
      legalTargets: legalTargets ?? const [],
      lastMove: lastMove,
    );
  }

  /// 从外部恢复历史走法，逐手 replay。
  ///
  /// [moves] 的每条记录为 [fromCol, fromRow, toCol, toRow] 四元组。
  ///
  /// 恢复期间不触发 state 更新，仅在完成后通知一次。
  void restore({required String fen, required List<List<int>> moves}) {
    try {
      _board = Board.fromFen(fen);
    } on Object {
      // FEN 无效则用初始局面，避免崩溃。
      _board = Board.initial();
    }

    _moveHistory = [];
    for (final m in moves) {
      if (m.length != 4) continue; // 跳过不完整的数据
      final fromPos = Position(m[0], m[1]);
      final toPos = Position(m[2], m[3]);

      // 跳过越界的走法（防止历史数据错误导致崩溃）。
      if (!Board.inBoard(fromPos.col, fromPos.row) ||
          !Board.inBoard(toPos.col, toPos.row)) {
        continue;
      }

      final piece = _board.pieceAtP(fromPos);
      if (piece == null) continue; // 源格无棋子（数据不一致），跳过

      final move = Move(from: fromPos, to: toPos);
      final applied = _board.applyMove(move);
      _moveHistory.add(Move(
        from: applied.from,
        to: applied.to,
        piece: piece,
        captured: applied.captured,
      ));
    }

    // 恢复后清空选中/合法目标，但保留 lastMove 用于高亮。
    final lastMove = _moveHistory.isEmpty ? null : _moveHistory.last;
    final restoredState = _snapshot(
      selected: null,
      legalTargets: const [],
      lastMove: lastMove,
    );

    // 异步通知 UI 更新，避免阻塞恢复过程。
    Future.microtask(() {
      state = restoredState;
    });
  }

  /// 处理点击事件。
  ///
  /// - 若点击空格或对方棋子且无选中：忽略。
  /// - 若点击己方棋子：选中并展示合法走法。
  /// - 若已选中且点击在合法走法目标：执行走子。
  /// - 若已选中但点击非合法走法目标：清空选中或切换选中。
  void onTap(int col, int row) {
    if (_inputLocked || state.isFinished) return;
    final tapped = _board.pieceAt(col, row);
    final selected = state.selected;

    if (selected != null) {
      // 已选中，判断是否点击合法目标。
      final isLegalTarget =
          state.legalTargets.any((p) => p.col == col && p.row == row);
      if (isLegalTarget) {
        _executeMove(from: selected, to: Position(col, row));
        return;
      }
      // 点击的是己方另一棋子 → 切换选中。
      if (tapped != null && tapped.side == _board.turn) {
        _select(col, row);
        return;
      }
      // 否则取消选中。
      state = state.copyWith(
        selected: null,
        legalTargets: const <Position>[],
      );
      return;
    }

    // 未选中，必须点击己方棋子。
    if (tapped != null && tapped.side == _board.turn) {
      _select(col, row);
    }
  }

  void _select(int col, int row) {
    final pos = Position(col, row);
    final legal = _board.legalMovesFor(pos).map((m) => m.to).toList();
    state = state.copyWith(selected: pos, legalTargets: legal);
  }

  void _executeMove({required Position from, required Position to}) {
    final piece = _board.pieceAtP(from)!;
    final applied = _board.applyMove(Move(from: from, to: to));
    // 把 piece 信息附到 move history 的条目上，供走法记录展示。
    final record = Move(
      from: applied.from,
      to: applied.to,
      piece: piece,
      captured: applied.captured,
    );
    _moveHistory.add(record);

    final snapshot = _snapshot(lastMove: applied);
    state = snapshot.copyWith(
      selected: null,
      legalTargets: const <Position>[],
    );

    // Debug：输出中文记法。
    assert(() {
      // ignore: avoid_print
      print('Move: ${record.toString()} (${record.chineseNotation(piece)})');
      return true;
    }());
  }

  /// 直接执行一步走子（供 AI 应手调用），并校验合法性。
  ///
  /// 返回 false 表示走子非法（起点无己方棋子、目标不合法或对局已结束），
  /// 此时状态不变。
  bool playMove(Position from, Position to) {
    if (state.isFinished) return false;
    final piece = _board.pieceAtP(from);
    if (piece == null || piece.side != _board.turn) return false;
    final isLegal =
        _board.legalMovesFor(from).any((m) => m.to.col == to.col && m.to.row == to.row);
    if (!isLegal) return false;
    _executeMove(from: from, to: to);
    return true;
  }

  /// 锁定/解锁棋盘输入（AI 思考期间锁定，防止玩家替 AI 走子）。
  void lockInput() => _inputLocked = true;
  void unlockInput() => _inputLocked = false;

  /// 悔一整轮（人机模式）：同时撤销 AI 的应手与玩家最近一手。
  ///
  /// 若历史中只有玩家的走子，则只撤销那一手。
  /// 悔一整轮（撤销 AI 与玩家各一手；默认按红方玩家语义）。
  ///
  /// [playerSide] 为执子方。与走子顺序无关：最后若为 AI 一手则先撤，
  /// 再撤玩家一手；玩家一手之前若还有 AI 一手（AI 先行开局轮）一并撤销。
  void undoRound({Side playerSide = Side.red}) {
    if (_inputLocked || _moveHistory.isEmpty) return;
    final aiSide = playerSide.opponent;
    if (_moveHistory.last.piece?.side == aiSide) {
      _undoOnce();
    }
    if (_moveHistory.isNotEmpty &&
        _moveHistory.last.piece?.side == playerSide) {
      _undoOnce();
      if (_moveHistory.isNotEmpty &&
          _moveHistory.last.piece?.side == aiSide) {
        _undoOnce();
      }
    }
  }

  /// 悔棋一步。
  ///
  /// 撤销最近一次走子，并清空选中。
  void undo() {
    if (_moveHistory.isEmpty) return;
    _undoOnce();
  }

  void _undoOnce() {
    final last = _moveHistory.removeLast();
    _board.undoMove(last);
    final snapshot = _snapshot();
    state = snapshot.copyWith(
      selected: null,
      legalTargets: const <Position>[],
      lastMove: _moveHistory.isEmpty ? null : _moveHistory.last,
    );
  }

  /// 重置为新游戏。
  void newGame() {
    _inputLocked = false;
    _board = Board.initial();
    _moveHistory = [];
    state = _snapshot(
      selected: null,
      legalTargets: const [],
      lastMove: null,
    );
  }

  /// 以指定 FEN 开始新对局（残局闯关等人机场景）。
  ///
  /// FEN 无效时回退为标准初始局面，避免崩溃。轮走方由 FEN 决定——
  /// 若黑方先行，调用方应自行触发 AI 应手。
  void newGameFromFen(String fen) {
    _inputLocked = false;
    try {
      _board = Board.fromFen(fen);
    } on Object {
      _board = Board.initial();
    }
    _moveHistory = [];
    state = _snapshot(
      selected: null,
      legalTargets: const [],
      lastMove: null,
    );
  }

  /// 认负（[loser] 方判负）：大模型走子失败等场景显式终局，
  /// 使 ResultBanner/棋谱结果/自动存档恢复判定有据可依。
  void resign(Side loser) {
    _inputLocked = false;
    state = _snapshot().copyWith(
      result: loser.isRed ? GameResult.blackWins : GameResult.redWins,
      selected: null,
      legalTargets: const <Position>[],
    );
  }

  /// 将当前局面状态序列化为可保存数据。
  ({String fen, List<Move> moves}) serialize() {
    return (fen: state.fen, moves: List.from(_moveHistory));
  }
}

/// 全局 Provider。
final boardViewModelProvider =
    NotifierProvider<BoardViewModel, BoardState>(BoardViewModel.new);
