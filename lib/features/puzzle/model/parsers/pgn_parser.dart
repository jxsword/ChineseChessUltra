/// PGN（中国象棋变体）棋谱解析器。
///
/// 支持两种着法文本：
/// - ICCS 坐标：`H2-E2` / `h2e2`（列 a-i、行 0-9，0 为红方底线）；
/// - 中文纵线记谱：`炮二平五`、`马8进7`、`前炮退二` 等，随局面逐着消解。
///
/// 标签对支持 `[FEN]`（自定义起始局面）、`[Event]`、`[Red]`、`[Black]` 等；
/// 无 `[FEN]` 时使用标准初始局面。注释 `{...}`、行注释 `;...`、NAG `$n`、
/// 变着 `(...)` 被跳过；多局文件按局切分。
///
/// 大文件（多局合一 `.pgns`，可达百 MB）不要整读内存：用 [scanGameOffsets]
/// 流式建立按局偏移索引，再用 [readGameAt] 按需读取单局交给 [parseGame]。
library;

import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:meta/meta.dart';

import '../../../board/model/board.dart';
import '../../../board/model/fen.dart';
import '../../../board/model/move.dart';
import '../../../board/model/piece.dart';
import '../iccs.dart';
import '../puzzle_data.dart';

/// PGN 棋谱解析器。
class PgnParser {
  PgnParser._();

  static final _log = Logger('PgnParser');

  static final _tagPattern = RegExp(r'^\s*\[(\w+)\s+"(.*)"\]\s*$');
  static final _moveNumberPattern = RegExp(r'\d+\s*\.+');
  static final _resultPattern = RegExp(r'(1-0|0-1|1/2-1/2|\*)');
  static final _nagPattern = RegExp(r'\$\d+');
static final _innermostVarPattern = RegExp(r'\([^()]*\)');

  /// 着法 token（已去除空白与序号）的整体匹配。
  ///
  /// ICCS 与中文纵线记谱交替扫描；中文形如
  /// `[前后中]?棋子[列号?]平/进/退[数字]`（前/后/中 消歧时省略列号）。
  static final _movePattern = RegExp(
      r'([a-iA-I]\d{1,2}-?[a-iA-I]\d{1,2})'
      r'|([前后中]?[车马炮兵卒帅将仕士相象砲][一二三四五六七八九\d０-９]?[平进退][一二三四五六七八九\d０-９])');

  /// 红方汉字数字（一~九）。
  static const _cnDigits = {
    '一': 1, '二': 2, '三': 3, '四': 4, '五': 5,
    '六': 6, '七': 7, '八': 8, '九': 9,
  };

  /// 棋子中文字符 → 种类（颜色由轮走方决定，因 车/马/炮 等红黑同形）。
  static const _pieceKindByChar = <String, PieceKind>{
    '车': PieceKind.rook, '马': PieceKind.knight, '炮': PieceKind.cannon,
    '砲': PieceKind.cannon, '兵': PieceKind.pawn, '卒': PieceKind.pawn,
    '帅': PieceKind.king, '将': PieceKind.king,
    '仕': PieceKind.advisor, '士': PieceKind.advisor,
    '相': PieceKind.minister, '象': PieceKind.minister,
  };

  /// 直线走子（进/退后跟格数）；其余为斜走子（进/退后跟目标纵线）。
  static const _linearKinds = {
    PieceKind.rook, PieceKind.cannon, PieceKind.king, PieceKind.pawn,
  };

  // ----- 多局切分与整段解析 -----

  /// 解析整段 PGN 文本（可含多局），返回全部棋局。
  ///
  /// 单局解析失败时记录日志并跳过，不影响其余棋局。
  static List<ParsedPuzzle> parseGames(String content,
      {String source = 'pgn'}) {
    final games = <ParsedPuzzle>[];
    for (final gameText in splitGames(content)) {
      try {
        games.add(parseGame(gameText, source: source));
      } on FormatException catch (e) {
        _log.warning('PGN 局解析失败，已跳过: ${e.message}');
      }
    }
    return games;
  }

  /// 把多局 PGN 文本按局切分。
  ///
  /// 以"出现着法之后再次遇到标签行"作为新一局的开始。
  static List<String> splitGames(String content) {
    final games = <String>[];
    final buf = StringBuffer();
    var inMoves = false;
    for (final line in content.split(RegExp(r'\r?\n'))) {
      final isTag = line.startsWith('[') && _tagPattern.hasMatch(line);
      if (isTag && inMoves) {
        games.add(buf.toString());
        buf.clear();
        inMoves = false;
      }
      buf.writeln(line);
      if (!isTag && line.trim().isNotEmpty) inMoves = true;
    }
    if (buf.toString().trim().isNotEmpty) games.add(buf.toString());
    return games;
  }

