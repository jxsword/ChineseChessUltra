/// 棋子类型（参照 shirne/chinese_chess 的 Piece 设计，纯 Dart 实现）。
///
/// 中国象棋共 7 种棋子：将/帅、士/仕、象/相、马、车、炮、兵/卒。
/// 同一种棋子在红/黑两方共用同一个 [PieceKind]，颜色由 [Side] 区分。
enum PieceKind {
  king, // 将/帅
  advisor, // 士/仕
  minister, // 象/相
  knight, // 马
  rook, // 车
  cannon, // 炮
  pawn, // 兵/卒
}

/// 棋子归属方。
enum Side {
  red,
  black;

  /// 对手方。
  Side get opponent => this == Side.red ? Side.black : Side.red;

  /// 是否为红方。
  bool get isRed => this == Side.red;

  /// 该方在棋盘上的"前进方向"：红方从下往上走（行号减小），黑方反之。
  int get forward => this == Side.red ? -1 : 1;
}

/// FEN 字符与棋子的映射（红方大写、黑方小写，参考 XQFEN 标准）。
const _kindToFenRed = <PieceKind, String>{
  PieceKind.king: 'K',
  PieceKind.advisor: 'A',
  PieceKind.minister: 'B',
  PieceKind.knight: 'N',
  PieceKind.rook: 'R',
  PieceKind.cannon: 'C',
  PieceKind.pawn: 'P',
};

const _kindToFenBlack = <PieceKind, String>{
  PieceKind.king: 'k',
  PieceKind.advisor: 'a',
  PieceKind.minister: 'b',
  PieceKind.knight: 'n',
  PieceKind.rook: 'r',
  PieceKind.cannon: 'c',
  PieceKind.pawn: 'p',
};

/// FEN 字符反查（不区分大小写）。
final _fenToKind = <String, (PieceKind, Side)>{
  for (final entry in _kindToFenRed.entries)
    entry.value: (entry.key, Side.red),
  for (final entry in _kindToFenBlack.entries)
    entry.value: (entry.key, Side.black),
};

/// 一个具体棋子（种类 + 归属方）。
class Piece {
  const Piece({required this.kind, required this.side});

  final PieceKind kind;
  final Side side;

  /// 该棋子的 FEN 字符。
  String get fen => side.isRed ? _kindToFenRed[kind]! : _kindToFenBlack[kind]!;

  /// 中文字符（用于走法记录展示）。
  String get label {
    const redLabels = {
      PieceKind.king: '帅',
      PieceKind.advisor: '仕',
      PieceKind.minister: '相',
      PieceKind.knight: '马',
      PieceKind.rook: '车',
      PieceKind.cannon: '炮',
      PieceKind.pawn: '兵',
    };
    const blackLabels = {
      PieceKind.king: '将',
      PieceKind.advisor: '士',
      PieceKind.minister: '象',
      PieceKind.knight: '马',
      PieceKind.rook: '车',
      PieceKind.cannon: '炮',
      PieceKind.pawn: '卒',
    };
    return side.isRed ? redLabels[kind]! : blackLabels[kind]!;
  }

  @override
  bool operator ==(Object other) =>
      other is Piece && other.kind == kind && other.side == side;

  @override
  int get hashCode => Object.hash(kind, side);

  @override
  String toString() => '$fen(${side.name})';
}

/// 从 FEN 字符解析单个棋子。
Piece? pieceFromFenChar(String char) {
  final result = _fenToKind[char];
  if (result == null) return null;
  return Piece(kind: result.$1, side: result.$2);
}
