/// XQF（象棋演播室）二进制棋谱解析器。
///
/// 格式参考 XQF 规范（www.xqbase.com/protocol/cchess_xqf.htm）与
/// walker8088/cchess 的 `io_xqf.py` 实现（已对本项目语料实测）。
///
/// 要点：
/// - 魔数为前两字节 `XQ`（0x58 0x51），第 3 字节是格式版本号，语料中分布
///   在 0x0A–0x12；版本 <= 0x0A 的旧格式无加密，之后的版本对棋子布局与
///   走子数据做字节变换加密。
/// - 32 个棋子的存放顺序固定（帅仕相马车炮兵 / 将士象马车炮卒），
///   每子 1 字节位置，编码为 `x*10 + y`（x=列 0-8，y=行，0 为红方底线），
///   0xFF 表示让子（无此子）。
/// - 字符串字段为 GB18030（GBK 超集），按长度前缀存放。
/// - 走子数据是一棵记录树（每条记录 4 字节 + 可选注解），本解析器只取
///   主线（变着分支仅存在于主线结束之后，不影响缓冲区对齐）。
library;

import 'dart:typed_data';

import 'package:fast_gbk/fast_gbk.dart';
import 'package:logging/logging.dart';

import '../../../board/model/fen.dart';
import '../../../board/model/piece.dart';
import '../../../board/model/move.dart';
import '../iccs.dart';
import '../puzzle_data.dart';

/// XQF 棋谱解析结果与解析入口。
class XqfParser {
  XqfParser._();

  static final _log = Logger('XqfParser');

  // ----- 格式常量 -----

  /// 文件头大小。
  static const int headerSize = 0x400;

  static const int _moveFromOffset = 0x18;
  static const int _moveToOffset = 0x20;
  static const int _stepFlagMask = 0xE0;
  static const int _stepHasAnno = 0x20;
  static const int _stepHasNext = 0x80;

  // 变着标志位（0x40）仅用于完整树遍历，本解析器只取主线，故未消费。

  /// 旧格式（版本 <= 0x0A）分界。
  static const int _legacyVersionMax = 0x0A;

  /// 32 个棋子位次的 FEN 字符（红方大写、黑方小写）。
  ///
  /// XQF 存放顺序为对称回文序：车马相仕帅仕相马车（9）+ 炮炮（2）+ 兵×5（16 子），
  /// 黑方同序小写（已用语料实证校准，非部分文档所写的帅仕相马车序）。
  static const List<String> _pieceChars = [
    'R', 'N', 'B', 'A', 'K', 'A', 'B', 'N', 'R', 'C', 'C',
    'P', 'P', 'P', 'P', 'P',
    'r', 'n', 'b', 'a', 'k', 'a', 'b', 'n', 'r', 'c', 'c',
    'p', 'p', 'p', 'p', 'p',
  ];

  /// 解密变换的种子串（XQF 作者版权串，用于生成 32 字节密钥表）。
  static const String _keySeed = '[(C) Copyright Mr. Dong Shiwei.]';

  // ----- 公共入口 -----