  // ----- 单局解析 -----

  /// 解析单局 PGN 文本为 [ParsedPuzzle]。
  ///
  /// [source] 为来源标注（如语料子目录名）。着法无法消解或局面非法时抛
  /// [FormatException]。
  static ParsedPuzzle parseGame(String gameText, {String source = 'pgn'}) {
    final tags = _readTags(gameText);
    final moveSection = _extractMoveSection(gameText);

    // 起始局面：优先 FEN 标签，否则标准初始局面。
    final fenTag = tags['fen']?.trim();
    var initialBoard = Board.initial();
    var isRedTurn = true;
    if (fenTag != null && fenTag.isNotEmpty) {
      initialBoard = Board.fromFen(fenTag);
      isRedTurn = Fen.parseTurn(fenTag);
    }
    final initialFen = Fen.build(
      board: Fen.parseBoard(initialBoard.toFen()),
      isRedTurn: isRedTurn,
    );

    // 逐着消解（在棋盘上验证合法性）。
    final board = Board.fromFen(initialFen);
    final moves = <String>[];
    for (final token in moveSection) {
      final resolved = _resolveToken(token, board, isRedTurn);
      if (resolved == null) {
        // 着法无法消解：停在当前处，保留已解析的合法前缀。
        _log.warning(
            'PGN 着法 "$token" 无法消解（第 ${moves.length + 1} 着，轮走'
            '${isRedTurn ? "红" : "黑"}方），该局按 ${moves.length} 着截断');
        break;
      }
      moves.add(Iccs.format(resolved.from, resolved.to)!);
      board.applyMove(Move(from: resolved.from, to: resolved.to));
      isRedTurn = !isRedTurn;
    }
    if (moves.isEmpty) {
      throw const FormatException('PGN 局不含任何可解析着法');
    }

    final title = _nonEmpty(tags['event']) ?? _defaultTitle(tags['red'], tags['black']);
    final descParts = <String>[
      if (_nonEmpty(tags['red']) != null || _nonEmpty(tags['black']) != null)
        '${_nonEmpty(tags['red']) ?? '?'} vs ${_nonEmpty(tags['black']) ?? '?'}',
      if (_nonEmpty(tags['date']) != null) tags['date']!,
      if (_nonEmpty(tags['site']) != null) tags['site']!,
    ];

    return ParsedPuzzle(
      id: 'pgn/$source/$title/${moves.length}',
      initialFen: initialFen,
      solutionMoves: moves,
      title: title,
      description: descParts.join(' · '),
      source: source,
      format: 'pgn',
      difficulty: ParsedPuzzle.difficultyFromMoveCount(moves.length),
    );
  }

