import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import '../../board/model/board.dart';
import '../../board/model/move.dart';
import '../../board/model/move_notation.dart';
import '../../board/model/piece.dart';
import 'llm_config.dart';
import 'move_annotation.dart';
import 'move_source.dart';

/// Prompt 组装（纯函数，便于单测）。
class LlmPrompts {
  LlmPrompts._();

  static String system(Side side) {
    final sideName = side.isRed ? '红方' : '黑方';
    return '你是中国象棋对弈引擎的着法接口，本局执$sideName。\n'
        '坐标约定：列用字母 a-i（从左到右），行用数字 0-9'
        '（0 为黑方底线、棋盘顶部，9 为红方底线、棋盘底部）。\n'
        '你只能从用户提供的「合法着法清单」中选择一步，禁止编造清单之外的着法。\n'
        '\n'
        '【回复格式（唯一允许的格式，违反即视为无效）】\n'
        '整个回复只包含一行，形式为：\n'
        '着法: 起点-终点\n'
        '示例：着法: b2-e2\n'
        '\n'
        '禁止输出：任何解释、推理过程、心理活动、道歉、开场白、'
        'markdown、代码块、引号、多行文本。你的回复将被程序逐字解析，'
        '任何多余字符都会导致这步棋作废。';
  }

  static String user({
    required Board board,
    required List<Move> history,
    required List<String> legalCodes,
  }) {
    final buf = StringBuffer();
    buf.writeln('【当前局面 FEN】${board.toFen()}');
    buf.writeln('【轮走方】${board.isRedTurn ? '红方' : '黑方'}（该方是你）');
    if (history.isEmpty) {
      buf.writeln('【最近着法】（开局，暂无历史）');
    } else {
      final recent = history.length > 12
          ? history.sublist(history.length - 12)
          : history;
      final parts = <String>[];
      for (final move in recent) {
        final piece = move.piece;
        parts.add(piece == null
            ? encodeMove(move)
            : move.chineseNotation(piece));
      }
      buf.writeln('【最近着法（中文记法，最新在最后）】${parts.join('  ')}');
    }
    buf.writeln('【合法着法清单（共 ${legalCodes.length} 条，必须从中选择一条）】');
    buf.writeln(legalCodes.join(', '));
    buf.write('【输出】仅一行，格式：着法: 起点-终点（起点与终点均取自上方清单）');
    return buf.toString();
  }

  /// 非法回复后的追加反馈。
  static String retryFeedback({required String reason}) =>
      '\n\n你上一次的回复无效（$reason）。'
      '请重新回答：整个回复只含一行「着法: 起点-终点」，'
      '着法必须取自合法着法清单，不要输出任何其他文字。';

  // ---------------------------------------------------------------------------
  // Prompt v2（五期 P0）：棋盘图 + 着法注解 + 放开分析段
  // ---------------------------------------------------------------------------

  /// v2 系统提示：允许先输出分析段，最后一行才是着法。
  ///
  /// 解析器 [LlmMoveParser.extract] 优先取「着法:」标记后的坐标，
  /// 与本格式天然兼容。
  static String systemV2(Side side) {
    final sideName = side.isRed ? '红方' : '黑方';
    return '你是中国象棋对弈引擎的着法接口，本局执$sideName。\n'
        '坐标约定：列用字母 a-i（从左到右），行用数字 0-9'
        '（0 为黑方底线、棋盘顶部，9 为红方底线、棋盘底部）。\n'
        '你只能从用户提供的「合法着法清单」中选择一步，禁止编造清单之外的着法。\n'
        '\n'
        '【回复格式（唯一允许的格式，共两段）】\n'
        '第一段以「分析:」开头，用一两句话（不超过 100 字）说明你的计划'
        '（进攻目标、需要提防的威胁）。\n'
        '最后一段为一行，形式为：\n'
        '着法: 起点-终点\n'
        '示例：着法: b2-e2\n'
        '\n'
        '合法着法清单中每条着法附有括号注解（中文记法/吃子/将军）'
        '与「—」后的引擎评估分档，请优先考虑评估为「最佳/均势」的着法，'
        '避免选择「大亏/致命」档的着法。';
  }

