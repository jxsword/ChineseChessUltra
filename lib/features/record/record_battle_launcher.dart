import 'package:flutter/material.dart';

import '../board/model/piece.dart';
import '../board/view/human_vs_ai_page.dart';
import '../board/view/human_vs_human_page.dart';
import '../board/view/human_vs_llm_page.dart';
import '../board/view/llm_vs_llm_page.dart';
import 'game_record.dart';

/// 棋谱"进入对战"的模式选项。
enum _BattleMode {
  humanVsAi('人机对战（内置 AI）', '可选难度与执方，AI 自动应手', Icons.computer),
  humanVsHuman('双人对弈', '同屏轮流走子', Icons.people),
  humanVsLlm('人机对战（大模型）', '玩家执红，大模型执黑', Icons.psychology),
  llmVsLlm('大模型对战', '红黑双模型自动对弈', Icons.smart_toy);

  const _BattleMode(this.label, this.subtitle, this.icon);
  final String label;
  final String subtitle;
  final IconData icon;
}

/// 计算棋谱"从保存局面继续"的起点 FEN（纯函数，便于单测）。
///
/// - 对局类（有走法）：起点 = 终局局面（initialFen 重放 moves，见
///   [GameRecord.finalFen]）；
/// - 残局类（无走法）：起点 = initialFen（行棋方由 FEN 决定）；
/// - 已分胜负的对局：无对战入口，返回 null。
String? battleStartFen(GameRecord record) {
  if (!record.isEndgame && record.result != null) return null;
  return record.isEndgame ? record.initialFen : record.finalFen;
}

/// 棋谱是否提供"进入对战"入口（纯函数，便于单测）。
bool canLaunchBattle(GameRecord record) => battleStartFen(record) != null;

/// 弹出模式选择并进入对应对战页。
///
/// 返回 false 表示用户取消或该棋谱无入口。
Future<bool> launchBattle(BuildContext context, GameRecord record) async {
  final fen = battleStartFen(record);
  if (fen == null) return false;
  if (!context.mounted) return false;

  final mode = await showModalBottomSheet<_BattleMode>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('选择对战模式（从保存局面继续）'),
          ),
          for (final mode in _BattleMode.values)
            ListTile(
              leading: Icon(mode.icon),
              title: Text(mode.label),
              subtitle: Text(
                mode.subtitle,
                style: const TextStyle(fontSize: 12),
              ),
              onTap: () => Navigator.pop(sheetContext, mode),
            ),
        ],
      ),
    ),
  );
  if (mode == null || !context.mounted) return false;

  // 人机 AI：附执方选择。
  var playerSide = Side.red;
  if (mode == _BattleMode.humanVsAi) {
    final side = await showModalBottomSheet<Side>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('选择执方（AI 执另一方）'),
            ),
            ListTile(
              leading: const Icon(Icons.circle, color: Colors.red),
              title: const Text('玩家执红'),
              onTap: () => Navigator.pop(sheetContext, Side.red),
            ),
            ListTile(
              leading: const Icon(Icons.circle, color: Colors.black),
              title: const Text('玩家执黑'),
              onTap: () => Navigator.pop(sheetContext, Side.black),
            ),
          ],
        ),
      ),
    );
    if (side == null) return false;
    playerSide = side;
  }

  final route = switch (mode) {
    _BattleMode.humanVsAi => MaterialPageRoute<void>(
        builder: (_) => HumanVsAiPage(initialFen: fen, playerSide: playerSide),
      ),
    _BattleMode.humanVsHuman => MaterialPageRoute<void>(
        builder: (_) => HumanVsHumanGamePage(initialFen: fen),
      ),
    _BattleMode.humanVsLlm => MaterialPageRoute<void>(
        builder: (_) => HumanVsLlmPage(initialFen: fen),
      ),
    _BattleMode.llmVsLlm => MaterialPageRoute<void>(
        builder: (_) => LlmVsLlmPage(initialFen: fen),
      ),
  };
  Navigator.push(context, route);
  return true;
}
