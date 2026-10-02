import '../board/model/board.dart';
import '../board/model/piece.dart';

/// 残局摆盘的合法性规则（纯函数，便于单测）。
///
/// 车马炮可到任意空位；帅/将限九宫；士/仕限九宫 5 个斜线点；
/// 相/象限己方半场的田字点（偶数列，且行奇偶随起点锁定：红 5/7/9 排、
/// 黑 0/2/4 排——田字移动不改变 列+行 的奇偶性）；兵/卒不能位于本方
/// 底线三排（红兵起始 row 6 只进不退，黑卒同理）。
class BoardSetupRules {
  BoardSetupRules._();

  /// 每种棋子每方的数量上限（象棋标准配置）。
  static const Map<PieceKind, int> maxCountPerKind = {
    PieceKind.king: 1,
    PieceKind.advisor: 2,
    PieceKind.minister: 2,
    PieceKind.knight: 2,
    PieceKind.rook: 2,
    PieceKind.cannon: 2,
    PieceKind.pawn: 5,
  };

  /// [piece] 放到 (col,row) 是否合法；不合法返回给用户看的原因，合法返回 null。
  static String? placementIssue(Piece piece, int col, int row) {
    switch (piece.kind) {
      case PieceKind.king:
        if (!Board.inPalace(col, row, piece.side)) {
          return '帅/将只能放在九宫内的 9 个位置';
        }
      case PieceKind.advisor:
        if (!Board.inPalace(col, row, piece.side)) {
          return '士/仕只能放在己方九宫内';
        }
        // 士走斜线：只能在九宫的 5 个斜线点。
        // 黑方九宫斜线点满足 (col+row) 为奇数，红方为偶数。
        final parity = (col + row) % 2;
        final ok = piece.side.isRed ? parity == 0 : parity == 1;
        if (!ok) return '士/仕只能放在九宫的 5 个斜线位置上';
      case PieceKind.minister:
        if (!Board.inOwnHalf(row, piece.side)) {
          return '相/象不能摆到对方半场';
        }
        // 象走田字（列行各 ±2），(col+row) 奇偶性永不改变：
        // 红相起点 (2,9)/(6,9) 为奇数和 → 只能落在奇数行（5/7/9 排）；
        // 黑象起点 (2,0)/(6,0) 为偶数和 → 只能落在偶数行（0/2/4 排）。
        if (col % 2 != 0) {
          return '相/象只能落在偶数列的田字点上';
        }
        final rowParityOk =
            piece.side.isRed ? row.isOdd : row.isEven;
        if (!rowParityOk) {
          return piece.side.isRed
              ? '相只能放在己方半场 5/7/9 排的田字点上'
              : '象只能放在己方半场 0/2/4 排的田字点上';
        }
      case PieceKind.pawn:
        // 兵/卒只进不退（过河后可横走）：红兵不可能出现在 row 7~9，
        // 黑卒不可能出现在 row 0~2。
        final ok = piece.side.isRed ? row <= 6 : row >= 3;
        if (!ok) return '兵/卒不能放在本方底线三排';
      case PieceKind.rook:
      case PieceKind.knight:
      case PieceKind.cannon:
        break; // 无位置限制
    }
    return null;
  }

  /// [counts]（按棋子统计的已有数量）整体数量是否合法；
  /// 返回首个超限原因，合法返回 null。
  static String? countIssue(Map<Piece, int> counts) {
    for (final entry in counts.entries) {
      final limit = maxCountPerKind[entry.key.kind]!;
      if (entry.value > limit) {
        return '${entry.key.side.isRed ? '红方' : '黑方'}'
            '${entry.key.label}最多 $limit 枚（当前 ${entry.value} 枚）';
      }
    }
    return null;
  }

  /// 放置 [piece] 前的数量校验：若目标格已有同种棋子则替换不算新增。
  static String? countIssueForPlacement(
    Piece piece,
    int currentCount, {
    Piece? occupant,
  }) {
    final replacesSame = occupant != null &&
        occupant.kind == piece.kind &&
        occupant.side == piece.side;
    if (replacesSame) return null;
    final limit = maxCountPerKind[piece.kind]!;
    if (currentCount + 1 > limit) {
      return '${piece.side.isRed ? '红方' : '黑方'}'
          '${piece.label}最多 $limit 枚';
    }
    return null;
  }
}
