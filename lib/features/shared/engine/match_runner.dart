import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import '../../board/model/board.dart';
import '../../board/model/move.dart';
import '../../board/model/piece.dart';
import 'ai_engine.dart';
import 'move_source.dart';

/// 一场对局的统计报告（五期能力评估用）。
class MatchReport {
  MatchReport({
    required this.winner,
    required this.endReason,
    required this.plies,
    required this.redTime,
    required this.blackTime,
    required this.redFallbacks,
    required this.blackFallbacks,
    required this.redBlunders,
    required this.blackBlunders,
    required this.evaluatedPlies,
    required this.redTop3Hits,
    required this.redTop3Misses,
    required this.blackTop3Hits,
    required this.blackTop3Misses,
    required this.movesIccs,
  });

  /// 'red' | 'black' | 'draw-limit' | 'red-resign' | 'black-resign' |
  /// 'red-illegal' | 'black-illegal'
  final String winner;
  final String endReason;
  final int plies;
  final Duration redTime;
  final Duration blackTime;

  /// 走子来源触发兜底（fromFallback）的次数。
  final int redFallbacks;
  final int blackFallbacks;

  /// 相对引擎最佳损失 > [blunderThresholdCp] 的手数（质量指标）。
  final int redBlunders;
  final int blackBlunders;
  final int evaluatedPlies;

  /// 所选着法 ∈ 引擎当层 Top-3 的跟随统计（质量跟随度指标）。
  final int redTop3Hits;
  final int redTop3Misses;
  final int blackTop3Hits;
  final int blackTop3Misses;
  final List<String> movesIccs;

  Map<String, dynamic> toJson() => {
        'winner': winner,
        'endReason': endReason,
        'plies': plies,
        'redTimeMs': redTime.inMilliseconds,
        'blackTimeMs': blackTime.inMilliseconds,
        'redFallbacks': redFallbacks,
        'blackFallbacks': blackFallbacks,
        'redBlunders': redBlunders,
        'blackBlunders': blackBlunders,
        'evaluatedPlies': evaluatedPlies,
        'redTop3Hits': redTop3Hits,
        'redTop3Misses': redTop3Misses,
        'blackTop3Hits': blackTop3Hits,
        'blackTop3Misses': blackTop3Misses,
        'moves': movesIccs,
      };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(this);
}

/// 无 UI 的对局运行器：两枚 [MoveSource] 对打并产出统计。
///
/// 用于"大模型对战"（两 LLM 互打）与"人 vs 大模型"（ChessAi 代打人类侧）
/// 的能力评估；也可在测试中以脚本化假 LLM 驱动做确定性断言。
class MatchRunner {
  MatchRunner._();

  /// 逐手质量评估的"失误"阈值（厘兵，docs/phase5/02 §4）。
  static const int blunderThresholdCp = 250;

