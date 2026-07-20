import 'dart:io';

import '../../features/board/model/move.dart';
import '../../features/puzzle/viewmodel/puzzle_vm.dart' show HintStrategy;

/// 提示走法结果。
class HintResult {
  const HintResult({required this.move, this.score, this.depth, this.pv});

  /// 引擎推荐的走法。
  final Move move;

  /// 评分（centipawn，从当前走子方视角）。
  final int? score;

  /// 搜索深度。
  final int? depth;

  /// 主变（principal variation），可选。
  final List<Move>? pv;
}

/// Pikafish UCI 引擎桥（二期）。
///
/// 通过 `dart:io` 的 [Process] 启动 Pikafish 二进制，按 UCI 协议通信。
///
/// 第一期不实现，仅保留接口与示例骨架；二期接入 Pikafish-org/Pikafish
/// 预编译二进制即可。
abstract class PikafishBridge {
  /// 启动引擎进程；返回是否就绪。
  Future<bool> start();

  /// 关闭引擎进程。
  Future<void> dispose();

  /// 同步设置当前局面（UCI `position fen ...`）。
  void position(String fen);

  /// 异步分析当前局面至指定深度，返回最佳走法。
  Future<HintResult?> analyze({int depth = 18, int multipv = 1});

  /// 简短查询：直接获取最佳走法（UCI `go movetime ...` 或 `go depth ...`）。
  Future<Move?> bestMove({int depth = 15});
}

/// 默认 [PikafishBridge] 实现（二期）。
///
/// 仅为编译占位，调用即抛 [UnimplementedError]。
class LocalPikafishBridge implements PikafishBridge {
  LocalPikafishBridge({required this.binaryPath});

  final String binaryPath;
  Process? _process;

  @override
  Future<bool> start() async {
    // TODO(二期): 启动 Pikafish 进程并完成 UCI 握手（uci -> uciok）。
    throw UnimplementedError('PikafishBridge.start() not implemented');
  }

  @override
  Future<void> dispose() async {
    await _process?.kill();
    _process = null;
  }

  @override
  void position(String fen) {
    // TODO(二期): 发送 `position fen $fen` 到 stdin。
    throw UnimplementedError('PikafishBridge.position() not implemented');
  }

  @override
  Future<HintResult?> analyze({int depth = 18, int multipv = 1}) {
    // TODO(二期): 发送 `go depth $depth multipv $multipv`，
    // 解析 stdout 中的 `info depth ... pv ...` 行。
    throw UnimplementedError('PikafishBridge.analyze() not implemented');
  }

  @override
  Future<Move?> bestMove({int depth = 15}) async {
    final r = await analyze(depth: depth);
    return r?.move;
  }

  // ignore: unused_element
  void _send(String line) {
    _process?.stdin.writeln(line);
  }
}

/// 基于引擎的提示策略（二期）。
class EngineHintStrategy implements HintStrategy {
  EngineHintStrategy(this._bridge, {required this.currentFen});

  final PikafishBridge _bridge;
  String currentFen;

  @override
  Future<Move?> getBestMove() async {
    _bridge.position(currentFen);
    return _bridge.bestMove();
  }
}

/// 基于预录残局破解走法的提示策略（二期）。
class PuzzleSolutionHintStrategy implements HintStrategy {
  PuzzleSolutionHintStrategy(this.solution, {this.currentIndex = 0});

  final List<Move> solution;
  int currentIndex;

  @override
  Future<Move?> getBestMove() async {
    if (currentIndex >= solution.length) return null;
    final m = solution[currentIndex];
    currentIndex += 1;
    return m;
  }
}