  /// 解析 XQF 字节流为 [ParsedPuzzle]。
  ///
  /// [source] 为来源标注（如语料分类路径），缺省 `xqf`。
  /// 魔数错误 / 文件过短 / 无将帅时抛 [FormatException]。
  static ParsedPuzzle parse(Uint8List bytes, {String source = 'xqf'}) {
    if (bytes.length < headerSize + 8) {
      throw FormatException('XQF 文件过短: ${bytes.length} 字节');
    }
    if (bytes[0] != 0x58 || bytes[1] != 0x51) {
      throw FormatException(
          'XQF 魔数错误: 0x${bytes[0].toRadixString(16)}0x${bytes[1].toRadixString(16)}');
    }
    final version = bytes[2];

    // 头部字段（偏移见类注释；与 cchess io_xqf.py 的 struct 布局一致）。
    final keyMask = bytes[3];
    final keyOrA = bytes[8], keyOrB = bytes[9], keyOrC = bytes[10];
    final keyOrD = bytes[11];
    final keysSum = bytes[12], headKeyXY = bytes[13];
    final headKeyXYf = bytes[14], headKeyXYt = bytes[15];
    final boardBytes = Uint8List.sublistView(bytes, 16, 48);
    final title = _readString(bytes, 80, 63);
    final event = _readString(bytes, 208, 63);
    final date = _readString(bytes, 272, 15);
    final redName = _readString(bytes, 352, 15);
    final blackName = _readString(bytes, 368, 15);

    // 密钥与数据解密（仅新格式）。
    final encrypted = version > _legacyVersionMax;
    _XqfKeys? keys;
    if (encrypted) {
      keys = _deriveKeys(
        keyMask: keyMask,
        keyOrA: keyOrA,
        keyOrB: keyOrB,
        keyOrC: keyOrC,
        keyOrD: keyOrD,
        keysSum: keysSum,
        headKeyXY: headKeyXY,
        headKeyXYf: headKeyXYf,
        headKeyXYt: headKeyXYt,
      );
    }

    // 棋子布局 → 棋盘矩阵。
    final board = _decodeBoard(boardBytes, version, keys);
    var hasRedKing = false, hasBlackKing = false;
    for (final row in board) {
      for (final p in row) {
        if (p?.kind == PieceKind.king) {
          if (p!.side == Side.red) {
            hasRedKing = true;
          } else {
            hasBlackKing = true;
          }
        }
      }
    }
    if (!hasRedKing || !hasBlackKing) {
      throw const FormatException('XQF 局面缺少将/帅');
    }

    // 走子主线。
    final moves = _decodeMainLine(bytes, version, keys);

    // 走子方：有走法则看第一着起点棋子颜色，否则默认红先。
    var isRedTurn = true;
    if (moves.isNotEmpty) {
      final first = Iccs.parse(moves.first);
      if (first != null) {
        final mover = board[first.from.row][first.from.col];
        if (mover != null) isRedTurn = mover.side == Side.red;
      }
    }
    final fen = Fen.build(board: board, isRedTurn: isRedTurn);

    // 元数据组装。
    final titleText = (title == null || title.trim().isEmpty)
        ? _defaultTitle(redName, blackName)
        : title.trim();
    final players =
        '${redName ?? '?'} vs ${blackName ?? '?'}';
    final descParts = [
      if (event != null && event.trim().isNotEmpty) event.trim(),
      if (date != null && date.trim().isNotEmpty) date.trim(),
      players,
    ];

    return ParsedPuzzle(
      id: 'xqf/$source/$titleText',
      initialFen: fen,
      solutionMoves: moves,
      title: titleText,
      description: descParts.join(' · '),
      source: source,
      format: 'xqf',
      difficulty: ParsedPuzzle.difficultyFromMoveCount(moves.length),
    );
  }

  // ----- 头部字符串 -----

  static String? _readString(Uint8List bytes, int lenOffset, int maxLen) {
    final len = bytes[lenOffset];
    if (len <= 0 || len > maxLen) return null;
    final raw = Uint8List.sublistView(bytes, lenOffset + 1, lenOffset + 1 + len);
    try {
      return const GbkCodec(allowMalformed: true).decode(raw);
    } on FormatException {
      return null;
    }
  }

  static String _defaultTitle(String? red, String? black) {
    if (red != null || black != null) return '${red ?? '?'} 对 ${black ?? '?'}';
    return '未命名对局';
  }

  // ----- 密钥派生 -----

  static _XqfKeys _deriveKeys({
    required int keyMask,
    required int keyOrA,
    required int keyOrB,
    required int keyOrC,
    required int keyOrD,
    required int keysSum,
    required int headKeyXY,
    required int headKeyXYf,
    required int headKeyXYt,
  }) {
    // 单字节变换基数（XQF 原始公式： ((((x²*3+9)*3+8)*2+1)*3+8)，注意无尾因子）。
    int formula(int x) => ((((x * x) * 3 + 9) * 3 + 8) * 2 + 1) * 3 + 8;

    // KeyXY 多乘一次自身头字节；KeyXYf/KeyXYt 依次链乘前一把钥匙。
    final keyXY = formula(headKeyXY) * headKeyXY & 0xFF;
    final keyXYf = formula(headKeyXYf) * keyXY & 0xFF;
    final keyXYt = formula(headKeyXYt) * keyXYf & 0xFF;
    final keyRmkSize = ((keysSum * 256 + headKeyXY) % 32000 + 767) & 0xFFFF;

    // FKeyBytes 由头部原始字节（而非派生密钥）与掩码/或值组合而成。
    final keyBytes = [
      (keysSum & keyMask) | keyOrA,
      (headKeyXY & keyMask) | keyOrB,
      (headKeyXYf & keyMask) | keyOrC,
      (headKeyXYt & keyMask) | keyOrD,
    ];
    final f32 = List<int>.generate(
      32,
      (i) => _keySeed.codeUnitAt(i) & keyBytes[i % 4],
    );
    return _XqfKeys(
      keyXY: keyXY,
      keyXYf: keyXYf,
      keyXYt: keyXYt,
      keyRmkSize: keyRmkSize,
      f32: f32,
    );
  }

  // ----- 棋子布局 -----