  static Future<MatchReport> run({
    required MoveSource red,
    required MoveSource black,
    Board? initial,
    int maxPlies = 120,
    bool evaluateQuality = false,
    int qualityDepth = 4,
    Duration? perMoveTimeout,
  }) async {
    final board = (initial ?? Board.initial()).copy();
    final history = <Move>[];
    final movesIccs = <String>[];
    var redTime = Duration.zero;
    var blackTime = Duration.zero;
    var redFallbacks = 0;
    var blackFallbacks = 0;
    var redBlunders = 0;
    var blackBlunders = 0;
    var evaluatedPlies = 0;
    var redTop3Hits = 0;
    var redTop3Misses = 0;
    var blackTop3Hits = 0;
    var blackTop3Misses = 0;

    String sideResign(Side loser, String note) => loser.isRed
        ? 'red-resign'
        : 'black-resign';

    for (var ply = 0; ply < maxPlies; ply++) {
      final mover = board.turn;
      final source = mover.isRed ? red : black;

      final watch = Stopwatch()..start();
      MoveSourceResult result;
      try {
        result = await source
            .nextMove(board, history: List.of(history))
            .timeout(
          perMoveTimeout ?? const Duration(minutes: 5),
          onTimeout: () => MoveSourceResult.failed('单手超时'),
        );
      } on Object catch (e) {
        return _finish(
          winner: sideResign(mover, '$e'),
          endReason: 'source-error',
          plies: ply,
          redTime: redTime,
          blackTime: blackTime,
          redFallbacks: redFallbacks,
          blackFallbacks: blackFallbacks,
          redBlunders: redBlunders,
          blackBlunders: blackBlunders,
          evaluatedPlies: evaluatedPlies,
          redTop3Hits: redTop3Hits,
          redTop3Misses: redTop3Misses,
          blackTop3Hits: blackTop3Hits,
          blackTop3Misses: blackTop3Misses,
          movesIccs: movesIccs,
        );
      }
      if (mover.isRed) {
        redTime += watch.elapsed;
      } else {
        blackTime += watch.elapsed;
      }

      // 失败/无着 → 当方认输。
      if (result.status != MoveSourceStatus.ok || result.move == null) {
        return _finish(
          winner: sideResign(mover, result.note ?? 'no move'),
          endReason: result.status == MoveSourceStatus.noLegalMove
              ? 'no-legal-move'
              : 'resign',
          plies: ply,
          redTime: redTime,
          blackTime: blackTime,
          redFallbacks: redFallbacks,
          blackFallbacks: blackFallbacks,
          redBlunders: redBlunders,
          blackBlunders: blackBlunders,
          evaluatedPlies: evaluatedPlies,
          redTop3Hits: redTop3Hits,
          redTop3Misses: redTop3Misses,
          blackTop3Hits: blackTop3Hits,
          blackTop3Misses: blackTop3Misses,
          movesIccs: movesIccs,
        );
      }

      final move = result.move!;
      // 合法性终审（来源自带校验，这里兜底）。
      final legal = board
          .legalMovesFor(move.from)
          .any((m) => m.to == move.to);
      if (!legal) {
        return _finish(
          winner: sideResign(mover, 'illegal ${move.from}->${move.to}'),
          endReason: 'illegal-move',
          plies: ply,
          redTime: redTime,
          blackTime: blackTime,
          redFallbacks: redFallbacks,
          blackFallbacks: blackFallbacks,
          redBlunders: redBlunders,
          blackBlunders: blackBlunders,
          evaluatedPlies: evaluatedPlies,
          redTop3Hits: redTop3Hits,
          redTop3Misses: redTop3Misses,
          blackTop3Hits: blackTop3Hits,
          blackTop3Misses: blackTop3Misses,
          movesIccs: movesIccs,
        );
      }

      if (result.fromFallback) {
        if (mover.isRed) {
          redFallbacks++;
        } else {
          blackFallbacks++;
        }
      }

      // 逐手质量评估：所选着法相对引擎最佳的损失。
      if (evaluateQuality) {
        final snapshot = board.copy();
        // 评估深度口径：findBestMoveEx(depth) 的根分 = 走 1 步后对手搜
        // depth-1 层（总深 depth ply）；evaluateMove 须取 depth-1 对齐，
        // 否则不同深度的分相减会系统性失真。重搜索包 Isolate 避免卡 UI。
        final evalDepth = (qualityDepth - 1).clamp(1, 6);
        final report = await Isolate.run(
          () => ChessAi.findBestMoveEx(snapshot, depth: qualityDepth),
        );
        if (report != null) {
          evaluatedPlies++;
          final pickedCp = await Isolate.run(
            () => ChessAi.evaluateMove(snapshot, move, depth: evalDepth),
          );
          final loss = pickedCp == null
              ? MatchRunnerBlunder.mate
              : report.bestCp - pickedCp;
          if (loss > blunderThresholdCp) {
            if (mover.isRed) {
              redBlunders++;
            } else {
              blackBlunders++;
            }
          }
          final inTop3 = report.topK
              .take(3)
              .any((e) => e.$1.from == move.from && e.$1.to == move.to);
          if (mover.isRed) {
            inTop3 ? redTop3Hits++ : redTop3Misses++;
          } else {
            inTop3 ? blackTop3Hits++ : blackTop3Misses++;
          }
        }
      }

      // 落子。
      final piece = board.pieceAtP(move.from);
      final applied = board.applyMove(Move(from: move.from, to: move.to));
      history.add(Move(
        from: applied.from,
        to: applied.to,
        piece: piece,
        captured: applied.captured,
      ));
      movesIccs.add(_iccs(applied.from, applied.to));

      // 终局判定。
      final next = board.turn;
      if (board.isCheckmate(next)) {
        return _finish(
          winner: mover.isRed ? 'red' : 'black',
          endReason: 'checkmate',
          plies: ply + 1,
          redTime: redTime,
          blackTime: blackTime,
          redFallbacks: redFallbacks,
          blackFallbacks: blackFallbacks,
          redBlunders: redBlunders,
          blackBlunders: blackBlunders,
          evaluatedPlies: evaluatedPlies,
          redTop3Hits: redTop3Hits,
          redTop3Misses: redTop3Misses,
          blackTop3Hits: blackTop3Hits,
          blackTop3Misses: blackTop3Misses,
          movesIccs: movesIccs,
        );
      }
      if (board.isStalemate(next)) {
        // 困毙判负（中国象棋规则）。
        return _finish(
          winner: mover.isRed ? 'red' : 'black',
          endReason: 'stalemate',
          plies: ply + 1,
          redTime: redTime,
          blackTime: blackTime,
          redFallbacks: redFallbacks,
          blackFallbacks: blackFallbacks,
          redBlunders: redBlunders,
          blackBlunders: blackBlunders,
          evaluatedPlies: evaluatedPlies,
          redTop3Hits: redTop3Hits,
          redTop3Misses: redTop3Misses,
          blackTop3Hits: blackTop3Hits,
          blackTop3Misses: blackTop3Misses,
          movesIccs: movesIccs,
        );
      }
    }

    return _finish(
      winner: 'draw-limit',
      endReason: 'move-limit',
      plies: maxPlies,
      redTime: redTime,
      blackTime: blackTime,
      redFallbacks: redFallbacks,
      blackFallbacks: blackFallbacks,
      redBlunders: redBlunders,
      blackBlunders: blackBlunders,
      evaluatedPlies: evaluatedPlies,
      redTop3Hits: redTop3Hits,
      redTop3Misses: redTop3Misses,
      blackTop3Hits: blackTop3Hits,
      blackTop3Misses: blackTop3Misses,
      movesIccs: movesIccs,
    );
  }

