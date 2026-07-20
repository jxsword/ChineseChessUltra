import 'board.dart';
import 'move.dart';
import 'piece.dart';

/// 对局结果。
enum GameResult { redWins, blackWins, draw }

/// 棋盘 UI 状态（不可变）。
///
/// 由 [BoardViewModel] 维护，通过 Riverpod 暴露给 UI 层。
class BoardState {
  const BoardState({
    required this.fen,
    required this.moveHistory,
    required this.isRedTurn,
    required this.isCheck,
    required this.result,
    this.selected,
    this.legalTargets = const [],
    this.lastMove,
  });

  /// 当前局面 FEN。
  final String fen;

  /// 走法历史（用于悔棋与重播）。
  final List<Move> moveHistory;

  /// 当前是否轮到红方。
  final bool isRedTurn;

  /// 当前局面下当前走子方是否被将军。
  final bool isCheck;

  /// 对局结果，null 表示进行中。
  final GameResult? result;

  /// UI 选中位置（点击棋子后置位，点击合法走法目标后清空）。
  final Position? selected;

  /// 选中棋子的合法走法目标集合（用于高亮）。
  final List<Position> legalTargets;

  /// 最近一步走法（用于高亮起止点）。
  final Move? lastMove;

  /// 当前走子方。
  Side get turn => isRedTurn ? Side.red : Side.black;

  /// 是否结束。
  bool get isFinished => result != null;

  BoardState copyWith({
    String? fen,
    List<Move>? moveHistory,
    bool? isRedTurn,
    bool? isCheck,
    GameResult? result,
    Object? selected = _sentinel,
    Object? legalTargets = _sentinel,
    Object? lastMove = _sentinel,
  }) {
    return BoardState(
      fen: fen ?? this.fen,
      moveHistory: moveHistory ?? this.moveHistory,
      isRedTurn: isRedTurn ?? this.isRedTurn,
      isCheck: isCheck ?? this.isCheck,
      result: result ?? this.result,
      selected: identical(selected, _sentinel)
          ? this.selected
          : selected as Position?,
      legalTargets: identical(legalTargets, _sentinel)
          ? this.legalTargets
          : legalTargets as List<Position>,
      lastMove: identical(lastMove, _sentinel)
          ? this.lastMove
          : lastMove as Move?,
    );
  }

  static const _sentinel = Object();
}