  /// v2 用户提示：FEN + 棋盘 ASCII 图 + 整局历史（≤60 着）+
  /// 逐条注解的合法清单；历史出现来回重复时附循环警示。
  static String userV2({
    required Board board,
    required List<Move> history,
    required List<Move> legalMoves,
  }) {
    final buf = StringBuffer();
    buf.writeln('【当前局面 FEN】${board.toFen()}');
    buf.write('【棋盘图】\n');
    buf.write(MoveAnnotation.asciiBoard(board));
    buf.writeln('【轮走方】${board.isRedTurn ? '红方' : '黑方'}（该方是你）');
    buf.writeln('【对局着法（中文记法，最新在最后）】${_historyText(history)}');
    if (_looksLikeRepetition(history)) {
      buf.writeln('【警示】最近着法出现来回重复。长将/长捉判负，'
          '重复局面会被视为无效——请选择打破循环的着法。');
    }
    buf.writeln(
        '【合法着法清单（共 ${legalMoves.length} 条，必须从中选择一条；'
        '括号内为中文记法/吃子/将军注解）】');
    for (final move in legalMoves) {
      buf.writeln(MoveAnnotation.annotate(board, move));
    }
    buf.write('【输出】先输出「分析:」段，最后一行输出「着法: 起点-终点」'
        '（起点与终点均取自上方清单）');
    return buf.toString();
  }

  /// v2 非法回复反馈：回显上次着法与原因。
  static String retryFeedbackV2({
    required String reason,
    String? lastCode,
  }) =>
      '\n\n你上一次的回复${lastCode == null ? '' : '的着法 $lastCode'}无效'
      '（$reason）。着法必须取自合法着法清单。'
      '请重新回答：先「分析:」一两句，最后一行「着法: 起点-终点」。';

  /// 历史中文记法文本：v2 扩到整局（>60 着从最早截断）。
  static String _historyText(List<Move> history) {
    if (history.isEmpty) return '（开局，暂无历史）';
    final recent = history.length > 60 ? history.sublist(history.length - 60) : history;
    final parts = <String>[];
    for (final move in recent) {
      final piece = move.piece;
      parts.add(piece == null ? encodeMove(move) : move.chineseNotation(piece));
    }
    return parts.join('  ');
  }

  /// 检测历史末尾的来回重复（最近 4 着两两相同）。
  static bool _looksLikeRepetition(List<Move> history) {
    if (history.length < 4) return false;
    bool same(Move a, Move b) => a.from == b.from && a.to == b.to;
    final n = history.length;
    return same(history[n - 1], history[n - 3]) &&
        same(history[n - 2], history[n - 4]);
  }
}

/// 从模型回复中提取着法（纯函数，便于单测）。
///
/// 模型即使被严格约束也可能输出杂质（markdown 代码块、全角字符、
/// 零宽字符、多余空白），这里全部归一化后再解析。
class LlmMoveParser {
  LlmMoveParser._();

  static final _movePattern = RegExp(
    r'([a-i])\s*(\d)\s*[-–—~到至]?\s*([a-i])\s*(\d)',
  );

  static final _labeledPattern = RegExp(r'着法\s*:');

  /// 返回归一化的 "b2-e2" 形式；无法解析返回 null。
  ///
  /// 若回复含多个坐标对，优先取「着法:」标记之后的，否则取最后一个。
  static String? extract(String rawContent) {
    final content = _normalize(rawContent);
    if (content.trim().isEmpty) return null;
    final matches = _movePattern.allMatches(content).toList();
    if (matches.isEmpty) return null;

    Match pick = matches.last;
    final labeled = _labeledPattern.allMatches(content).toList();
    if (labeled.isNotEmpty) {
      final labeledPos = labeled.last.end;
      for (final m in matches) {
        if (m.start >= labeledPos) {
          pick = m;
          break;
        }
      }
    }
    final from = decodeCell('${pick.group(1)}${pick.group(2)!}');
    final to = decodeCell('${pick.group(3)}${pick.group(4)!}');
    if (from == null || to == null) return null;
    return encodeMove(Move(from: from, to: to));
  }

