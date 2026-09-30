/// 棋谱解析门面。
///
/// 按文件扩展名分发到 [XqfParser] / [PgnParser]，并对解析结果做
/// 重放校验（用项目内 [Board] 逐着验证合法性，遇到非法着即截断），
/// 保证进入 UI 的棋谱可以在演示器中完整播放。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:logging/logging.dart';

import '../../board/model/board.dart';
import '../../board/model/move.dart';
import 'iccs.dart';
import 'puzzle_data.dart';
import 'parsers/pgn_parser.dart';
import 'parsers/xqf_parser.dart';

/// 棋谱解析入口。
class PuzzleParser {
  PuzzleParser._();

  static final _log = Logger('PuzzleParser');

  /// 解析棋谱字节流为棋局列表（XQF 单局；PGN 可多局）。
  ///
  /// [fileName] 仅用于判断格式；[source] 作为来源标注（如语料分类）。
  /// 不认识的扩展名抛 [FormatException]。
  static List<ParsedPuzzle> parse({
    required String fileName,
    required Uint8List bytes,
    String source = 'import',
  }) {
    final ext = fileName.toLowerCase().split('.').last;
    final List<ParsedPuzzle> parsed;
    switch (ext) {
      case 'xqf':
        parsed = [XqfParser.parse(bytes, source: source)];
      case 'pgn':
      case 'pgns':
        final content = utf8.decode(bytes, allowMalformed: true);
        parsed = PgnParser.parseGames(content, source: source);
      default:
        throw FormatException('不支持的棋谱格式: .$ext（支持 .xqf / .pgn）');
    }
    return _validateAndDedupe(parsed);
  }

  /// 大文件导入阈值：超过此大小的多局 PGN 整读内存代价过高
  /// （如 101MB 的 .pgns），应改走按局偏移索引的流式路径。
  static const int streamImportThresholdBytes = 8 * 1024 * 1024;

  /// 判断导入是否应走按局索引流式路径（仅多局 PGN 大文件）。
  static bool shouldStreamImport(String fileName, int byteLength) {
    final ext = fileName.toLowerCase().split('.').last;
    return (ext == 'pgn' || ext == 'pgns') &&
        byteLength > streamImportThresholdBytes;
  }

  /// 逐局重放校验；非法着截断（至少保留 1 着，否则丢弃该局），并保证 id 唯一。
  static List<ParsedPuzzle> _validateAndDedupe(List<ParsedPuzzle> input) {
    final result = <ParsedPuzzle>[];
    final seenIds = <String>{};
    for (final puzzle in input) {
      try {
        final board = Board.fromFen(puzzle.initialFen);
        var valid = <String>[];
        for (final iccs in puzzle.moves) {
          final pos = Iccs.parse(iccs);
          if (pos == null || board.pieceAtP(pos.from) == null) break;
          final legal = board
              .legalMovesFor(pos.from)
              .any((m) => m.from == pos.from && m.to == pos.to);
          if (!legal) {
            _log.warning(
                '棋局 "${puzzle.title}" 第 ${valid.length + 1} 着 $iccs 不合法，已截断');
            break;
          }
          board.applyMove(Move(from: pos.from, to: pos.to));
          valid.add(iccs);
        }
        if (valid.isEmpty) {
          _log.warning('棋局 "${puzzle.title}" 无可演示走法，已丢弃');
          continue;
        }
        var id = puzzle.id;
        while (!seenIds.add(id)) {
          id = '$id#';
        }
        result.add(puzzle.copyWith(
          id: id,
          solutionMoves: valid,
          difficulty: ParsedPuzzle.difficultyFromMoveCount(valid.length),
        ));
      } on FormatException catch (e) {
        _log.warning('棋局 "${puzzle.title}" FEN 无效，已丢弃: ${e.message}');
      }
    }
    return result;
  }
}
