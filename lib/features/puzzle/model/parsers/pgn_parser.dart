import '../puzzle_parser.dart';

/// PGN 格式残局解析器（二期实现示例骨架）。
///
/// 第一期不实现具体解析逻辑，仅作为占位，让 [PuzzleParserFactory]
/// 在二期可以无侵入注册。
class PgnParser implements PuzzleParser {
  const PgnParser();

  @override
  Set<String> get supportedExtensions => const {'pgn'};

  @override
  Puzzle parse(List<int> bytes, {String? filename}) {
    // TODO(二期): 实现 PGN 文本解析（含变例、FEN 标签、走法列表）。
    throw PuzzleParseException('PGN parser not implemented yet');
  }
}

/// XQF 格式残局解析器（二期）。
class XqfParser implements PuzzleParser {
  const XqfParser();

  @override
  Set<String> get supportedExtensions => const {'xqf'};

  @override
  Puzzle parse(List<int> bytes, {String? filename}) {
    // TODO(二期): 实现 XQF 二进制格式解析。
    throw PuzzleParseException('XQF parser not implemented yet');
  }
}
