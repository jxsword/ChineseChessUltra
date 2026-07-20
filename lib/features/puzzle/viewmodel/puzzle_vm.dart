import '../../board/model/move.dart';

/// 残局对弈 ViewModel（二期）。
///
/// 第一期仅保留骨架，注入 [HintStrategy]，由 UI 在"提示"按钮触发。
class PuzzleViewModel {
  PuzzleViewModel({HintStrategy? hintStrategy}) : _hintStrategy = hintStrategy;

  HintStrategy? _hintStrategy;

  /// 当前残局。
  // ignore: unused_field
  // final Puzzle? _puzzle = null;

  /// 提示策略（二期可换为引擎实时分析）。
  HintStrategy? get hintStrategy => _hintStrategy;
  set hintStrategy(HintStrategy? strategy) => _hintStrategy = strategy;

  /// 获取下一步破解提示。
  ///
  /// 第一期返回 null，表示无提示。
  Future<Move?> getHint() async {
    return _hintStrategy?.getBestMove();
  }
}

/// 提示策略接口（二期）。
///
/// 抽象出"如何决定下一步提示走法"的策略，便于：
/// - [PuzzleSolutionHintStrategy]：优先按残局预录的破解走法演示。
/// - [EngineHintStrategy]：调用 Pikafish 实时计算最佳走法。
abstract interface class HintStrategy {
  /// 返回当前局面下的最佳/建议走法，无建议返回 null。
  Future<Move?> getBestMove();
}
