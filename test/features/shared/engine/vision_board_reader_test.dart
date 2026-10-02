import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:chinese_chess_ultra/features/shared/engine/llm_config.dart';
import 'package:chinese_chess_ultra/features/shared/engine/llm_solve_assist.dart';
import 'package:chinese_chess_ultra/features/shared/engine/llm_move_source.dart';
import 'package:chinese_chess_ultra/features/shared/engine/vision_board_reader.dart';

void main() {
  group('VisionBoardReader.parsePiecesJson', () {
    test('解析合法 JSON（含代码围栏包裹）', () {
      final content = '```json\n'
          '{"turn":"red","pieces":['
          '{"col":"d","row":"0","piece":"k"},'
          '{"col":"e","row":"9","piece":"K"},'
          '{"col":"h","row":"2","piece":"C"}'
          ']}\n'
          '```';
      final grid = VisionBoardReader.parsePiecesJson(content);
      expect(grid[0][3]?.label, '将');
      expect(grid[9][4]?.label, '帅');
      expect(grid[2][7]?.label, '炮');
      // 其余为空。
      expect(grid[5][4], isNull);
    });

    test('缺少任一方王 → 抛 FormatException', () {
      const content = '{"turn":"red","pieces":['
          '{"col":"d","row":"0","piece":"k"}]}';
      expect(
        () => VisionBoardReader.parsePiecesJson(content),
        throwsFormatException,
      );
    });

    test('未知棋子字符 → 抛 FormatException', () {
      const content = '{"turn":"red","pieces":['
          '{"col":"d","row":"0","piece":"k"},'
          '{"col":"e","row":"9","piece":"K"},'
          '{"col":"h","row":"2","piece":"X"}'
          ']}';
      expect(
        () => VisionBoardReader.parsePiecesJson(content),
        throwsFormatException,
      );
    });

    test('坐标越界 → 抛 FormatException', () {
      const content = '{"turn":"red","pieces":['
          '{"col":"d","row":"0","piece":"k"},'
          '{"col":"e","row":"9","piece":"K"},'
          '{"col":"z","row":"1","piece":"C"}'
          ']}';
      expect(
        () => VisionBoardReader.parsePiecesJson(content),
        throwsFormatException,
      );
    });

    test('无 JSON → 抛 FormatException', () {
      expect(
        () => VisionBoardReader.parsePiecesJson('抱歉，我无法识别该图片'),
        throwsFormatException,
      );
    });
  });

  group('VisionBoardReader.readBoard（MockClient）', () {
    const config = LlmConfig(
      baseUrl: 'https://example.com/v1',
      model: 'vision-model',
      apiKey: '', // 测试不写凭据：空 Key 允许（本地网关语义）
    );

    final pngBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);

    test('成功：返回组装后的 FEN', () async {
      final client = MockClient((request) async {
        final body = jsonEncode({
          'choices': [
            {
              'message': {
                'content': '{"turn":"red","pieces":['
                    '{"col":"d","row":"0","piece":"k"},'
                    '{"col":"e","row":"9","piece":"K"}'
                    ']}',
              },
            },
          ],
        });
        return http.Response(body, 200);
      });
      final result = await VisionBoardReader(client: client)
          .readBoard(config: config, imageBytes: pngBytes);
      expect(result.pieceCount, 2);
      expect(result.fen.split(' ').first, contains('K'));
      expect(result.fen.split(' ')[1], 'w');
    });

    test('黑方行棋的 turn 写入 FEN', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': '{"turn":"black","pieces":['
                      '{"col":"d","row":"0","piece":"k"},'
                      '{"col":"e","row":"9","piece":"K"}'
                      ']}',
                },
              },
            ],
          }),
          200,
        );
      });
      final result = await VisionBoardReader(client: client)
          .readBoard(config: config, imageBytes: pngBytes);
      expect(result.fen.split(' ')[1], 'b');
    });

    test('HTTP 500 → 重试后抛 LlmApiException', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response('server error', 500);
      });
      await expectLater(
        VisionBoardReader(client: client)
            .readBoard(config: config, imageBytes: pngBytes, maxAttempts: 2),
        throwsA(isA<LlmApiException>()),
      );
      expect(calls, 2);
    });

    test('未配置 → 抛 LlmConfigException', () async {
      await expectLater(
        VisionBoardReader(client: MockClient((_) async => http.Response('', 200)))
            .readBoard(
          config: const LlmConfig(),
          imageBytes: pngBytes,
        ),
        throwsA(isA<LlmConfigException>()),
      );
    });

    test('默认关闭思维链（请求体带 enable_thinking=false）', () async {
      Map<String, dynamic>? captured;
      final client = MockClient((request) async {
        captured = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': '{"turn":"red","pieces":['
                      '{"col":"d","row":"0","piece":"k"},'
                      '{"col":"e","row":"9","piece":"K"}'
                      ']}',
                },
              },
            ],
          }),
          200,
        );
      });
      await VisionBoardReader(client: client)
          .readBoard(config: config, imageBytes: pngBytes);
      // LlmConfig 默认 disableThinking=true。
      expect(captured?['enable_thinking'], false);
    });

    test('disableThinking=false 时不发送该参数', () async {
      Map<String, dynamic>? captured;
      final client = MockClient((request) async {
        captured = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': '{"turn":"red","pieces":['
                      '{"col":"d","row":"0","piece":"k"},'
                      '{"col":"e","row":"9","piece":"K"}'
                      ']}',
                },
              },
            ],
          }),
          200,
        );
      });
      const cfg = LlmConfig(
        baseUrl: 'https://example.com/v1',
        model: 'vision-model',
        disableThinking: false,
      );
      await VisionBoardReader(client: client)
          .readBoard(config: cfg, imageBytes: pngBytes);
      expect(captured?.containsKey('enable_thinking'), isFalse);
    });

    test('请求超时 → 返回友好的 LlmApiException 提示', () async {
      final client = MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return http.Response('{}', 200);
      });
      await expectLater(
        VisionBoardReader(
          client: client,
          timeout: const Duration(milliseconds: 50),
        ).readBoard(config: config, imageBytes: pngBytes, maxAttempts: 1),
        throwsA(
          isA<LlmApiException>()
              .having((e) => '$e', 'message', contains('请求超时')),
        ),
      );
    });
  });

  group('LlmSolveAssist.parseProposal', () {
    test('解析三行格式', () {
      final proposal = LlmSolveAssist.parseProposal(
        '首选着法: h2-e2\n备选着法: h2-g4\n思路: 平炮中路，威胁中卒',
      );
      expect(proposal?.firstMoveCode, 'h2-e2');
      expect(proposal?.alternateCode, 'h2-g4');
      expect(proposal?.idea, contains('中路'));
    });

    test('备选为"无"与杂质容错', () {
      final proposal = LlmSolveAssist.parseProposal(
        '首选着法: b0c2\n备选着法: 无\n思路: 跳马出子。\n（以上分析仅供参考）',
      );
      expect(proposal?.firstMoveCode, 'b0-c2');
      expect(proposal?.alternateCode, isNull);
    });

    test('无坐标对返回 null 字段', () {
      final proposal = LlmSolveAssist.parseProposal('我无法判断该残局');
      expect(proposal?.firstMoveCode, isNull);
    });
  });
}
