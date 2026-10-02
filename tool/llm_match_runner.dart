// 五期能力评估 CLI：真实大模型对抗赛。
//
// 用法（需真实 API Key，密钥只从环境变量读取，不落仓库）：
//   LLM_BASE_URL=https://dashscope.aliyuncs.com/compatible-mode/v1 \
//   LLM_MODEL=qwen3.8-max \
//   LLM_API_KEY=sk-xxx \
//   flutter run tool/llm_match_runner.dart --games 2 --profile hybrid-candidate
//
// 或一条命令跑四档对比（基线/P0/候选/护航，每档对抗内置 AI）：
//   ... flutter run tool/llm_match_runner.dart --suite
//
// 场景：
//   - profile vs 内置 AI（"人 vs 大模型"，引擎代打人类侧）
//   - profile vs profile（"大模型对战"，可用 --red/--black 组合）
//
// 输出 JSON 报告：胜负/手数/每手耗时/失误率/兜底率，可直接归档对比。
import 'dart:convert';
import 'dart:io';

import 'package:chinese_chess_ultra/features/shared/engine/hybrid_llm_move_source.dart';
import 'package:chinese_chess_ultra/features/shared/engine/llm_config.dart';
import 'package:chinese_chess_ultra/features/shared/engine/llm_move_source.dart';
import 'package:chinese_chess_ultra/features/shared/engine/llm_settings.dart';
import 'package:chinese_chess_ultra/features/shared/engine/match_runner.dart';
import 'package:chinese_chess_ultra/features/shared/engine/move_source.dart';

Future<void> main(List<String> args) async {
  final baseUrl = Platform.environment['LLM_BASE_URL'];
  final model = Platform.environment['LLM_MODEL'];
  final apiKey = Platform.environment['LLM_API_KEY'] ?? '';
  if (baseUrl == null || model == null) {
    stderr.writeln('请设置环境变量 LLM_BASE_URL、LLM_MODEL（可选 LLM_API_KEY）。');
    exit(2);
  }
  final config = LlmConfig(baseUrl: baseUrl, model: model, apiKey: apiKey);

  final suite = args.contains('--suite');
  final games = _intArg(args, '--games', 2);
  final maxPlies = _intArg(args, '--max-plies', 120);
  final blend = _intArg(args, '--blend', 50);

  final profiles = <String, MoveSource Function()>{
    'baseline-v1': () => LlmMoveSource(config: config, maxAttempts: 3),
    'p0-prompt-v2': () =>
        LlmMoveSource(config: config, usePromptV2: true, maxAttempts: 3),
    'hybrid-candidate': () => HybridLlmMoveSource(
          config: config,
          advisorMode: AdvisorMode.candidate,
          strengthBlend: blend,
          advisorDifficulty: 5,
          maxAttempts: 3,
        ),
    'hybrid-gate': () => HybridLlmMoveSource(
          config: config,
          advisorMode: AdvisorMode.gate,
          strengthBlend: blend,
          advisorDifficulty: 5,
          maxAttempts: 3,
        ),
  };

  final report = <String, dynamic>{'games': games, 'maxPlies': maxPlies};

  if (suite) {
    // 四档对比：每档以红/黑两视角各对抗内置 AI（难度 3）一局。
    for (final name in profiles.keys) {
      report[name] = await _matchVsEngine(
        profiles[name]!(), games: 2, maxPlies: maxPlies);
    }
  } else {
    final profileName = _stringArg(args, '--profile', 'hybrid-candidate');
    final build = profiles[profileName];
    if (build == null) {
      stderr.writeln('未知 profile: $profileName（可选：${profiles.keys.join(', ')}）');
      exit(2);
    }
    final redName = _stringArg(args, '--red', profileName);
    final blackName = _stringArg(args, '--black', 'chessai-3');
    if (redName == profileName && blackName == 'chessai-3') {
      report['match'] = await _matchVsEngine(build(), games: games, maxPlies: maxPlies);
    } else {
      // 大模型对战：profile vs profile。
      final redBuild = profiles[redName];
      final blackBuild = profiles[blackName];
      final reports = <MatchReport>[];
      for (var i = 0; i < games; i++) {
        reports.add(await MatchRunner.run(
          red: i.isEven ? (redBuild ?? build)() : (blackBuild ?? build)(),
          black: i.isEven ? (blackBuild ?? build)() : (redBuild ?? build)(),
          maxPlies: maxPlies,
        ));
      }
      report['match'] = reports.map((r) => r.toJson()).toList();
    }
  }

  print(const JsonEncoder.withIndent('  ').convert(report));
}

Future<List<Map<String, dynamic>>> _matchVsEngine(
  MoveSource source, {
  required int games,
  required int maxPlies,
}) async {
  final reports = <Map<String, dynamic>>[];
  for (var i = 0; i < games; i++) {
    // 红黑换边：偶数局 LLM 执红，奇数局执黑。
    final llmIsRed = i.isEven;
    final report = await MatchRunner.run(
      red: llmIsRed ? source : ChessAiMoveSource(difficulty: 3),
      black: llmIsRed ? ChessAiMoveSource(difficulty: 3) : source,
      maxPlies: maxPlies,
      evaluateQuality: true,
      qualityDepth: 4,
    );
    final json = report.toJson();
    json['llmSide'] = llmIsRed ? 'red' : 'black';
    reports.add(json);
  }
  return reports;
}

int _intArg(List<String> args, String name, int def) {
  final idx = args.indexOf(name);
  if (idx < 0 || idx + 1 >= args.length) return def;
  return int.tryParse(args[idx + 1]) ?? def;
}

String _stringArg(List<String> args, String name, String def) {
  final idx = args.indexOf(name);
  if (idx < 0 || idx + 1 >= args.length) return def;
  return args[idx + 1];
}
