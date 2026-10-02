import 'dart:isolate';

import 'package:http/http.dart' as http;

import '../../board/model/board.dart';
import '../../board/model/move.dart';
import '../../board/model/move_notation.dart';
import 'ai_engine.dart';
import 'llm_config.dart';
import 'llm_move_source.dart';
import 'move_annotation.dart';
import 'move_source.dart';

/// 引擎参谋模式（五期 P1）。
enum AdvisorMode {
  /// 关闭参谋：纯 Prompt v2（P0），LLM 在全量清单中自由选择。
  off,

  /// 候选模式：引擎出 Top-K 短名单，LLM 只在 K 条里选。
  candidate,

  /// 护航模式：LLM 自由选，引擎对致命失误有一票否决权。
  gate;

  String get label => switch (this) {
        AdvisorMode.off => '关闭（纯大模型）',
        AdvisorMode.candidate => '候选模式（引擎出名单）',
        AdvisorMode.gate => '护航模式（引擎否决权）',
      };
}

/// 引擎参谋制走子来源（五期 P1 核心，docs/phase5/02 §2）。
///
/// 每手棋先由本地引擎（[ChessAi]）搜索出带评分的候选报告，再按
/// [advisorMode] 决定 LLM 的决策空间：
/// - **候选模式**：Prompt 只给引擎 Top-K 短名单（附分数分桶），LLM 从中
///   选一——"只在好棋里挑"；
/// - **护航模式**：LLM 在全量清单中自由选择，引擎对其选择单独评估，
///   相对最佳分差超过否决阈值（丢大子/被杀）时行使否决权——带理由再问
///   一次，仍不行由引擎最佳着法代走；
/// - **关闭**：等价 P0（Prompt v2 + 全量清单），用于能力评估基线对比。
///
/// 棋力旋钮 [strengthBlend]（0~100）：候选模式 K = 3 + blend/20（3~8）；
/// 护航模式否决阈值 = 80 + 3.2×blend 厘兵（blend=100 时不否决）。
/// 兜底链：LLM 失效 → 引擎最佳着法代走（note 注明），永不卡死。
class HybridLlmMoveSource implements MoveSource {
  HybridLlmMoveSource({
    required this.config,
    this.advisorMode = AdvisorMode.candidate,
    this.strengthBlend = 50,
    this.advisorDifficulty = 5,
    this.timeout = const Duration(seconds: 60),
    this.maxAttempts = 3,
    LlmFallback fallback = LlmFallback.builtinAi,
    http.Client? client,
  })  : _fallbackMode = fallback,
        _client = client;

  final LlmConfig config;
  final AdvisorMode advisorMode;
  final int strengthBlend;

  /// 参谋搜索深度档 1~5（迭代深度 = 档 + 1，最高 6）。
  final int advisorDifficulty;

  /// LLM 调用超时/重试（与 LlmMoveSource 语义一致）。
  final Duration timeout;
  final int maxAttempts;
  final LlmFallback _fallbackMode;
  final http.Client? _client;

  /// 候选名单宽度：blend 0→3，100→8。
  static int shortlistSize(int blend) => (3 + blend ~/ 20).clamp(3, 8);

  /// 护航否决阈值（厘兵）：blend 0→80（严），100→400（最宽）。
  static int vetoThresholdCp(int blend) => 80 + (320 * blend.clamp(0, 100)) ~/ 100;

  @override
  String get displayName =>
      config.model.trim().isEmpty ? '（未配置模型）' : config.model.trim();

  /// 参谋迭代深度：档位 1~5 → 2~6。
  int get _depth => (advisorDifficulty.clamp(1, 5)) + 1;

