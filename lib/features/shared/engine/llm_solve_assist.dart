import 'package:http/http.dart' as http;

import '../../board/model/board.dart';
import '../../board/model/move.dart';
import 'llm_config.dart';
import 'llm_move_source.dart';
import 'move_annotation.dart';
import 'move_source.dart';

/// 残局求解的提示词组装与解析（纯函数，便于单测）。
///
/// 设计见 docs/phase4/02 §2.4：模型只"提议"首着与思路，是否必胜由
/// [EndgameSolver] 验证后才写入棋谱（Hybrid 架构：模型启发式、引擎裁判）。
class LlmSolvePrompts {
  LlmSolvePrompts._();

  static String system() =>
      '你是中国象棋残局研究助手，协助分析一个残局是否有强制将死的杀法。\n'
      '坐标约定：列用字母 a-i（从左到右），行用数字 0-9'
      '（0 为黑方底线、棋盘顶部，9 为红方底线、棋盘底部）。\n'
      '你只能从「合法着法清单」中选择首着，禁止编造清单之外的着法。\n'
      '\n'
      '【回复格式（唯一允许的格式，共三行）】\n'
      '首选着法: 起点-终点\n'
      '备选着法: 起点-终点（没有则写 无）\n'
      '思路: 一句话说明攻击目标与关键点\n'
      '禁止输出其他任何内容。';

  static String user(Board board, List<String> legalCodes) {
    final buf = StringBuffer();
    buf.writeln('【局面 FEN】${board.toFen()}');
    buf.writeln('【棋盘图（大写为红方、小写为黑方，第一行是黑方底线）】');
    buf.write(MoveAnnotation.asciiBoard(board));
    buf.writeln('【轮走方】${board.isRedTurn ? '红方' : '黑方'}（求解方）');
    buf.writeln('【任务】判断该局面求解方是否有强制将死的杀法；'
        '若有，给出首选首着与备选首着（均取自合法着法清单）。');
    buf.writeln('【合法着法清单（共 ${legalCodes.length} 条）】');
    buf.write(legalCodes.join(', '));
    return buf.toString();
  }

}

/// 模型提议的解析结果。
class SolveProposal {
  const SolveProposal({this.firstMoveCode, this.alternateCode, this.idea});

  /// 归一化 ICCS 式 "h2e2"（内部行号约定，同 LLM 对弈协议）。
  final String? firstMoveCode;
  final String? alternateCode;
  final String? idea;
}

/// 大模型求解辅助：一次调用，返回候选首着与思路注释。
class LlmSolveAssist {
  LlmSolveAssist({required this.config, this.client, this.maxAttempts = 2});

  final LlmConfig config;
  final http.Client? client;
  final int maxAttempts;

  /// 返回 (提议, 说明)。失败时提议为 null，说明给出原因。
  Future<(SolveProposal?, String)> propose(Board board) async {
    if (!config.isConfigured) {
      return (null, '研究助手模型未配置');
    }
    final legal = allLegalMoves(board);
    if (legal.isEmpty) return (null, '当前局面无合法着法');

    final codes = <String, Move>{
      for (final m in legal) encodeMove(m): m,
    };
    final system = LlmSolvePrompts.system();
    var user = LlmSolvePrompts.user(board, codes.keys.toList());

    String? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final source = LlmMoveSource(
          config: config,
          maxAttempts: 1,
          client: client,
        );
        // 复用 LlmMoveSource 的流式通道：system/user 文本走同一协议。
        final content = await source.chatOnce(system, user);
        final proposal = parseProposal(content);
        if (proposal?.firstMoveCode != null &&
            codes.containsKey(proposal!.firstMoveCode)) {
          return (proposal, proposal.idea ?? '');
        }
        lastError = '回复 ${proposal?.firstMoveCode ?? content} 不在合法清单中';
      } on Object catch (e) {
        lastError = '$e';
      }
      user = '$user\n\n（上次回复无效：$lastError，请严格按三行格式重新回答）';
    }
    return (null, lastError ?? '未知错误');
  }

  /// 解析三行格式回复；坐标归一化复用 [LlmMoveParser.extract]。
  static SolveProposal? parseProposal(String content) {
    String? field(String label) {
      final match = RegExp('$label\\s*[:：]\\s*(.+)').firstMatch(content);
      return match?.group(1)?.trim();
    }

    final first = field('首选着法');
    final alternate = field('备选着法');
    final idea = field('思路');
    String? code(String? raw) {
      if (raw == null || raw.isEmpty || raw.contains('无')) return null;
      return LlmMoveParser.extract(raw);
    }

    return SolveProposal(
      firstMoveCode: code(first),
      alternateCode: code(alternate),
      idea: (idea == null || idea.isEmpty) ? null : idea,
    );
  }
}

/// 提议 → 走法（内部坐标）转换工具。
extension SolveProposalX on SolveProposal {
  Move? toMove(Map<String, Move> codeIndex) =>
      firstMoveCode == null ? null : codeIndex[firstMoveCode];
}