  /// 解析前的清洗：剥离代码块围栏、全角字符转半角、去零宽字符与 BOM。
  static String _normalize(String raw) {
    var text = raw.replaceAll(RegExp(r'```[a-zA-Z]*'), '').replaceAll('```', '');
    text = text.replaceAll(RegExp(r'[\u200b-\u200f\uFEFF\u2060]'), '');
    return text
        .toLowerCase()
        .codeUnits
        .map((u) {
          // 全角 ASCII 区（！到 ～）平移回半角。
          return u >= 0xFF01 && u <= 0xFF5E
              ? String.fromCharCode(u - 0xFEE0)
              : String.fromCharCode(u);
        })
        .join();
  }
}

/// 大模型棋手：OpenAI 兼容 /chat/completions，模型只"提议"，本地规则裁决。
///
/// 每手流程：合法清单 → Prompt → 调用 → 解析 → 校验 →（失败）重试 →（耗尽）降级。
class LlmMoveSource implements MoveSource {
  /// 单次回复的最大 token 数（思考型模型的思维链也计入，需留足预算）。
  static const int _maxTokens = 4096;

  /// Prompt v2 的 token 预算（分析段 + 更长历史/清单）。
  static const int _maxTokensV2 = 8192;

  /// 总耗时上限 = 空闲超时 × 该系数（防止思维链无限制输出）。
  static const int _totalCapFactor = 4;

  LlmMoveSource({
    required this.config,
    this.timeout = const Duration(seconds: 60),
    this.maxAttempts = 3,
    LlmFallback fallback = LlmFallback.builtinAi,
    this.usePromptV2 = false,
    http.Client? client,
  })  : _fallbackMode = fallback,
        _client = client;

  final LlmConfig config;

  /// 是否使用 Prompt v2（棋盘图 + 着法注解 + 分析段，五期 P0）。
  /// 默认 false 保留 v1 协议（作能力评估基线）。
  final bool usePromptV2;

  /// 单次 HTTP 请求超时。
  final Duration timeout;

  /// 最多请求次数（含首次）。
  final int maxAttempts;

  final LlmFallback _fallbackMode;
  final http.Client? _client;

  @override
  String get displayName => config.model.trim().isEmpty ? '（未配置模型）' : config.model.trim();