  @override
  Future<MoveSourceResult> nextMove(
    Board board, {
    List<Move> history = const [],
  }) async {
    if (advisorMode == AdvisorMode.off) {
      // P0 基线：Prompt v2 + 全量清单，无参谋。
      final source = LlmMoveSource(
        config: config,
        timeout: timeout,
        maxAttempts: maxAttempts,
        fallback: _fallbackMode,
        usePromptV2: true,
        client: _client,
      );
      return source.nextMove(board, history: history);
    }

    final legal = allLegalMoves(board);
    if (legal.isEmpty) return MoveSourceResult.noLegalMove();

    // 1. 引擎参谋搜索（Isolate，全窗口真实分）。
    final snapshot = board.copy();
    final depth = _depth;
    final topK = shortlistSize(strengthBlend);
    final report = await Isolate.run(
      () => ChessAi.findBestMoveEx(
        snapshot,
        depth: depth,
        topK: topK,
        timeLimit: const Duration(seconds: 5),
      ),
    );
    if (report == null) return MoveSourceResult.noLegalMove();

    // 2. 本轮 LLM 可见池 + Prompt v2。
    final pool = advisorMode == AdvisorMode.candidate
        ? report.topK.map((e) => e.$1).toList()
        : legal;
    final poolByCode = <String, Move>{
      for (final move in pool) encodeMove(move): move,
    };
    final system = LlmPrompts.systemV2(board.turn);
    var user = _buildUser(board, history, pool, report);

    // 3. LLM 提议（重试带失败原因）。
    String? lastReason;
    Move? pick;
    String? lastCode;
    for (var attempt = 1; attempt <= maxAttempts && pick == null; attempt++) {
      final String content;
      try {
        final llm = LlmMoveSource(
          config: config,
          timeout: timeout,
          maxAttempts: 1,
          client: _client,
        );
        content = await llm.chatOnce(system, user);
      } on Object catch (e) {
        lastReason = '第 $attempt 次调用失败：$e';
        continue;
      }
      lastCode = LlmMoveParser.extract(content);
      pick = lastCode == null ? null : poolByCode[lastCode];
      if (pick == null) {
        lastReason = lastCode == null
            ? '无法从回复中解析出着法'
            : '着法 $lastCode 不在候选清单中';
        user = '$user${LlmPrompts.retryFeedbackV2(
          reason: lastReason,
          lastCode: lastCode,
        )}';
      }
    }

    // 4. 护航模式：引擎否决权。
    int? vetoEvalCp;
    if (pick != null &&
        advisorMode == AdvisorMode.gate &&
        strengthBlend < 100) {
      final vetoDepth = _depth - 1;
      final picked = pick;
      vetoEvalCp = await Isolate.run(() {
        final snapshot = board.copy();
        return ChessAi.evaluateMove(snapshot, picked, depth: vetoDepth);
      });
      if (vetoEvalCp == null) {
        pick = null; // 非法着法（理论上不会发生，池内均合法）
      } else {
        final loss = report.bestCp - vetoEvalCp;
        if (loss > vetoThresholdCp(strengthBlend)) {
          final vetoed = pick;
          final second = await _askAgainWithVeto(
            board,
            history,
            pool,
            poolByCode,
            report,
            system,
            user,
            vetoed: vetoed,
            loss: loss,
          );
          pick = second;
        }
      }
    }

    // 5. 兜底链与注解。
    if (pick == null) {
      if (advisorMode == AdvisorMode.candidate || _fallbackMode == LlmFallback.builtinAi) {
        final note = lastReason == null
            ? '已由参谋（内置引擎）代走'
            : '模型未给出有效着法（$lastReason），已由参谋代走';
        return MoveSourceResult(
          status: MoveSourceStatus.ok,
          move: report.best,
          note: note,
          fromFallback: true,
        );
      }
      return MoveSourceResult.failed(
          '模型未给出有效着法（$lastReason），按判负处理');
    }

    var chosenCp = _cpOf(report, pick);
    if (chosenCp == null) chosenCp = vetoEvalCp;
    final note = chosenCp == null
        ? '参谋评分: 未单独评估'
        : '参谋评分: ${MoveAnnotation.scoreBucket(report.bestCp - chosenCp)}';
    return MoveSourceResult.ok(pick, note: note);
  }

  /// 否决后的再问：带否决理由重新提议一次；第二次选择仍超阈值或无效
  /// 时返回 null（由调用方采用引擎最佳）。
  Future<Move?> _askAgainWithVeto(
    Board board,
    List<Move> history,
    List<Move> pool,
    Map<String, Move> poolByCode,
    EngineReport report,
    String system,
    String user, {
    required Move vetoed,
    required int loss,
  }) async {
    final vetoNote =
        '$user\n\n【参谋否决】你上一次选择的 ${encodeMove(vetoed)} '
        '会被引擎惩罚（${MoveAnnotation.scoreBucket(loss)}，'
        '相对最佳损失 $loss 厘兵）。请重新从候选清单中选择，'
        '优先考虑「最佳/均势」档；先「分析:」一句，最后一行「着法: 起点-终点」。';
    final String content;
    try {
      final llm = LlmMoveSource(
        config: config,
        timeout: timeout,
        maxAttempts: 1,
        client: _client,
      );
      content = await llm.chatOnce(system, vetoNote);
    } on Object {
      return null;
    }
    final code = LlmMoveParser.extract(content);
    final second = code == null ? null : poolByCode[code];
    if (second == null) return null;

    final vetoDepth = _depth - 1;
    final chosen = second;
    final secondCp = await Isolate.run(() {
      final snapshot = board.copy();
      return ChessAi.evaluateMove(snapshot, chosen, depth: vetoDepth);
    });
    if (secondCp == null) return null;
    final secondLoss = report.bestCp - secondCp;
    if (secondLoss > vetoThresholdCp(strengthBlend)) return null;
    return second;
  }

  /// v2 用户提示的 Hybrid 版：清单为 [pool]（候选模式附分数分桶）。
  String _buildUser(
    Board board,
    List<Move> history,
    List<Move> pool,
    EngineReport report,
  ) {
    final buf = StringBuffer();
    buf.writeln('【当前局面 FEN】${board.toFen()}');
    buf.write('【棋盘图】\n');
    buf.write(MoveAnnotation.asciiBoard(board));
    buf.writeln('【轮走方】${board.isRedTurn ? '红方' : '黑方'}（该方是你）');
    buf.writeln(
        '【对局着法（中文记法，最新在最后）】${_historyText(history)}');
    if (advisorMode == AdvisorMode.candidate) {
      buf.writeln('【候选着法清单（共 ${pool.length} 条，由本地引擎选出，'
          '必须从中选择一条；「—」后为引擎评估分档）】');
      for (final (move, cp) in report.topK) {
        buf.writeln(
            MoveAnnotation.annotatedWithBucket(board, move, report.bestCp - cp));
      }
    } else {
      buf.writeln('【合法着法清单（共 ${pool.length} 条，必须从中选择一条）】');
      for (final move in pool) {
        buf.writeln(MoveAnnotation.annotate(board, move));
      }
    }
    buf.write('【输出】先输出「分析:」段，最后一行输出「着法: 起点-终点」');
    return buf.toString();
  }

  static String _historyText(List<Move> history) {
    if (history.isEmpty) return '（开局，暂无历史）';
    final recent =
        history.length > 60 ? history.sublist(history.length - 60) : history;
    final parts = <String>[];
    for (final move in recent) {
      final piece = move.piece;
      parts.add(piece == null ? encodeMove(move) : move.chineseNotation(piece));
    }
    return parts.join('  ');
  }

  static int? _cpOf(EngineReport report, Move move) {
    for (final (m, cp) in report.topK) {
      if (m.from == move.from && m.to == move.to) return cp;
    }
    return null; // 护航模式的选择不在 Top-K 内，需单独评估
  }
}
