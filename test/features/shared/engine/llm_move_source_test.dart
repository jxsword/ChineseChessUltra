import 'package:flutter_test/flutter_test.dart';

import 'package:chinese_chess_ultra/features/board/model/board.dart';
import 'package:chinese_chess_ultra/features/board/model/move.dart';
import 'package:chinese_chess_ultra/features/board/model/piece.dart';
import 'package:chinese_chess_ultra/features/shared/engine/llm_config.dart';
import 'package:chinese_chess_ultra/features/shared/engine/llm_move_source.dart';
import 'package:chinese_chess_ultra/features/shared/engine/move_source.dart';

void main() {
  group('坐标编解码', () {
    test('encodeCell / decodeCell 往返一致', () {
      for (var col = 0; col < 9; col++) {
        for (var row = 0; row < 10; row++) {
          final pos = Position(col, row);
          expect(decodeCell(encodeCell(pos)), pos);
        }
      }
    });

    test('encodeCell 边界：a0 为左上（黑方底线），i9 为右下（红方底线）', () {
      expect(encodeCell(const Position(0, 0)), 'a0');
      expect(encodeCell(const Position(8, 9)), 'i9');
    });

    test('decodeCell 非法输入返回 null', () {
      expect(decodeCell('j3'), isNull); // 列越界
      expect(decodeCell('a10'), isNull); // 长度错误
      expect(decodeCell('b'), isNull);
      expect(decodeCell('a9a'), isNull);
    });
  });

  group('LlmMoveParser.extract', () {
    test('解析标准着法行', () {
      expect(LlmMoveParser.extract('着法: h7-e7'), 'h7-e7');
      expect(LlmMoveParser.extract('着法：B2 - E2'), 'b2-e2');
    });

    test('解析带思路的回复', () {
      const content = '思路：先跳马防守。\n着法: b0-c2';
      expect(LlmMoveParser.extract(content), 'b0-c2');
    });

    test('「着法:」标记优先于思路中引用的坐标', () {
      const content = '上一步 h7-e7 后我方占优，本手选择：\n着法: b2-e2';
      expect(LlmMoveParser.extract(content), 'b2-e2');
    });

    test('无标记时取最后一个坐标对', () {
      const content = '考虑 a0-a1 或 c1-e3，最终决定 c1-e3';
      expect(LlmMoveParser.extract(content), 'c1-e3');
    });

    test('无法解析返回 null', () {
      expect(LlmMoveParser.extract('我认输了'), isNull);
      expect(LlmMoveParser.extract(''), isNull);
      expect(LlmMoveParser.extract('炮二平五'), isNull); // 中文记法不在 v1 支持内
    });

    test('清洗杂质：markdown 代码块、全角字符、大小写', () {
      expect(
        LlmMoveParser.extract('```\n着法: B2-E2\n```'),
        'b2-e2',
      );
      expect(
        LlmMoveParser.extract('着法: ｂ２－ｅ２'),
        'b2-e2',
      );
      expect(
        LlmMoveParser.extract('​着法: h7-e7'), // 含零宽空格
        'h7-e7',
      );
    });
  });

  group('LlmPrompts', () {
    test('system prompt 包含执方与格式要求', () {
      final red = LlmPrompts.system(Side.red);
      expect(red, contains('执红方'));
      expect(red, contains('着法:'));
      final black = LlmPrompts.system(Side.black);
      expect(black, contains('执黑方'));
    });

    test('user prompt 包含 FEN、轮走方与合法着法清单', () {
      final board = Board.initial();
      final legal = allLegalMoves(board);
      expect(legal, isNotEmpty);
      final prompt = LlmPrompts.user(
        board: board,
        history: const [],
        legalCodes: [for (final m in legal) encodeMove(m)],
      );
      expect(prompt, contains(board.toFen()));
      expect(prompt, contains('红方'));
      expect(prompt, contains('共 ${legal.length} 条'));
      expect(prompt, contains(encodeMove(legal.first)));
    });

    test('历史走法以中文记法呈现', () {
      final board = Board.initial();
      // 走一手"炮二平五"：h7-e7（红炮从 col7,row7 平移到 col4,row7）。
      final applied = board.applyMove(
        const Move(from: Position(7, 7), to: Position(4, 7)),
      );
      final record = Move(
        from: applied.from,
        to: applied.to,
        piece: const Piece(kind: PieceKind.cannon, side: Side.red),
      );
      final prompt = LlmPrompts.user(
        board: board,
        history: [record],
        legalCodes: ['a0-a1'],
      );
      expect(prompt, contains('炮二平五'));
    });
  });

  group('LlmConfig', () {
    test('requestUrl 归一化', () {
      const root = LlmConfig(baseUrl: 'https://api.example.com/v1/');
      expect(root.requestUrl, 'https://api.example.com/v1/chat/completions');

      const full = LlmConfig(
        baseUrl: 'https://api.example.com/v1/chat/completions',
      );
      expect(full.requestUrl, 'https://api.example.com/v1/chat/completions');
    });

    test('序列化往返一致', () {
      const config = LlmConfig(
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'test-only-dummy-key',
        model: 'test-model',
      );
      final restored = LlmConfig.deserialize(config.serialize());
      expect(restored.baseUrl, config.baseUrl);
      expect(restored.apiKey, config.apiKey);
      expect(restored.model, config.model);
    });

    test('损坏的序列化数据回落为空配置', () {
      final restored = LlmConfig.deserialize('not-json');
      expect(restored.baseUrl, isEmpty);
      expect(restored.isConfigured, isFalse);
    });

    test('maskedApiKey 不暴露完整凭据', () {
      const config = LlmConfig(apiKey: 'test-only-dummy-key');
      expect(config.maskedApiKey, '****-key');
      expect(config.maskedApiKey, isNot(contains('dummy')));
    });
  });

  group('allLegalMoves / ChessAiMoveSource', () {
    test('初始局面红方合法着法为 44 种', () {
      final moves = allLegalMoves(Board.initial());
      // 车马炮相士各 2 + 兵 5 的常规开局着法数。
      expect(moves.length, 44);
    });

    test('ChessAiMoveSource 在初始局面返回合法着法', () async {
      final source = ChessAiMoveSource(difficulty: 1);
      expect(source.displayName, contains('内置 AI'));
      final result = await source.nextMove(Board.initial());
      expect(result.status, MoveSourceStatus.ok);
      final legal = allLegalMoves(Board.initial());
      expect(
        legal.any((m) => m.from == result.move!.from && m.to == result.move!.to),
        isTrue,
      );
    });
  });

  group('SSE 流式解析（handleStreamLine）', () {
    final source = LlmMoveSource(config: const LlmConfig(model: 'm', baseUrl: 'x'));
    late StringBuffer content;
    late StringBuffer reasoning;

    setUp(() {
      content = StringBuffer();
      reasoning = StringBuffer();
    });

    test('累积 content 增量，[DONE] 结束', () {
      expect(
        source.handleStreamLine(
          'data: {"choices":[{"delta":{"content":"着法: b2-e2"}}]}',
          content,
          reasoning,
        ),
        isFalse,
      );
      expect(
        source.handleStreamLine('data: [DONE]', content, reasoning),
        isTrue,
      );
      expect(content.toString(), '着法: b2-e2');
    });

    test('思维链增量写入 reasoning，不污染正文', () {
      source.handleStreamLine(
        'data: {"choices":[{"delta":{"reasoning_content":"先看炮的走位"}}]}',
        content,
        reasoning,
      );
      source.handleStreamLine(
        'data: {"choices":[{"delta":{"content":"着法: h7-e7"}}]}',
        content,
        reasoning,
      );
      expect(reasoning.toString(), '先看炮的走位');
      expect(content.toString(), '着法: h7-e7');
    });

    test('跳过空行、注释心跳与非 data 行', () {
      expect(source.handleStreamLine('', content, reasoning), isFalse);
      expect(source.handleStreamLine(': OPENROUTER PROCESSING', content, reasoning), isFalse);
      expect(source.handleStreamLine('event: ping', content, reasoning), isFalse);
      expect(content.toString(), isEmpty);
    });

    test('非 JSON 的 data 行被忽略', () {
      expect(source.handleStreamLine('data: <html>', content, reasoning), isFalse);
      expect(content.toString(), isEmpty);
    });

    test('含 error 字段的 chunk 抛出 LlmApiException', () {
      expect(
        () => source.handleStreamLine(
          'data: {"error":{"message":"rate limited"}}',
          content,
          reasoning,
        ),
        throwsA(isA<LlmApiException>()),
      );
    });

    test('choices 为空的 chunk 被忽略', () {
      expect(
        source.handleStreamLine('data: {"choices":[]}', content, reasoning),
        isFalse,
      );
    });
  });

  group('disableThinking 请求参数', () {
    test('默认禁用思维链（发送 enable_thinking=false）', () {
      const config = LlmConfig(baseUrl: 'https://x/v1', model: 'm');
      expect(config.disableThinking, isTrue);
    });

    test('旧版存档（无该字段）按禁用思维链处理', () {
      final restored = LlmConfig.deserialize('{"baseUrl":"https://x/v1","model":"m"}');
      expect(restored.disableThinking, isTrue);
    });

    test('序列化往返保留开关', () {
      const config = LlmConfig(baseUrl: 'https://x/v1', model: 'm', disableThinking: true);
      final restored = LlmConfig.deserialize(config.serialize());
      expect(restored.disableThinking, isTrue);
    });
  });

  group('annotateModelHint 模型类型提示', () {
    test('图片生成模型的典型报错被翻译为可操作提示', () {
      final raw = '流式响应错误: {"code":"invalid_parameter_error",'
          '"message":"Input should be \'user\': input.messages 0.role"}';
      final hint = LlmMoveSource.annotateModelHint(raw);
      expect(hint, contains('视觉理解模型'));
      expect(hint, contains('qwen-vl-max'));
    });

    test('普通网络错误不附加提示', () {
      final hint = LlmMoveSource.annotateModelHint('HTTP 500: server error');
      expect(hint, 'HTTP 500: server error');
    });

    test('翻译模型不支持流式的报错被翻译为可操作提示', () {
      const raw = 'HTTP 400: {"error":{"message":'
          '"Streaming translation is not supported","code":'
          '"invalid_parameter_error"}}';
      final hint = LlmMoveSource.annotateModelHint(raw);
      expect(hint, contains('翻译模型'));
      expect(hint, contains('qwen-vl-max'));
    });
  });
}
