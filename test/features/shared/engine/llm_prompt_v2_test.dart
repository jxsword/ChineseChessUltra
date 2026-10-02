import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:chinese_chess_ultra/features/board/model/board.dart';
import 'package:chinese_chess_ultra/features/board/model/move.dart';
import 'package:chinese_chess_ultra/features/board/model/piece.dart';
import 'package:chinese_chess_ultra/features/shared/engine/llm_config.dart';
import 'package:chinese_chess_ultra/features/shared/engine/llm_move_source.dart';
import 'package:chinese_chess_ultra/features/shared/engine/move_source.dart';

const config = LlmConfig(baseUrl: 'https://example.com/v1', model: 'm');

/// 初始局面第一步后（轮黑）的简单局面。
Board blackToMoveBoard() {
  final board = Board.initial();
  board.applyMove(const Move(from: Position(7, 7), to: Position(4, 7)));
  return board;
}

/// 构造流式 SSE 单 chunk 回复。
http.Response sseReply(String content) {
  final chunk = jsonEncode({
    'choices': [
      {
        'delta': {'content': content},
      }
    ],
  });
  return http.Response(
    'data: $chunk\n\ndata: [DONE]\n',
    200,
    headers: {'content-type': 'text/event-stream; charset=utf-8'},
  );
}

void main() {
  group('LlmPrompts v2', () {
    test('systemV2：分析段 + 着法行；分档引导仅候选模式携带', () {
      final system = LlmPrompts.systemV2(Side.red);
      expect(system, contains('分析:'));
      expect(system, contains('着法: 起点-终点'));
      expect(system, contains('红方'));
      // off/护航模式清单无分档，系统提示不应承诺分档。
      expect(system, isNot(contains('最佳/均势')));
      expect(
        LlmPrompts.systemV2(Side.red, withBucketGuide: true),
        contains('最佳/均势'),
      );
    });

    test('userV2：含棋盘图、注解清单、吃子标注', () {
      final board = blackToMoveBoard();
      final legal = allLegalMoves(board);
      final user = LlmPrompts.userV2(
        board: board,
        history: const [],
        legalMoves: legal,
      );
      expect(user, contains('【棋盘图】'));
      expect(user, contains('    a b c d e f g h i'));
      expect(user, contains('【合法着法清单'));
      expect(RegExp(r'[a-i]\d-[a-i]\d\(.+\)').hasMatch(user), isTrue);
      expect(user, isNot(contains('【警示】')));
    });

    test('userV2：历史来回重复时带循环警示', () {
      final board = blackToMoveBoard();
      // 真实拉锯：红炮平中、黑马跳外，随后双方原路返回。
      final history = [
        const Move(from: Position(7, 7), to: Position(4, 7)),
        const Move(from: Position(7, 0), to: Position(6, 2)),
        const Move(from: Position(4, 7), to: Position(7, 7)),
        const Move(from: Position(6, 2), to: Position(7, 0)),
      ];
      final user = LlmPrompts.userV2(
        board: board,
        history: history,
        legalMoves: allLegalMoves(board),
      );
      expect(user, contains('【警示】'));
      expect(user, contains('长将/长捉判负'));
    });

    test('retryFeedbackV2：回显上次着法', () {
      final feedback = LlmPrompts.retryFeedbackV2(
        reason: '不在合法清单中',
        lastCode: 'e3-e6',
      );
      expect(feedback, contains('e3-e6'));
      expect(feedback, contains('分析:'));
    });
  });

  group('LlmMoveSource usePromptV2 全链路（MockClient）', () {
    test('v2：请求体含棋盘图且 max_tokens=8192，分析段回复可解析', () async {
      Map<String, dynamic>? capturedBody;
      final client = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return sseReply('分析: 跳马出子，巩固中路。\n着法: h0-g2');
      });
      final source = LlmMoveSource(
        config: config,
        usePromptV2: true,
        client: client,
      );
      final result = await source.nextMove(blackToMoveBoard());
      expect(result.status, MoveSourceStatus.ok);
      expect(result.move, isNotNull);
      expect(encodeMove(result.move!), 'h0-g2');
      expect(capturedBody?['max_tokens'], 8192);
      final userContent = capturedBody?['messages'][1]['content'] as String;
      expect(userContent, contains('【棋盘图】'));
    });

    test('v1（默认）：max_tokens=4096 且无棋盘图（评估基线不回归）', () async {
      Map<String, dynamic>? capturedBody;
      final client = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return sseReply('着法: h0-g2');
      });
      final source = LlmMoveSource(config: config, client: client);
      final result = await source.nextMove(blackToMoveBoard());
      expect(result.status, MoveSourceStatus.ok);
      expect(capturedBody?['max_tokens'], 4096);
      final userContent = capturedBody?['messages'][1]['content'] as String;
      expect(userContent, isNot(contains('【棋盘图】')));
    });

    test('解析器：分析段含坐标干扰时仍取「着法:」标记后的坐标', () {
      const content =
          '分析: 我考虑 b2-e2 或 h9-g9，最终决定跳马。\n着法: h9-g9';
      expect(LlmMoveParser.extract(content), 'h9-g9');
    });
  });
}
