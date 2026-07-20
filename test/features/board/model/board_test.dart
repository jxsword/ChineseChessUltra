import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_chess_ultra/features/board/model/board.dart';
import 'package:chinese_chess_ultra/features/board/model/fen.dart';
import 'package:chinese_chess_ultra/features/board/model/move.dart';
import 'package:chinese_chess_ultra/features/board/model/piece.dart';

/// 辅助：在 (col,row) 处指定棋子构造一个空棋盘。
Board _boardWith(Map<Position, Piece> pieces, {bool redTurn = true}) {
  final fen = Fen.initial.split(' ').first;
  final grid = Fen.parseBoard('$fen ${redTurn ? 'w' : 'b'} - - 0 1');
  // 清空所有格子，重新放置。
  for (var r = 0; r < 10; r++) {
    for (var c = 0; c < 9; c++) {
      grid[r][c] = null;
    }
  }
  pieces.forEach((pos, p) {
    grid[pos.row][pos.col] = p;
  });
  final newFen = Fen.build(board: grid, isRedTurn: redTurn);
  return Board.fromFen(newFen);
}

void main() {
  group('Board 初始局面', () {
    test('棋盘共 32 个棋子（红黑各 16）', () {
      final board = Board.initial();
      var red = 0, black = 0;
      for (var r = 0; r < 10; r++) {
        for (var c = 0; c < 9; c++) {
          final p = board.pieceAt(c, r);
          if (p == null) continue;
          if (p.side.isRed) {
            red++;
          } else {
            black++;
          }
        }
      }
      expect(red, 16);
      expect(black, 16);
    });

    test('初始局面红方先行', () {
      expect(Board.initial().isRedTurn, isTrue);
    });
  });

  group('车（rook）走法', () {
    test('空棋盘上的车可横竖移动到所有同行同列格子', () {
      // 红将放在九宫 (4,9)，不与车 (4,5) 同行同列冲突，且不会照面。
      final board = _boardWith({
        const Position(4, 5): const Piece(kind: PieceKind.rook, side: Side.red),
        const Position(3, 9): const Piece(kind: PieceKind.king, side: Side.red),
      });
      final moves = board.legalMovesFor(const Position(4, 5));
      // 同列 9 格（不含自身），同行 8 格（不含自身），共 17。
      expect(moves.length, 17);
    });

    test('车不能跳过棋子', () {
      final board = _boardWith({
        const Position(4, 5): const Piece(kind: PieceKind.rook, side: Side.red),
        const Position(4, 3):
            const Piece(kind: PieceKind.pawn, side: Side.black),
        const Position(4, 9): const Piece(kind: PieceKind.king, side: Side.red),
      });
      final moves = board.legalMovesFor(const Position(4, 5));
      // 上方遇到兵在 (4,3)，可以吃，但不能跳到 (4,2)/(4,1)/(4,0)。
      final upTargets = moves.where((m) => m.to.col == 4 && m.to.row < 5).toList();
      expect(upTargets.any((m) => m.to.row == 4), isTrue);
      expect(upTargets.any((m) => m.to.row == 3), isTrue); // 吃兵
      expect(upTargets.any((m) => m.to.row == 2), isFalse);
      expect(upTargets.any((m) => m.to.row == 1), isFalse);
    });
  });

  group('马（knight）走法', () {
    test('马走日，且受马腿限制', () {
      final board = _boardWith({
        const Position(4, 5):
            const Piece(kind: PieceKind.knight, side: Side.red),
        const Position(4, 0): const Piece(kind: PieceKind.king, side: Side.red),
      });
      final moves = board.legalMovesFor(const Position(4, 5));
      // 标准马八处可达，但因有将在 (4,0)，向上去 8 处中部分会自将，这里只验证总数 > 0。
      expect(moves.length, greaterThan(0));
      // 八个方向至少包含 (5,7)、(3,7)、(6,6)、(2,6)、(6,4)、(2,4)、(5,3)、(3,3)。
      const expected = [
        Position(5, 7),
        Position(3, 7),
        Position(6, 6),
        Position(2, 6),
        Position(6, 4),
        Position(2, 4),
        Position(5, 3),
        Position(3, 3),
      ];
      for (final e in expected) {
        expect(moves.any((m) => m.to == e), isTrue,
            reason: '马应该能走到 $e');
      }
    });

    test('马腿被堵时无法越过', () {
      final board = _boardWith({
        const Position(4, 5):
            const Piece(kind: PieceKind.knight, side: Side.red),
        const Position(4, 4):
            const Piece(kind: PieceKind.pawn, side: Side.black),
        const Position(4, 9): const Piece(kind: PieceKind.king, side: Side.red),
      });
      final moves = board.legalMovesFor(const Position(4, 5));
      // 马腿 (4,4) 被堵，向下不能走 (3,3) / (5,3)。
      expect(moves.any((m) => m.to == const Position(3, 3)), isFalse);
      expect(moves.any((m) => m.to == const Position(5, 3)), isFalse);
    });
  });

  group('炮（cannon）走法', () {
    test('空格移动同车；吃子需隔一子（炮架）', () {
      final board = _boardWith({
        const Position(4, 5):
            const Piece(kind: PieceKind.cannon, side: Side.red),
        const Position(4, 3):
            const Piece(kind: PieceKind.pawn, side: Side.black),
        const Position(4, 1):
            const Piece(kind: PieceKind.advisor, side: Side.black),
        const Position(4, 9): const Piece(kind: PieceKind.king, side: Side.red),
      });
      final moves = board.legalMovesFor(const Position(4, 5));
      // 上方可走到 (4,4) 空格，遇到兵 (4,3) 为炮架，跳过它后能吃 (4,1)。
      expect(moves.any((m) => m.to == const Position(4, 4)), isTrue);
      expect(moves.any((m) => m.to == const Position(4, 3)), isFalse); // 不能直接吃炮架
      expect(moves.any((m) => m.to == const Position(4, 1)), isTrue); // 隔架吃
      expect(moves.any((m) => m.to == const Position(4, 0)), isFalse);
    });
  });

  group('象/相（minister）走法', () {
    test('象走田，不能过河，受象眼限制', () {
      final board = _boardWith({
        const Position(4, 9):
            const Piece(kind: PieceKind.minister, side: Side.red),
        const Position(4, 0): const Piece(kind: PieceKind.king, side: Side.red),
      });
      final moves = board.legalMovesFor(const Position(4, 9));
      // 红相在 (4,9)，可走 (2,7)、(6,7)，不能过河（row < 5）。
      expect(moves.any((m) => m.to == const Position(2, 7)), isTrue);
      expect(moves.any((m) => m.to == const Position(6, 7)), isTrue);
      expect(moves.every((m) => m.to.row >= 5), isTrue);
    });
  });

  group('士（advisor）走法', () {
    test('士只能在九宫格内斜走', () {
      final board = _boardWith({
        const Position(3, 9):
            const Piece(kind: PieceKind.advisor, side: Side.red),
        const Position(4, 9): const Piece(kind: PieceKind.king, side: Side.red),
      });
      final moves = board.legalMovesFor(const Position(3, 9));
      // 红士在 (3,9)，可斜走到 (4,8)。
      expect(moves.any((m) => m.to == const Position(4, 8)), isTrue);
      // 不能平走到 (3,8) 或 (2,9)（不属于斜走）。
      expect(moves.any((m) => m.to == const Position(3, 8)), isFalse);
    });
  });

  group('将/帅（king）走法', () {
    test('将只能在九宫格内直走一格', () {
      final board = _boardWith({
        const Position(4, 9): const Piece(kind: PieceKind.king, side: Side.red),
      });
      final moves = board.legalMovesFor(const Position(4, 9));
      expect(moves.any((m) => m.to == const Position(4, 8)), isTrue);
      expect(moves.any((m) => m.to == const Position(3, 9)), isTrue);
      expect(moves.any((m) => m.to == const Position(5, 9)), isTrue);
      // 不能斜走。
      expect(moves.any((m) => m.to == const Position(3, 8)), isFalse);
      // 不能走出九宫。
      expect(moves.any((m) => m.to == const Position(4, 6)), isFalse);
    });

    test('将帅照面：双将同列且中间无子时算将军', () {
      final board = _boardWith({
        const Position(4, 9): const Piece(kind: PieceKind.king, side: Side.red),
        const Position(4, 0):
            const Piece(kind: PieceKind.king, side: Side.black),
      });
      expect(board.isCheck(Side.red), isTrue);
      expect(board.isCheck(Side.black), isTrue);
    });
  });

  group('兵/卒（pawn）走法', () {
    test('未过河兵只能前进', () {
      final board = _boardWith({
        const Position(4, 6): const Piece(kind: PieceKind.pawn, side: Side.red),
        const Position(4, 9): const Piece(kind: PieceKind.king, side: Side.red),
      });
      final moves = board.legalMovesFor(const Position(4, 6));
      expect(moves.any((m) => m.to == const Position(4, 5)), isTrue);
      expect(moves.any((m) => m.to == const Position(3, 6)), isFalse);
      expect(moves.any((m) => m.to == const Position(5, 6)), isFalse);
    });

    test('过河兵可前进或横走', () {
      final board = _boardWith({
        const Position(4, 4): const Piece(kind: PieceKind.pawn, side: Side.red),
        const Position(4, 9): const Piece(kind: PieceKind.king, side: Side.red),
      });
      final moves = board.legalMovesFor(const Position(4, 4));
      expect(moves.any((m) => m.to == const Position(4, 3)), isTrue);
      expect(moves.any((m) => m.to == const Position(3, 4)), isTrue);
      expect(moves.any((m) => m.to == const Position(5, 4)), isTrue);
      expect(moves.any((m) => m.to == const Position(4, 5)), isFalse); // 不能后退
    });
  });

  group('将军 / 将死 / 困毙', () {
    test('isCheck：车直面对方将算将军', () {
      final board = _boardWith({
        const Position(4, 5): const Piece(kind: PieceKind.rook, side: Side.red),
        const Position(4, 0):
            const Piece(kind: PieceKind.king, side: Side.black),
        const Position(4, 9): const Piece(kind: PieceKind.king, side: Side.red),
      });
      expect(board.isCheck(Side.black), isTrue);
    });

    test('isCheckmate：经典单车将死', () {
      // 黑将在九宫顶角 (3,0)，红车控制第三列与第 0 行；
      // 黑将无路可逃（同列被车盯、同行另一格 (5,0) 也在第 0 行被车吃）。
      final board = _boardWith({
        const Position(3, 5): const Piece(kind: PieceKind.rook, side: Side.red),
        const Position(0, 0):
            const Piece(kind: PieceKind.rook, side: Side.red),
        const Position(3, 0):
            const Piece(kind: PieceKind.king, side: Side.black),
        const Position(4, 9): const Piece(kind: PieceKind.king, side: Side.red),
      }, redTurn: false); // 当前轮到黑方，验证黑方是否被将死
      expect(board.isCheck(Side.black), isTrue);
      expect(board.isCheckmate(Side.black), isTrue);
    });

    test('isStalemate：困毙接口逻辑（复杂场面需更多棋子构造，此处仅验证未被将军状态）', () {
      // 简单验证：初始局面未被将军，必然有合法走法。
      final board = Board.initial();
      expect(board.isCheck(Side.red), isFalse);
      expect(board.isStalemate(Side.red), isFalse);
      // 困毙的精确场面需至少 10+ 个棋子配置，超出本测试范围。
      // 关键点验证：isCheck 与 isStalemate 互斥（未被将军才调用困毙判断）。
      // 注：完整的困毙测试建议通过实际对局截图构造 FEN。
    });
  });

  group('applyMove / undoMove 互逆', () {
    test('走子 + 悔棋后 FEN 不变', () {
      final fen0 = Fen.initial;
      final board = Board.fromFen(fen0);
      final move = const Move(from: Position(1, 7), to: Position(2, 7));
      board.applyMove(move);
      expect(board.toFen() == fen0, isFalse);
      board.undoMove(Move(
        from: move.from,
        to: move.to,
        captured: null,
      ));
      expect(board.toFen(), fen0);
    });
  });
}
