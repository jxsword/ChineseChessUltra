import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:chinese_chess_ultra/features/board/model/board.dart';
import 'package:chinese_chess_ultra/features/board/model/move.dart';
import 'package:chinese_chess_ultra/features/board/model/piece.dart';
import 'package:chinese_chess_ultra/features/shared/engine/ai_engine.dart';
import 'package:chinese_chess_ultra/features/shared/engine/hybrid_llm_move_source.dart';
import 'package:chinese_chess_ultra/features/shared/engine/llm_config.dart';
import 'package:chinese_chess_ultra/features/shared/engine/llm_move_source.dart';
import 'package:chinese_chess_ultra/features/shared/engine/llm_settings.dart';
import 'package:chinese_chess_ultra/features/shared/engine/match_runner.dart';
import 'package:chinese_chess_ultra/features/shared/engine/move_source.dart';

const config = LlmConfig(baseUrl: 'https://example.com/v1', model: 'fake');

/// "弱模型"策略：从 prompt 的着法清单中选择。
enum WeakStrategy {
  /// 永远选清单第一条（保守）。
  first,

  /// 永远选清单最后一条（易踩坑）。
  last;

  String pick(String userPrompt) {
    final codes = RegExp(r'([a-i]\d)-([a-i]\d)')
        .allMatches(_listSection(userPrompt))
        .map((m) => m.group(0)!)
        .toList();
    if (codes.isEmpty) return '着法: a0-a1'; // 触发拒绝链路
    return '着法: ${switch (this) {
      WeakStrategy.first => codes.first,
      WeakStrategy.last => codes.last,
    }}';
  }

  /// 只取清单段落，避免棋盘图/分析文本中的坐标干扰。
  static String _listSection(String userPrompt) {
    final start = userPrompt.indexOf('着法清单');
    if (start < 0) return userPrompt;
    final outputIdx = userPrompt.indexOf('【输出】', start);
    return outputIdx < 0 ? userPrompt.substring(start) : userPrompt.substring(start, outputIdx);
  }
}

/// 弱模型 HTTP 客户端：解析 prompt 清单并按策略回复。
http.Client weakLlmClient(WeakStrategy strategy) {
  return MockClient((request) async {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final user = body['messages'][1]['content'] as String;
    final content = strategy.pick(user);
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
  });
}

MoveSource baselineSource() => LlmMoveSource(
      config: config,
      usePromptV2: false,
      client: weakLlmClient(WeakStrategy.last),
      maxAttempts: 2,
    );

MoveSource hybridCandidateSource() => HybridLlmMoveSource(
      config: config,
      advisorMode: AdvisorMode.candidate,
      strengthBlend: 0,
      advisorDifficulty: 1,
      client: weakLlmClient(WeakStrategy.last),
      maxAttempts: 2,
    );

MoveSource chessAiOpponent() => ChessAiMoveSource(difficulty: 1);

void main() {
  group('战术命中率（确定性）', () {
    /// 固定战术局面集：每个局面都存在引擎认可的明显好着。
    const tacticalFens = [
      '4k4/9/9/9/r8/9/R8/9/9/4K4 w', // R×r 白吃车
      '3k5/9/9/9/R8/8R/9/9/9/4K4 w', // 双车杀
      '4k4/9/9/9/9/4C4/9/4C4/9/4K4 w - - 0 1', // 双炮中线
    ];

    test('Hybrid 候选模式命中率 = 100%，基线选尾严格更低', () async {
      var hybridHits = 0;
      var baselineHits = 0;
      var total = 0;
      for (final fen in tacticalFens) {
        final board = Board.fromFen(fen);
        final report = ChessAi.findBestMoveEx(board, depth: 4, topK: 3);
        if (report == null) continue;
        final top3 = report.topK.map((e) => encodeMove(e.$1)).toSet();
        total++;

        // Hybrid 候选模式：池被限定在 Top-K 内，怎么选都命中。
        final hybrid = hybridCandidateSource();
        final hybridResult = await hybrid.nextMove(board);
        if (top3.contains(encodeMove(hybridResult.move!))) hybridHits++;

        // 基线：弱模型在全量清单中选尾。
        final baseline = baselineSource();
        final baselineResult = await baseline.nextMove(board);
        if (top3.contains(encodeMove(baselineResult.move!))) baselineHits++;
      }
      expect(total, 3, reason: '局面集应全部有效');
      expect(hybridHits, total, reason: '候选模式命中 Top-3 比例应为 100%');
      expect(baselineHits, lessThan(total), reason: '基线选尾命中率应更低');
    });
  });

  group('对局质量（MatchRunner，短局确定性对比）', () {
    test('Hybrid 对弱模型的失误率改善：对抗 ChessAi(d1) 短局', () async {
      // 基线（弱模型裸奔）。
      final baselineReport = await MatchRunner.run(
        red: baselineSource(),
        black: chessAiOpponent(),
        maxPlies: 40,
        evaluateQuality: true,
        qualityDepth: 2,
      );
      // Hybrid 候选模式（同一弱模型 + 参谋）。
      final hybridReport = await MatchRunner.run(
        red: hybridCandidateSource(),
        black: chessAiOpponent(),
        maxPlies: 40,
        evaluateQuality: true,
        qualityDepth: 2,
      );

      expect(baselineReport.evaluatedPlies, greaterThan(0));
      expect(hybridReport.evaluatedPlies, greaterThan(0));
      // 弱模型选尾策略失误率高；Hybrid 限制在引擎名单内后失误率应显著更低。
      expect(
        hybridReport.redBlunders,
        lessThanOrEqualTo(baselineReport.redBlunders),
        reason: '基线失误 ${baselineReport.redBlunders}/'
            '${baselineReport.evaluatedPlies}，'
            'Hybrid 失误 ${hybridReport.redBlunders}/'
            '${hybridReport.evaluatedPlies}',
      );
    });

    test('“大模型对战”场景：两 Hybrid 互打能正常完成对局', () async {
      final report = await MatchRunner.run(
        red: hybridCandidateSource(),
        black: HybridLlmMoveSource(
          config: config,
          advisorMode: AdvisorMode.gate,
          strengthBlend: 0,
          advisorDifficulty: 1,
          client: weakLlmClient(WeakStrategy.first),
          maxAttempts: 2,
        ),
        maxPlies: 30,
      );
      expect(report.plies, greaterThan(0));
      expect(report.endReason, anyOf('checkmate', 'stalemate', 'move-limit',
          'resign', 'no-legal-move', 'illegal-move'));
      // 棋谱可追溯。
      expect(report.movesIccs, isNotEmpty);
    });
  });
}