  @override
  Future<MoveSourceResult> nextMove(
    Board board, {
    List<Move> history = const [],
  }) async {
    final legal = allLegalMoves(board);
    if (legal.isEmpty) return MoveSourceResult.noLegalMove();

    final codesByMove = <String, Move>{
      for (final move in legal) encodeMove(move): move,
    };
    final legalCodes = codesByMove.keys.toList(growable: false);

    final useV2 = usePromptV2;
    final system =
        useV2 ? LlmPrompts.systemV2(board.turn) : LlmPrompts.system(board.turn);
    var user = useV2
        ? LlmPrompts.userV2(
            board: board,
            history: history,
            legalMoves: legal,
          )
        : LlmPrompts.user(
            board: board,
            history: history,
            legalCodes: legalCodes,
          );

    String? lastNote;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      String? content;
      try {
        content = await _chat(system, user);
      } on Object catch (e) {
        lastNote = '第 $attempt 次调用失败：$e';
        // 网络类错误重试意义有限，但仍给满次数（端点偶发抖动常见）。
        continue;
      }

      final code = LlmMoveParser.extract(content);
      final move = code == null ? null : codesByMove[code];
      if (move != null) {
        // 严格单行格式下回复无附加信息，成功时 note 留空。
        return MoveSourceResult.ok(move);
      }

      final reason = code == null
          ? '无法从回复中解析出着法'
          : '着法 $code 不在合法清单中';
      lastNote = '第 $attempt 次回复无效（$reason）';
      user = '$user${useV2
          ? LlmPrompts.retryFeedbackV2(reason: reason, lastCode: code)
          : LlmPrompts.retryFeedback(reason: reason)}';
    }

    return _fallback(board, lastNote ?? '模型连续 $maxAttempts 次未给出合法着法');
  }

  /// 降级：内置 AI 代走（默认）或判负。
  Future<MoveSourceResult> _fallback(Board board, String reason) async {
    switch (_fallbackMode) {
      case LlmFallback.builtinAi:
        final source = ChessAiMoveSource();
        final result = await source.nextMove(board);
        if (result.status == MoveSourceStatus.ok) {
          return MoveSourceResult(
            status: MoveSourceStatus.ok,
            move: result.move,
            note: '$reason，已由内置 AI 兜底走子',
            fromFallback: true,
          );
        }
        return MoveSourceResult.noLegalMove();
      case LlmFallback.resign:
        return MoveSourceResult.failed('$reason，按判负处理');
    }
  }

  /// 一次性的文本问答（残局求解辅助等复用同一条流式通道）。
  ///
  /// 与 [nextMove] 的区别：不附加合法清单协议，也不做重试降级。
  Future<String> chatOnce(String system, String user) => _chat(system, user);

  /// 发起一次 chat/completions 请求（流式 SSE），返回回复文本。
  ///
  /// 思考型模型（如 Qwen3 系列）会先输出很长的思维链，非流式短超时必然失败；
  /// 因此采用流式接收，[timeout] 作为**空闲超时**（两次数据块之间的最大间隔），
  /// 总耗时另有 [totalCap] 上限。模型正常吐字期间不会被误判超时。
  Future<String> _chat(String system, String user) async {
    if (!config.isConfigured) {
      throw const LlmConfigException('模型端点未配置（需填写端点与模型 ID）');
    }
    final totalCap = timeout * _totalCapFactor;
    final client = _client ?? http.Client();
    final ownsClient = _client == null;
    try {
      final request = http.Request('POST', Uri.parse(config.requestUrl))
        ..headers['Content-Type'] = 'application/json'
        ..headers['Accept'] = 'text/event-stream'
        ..body = jsonEncode({
          'model': config.model.trim(),
          'messages': [
            {'role': 'system', 'content': system},
            {'role': 'user', 'content': user},
          ],
          'temperature': 0.3,
          'max_tokens': usePromptV2 ? _maxTokensV2 : _maxTokens,
          'stream': true,
          // 思考型模型（Qwen3 等）的关闭开关；其他端点会忽略未知参数，
          // 因此仅在用户显式开启时发送。
          if (config.disableThinking) 'enable_thinking': false,
        });
      // 本地网关等允许空 Key：仅在填写时携带鉴权头。
      if (config.apiKey.trim().isNotEmpty) {
        request.headers['Authorization'] = 'Bearer ${config.apiKey.trim()}';
      }

      final response = await client.send(request).timeout(timeout);
      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        throw LlmApiException(
          'HTTP ${response.statusCode}: ${_excerpt(body)}',
        );
      }

      final content = StringBuffer();
      final reasoning = StringBuffer();
      final completer = Completer<String>();

      final subscription = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(
            timeout,
            onTimeout: (sink) =>
                sink.addError(TimeoutException('空闲超时', timeout)),
          )
          .listen(
            (line) {
              try {
                if (handleStreamLine(line, content, reasoning)) {
                  if (!completer.isCompleted) {
                    completer.complete(_pickAnswer(content, reasoning));
                  }
                }
              } on Object catch (e) {
                if (!completer.isCompleted) completer.completeError(e);
              }
            },
            onError: (Object e) {
              if (!completer.isCompleted) completer.completeError(e);
            },
            onDone: () {
              if (!completer.isCompleted) {
                completer.complete(_pickAnswer(content, reasoning));
              }
            },
          );

      try {
        return await completer.future.timeout(
          totalCap,
          onTimeout: () => throw LlmApiException(
            '总耗时超过 ${totalCap.inSeconds}s（可在对局设置中调大超时，'
            '或为 Qwen3 等模型开启「关闭思维链」）',
          ),
        );
      } on TimeoutException {
        throw LlmApiException(
          '空闲超时（${timeout.inSeconds}s 内无响应数据，可在对局设置中调大）',
        );
      } finally {
        await subscription.cancel();
      }
    } finally {
      if (ownsClient) client.close();
    }
  }

  /// 解析一行 SSE 数据；返回 true 表示流已结束（[DONE] 或完整回复）。
  @visibleForTesting
  bool handleStreamLine(
    String line,
    StringBuffer content,
    StringBuffer reasoning,
  ) {
    final trimmed = line.trim();
    // 空行与注释（如 OpenRouter 的 ": OPENROUTER PROCESSING" 心跳）跳过。
    if (trimmed.isEmpty || trimmed.startsWith(':')) return false;
    if (!trimmed.startsWith('data:')) return false;
    final payload = trimmed.substring(5).trim();
    if (payload == '[DONE]') {
      return true;
    }
    dynamic chunk;
    try {
      chunk = jsonDecode(payload);
    } on Object {
      return false; // 非 JSON 行忽略
    }
    if (chunk is Map && chunk['error'] != null) {
      throw LlmApiException('流式响应错误: ${jsonEncode(chunk['error'])}');
    }
    final choices = chunk is Map ? chunk['choices'] as List<dynamic>? : null;
    if (choices == null || choices.isEmpty) return false;
    final delta = choices.first['delta'];
    if (delta is Map) {
      final c = delta['content'];
      if (c is String) content.write(c);
      final r = delta['reasoning_content'] ?? delta['reasoning'];
      if (r is String) reasoning.write(r);
    }
    return false;
  }

  /// 最终答案：正文优先；正文为空（思考型模型耗尽 token）时退回思维链文本，
  /// 交给着法解析器尽力提取。
  static String _pickAnswer(StringBuffer content, StringBuffer reasoning) {
    final c = content.toString();
    if (c.trim().isNotEmpty) return c;
    return reasoning.toString();
  }

  static String _excerpt(String body) {
    final text = body.trim();
    if (text.length <= 160) return text;
    return '${text.substring(0, 160)}…';
  }

  /// 配置卡"测试连接"：发一条最小请求，返回 (是否成功, 说明)。
  static Future<(bool, String)> testConnection(LlmConfig config) async {
    final source = LlmMoveSource(config: config, maxAttempts: 1);
    try {
      await source._chat('你是一个连通性测试助手。', '请回复：ok');
      return (true, '连接成功，模型 ${config.model} 响应正常');
    } on Object catch (e) {
      return (false, '连接失败：${annotateModelHint('$e')}');
    }
  }

  /// 把"模型类型用错"的典型服务端报错翻译成可操作的提示（公开以便单测）。
  ///
  /// 两类典型：
  /// - 图片生成模型（qwen-image-* 等）：请求被路由到原生生成接口并用
  ///   input.messages 的格式校验，报 "Input should be 'user': input.messages ..."；
  /// - 翻译模型（qwen-mt-* 等）：不支持流式，报 "Streaming translation is
  ///   not supported"——输入虽可多模态，但任务是翻译，不能用于识图。
  static String annotateModelHint(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('streaming translation') ||
        lower.contains('translation is not supported')) {
      return '$message\n\n提示：这是翻译模型（qwen-mt-* 系列），'
          '不支持流式输出、也不能做棋盘识图。识图请改用视觉理解模型'
          '（如 qwen-vl-max、qwen3-vl-plus、glm-4.5v）。';
    }
    final looksLikeWrongModelType = message.contains('invalid_parameter_error') ||
        message.contains("should be 'user'") ||
        message.contains('input.messages');
    if (looksLikeWrongModelType) {
      return '$message\n\n提示：该模型可能不支持 OpenAI 兼容对话接口'
          '（图片生成类模型会这样报错）。识图请改用视觉理解模型'
          '（如 qwen-vl-max、glm-4.5v），对话请改用对应对话模型。';
    }
    return message;
  }
}

/// 降级策略。
enum LlmFallback {
  /// 由内置 AI 代走一手（对局继续）。
  builtinAi,

  /// 该方判负，对局终止。
  resign,
}

class LlmConfigException implements Exception {
  const LlmConfigException(this.message);
  final String message;

  @override
  String toString() => message;
}

class LlmApiException implements Exception {
  const LlmApiException(this.message);
  final String message;

  @override
  String toString() => message;
}
