import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:chinese_chess_ultra/features/board/model/board.dart';
import 'package:chinese_chess_ultra/features/board/model/move.dart';
import 'package:chinese_chess_ultra/features/board/model/piece.dart';
import 'package:chinese_chess_ultra/features/shared/engine/ai_engine.dart';
import 'package:chinese_chess_ultra/features/shared/engine/hybrid_llm_move_source.dart';
import 'package:chinese_chess_ultra/features/shared/engine/llm_config.dart';
import 'package:chinese_chess_ultra/features/shared/engine/llm_move_source.dart';
import 'package:chinese_chess_ultra/features/shared/engine/llm_settings.dart';
import 'package:chinese_chess_ultra/features/shared/engine/move_source.dart';

const config = LlmConfig(baseUrl: 'https://example.com/v1', model: 'm');

/// 初始局面第一步后（轮黑）的局面。
Board blackToMoveBoard() {
  final board = Board.initial();
  board.applyMove(const Move(from: Position(7, 7), to: Position(4, 7)));
  return board;
}

/// 脚本化假 LLM：按队列依次回复内容，并记录收到的 user prompt。
class ScriptedLlmClient extends http.BaseClient {
  ScriptedLlmClient(this.replies);

  final List<String> replies;
  final List<String> userPrompts = [];
  int _cursor = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = jsonDecode((request as http.Request).body)
        as Map<String, dynamic>;
    userPrompts.add(body['messages'][1]['content'] as String);
    final content = _cursor < replies.length ? replies[_cursor++] : replies.last;
    final chunk = jsonEncode({
      'choices': [
        {
          'delta': {'content': content},
        }
      ],
    });
    final responseBytes = utf8.encode(
      'data: $chunk\n\ndata: [DONE]\n',
    );
    return http.StreamedResponse(
      Stream.value(responseBytes),
      200,
      headers: {'content-type': 'text/event-stream; charset=utf-8'},
    );
  }
}

/// 从回复内容组装"分析 + 着法"两段格式。
String replyWith(String code) => '分析: 测试回复。\n着法: $code';

