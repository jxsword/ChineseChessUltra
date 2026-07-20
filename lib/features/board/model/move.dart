import 'piece.dart';

/// 坐标：列 (0..8，从左到右)，行 (0..9，红方在下)。
///
/// 注意：作为方向向量时，[col]/[row] 可能为负数或越界（如马腿偏移），
/// 因此构造函数不做范围断言，由 [isValid] 在使用时校验。
class Position {
  const Position(this.col, this.row);

  final int col;
  final int row;

  /// 加法运算（结果可能越界，调用方需检查）。
  Position operator +(Position other) =>
      Position(col + other.col, row + other.row);

  Position operator -(Position other) =>
      Position(col - other.col, row - other.row);

  @override
  bool operator ==(Object other) =>
      other is Position && other.col == col && other.row == row;

  @override
  int get hashCode => Object.hash(col, row);

  bool get isValid => col >= 0 && col < 9 && row >= 0 && row < 10;

  @override
  String toString() => '($col,$row)';
}

/// 单步走法。
///
/// 含起点 / 终点 / 被吃棋子（如有）/ 走子棋子，便于悔棋与走法记录展示。
class Move {
  const Move({
    required this.from,
    required this.to,
    this.piece,
    this.captured,
  });

  final Position from;
  final Position to;

  /// 走子棋子标识（srs.md §4.3 要求）。
  final Piece? piece;

  /// 被吃棋子；走空格时为 null。
  final Piece? captured;

  Move copyWith({
    Position? from,
    Position? to,
    Piece? piece,
    Piece? captured,
  }) =>
      Move(
        from: from ?? this.from,
        to: to ?? this.to,
        piece: piece ?? this.piece,
        captured: captured ?? this.captured,
      );

  @override
  String toString() =>
      'Move ${from.col},${from.row} -> ${to.col},${to.row}'
      '${piece != null ? ' by $piece' : ''}'
      '${captured != null ? ' x$captured' : ''}';
}
