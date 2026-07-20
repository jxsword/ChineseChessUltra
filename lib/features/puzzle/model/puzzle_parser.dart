import '../../board/model/move.dart';

/// 残局棋谱解析结果。
///
/// 包含初始局面 FEN、破解走法序列、元数据（标题/来源等）。
class Puzzle {
  const Puzzle({
    required this.fen,
    required this.solution,
    this.title,
    this.source,
  });

  /// 初始局面（红方先行）。
  final String fen;

  /// 破解走法序列（红黑交替）。
  final List<Move> solution;

  /// 残局标题。
  final String? title;

  /// 来源文件名。
  final String? source;
}

/// 残局棋谱解析器抽象接口（二期）。
///
/// 策略模式：每种文件格式（PGN/XQF/CHE）实现一个具体解析器，
/// 由 [PuzzleParserFactory] 注册。
///
/// 第一期不实现具体解析器，仅保留接口便于二期无缝扩展。
abstract interface class PuzzleParser {
  /// 此解析器支持的文件扩展名集合（小写，不含点）。
  ///
  /// 例如：{'pgn'} 或 {'xqf', 'che'}。
  Set<String> get supportedExtensions;

  /// 解析文件字节为 [Puzzle] 对象。
  ///
  /// 解析失败抛 [PuzzleParseException]。
  Puzzle parse(List<int> bytes, {String? filename});
}

/// 残局解析失败异常。
class PuzzleParseException implements Exception {
  const PuzzleParseException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() =>
      'PuzzleParseException: $message${cause != null ? ' ($cause)' : ''}';
}

/// 残局解析器工厂（二期）。
///
/// 通过扩展注册机制，按文件后缀路由到具体 [PuzzleParser]：
/// ```dart
/// PuzzleParserFactory.instance.register(PgnParser());
/// final puzzle = PuzzleParserFactory.instance.parseFile(bytes, 'foo.pgn');
/// ```
class PuzzleParserFactory {
  PuzzleParserFactory._();
  static final PuzzleParserFactory instance = PuzzleParserFactory._();

  final Map<String, PuzzleParser> _byExt = {};

  /// 注册一个解析器。
  void register(PuzzleParser parser) {
    for (final ext in parser.supportedExtensions) {
      _byExt[ext.toLowerCase()] = parser;
    }
  }

  /// 取消注册。
  void unregister(PuzzleParser parser) {
    for (final ext in parser.supportedExtensions) {
      _byExt.remove(ext.toLowerCase());
    }
  }

  /// 根据文件名后缀查找解析器。
  PuzzleParser? parserFor(String filename) {
    final dot = filename.lastIndexOf('.');
    if (dot < 0 || dot == filename.length - 1) return null;
    final ext = filename.substring(dot + 1).toLowerCase();
    return _byExt[ext];
  }

  /// 解析给定文件字节。
  ///
  /// 自动按文件名选择合适的解析器；未注册则抛 [PuzzleParseException]。
  Puzzle parseFile(List<int> bytes, String filename) {
    final parser = parserFor(filename);
    if (parser == null) {
      throw PuzzleParseException(
        'No parser registered for file: $filename',
      );
    }
    return parser.parse(bytes, filename: filename);
  }
}