void main() {
  group('强度旋钮映射', () {
    test('shortlistSize：blend 0→3，60→6，100→8', () {
      expect(HybridLlmMoveSource.shortlistSize(0), 3);
      expect(HybridLlmMoveSource.shortlistSize(60), 6);
      expect(HybridLlmMoveSource.shortlistSize(100), 8);
      expect(HybridLlmMoveSource.shortlistSize(200), 8);
    });

    test('vetoThresholdCp：blend 0→80，50→240，100→400', () {
      expect(HybridLlmMoveSource.vetoThresholdCp(0), 80);
      expect(HybridLlmMoveSource.vetoThresholdCp(50), 240);
      expect(HybridLlmMoveSource.vetoThresholdCp(100), 400);
    });
  });

  group('候选模式', () {
    test('LLM 从 Top-K 中选择：直接采用并附参谋评分注解', () async {
      final board = blackToMoveBoard();
      final report = ChessAi.findBestMoveEx(board, depth: 4, topK: 3)!;
      final topCode = encodeMove(report.topK.first.$1);

      final client = ScriptedLlmClient([replyWith(topCode)]);
      final source = HybridLlmMoveSource(
        config: config,
        advisorMode: AdvisorMode.candidate,
        strengthBlend: 50,
        advisorDifficulty: 3,
        client: client,
      );
      final result = await source.nextMove(board);

      expect(result.status, MoveSourceStatus.ok);
      expect(result.fromFallback, isFalse);
      expect(encodeMove(result.move!), topCode);
      expect(result.note, contains('参谋评分'));
      // Prompt 含候选清单与分桶注解。
      expect(client.userPrompts.first, contains('候选着法清单'));
      expect(client.userPrompts.first, contains('— 最佳/均势'));
      expect(client.userPrompts.first, contains('【棋盘图】'));
    });

    test('LLM 选了 Top-K 之外的合法着法：拒绝并重试，耗尽后参谋代走', () async {
      final board = blackToMoveBoard();
      final report = ChessAi.findBestMoveEx(board, depth: 4, topK: 3)!;
      final topCodes = report.topK.map((e) => encodeMove(e.$1)).toSet();
      final outside = allLegalMoves(board)
          .map(encodeMove)
          .firstWhere((c) => !topCodes.contains(c));

      final client = ScriptedLlmClient([
        replyWith(outside),
        replyWith(outside),
        replyWith(outside),
      ]);
      final source = HybridLlmMoveSource(
        config: config,
        advisorMode: AdvisorMode.candidate,
        strengthBlend: 50,
        advisorDifficulty: 3,
        client: client,
      );
      final result = await source.nextMove(board);

      expect(result.fromFallback, isTrue);
      expect(encodeMove(result.move!), encodeMove(report.best));
      expect(result.note, contains('已由参谋（内置引擎）代走'));
      // 重试反馈被追加（拒绝原因：不在候选清单中）。
      expect(client.userPrompts.last, contains('不在候选清单中'));
    });
  });

  group('护航模式', () {
    test('LLM 选择明显亏着：否决后再问，第二次采纳', () async {
      final board = blackToMoveBoard();
      final report = ChessAi.findBestMoveEx(board, depth: 4, topK: 3)!;
      final bestCode = encodeMove(report.best);

      // 找一个相对最佳损失 > 80 厘兵（blend 0 阈值）的合法着法。
      String blunderCode = '';
      for (final move in allLegalMoves(board)) {
        final cp = ChessAi.evaluateMove(board, move, depth: 3);
        if (cp == null) continue;
        if (report.bestCp - cp > 80) {
          blunderCode = encodeMove(move);
          break;
        }
      }
      assumeTrue(blunderCode.isNotEmpty, '未找到超过否决阈值的着法');

      final client = ScriptedLlmClient([
        replyWith(blunderCode), // 第一次：送亏着 → 否决
        replyWith(bestCode), // 第二次：采纳引擎最佳 → 通过
      ]);
      final source = HybridLlmMoveSource(
        config: config,
        advisorMode: AdvisorMode.gate,
        strengthBlend: 0,
        advisorDifficulty: 3,
        client: client,
      );
      final result = await source.nextMove(board);

      expect(result.status, MoveSourceStatus.ok);
      expect(result.fromFallback, isFalse);
      expect(encodeMove(result.move!), bestCode);
      // 第一次提示是全量清单（护航模式），否决反馈出现在第二次。
      expect(client.userPrompts.first, contains('【合法着法清单'));
      expect(client.userPrompts.last, contains('【参谋否决】'));
    });

    test('两次选择都被否决：引擎最佳代走', () async {
      final board = blackToMoveBoard();
      final report = ChessAi.findBestMoveEx(board, depth: 4, topK: 3)!;
      final bestCode = encodeMove(report.best);
      final topCodes = report.topK.map((e) => encodeMove(e.$1)).toSet();

      // 两个不同亏着（均超阈值）。
      final blunders = <String>[];
      for (final move in allLegalMoves(board)) {
        final code = encodeMove(move);
        if (topCodes.contains(code)) continue;
        final cp = ChessAi.evaluateMove(board, move, depth: 3);
        if (cp == null) continue;
        if (report.bestCp - cp > 80) blunders.add(code);
        if (blunders.length == 2) break;
      }
      assumeTrue(blunders.length == 2, '亏着不足两个');

      final client = ScriptedLlmClient([
        replyWith(blunders[0]),
        replyWith(blunders[1]),
      ]);
      final source = HybridLlmMoveSource(
        config: config,
        advisorMode: AdvisorMode.gate,
        strengthBlend: 0,
        advisorDifficulty: 3,
        client: client,
      );
      final result = await source.nextMove(board);

      expect(result.fromFallback, isTrue);
      expect(encodeMove(result.move!), bestCode);
      expect(result.note, contains('参谋'));
    });
  });

  group('off 模式（P0 基线）', () {
    test('全量清单、无候选分桶、LLM 自由选择被采纳', () async {
      final client = ScriptedLlmClient([replyWith('h0-g2')]);
      final source = HybridLlmMoveSource(
        config: config,
        advisorMode: AdvisorMode.off,
        client: client,
      );
      final result = await source.nextMove(blackToMoveBoard());

      expect(result.status, MoveSourceStatus.ok);
      expect(result.fromFallback, isFalse);
      expect(encodeMove(result.move!), 'h0-g2');
      expect(client.userPrompts.first, contains('【合法着法清单'));
      expect(client.userPrompts.first, isNot(contains('候选着法清单')));
    });
  });
}

/// 前置条件断言：不满足即判失败（而非静默 Skip），防止否决链路
/// 的真实回归被跳过掩盖。
void assumeTrue(bool condition, String message) {
  expect(condition, isTrue, reason: message);
}
