import 'fen.dart';
import 'move.dart';
import 'piece.dart';

/// 中国象棋规则引擎。
///
/// 参照 shirne/chinese_chess 的 Board 设计：
/// - 棋盘以 10 行 × 9 列矩阵存储，[row] 0 为黑方底线（FEN 第一行），[row] 9 为红方底线。
/// - 提供 [move]、[legalMoves]、[isCheck]、[isCheckmate]、[isStalemate] 等接口。
///
/// 不依赖任何 Flutter / 第三方库，可独立单测。
class Board {
  Board._(this._grid, this._redTurn);

  /// 从 FEN 字符串构造棋盘。
  factory Board.fromFen(String fen) {
    final grid = Fen.parseBoard(fen);
    final redTurn = Fen.parseTurn(fen);
    return Board._(grid, redTurn);
  }

  /// 标准初始局面。
  factory Board.initial() => Board.fromFen(Fen.initial);

  final List<List<Piece?>> _grid;
  bool _redTurn;

  /// 当前是否轮到红方走。
  bool get isRedTurn => _redTurn;

  /// 当前轮走方。
  Side get turn => _redTurn ? Side.red : Side.black;

  /// 取某格棋子。
  Piece? pieceAt(int col, int row) => _grid[row][col];

  /// 取某格棋子（Position 版）。
  Piece? pieceAtP(Position p) => _grid[p.row][p.col];

  /// 序列化为 FEN。
  String toFen() => Fen.build(board: _grid, isRedTurn: _redTurn);

  /// 拷贝当前棋盘（深拷贝）。
  Board copy() {
    final grid = _grid.map((row) => List<Piece?>.from(row)).toList();
    return Board._(grid, _redTurn);
  }

  /// 是否在棋盘内。
  static bool inBoard(int col, int row) =>
      col >= 0 && col < 9 && row >= 0 && row < 10;

  /// 是否在九宫格内。
  static bool inPalace(int col, int row, Side side) {
    if (col < 3 || col > 5) return false;
    return side.isRed ? (row >= 7 && row <= 9) : (row >= 0 && row <= 2);
  }

  /// 是否在自己半场（未过河）。
  static bool inOwnHalf(int row, Side side) {
    return side.isRed ? row >= 5 : row <= 4;
  }

  /// 是否已过河到对方半场。
  static bool inOpponentHalf(int row, Side side) => !inOwnHalf(row, side);

  // ---------------------------------------------------------------------------
  // 走法生成
  // ---------------------------------------------------------------------------

  /// 计算某格棋子的所有伪合法走法（不检查是否自将，由 [legalMoves] 过滤）。
  ///
  /// 返回 [Move] 列表，[Move.captured] 已填好。
  List<Move> pseudoMovesFor(Position pos) {
    final piece = pieceAtP(pos);
    if (piece == null) return const [];
    switch (piece.kind) {
      case PieceKind.king:
        return _kingMoves(pos, piece);
      case PieceKind.advisor:
        return _advisorMoves(pos, piece);
      case PieceKind.minister:
        return _ministerMoves(pos, piece);
      case PieceKind.knight:
        return _knightMoves(pos, piece);
      case PieceKind.rook:
        return _rookMoves(pos, piece);
      case PieceKind.cannon:
        return _cannonMoves(pos, piece);
      case PieceKind.pawn:
        return _pawnMoves(pos, piece);
    }
  }

  /// 合法走法（过滤掉走完会自将的走法）。
  List<Move> legalMovesFor(Position pos) {
    final piece = pieceAtP(pos);
    if (piece == null || piece.side != turn) return const [];
    return pseudoMovesFor(pos)
        .where((m) => !_willBeInCheckAfter(m, piece.side))
        .toList();
  }

  /// 当前走子方是否还有任何合法走法。
  bool hasAnyLegalMove() {
    for (var r = 0; r < 10; r++) {
      for (var c = 0; c < 9; c++) {
        final p = _grid[r][c];
        if (p != null && p.side == turn) {
          if (pseudoMovesFor(Position(c, r)).any(
            (m) => !_willBeInCheckAfter(m, p.side),
          )) {
            return true;
          }
        }
      }
    }
    return false;
  }

  /// 执行一步走子（更新棋盘与轮走方）。
  ///
  /// 不做合法性校验，调用方负责；返回值是该 [Move] 的快照（含被吃子）。
  Move applyMove(Move move) {
    final mover = pieceAtP(move.from)!;
    final captured = pieceAtP(move.to);
    _grid[move.to.row][move.to.col] = mover;
    _grid[move.from.row][move.from.col] = null;
    _redTurn = !_redTurn;
    return Move(from: move.from, to: move.to, captured: captured);
  }