  static List<List<Piece?>> _decodeBoard(
    Uint8List boardBytes,
    int version,
    _XqfKeys? keys,
  ) {
    final pos = List<int>.filled(32, 0xFF);
    if (keys == null) {
      for (var i = 0; i < 32; i++) {
        pos[i] = boardBytes[i];
      }
    } else {
      for (var i = 0; i < 32; i++) {
        // 版本 >= 12 的布局做了位置置换。
        if (version >= 12) {
          pos[(keys.keyXY + i + 1) & 0x1F] = boardBytes[i];
        } else {
          pos[i] = boardBytes[i];
        }
      }
      for (var i = 0; i < 32; i++) {
        pos[i] = (pos[i] - keys.keyXY) & 0xFF;
      }
    }

    final board = List.generate(
        10, (_) => List<Piece?>.filled(9, null, growable: false),
        growable: false);
    for (var i = 0; i < 32; i++) {
      final v = pos[i];
      if (v > 89) continue; // 0xFF 或越界 = 无子
      final col = v ~/ 10;
      final row = v % 10;
      if (col > 8 || row > 9) continue;
      board[9 - row][col] = pieceFromFenChar(_pieceChars[i]);
    }
    return board;
  }

  // ----- 走子主线 -----

  static List<String> _decodeMainLine(
    Uint8List bytes,
    int version,
    _XqfKeys? keys,
  ) {
    Uint8List buff;
    if (keys == null) {
      buff = Uint8List.sublistView(bytes, headerSize);
    } else {
      final raw = Uint8List.sublistView(bytes, headerSize);
      buff = Uint8List(raw.length);
      for (var i = 0; i < raw.length; i++) {
        buff[i] = (raw[i] - keys.f32[(headerSize + i) % 32]) & 0xFF;
      }
    }

    var index = 0;
    // 根记录：代表初始局面的伪走子，只关心其注解位。
    if (buff.length - index < 4) return const [];
    final rootFlag = buff[index + 2];
    index += 4;
    var annoteLen = 0;
    if (keys == null) {
      annoteLen = _readInt32(buff, index);
      index += 4;
    } else {
      if ((rootFlag & _stepFlagMask & _stepHasAnno) != 0) {
        annoteLen = _readInt32(buff, index) - keys.keyRmkSize;
        index += 4;
      }
    }
    if (annoteLen > 0) {
      index += annoteLen; // 注解内容暂不展示，仅跳过
    }

    final moves = <String>[];
    while (buff.length - index >= 4) {
      final fromRaw = buff[index];
      final toRaw = buff[index + 1];
      final flagRaw = buff[index + 2];
      index += 4;

      bool hasNext;
      int fromPos, toPos;
      if (keys == null) {
        // 旧版本：注解长度总是存在；高 4 位有值 = 有后续走子。
        annoteLen = _readInt32(buff, index);
        index += 4;
        if (annoteLen > 0) index += annoteLen;
        hasNext = (flagRaw & 0xF0) != 0;
        fromPos = (fromRaw - _moveFromOffset) & 0xFF;
        toPos = (toRaw - _moveToOffset) & 0xFF;
      } else {
        final flag = flagRaw & _stepFlagMask;
        if ((flag & _stepHasAnno) != 0) {
          annoteLen = _readInt32(buff, index) - keys.keyRmkSize;
          index += 4;
          if (annoteLen > 0) index += annoteLen;
        }
        hasNext = (flag & _stepHasNext) != 0;
        fromPos = (fromRaw - _moveFromOffset - keys.keyXYf) & 0xFF;
        toPos = (toRaw - _moveToOffset - keys.keyXYt) & 0xFF;
      }

      final from = _decodePosition(fromPos);
      final to = _decodePosition(toPos);
      if (from == null || to == null) {
        _log.warning('XQF 走子位置越界（from=$fromPos, to=$toPos），主线终止');
        break;
      }
      final iccs = Iccs.format(from, to);
      if (iccs == null) break;
      moves.add(iccs);

      if (!hasNext) break;
    }
    return moves;
  }

  /// 解码位置字节 `x*10 + y` 为项目内部坐标（row 与 y 上下颠倒）。
  static Position? _decodePosition(int pos) {
    if (pos > 89) return null;
    final col = pos ~/ 10;
    final row = 9 - (pos % 10);
    final p = Position(col, row);
    return p.isValid ? p : null;
  }

  static int _readInt32(Uint8List b, int offset) {
    if (offset + 4 > b.length) return 0;
    return b[offset] |
        (b[offset + 1] << 8) |
        (b[offset + 2] << 16) |
        (b[offset + 3] << 24);
  }
}

/// XQF 解密密钥集。
class _XqfKeys {
  final int keyXY;
  final int keyXYf;
  final int keyXYt;
  final int keyRmkSize;
  final List<int> f32;

  const _XqfKeys({
    required this.keyXY,
    required this.keyXYf,
    required this.keyXYt,
    required this.keyRmkSize,
    required this.f32,
  });
}
