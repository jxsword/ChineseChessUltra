import '../../storage/game_mode.dart';
import '../../storage/repository.dart';
import 'board_vm.dart';

/// 进入对局页面时的存档恢复结果。
enum RestoreOutcome {
  /// 已从存档恢复局面。
  restored,

  /// 无存档或存档已分胜负（死局），已开新局。
  newGame,
}

/// 进入对局页面时按模式恢复存档。
///
/// - 有该模式存档且 FEN 有效：重放到全局棋盘，返回 [RestoreOutcome.restored]。
/// - 存档重放后已分胜负：视为死局，清掉该存档并开新局，避免每次进入
///   都恢复到同一盘已结束的棋。
/// - 无存档、FEN 无效或存储异常：开新局。
///
/// 调用方应在 await 前后自行检查 `mounted`。
Future<RestoreOutcome> restoreOrNewGame({
  required GameRepository repo,
  required BoardViewModel viewModel,
  required GameMode mode,
}) async {
  final saved = repo.loadLatest(mode);
  if (saved != null && isValidFen(saved.fen)) {
    viewModel.restore(fen: saved.fen, moves: saved.moves);
    // restore() 在 microtask 中更新 state，先让出事件循环再判断终局。
    await Future<void>.delayed(Duration.zero);
    if (viewModel.current.result != null) {
      repo.deleteForMode(mode);
      viewModel.newGame();
      return RestoreOutcome.newGame;
    }
    return RestoreOutcome.restored;
  }
  viewModel.newGame();
  return RestoreOutcome.newGame;
}