  /// 撤销一步走子。
  void undoMove(Move move) {
    final mover = pieceAtP(move.to)!;
    _grid[move.from.row][move.from.col] = mover;
    _grid[move.to.row][move.to.col] = move.captured;
    _redTurn = !_redTurn;
  }

  // ---------------------------------------------------------------------------
  // 将军 / 将死 / 困毙
  // ---------------------------------------------------------------------------

  /// 查找某方将/帅位置。
  Position? kingPositionOf(Side side) {
    for (var r = 0; r < 10; r++) {
      for (var c = 0; c < 9; c++) {
        final p = _grid[r][c];
        if (p != null && p.kind == PieceKind.king && p.side == side) {
          return Position(c, r);
        }
      }
    }
    return null;
  }

  /// [side] 方的将是否正被将军（即对方有任何棋子可吃到该将）。
  bool isCheck(Side side) {
    final kingPos = kingPositionOf(side);
    if (kingPos == null) return false;
    // 将帅照面也算"将军"（直接被对方将攻击）。
    final enemyKing = kingPositionOf(side.opponent);
    if (enemyKing != null && enemyKing.col == kingPos.col) {
      var blocked = false;
      final lo = kingPos.row < enemyKing.row ? kingPos.row : enemyKing.row;
      final hi = kingPos.row < enemyKing.row ? enemyKing.row : kingPos.row;
      for (var r = lo + 1; r < hi; r++) {
        if (_grid[r][kingPos.col] != null) {
          blocked = true;
          break;
        }
      }
      if (!blocked) return true;
    }
    // 任意对方棋子能吃到本方将位置即算将军。
    for (var r = 0; r < 10; r++) {
      for (var c = 0; c < 9; c++) {
        final p = _grid[r][c];
        if (p != null && p.side == side.opponent) {
          if (pseudoMovesFor(Position(c, r)).any((m) => m.to == kingPos)) {
            return true;
          }
        }
      }
    }
    return false;
  }

  /// [side] 方是否被将死（处于被将军且无任何合法走法解将）。
  bool isCheckmate(Side side) {
    if (!isCheck(side)) return false;
    return !hasAnyLegalMoveFor(side);
  }

  /// [side] 方是否被困毙（未在被将军，但无任何合法走法）。
  bool isStalemate(Side side) {
    if (isCheck(side)) return false;
    return !hasAnyLegalMoveFor(side);
  }

  /// [side] 方是否还有任何合法走法（不影响轮走方）。
  bool hasAnyLegalMoveFor(Side side) {
    for (var r = 0; r < 10; r++) {
      for (var c = 0; c < 9; c++) {
        final p = _grid[r][c];
        if (p != null && p.side == side) {
          if (pseudoMovesFor(Position(c, r)).any(
            (m) => !_willBeInCheckAfter(m, p.side),
          )) {
            return true;
          }
        }
      }
    }
    return false;
  }

  /// 模拟执行走子后，自己是否处于被将军状态。
  bool _willBeInCheckAfter(Move move, Side side) {
    final captured = pieceAtP(move.to);
    final mover = pieceAtP(move.from)!;
    _grid[move.to.row][move.to.col] = mover;
    _grid[move.from.row][move.from.col] = null;
    final inCheck = isCheck(side);
    // 还原
    _grid[move.from.row][move.from.col] = mover;
    _grid[move.to.row][move.to.col] = captured;
    return inCheck;
  }

  // ---------------------------------------------------------------------------
  // 各棋子走法实现
  // ---------------------------------------------------------------------------

  List<Move> _kingMoves(Position pos, Piece piece) {
    final moves = <Move>[];
    const dirs = [
      Position(0, 1),
      Position(0, -1),
      Position(1, 0),
      Position(-1, 0),
    ];
    for (final d in dirs) {
      final to = pos + d;
      if (!inBoard(to.col, to.row)) continue;
      if (!inPalace(to.col, to.row, piece.side)) continue;
      final target = pieceAtP(to);
      if (target != null && target.side == piece.side) continue;
      moves.add(Move(from: pos, to: to, captured: target));
    }
    return moves;
  }