  /// 连跑 [games] 局，红黑换边；返回每局报告与汇总。
  static Future<List<MatchReport>> runSeries({
    required MoveSource Function(Side side) buildRed,
    required MoveSource Function(Side side) buildBlack,
    required int games,
    Board? initial,
    int maxPlies = 120,
    bool evaluateQuality = false,
    int qualityDepth = 4,
  }) async {
    final reports = <MatchReport>[];
    for (var i = 0; i < games; i++) {
      // 奇数局红黑换边，消除执先偏差。
      final swap = i.isOdd;
      reports.add(await run(
        red: swap ? buildBlack(Side.black) : buildRed(Side.red),
        black: swap ? buildRed(Side.red) : buildBlack(Side.black),
        initial: initial,
        maxPlies: maxPlies,
        evaluateQuality: evaluateQuality,
        qualityDepth: qualityDepth,
      ));
    }
    return reports;
  }

  static MatchReport _finish({
    required String winner,
    required String endReason,
    required int plies,
    required Duration redTime,
    required Duration blackTime,
    required int redFallbacks,
    required int blackFallbacks,
    required int redBlunders,
    required int blackBlunders,
    required int evaluatedPlies,
    required int redTop3Hits,
    required int redTop3Misses,
    required int blackTop3Hits,
    required int blackTop3Misses,
    required List<String> movesIccs,
  }) {
    return MatchReport(
      winner: winner,
      endReason: endReason,
      plies: plies,
      redTime: redTime,
      blackTime: blackTime,
      redFallbacks: redFallbacks,
      blackFallbacks: blackFallbacks,
      redBlunders: redBlunders,
      blackBlunders: blackBlunders,
      evaluatedPlies: evaluatedPlies,
      redTop3Hits: redTop3Hits,
      redTop3Misses: redTop3Misses,
      blackTop3Hits: blackTop3Hits,
      blackTop3Misses: blackTop3Misses,
      movesIccs: movesIccs,
    );
  }

  static String _iccs(Position from, Position to) =>
      '${_cell(from)}${_cell(to)}';

  static String _cell(Position p) {
    final file = 'a'.codeUnitAt(0) + p.col;
    return '${String.fromCharCode(file)}${p.row}';
  }
}

/// 质量评估辅助常量。
class MatchRunnerBlunder {
  MatchRunnerBlunder._();

  /// 走完即杀对方时的损失按将杀级计。
  static const int mate = 30000;
}