  static String? _nonEmpty(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();

  static String _defaultTitle(String? red, String? black) {
    final r = _nonEmpty(red) ?? '?';
    final b = _nonEmpty(black) ?? '?';
    return '$r 对 $b';
  }

  static Map<String, String> _readTags(String gameText) {
    final tags = <String, String>{};
    for (final line in gameText.split(RegExp(r'\r?\n'))) {
      final m = _tagPattern.firstMatch(line);
      if (m != null) {
        tags[m.group(1)!.toLowerCase()] = m.group(2)!;
      }
    }
    return tags;
  }

  /// 抽取着法文本并切分为 token 列表。
  ///
  /// 处理顺序：去块注释 `{...}` → 去行注释 `;...` → 归一化空白 →
  /// 去变着 `(...)`（支持嵌套）→ 去步数序号/NAG/结果标记 → 全文匹配着法。
  static List<String> _extractMoveSection(String gameText) {
    // 先剔除标签行（FEN 棋盘串里的字母数字会被误认为着法）。
    var text = gameText
        .split(RegExp(r'\r?\n'))
        .where((l) => !_tagPattern.hasMatch(l))
        .join('\n');
    // 单遍扫描去注释：{} 块注释内可含 ;，; 行注释内可有未闭合 {。
    text = _stripComments(text);
    // 变着：反复删除最内层括号以处理嵌套。
    while (true) {
      final next = text.replaceAll(_innermostVarPattern, ' ');
      if (next == text) break;
      text = next;
    }
    text = text.replaceAll(_moveNumberPattern, ' ');
    text = text.replaceAll(_nagPattern, ' ');
    text = text.replaceAll(_resultPattern, ' ');
    text = text.replaceAll(RegExp(r'\s+'), '');

    return _movePattern
        .allMatches(text)
        .map((m) => m.group(0)!)
        .toList(growable: false);
  }

  /// 单遍扫描去注释：块注释 `{...}` 与行注释 `;...`（到行尾）。
  ///
  /// 不能先做行注释再删块注释（块注释里的 `;` 会被误切），故逐字符处理。
  static String _stripComments(String text) {
    final out = StringBuffer();
    var inBrace = false;
    var i = 0;
    while (i < text.length) {
      final ch = text[i];
      if (inBrace) {
        if (ch == '}') inBrace = false;
      } else if (ch == '{') {
        inBrace = true;
        out.write(' ');
      } else if (ch == ';') {
        while (i < text.length && text[i] != '\n') {
          i += 1;
        }
        out.write(' ');
        continue; // '\n' 本身留给下一轮正常写入
      } else {
        out.write(ch);
      }
      i += 1;
    }
    return out.toString();
  }

  // ----- 着法消解 -----

  /// 把单个着法 token 消解为棋盘上的起止坐标。
  ///
  /// ICCS 直接查坐标并验证起点有子；中文纵线记谱按候选棋子 + 合法走法
  /// 唯一匹配。失败返回 null。
  static ({Position from, Position to})? _resolveToken(
    String token,
    Board board,
    bool isRedTurn,
  ) {
    final iccs = Iccs.parse(token);
    if (iccs != null) {
      return board.pieceAtP(iccs.from) != null ? iccs : null;
    }
    return _resolveChineseMove(token, board, isRedTurn);
  }

  static ({Position from, Position to})? _resolveChineseMove(
    String token,
    Board board,
    bool isRedTurn,
  ) {
    if (token.isEmpty) return null;
    final side = isRedTurn ? Side.red : Side.black;

    // 结构解析：[前后中]? 棋子 [列号?] 平/进/退 数字
    var idx = 0;
    String? modifier;
    if (token[idx] == '前' || token[idx] == '后' || token[idx] == '中') {
      modifier = token[idx];
      idx += 1;
    }
    final kind = _pieceKindByChar[token[idx]];
    if (kind == null) return null;
    idx += 1;

    int? colNumber; // 列号（可能省略）
    if (idx < token.length) {
      colNumber = _parseNumber(token[idx]);
      if (colNumber != null) idx += 1;
    }
    if (idx >= token.length) return null;
    final action = token[idx]; // 平 / 进 / 退
    if (action != '平' && action != '进' && action != '退') return null;
    idx += 1;
    if (idx >= token.length) return null;
    final targetNumber = _parseNumber(token[idx]);
    if (targetNumber == null) return null;
    idx += 1;
    if (idx != token.length) return null; // 应恰好消费完

    final isLinear = _linearKinds.contains(kind);

    // 候选棋子：按列号或前/后/中修饰筛选。
    final candidates = <Position>[];
    for (var row = 0; row < 10; row++) {
      for (var col = 0; col < 9; col++) {
        final p = board.pieceAtP(Position(col, row));
        if (p != null && p.kind == kind && p.side == side) {
          candidates.add(Position(col, row));
        }
      }
    }
    if (candidates.isEmpty) return null;

    List<Position> fromChoices;
    if (modifier != null && colNumber != null) {
      // 非标准组合"前兵九平八"：先限定列，再在同列多子中取前/后/中。
      final col = _numberToCol(colNumber, side);
      final inCol = candidates.where((p) => p.col == col).toList()
        ..sort((a, b) => a.row.compareTo(b.row));
      if (inCol.length < 2) return null;
      final rows = inCol.map((p) => p.row).toList();
      final ordered = side == Side.red ? rows : rows.reversed.toList();
      final pick = switch (modifier) {
        '前' => ordered.first,
        '后' => ordered.last,
        '中' => ordered.length >= 3 ? ordered[ordered.length ~/ 2] : null,
        _ => null,
      };
      if (pick == null) return null;
      fromChoices = [inCol.firstWhere((p) => p.row == pick)];
    } else if (modifier != null) {
      // 前/后/中：用于同列同类多子，省略列号；找到有多个同类子的列。
      final byCol = <int, List<Position>>{};
      for (final c in candidates) {
        byCol.putIfAbsent(c.col, () => []).add(c);
      }
      fromChoices = [];
      for (final entry in byCol.entries) {
        if (entry.value.length < 2) continue;
        final rows = entry.value.map((p) => p.row).toList()..sort();
        // 红方 row 小者为"前"，黑方相反。
        final ordered = side == Side.red ? rows : rows.reversed.toList();
        final pick = switch (modifier) {
          '前' => ordered.first,
          '后' => ordered.last,
          '中' => ordered.length >= 3 ? ordered[ordered.length ~/ 2] : null,
          _ => null,
        };
        if (pick != null) {
          fromChoices.add(entry.value.firstWhere((p) => p.row == pick));
        }
      }
    } else if (colNumber != null) {
      final col = _numberToCol(colNumber, side);
      fromChoices = candidates.where((p) => p.col == col).toList();
    } else {
      return null; // 无列号也无前后修饰，无法消解
    }

    // 在候选棋子的合法走法中寻找唯一匹配。
    final matches = <({Position from, Position to})>{};
    for (final from in fromChoices) {
      for (final move in board.legalMovesFor(from)) {
        if (_matchesAction(move.to, from, action, targetNumber, isLinear, side)) {
          matches.add((from: from, to: move.to));
        }
      }
    }
    if (matches.length != 1) {
      if (matches.length > 1) {
        _log.fine('着法 "$token" 有 ${matches.length} 个候选匹配');
      }
      return null;
    }
    return matches.first;
  }

  /// 解析数字字符（汉字、半角或全角阿拉伯数字——部分生成器黑方用全角）。
  static int? _parseNumber(String ch) {
    final cn = _cnDigits[ch];
    if (cn != null) return cn;
    // 全角 ０-９ → 半角。
    final code = ch.codeUnitAt(0);
    if (code >= 0xFF10 && code <= 0xFF19) return code - 0xFF10;
    return int.tryParse(ch);
  }

  /// 纵线号 → 列号：红方从右起一~九（col = 9-n），黑方从其右手起 1~9（col = n-1）。
  static int _numberToCol(int n, Side side) =>
      side == Side.red ? 9 - n : n - 1;

  static bool _matchesAction(
    Position to,
    Position from,
    String action,
    int number,
    bool isLinear,
    Side side,
  ) {
    final red = side == Side.red;
    switch (action) {
      case '平':
        // 平移：目标纵线，行不变。
        return to.col == _numberToCol(number, side) && to.row == from.row;
      case '进':
        if (isLinear) {
          // 直线子进：列不变，前进 number 格。
          return to.col == from.col &&
              to.row == from.row + (red ? -number : number);
        }
        // 斜走子进：数字为目标纵线，行向前。
        return to.col == _numberToCol(number, side) &&
            (red ? to.row < from.row : to.row > from.row);
      case '退':
        if (isLinear) {
          return to.col == from.col &&
              to.row == from.row + (red ? number : -number);
        }
        return to.col == _numberToCol(number, side) &&
            (red ? to.row > from.row : to.row < from.row);
    }
    return false;
  }

  // ----- 大文件按局索引 -----

  /// 流式扫描多局合一 PGN 文件，返回每局的偏移与摘要信息。
  ///
  /// 不把文件读入内存；按字节定位行（UTF-8 多字节字符跨块安全），以
  /// "出现着法后再次遇到标签行"分界。仅标签行被解码，其余保持字节。
  static List<PgnGameIndex> scanGameOffsets(String path,
      {int maxGames = -1}) {
    final result = <PgnGameIndex>[];
    final raf = File(path).openSync();
    try {
      const chunkSize = 1 << 20;
      // 单行字节缓冲上限：超过后该行按非标签行（moves 行）处理并丢弃
      // 剩余内容，防止畸形 .pgns（单行百 MB 无换行）把 pending 撑到全文件大小。
      const maxPendingBytes = 8 << 20;
      var filePos = 0; // 已读完的字节数
      var pendingStart = 0; // pending[0] 在文件中的位置
      var gameStart = -1;
      var gameTags = <String, String>{};
      var inMoves = false;
      var pendingTruncated = false; // 当前行已超限、内容被丢弃
      List<int> pending = []; // 未成行的剩余字节

      void processTruncatedLine(List<int> lineBytes, int lineStart) {
        // 超长行按非标签行处理（计为 moves 行），不解析内容。
        if (lineBytes.any(
            (b) => b != 0x0D && b != 0x0A && b != 0x20 && b != 0x09)) {
          inMoves = true;
          if (gameStart < 0) gameStart = lineStart;
        }
      }

      void processLine(List<int> lineBytes, int lineStart) {
        if (pendingTruncated) {
          processTruncatedLine(lineBytes, lineStart);
          return;
        }
        final isTagLine = lineBytes.isNotEmpty && lineBytes[0] == 0x5B; // '['
        if (isTagLine) {
          if (inMoves) {
            result.add(PgnGameIndex(
              offset: gameStart,
              length: lineStart - gameStart,
              event: _nonEmpty(gameTags['event']),
              red: _nonEmpty(gameTags['red']),
              black: _nonEmpty(gameTags['black']),
            ));
            gameTags = {};
            inMoves = false;
            gameStart = lineStart;
          } else if (gameStart < 0) {
            gameStart = lineStart;
          }
          final lineText = utf8.decode(lineBytes, allowMalformed: true);
          final m = _tagPattern.firstMatch(lineText);
          if (m != null) {
            gameTags[m.group(1)!.toLowerCase()] = m.group(2)!;
          }
        } else if (lineBytes.any((b) =>
            b != 0x0D && b != 0x0A && b != 0x20 && b != 0x09)) {
          inMoves = true;
        }
      }

      while (true) {
        final chunk = raf.readSync(chunkSize);
        if (chunk.isEmpty) break;
        var segStart = 0;
        for (var i = 0; i < chunk.length; i++) {
          if (chunk[i] == 0x0A) {
            List<int> lineBytes;
            int lineStart;
            if (pending.isNotEmpty) {
              lineBytes = [...pending, ...chunk.sublist(segStart, i)];
              lineStart = pendingStart;
            } else {
              lineBytes = chunk.sublist(segStart, i);
              lineStart = filePos + segStart;
            }
            processLine(lineBytes, lineStart);
            pending = [];
            pendingTruncated = false;
            segStart = i + 1;
            if (maxGames > 0 && result.length >= maxGames) return result;
          }
        }
        if (pending.isEmpty) pendingStart = filePos + segStart;
        if (segStart < chunk.length) {
          final remainder = chunk.sublist(segStart);
          final room = maxPendingBytes - pending.length;
          if (remainder.length > room) {
            if (room > 0) {
              pending.addAll(remainder.sublist(0, room));
            }
            pendingTruncated = true;
          } else {
            pending.addAll(remainder);
          }
        }
        filePos += chunk.length;
      }
      // 文件末尾最后一行（若非空）。
      if (pending.isNotEmpty) {
        processLine(pending, pendingStart);
        pending = [];
        pendingTruncated = false;
      }
      if (gameStart >= 0) {
        final end = raf.lengthSync();
        if (end > gameStart) {
          result.add(PgnGameIndex(
            offset: gameStart,
            length: end - gameStart,
            event: _nonEmpty(gameTags['event']),
            red: _nonEmpty(gameTags['red']),
            black: _nonEmpty(gameTags['black']),
          ));
        }
      }
    } finally {
      raf.closeSync();
    }
    return result;
  }

  /// 读取 [index] 指向的单局文本。
  static String readGameAt(String path, PgnGameIndex index) {
    final raf = File(path).openSync();
    try {
      raf.setPositionSync(index.offset);
      final bytes = raf.readSync(index.length);
      return utf8.decode(bytes, allowMalformed: true);
    } finally {
      raf.closeSync();
    }
  }

  // ----- 测试钩子 -----

  /// 供测试使用的着法 token 抽取。
  @visibleForTesting
  static List<String> extractMovesForTest(String gameText) =>
      _extractMoveSection(gameText);

  /// 供测试使用的单着消解。
  @visibleForTesting
  static ({Position from, Position to})? resolveTokenForTest(
          String token, Board board, bool isRedTurn) =>
      _resolveToken(token, board, isRedTurn);

  /// 供测试使用的标签读取。
  @visibleForTesting
  static Map<String, String> readTagsForTest(String gameText) =>
      _readTags(gameText);
}

/// 大 PGN 文件中单局的索引条目（偏移 + 摘要）。
class PgnGameIndex {
  final int offset;
  final int length;
  final String? event;
  final String? red;
  final String? black;

  const PgnGameIndex({
    required this.offset,
    required this.length,
    this.event,
    this.red,
    this.black,
  });

  String get title => event ?? '${red ?? '?'} vs ${black ?? '?'}';
}