  List<Move> _advisorMoves(Position pos, Piece piece) {
    final moves = <Move>[];
    const dirs = [
      Position(1, 1),
      Position(1, -1),
      Position(-1, 1),
      Position(-1, -1),
    ];
    for (final d in dirs) {
      final to = pos + d;
      if (!inBoard(to.col, to.row)) continue;
      if (!inPalace(to.col, to.row, piece.side)) continue;
      final target = pieceAtP(to);
      if (target != null && target.side == piece.side) continue;
      moves.add(Move(from: pos, to: to, captured: target));
    }
    return moves;
  }

  List<Move> _ministerMoves(Position pos, Piece piece) {
    final moves = <Move>[];
    const dirs = [
      Position(2, 2),
      Position(2, -2),
      Position(-2, 2),
      Position(-2, -2),
    ];
    for (final d in dirs) {
      final to = pos + d;
      if (!inBoard(to.col, to.row)) continue;
      // 象不能过河。
      if (!inOwnHalf(to.row, piece.side)) continue;
      // 象眼检查。
      final eye = Position(pos.col + d.col ~/ 2, pos.row + d.row ~/ 2);
      if (pieceAtP(eye) != null) continue;
      final target = pieceAtP(to);
      if (target != null && target.side == piece.side) continue;
      moves.add(Move(from: pos, to: to, captured: target));
    }
    return moves;
  }

  List<Move> _knightMoves(Position pos, Piece piece) {
    final moves = <Move>[];
    // (走子偏移, 马腿位置偏移)
    const patterns = <(Position, Position)>[
      (Position(1, 2), Position(0, 1)), // 下右
      (Position(-1, 2), Position(0, 1)), // 下左
      (Position(1, -2), Position(0, -1)), // 上右
      (Position(-1, -2), Position(0, -1)), // 上左
      (Position(2, 1), Position(1, 0)), // 右下
      (Position(2, -1), Position(1, 0)), // 右上
      (Position(-2, 1), Position(-1, 0)), // 左下
      (Position(-2, -1), Position(-1, 0)), // 左上
    ];
    for (final (delta, leg) in patterns) {
      final to = pos + delta;
      if (!inBoard(to.col, to.row)) continue;
      // 马腿检查。
      if (pieceAtP(pos + leg) != null) continue;
      final target = pieceAtP(to);
      if (target != null && target.side == piece.side) continue;
      moves.add(Move(from: pos, to: to, captured: target));
    }
    return moves;
  }

  List<Move> _rookMoves(Position pos, Piece piece) {
    final moves = <Move>[];
    const dirs = [
      Position(0, 1),
      Position(0, -1),
      Position(1, 0),
      Position(-1, 0),
    ];
    for (final d in dirs) {
      var to = pos + d;
      while (inBoard(to.col, to.row)) {
        final target = pieceAtP(to);
        if (target == null) {
          moves.add(Move(from: pos, to: to));
        } else {
          if (target.side != piece.side) {
            moves.add(Move(from: pos, to: to, captured: target));
          }
          break;
        }
        to = to + d;
      }
    }
    return moves;
  }

  List<Move> _cannonMoves(Position pos, Piece piece) {
    final moves = <Move>[];
    const dirs = [
      Position(0, 1),
      Position(0, -1),
      Position(1, 0),
      Position(-1, 0),
    ];
    for (final d in dirs) {
      // 第一阶段：直线无阻走空格。
      var to = pos + d;
      while (inBoard(to.col, to.row) && pieceAtP(to) == null) {
        moves.add(Move(from: pos, to: to));
        to = to + d;
      }
      // 第二阶段：跳过炮架（第一个非空格）后，再吃对方。
      if (inBoard(to.col, to.row)) {
        // 此时 to 为炮架
        to = to + d;
        while (inBoard(to.col, to.row)) {
          final target = pieceAtP(to);
          if (target != null) {
            if (target.side != piece.side) {
              moves.add(Move(from: pos, to: to, captured: target));
            }
            break;
          }
          to = to + d;
        }
      }
    }
    return moves;
  }

  List<Move> _pawnMoves(Position pos, Piece piece) {
    final moves = <Move>[];
    final forward = piece.side.forward;
    final deltas = <Position>[
      Position(0, forward), // 前进
      if (!inOwnHalf(pos.row, piece.side)) ...[
        Position(1, 0), // 过河后可横走
        Position(-1, 0),
      ],
    ];
    for (final d in deltas) {
      final to = pos + d;
      if (!inBoard(to.col, to.row)) continue;
      final target = pieceAtP(to);
      if (target != null && target.side == piece.side) continue;
      moves.add(Move(from: pos, to: to, captured: target));
    }
    return moves;
  }
}
