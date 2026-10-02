import '../board/model/board_state.dart';
import 'game_record.dart';

/// 棋谱导出：标准 PGN 文本（ICCS 着法）与中文记谱分享文本。
///
/// 与 features/puzzle 的 PgnParser（导入方向）对偶：本文件只负责生成。
class PgnWriter {
  PgnWriter._();

  /// 生成 PGN（Seven Tag Roam + ICCS 着法序列，残局附 SetFen/FEN）。
  static String write(GameRecord record) {
    final date = record.createdAt ?? DateTime.now();
    final pad = (int v) => v.toString().padLeft(2, '0');
    final result = _resultTag(record);
    final headers = <String>[
      '[Event "中国象棋 Ultra"]',
      '[Site "ChineseChessUltra"]',
      '[Date "${date.year}.${pad(date.month)}.${pad(date.day)}"]',
      '[Round "-"]',
      '[Red "${record.redName ?? '红方'}"]',
      '[Black "${record.blackName ?? '黑方'}"]',
      '[Result "$result"]',
      if (record.solveStatus != SolveStatus.none)
        '[Annotator "${record.solveStatus.label}"]',
      // 残局与初始局面不同时标注起始 FEN，导入方可据此复原。
      if (!_isInitialFen(record.initialFen)) ...[
        '[SetFen "${record.initialFen}"]',
        '[FEN "${record.initialFen}"]',
      ],
    ];

    final movesBuf = StringBuffer();
    var plies = 0;
    for (final m in record.moves) {
      if (plies % 2 == 0) {
        if (plies > 0) movesBuf.write(' ');
        movesBuf.write('${plies ~/ 2 + 1}. ');
      } else {
        movesBuf.write(' ');
      }
      movesBuf.write(IccsFallback.format(m));
      plies++;
    }
    if (movesBuf.isNotEmpty) movesBuf.write(' ');

    final body = record.moves.isEmpty
        ? ''
        : '${movesBuf.toString().trim()} $result';
    return '${headers.join('\n')}\n\n$body\n';
  }

  /// 生成中文记谱分享文本（纯文本，便于直接粘贴给他人研究）。
  static String writeShareText(GameRecord record) {
    final buf = StringBuffer();
    buf.writeln('【中国象棋 Ultra 棋谱】${record.title}');
    buf.writeln(
      '模式: ${record.modeLabel}'
      '${record.redName != null ? '  红方: ${record.redName}' : ''}'
      '${record.blackName != null ? '  黑方: ${record.blackName}' : ''}',
    );
    if (record.result != null) {
      buf.writeln('结果: ${_resultLabel(record.result!)}');
    }
    if (!_isInitialFen(record.initialFen)) {
      buf.writeln('起始 FEN: ${record.initialFen}');
    }
    if (record.note != null && record.note!.trim().isNotEmpty) {
      buf.writeln('备注: ${record.note}');
    }
    if (record.moves.isNotEmpty) {
      buf.writeln('着法（中文记谱）:');
      final notations = record.chineseNotations();
      for (var i = 0; i < notations.length; i += 2) {
        final round = i ~/ 2 + 1;
        final red = notations[i];
        final black = i + 1 < notations.length ? notations[i + 1] : '';
        buf.writeln('$round. $red  $black');
      }
    }
    if (record.solutions.isNotEmpty) {
      buf.writeln(
        '破解之法（${record.solutions.length} 条'
        '${record.hasUniqueSolution ? '，唯一解' : ''}）:',
      );
      for (var i = 0; i < record.solutions.length; i++) {
        buf.writeln('解法${i + 1}: ${record.solutions[i].join(' ')}');
      }
    } else if (record.solveStatus == SolveStatus.noSolution) {
      buf.writeln('求解结论: 无解（深度上界内已证明）');
    } else if (record.solveStatus == SolveStatus.timeout) {
      buf.writeln('求解结论: 限时内未找到解法');
    }
    if (record.llmNote != null && record.llmNote!.trim().isNotEmpty) {
      buf.writeln('大模型注释: ${record.llmNote}');
    }
    return buf.toString().trimRight();
  }

  static String _resultLabel(GameResult result) => switch (result) {
        GameResult.redWins => '红方胜',
        GameResult.blackWins => '黑方胜',
        GameResult.draw => '和棋',
      };

  static String _resultTag(GameRecord record) {
    if (record.isEndgame) {
      return switch (record.solveStatus) {
        SolveStatus.solved => '1-0',
        SolveStatus.noSolution => '0-1',
        _ => '*',
      };
    }
    return switch (record.result) {
      GameResult.redWins => '1-0',
      GameResult.blackWins => '0-1',
      GameResult.draw => '1/2-1/2',
      null => '*',
    };
  }

  static bool _isInitialFen(String fen) {
    final board = fen.split(' ').first;
    return board == 'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR';
  }
}
