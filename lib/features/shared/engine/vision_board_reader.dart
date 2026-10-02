import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../board/model/fen.dart';
import '../../board/model/piece.dart';
import 'llm_config.dart';
import 'llm_move_source.dart';

/// 视觉识图结果。
class VisionReadResult {
  const VisionReadResult({
    required this.fen,
    required this.pieceCount,
    required this.rawContent,
  });

  /// 组装后的完整 FEN（轮走方来自模型识别，可在校正界面修改）。
  final String fen;
  final int pieceCount;

  /// 模型原始回复（调试/日志展示用，不含凭据）。
  final String rawContent;
}

/// 棋盘图片识别：多模态大模型（OpenAI 兼容 /chat/completions 多模态格式）。
///
/// 只负责"图片 → 候选 FEN"；识别结果必须经 Fen.isValid 与人工校正界面
/// 复核后方可进入求解流程（docs/phase4/02 §3.2 校验管线）。
class VisionBoardReader {
  VisionBoardReader({this.client, this.timeout = const Duration(seconds: 60)});

  final http.Client? client;
  final Duration timeout;

  /// 调用视觉模型识别棋盘，返回组装好的 FEN。
  ///
  /// [imageBytes] 支持/png/jpeg，自动压缩交给调用方（此处直接 base64）。
  Future<VisionReadResult> readBoard({
    required LlmConfig config,
    required Uint8List imageBytes,
    int maxAttempts = 2,
  }) async {
    if (!config.isConfigured) {
      throw const LlmConfigException('视觉模型未配置（需填写端点与模型 ID）');
    }
    final dataUrl = 'data:${_mimeOf(imageBytes)};base64,'
        '${base64Encode(imageBytes)}';

    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final content = await _request(config, dataUrl);
        final grid = parsePiecesJson(content);
        final turn = _parseTurn(content);
        final fen = Fen.build(board: grid, isRedTurn: turn);
        final pieceCount = grid
            .expand((row) => row)
            .where((p) => p != null)
            .length;
        return VisionReadResult(
          fen: fen,
          pieceCount: pieceCount,
          rawContent: content,
        );
      } on Object catch (e) {
        lastError = e;
      }
    }
    throw LlmApiException('识图失败（$maxAttempts 次）：$lastError');
  }

  Future<String> _request(LlmConfig config, String dataUrl) async {
    final ownsClient = client == null;
    final httpClient = client ?? http.Client();
    try {
      final response = await httpClient
          .post(
            Uri.parse(config.requestUrl),
            headers: {
              'Content-Type': 'application/json',
              if (config.apiKey.trim().isNotEmpty)
                'Authorization': 'Bearer ${config.apiKey.trim()}',
            },
            body: jsonEncode({
              'model': config.model.trim(),
              'messages': [
                {
                  'role': 'system',
                  'content': '你是中国象棋棋盘识别器，只输出约定的 JSON，不输出任何其他文字。',
                },
                {
                  'role': 'user',
                  'content': [
                    {
                      'type': 'image_url',
                      'image_url': {'url': dataUrl},
                    },
                    {'type': 'text', 'text': visionPrompt()},
                  ],
                },
              ],
              'temperature': 0.1,
              'max_tokens': 4096,
            }),
          )
          .timeout(timeout);
      if (response.statusCode != 200) {
        throw LlmApiException('HTTP ${response.statusCode}: '
            '${_excerpt(response.body)}');
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = body['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        throw const LlmApiException('响应缺少 choices');
      }
      final message = choices.first['message'];
      if (message is! Map || message['content'] is! String) {
        throw const LlmApiException('响应缺少正文');
      }
      return message['content'] as String;
    } finally {
      if (ownsClient) httpClient.close();
    }
  }

  /// 识图提示词：强制输出可程序校验的 JSON（docs/phase4/02 §3.2）。
  static String visionPrompt() => '识别图中中国象棋棋盘上的所有棋子。'
      '以 JSON 回复，不要输出任何其他文字：\n'
      '{"turn":"red或black","pieces":[{"col":"a-i","row":"0-9","piece":"棋子FEN字符"}]}\n'
      '约定：行 0 为棋盘顶部（黑方底线），行 9 为底部（红方底线）；'
      '列 a 在左、i 在右。棋子 FEN 字符：红方大写 '
      'K(帅) A(仕) B(相) N(马) R(车) C(炮) P(兵)，黑方小写 '
      'k(将) a(士) b(象) n(马) r(车) c(炮) p(卒)。只列实际出现的棋子。';

  /// 解析模型 JSON 回复为 10×9 棋盘矩阵（纯函数，便于单测）。
  ///
  /// JSON 坏损、坐标越界、未知棋子均抛 [FormatException]。
  static List<List<Piece?>> parsePiecesJson(String content) {
    final json = _extractJson(content);
    final pieces = json['pieces'];
    if (pieces is! List) {
      throw const FormatException('JSON 缺少 pieces 数组');
    }
    final grid = List<List<Piece?>>.generate(
      10,
      (_) => List<Piece?>.filled(9, null),
    );
    for (final item in pieces) {
      if (item is! Map) continue;
      final col = _colIndex(item['col'] as String?);
      final row = int.tryParse('${item['row']}');
      final piece = pieceFromFenChar('${item['piece']}');
      if (col == null || row == null || piece == null) {
        throw FormatException('非法棋子条目: $item');
      }
      if (row < 0 || row > 9 || col < 0 || col > 8) {
        throw FormatException('坐标越界: col=${item['col']} row=$row');
      }
      grid[row][col] = piece;
    }
    _validateKings(grid);
    return grid;
  }

  static bool _parseTurn(String content) {
    try {
      final turn = _extractJson(content)['turn'];
      return '$turn'.toLowerCase() != 'black';
    } on Object {
      return true;
    }
  }

  static Map<String, dynamic> _extractJson(String content) {
    var text = content.replaceAll(RegExp(r'```[a-zA-Z]*'), '')
        .replaceAll('```', '');
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const FormatException('回复中未找到 JSON');
    }
    text = text.substring(start, end + 1);
    return jsonDecode(text) as Map<String, dynamic>;
  }

  static void _validateKings(List<List<Piece?>> grid) {
    var redKing = 0;
    var blackKing = 0;
    for (final row in grid) {
      for (final piece in row) {
        if (piece == null) continue;
        if (piece.kind == PieceKind.king) {
          piece.side.isRed ? redKing++ : blackKing++;
        }
      }
    }
    if (redKing != 1 || blackKing != 1) {
      throw FormatException('双方王数量异常（红 $redKing / 黑 $blackKing）');
    }
  }

  static int? _colIndex(String? col) {
    if (col == null || col.isEmpty) return null;
    final c = col.toLowerCase().codeUnitAt(0) - 'a'.codeUnitAt(0);
    return (c >= 0 && c <= 8) ? c : null;
  }

  static String _mimeOf(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E) {
      return 'image/png';
    }
    return 'image/jpeg';
  }

  static String _excerpt(String body) {
    final text = body.trim();
    return text.length <= 160 ? text : '${text.substring(0, 160)}…';
  }
}
