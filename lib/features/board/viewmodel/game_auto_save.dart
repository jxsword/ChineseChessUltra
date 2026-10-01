import 'package:flutter/widgets.dart';

import '../../storage/game_mode.dart';
import '../../storage/repository.dart';
import '../../settings/global_settings.dart';
import 'board_vm.dart';

/// 对局页面的"自动保存"挂接。
///
/// 触发时机：离开棋盘页面（dispose）与应用切后台（paused/hidden），
/// 且全局设置"自动保存"开启时，把当前棋局静默落入 [mode] 存档桶。
/// 全局开关关闭时不做任何自动保存，持久化只来自页面上的"保存棋局"按钮。
class GameAutoSave with WidgetsBindingObserver {
  GameAutoSave({
    required this.mode,
    required BoardViewModel viewModel,
    bool Function()? canSave,
  })  : _viewModel = viewModel,
        _canSave = canSave;

  final GameMode mode;
  final BoardViewModel _viewModel;

  /// 页面级附加条件（如残局模式不参与保存）。返回 false 时不保存。
  final bool Function()? _canSave;

  GameRepository? _repo;
  bool _observerAdded = false;

  /// 已加载的仓库（页面恢复流程复用同一次读取）。
  GameRepository? get repository => _repo;

  /// 页面 initState 后调用：加载仓库并注册应用生命周期监听。
  ///
  /// [repoLoader] 由页面提供（内部读 gameRepositoryProvider.future）。
  Future<void> attach(Future<GameRepository?> Function() repoLoader) async {
    _repo ??= await repoLoader();
    _ensureObserver();
  }

  /// 页面已有仓库实例时直接注入（与既有恢复流程共用一次读取）。
  void adopt(GameRepository repo) {
    _repo = repo;
    _ensureObserver();
  }

  void _ensureObserver() {
    if (!_observerAdded) {
      WidgetsBinding.instance.addObserver(this);
      _observerAdded = true;
    }
  }

  /// 手动保存（页面"保存棋局"按钮）：不受全局开关限制。
  bool saveManual() => _write();

  /// 自动保存（离开/后台触发）：受全局开关与页面条件限制。
  void saveOnExit() {
    if (!GlobalSettings.instance.autoSave) return;
    _write();
  }

  bool _write() {
    if (_canSave != null && !_canSave()) return false;
    final repo = _repo;
    if (repo == null) return false;
    final data = _viewModel.serialize();
    repo.saveGame(mode: mode, fen: data.fen, moves: data.moves);
    return true;
  }

  /// 页面 dispose 时调用：先触发离开保存，再注销生命周期监听。
  void dispose() {
    saveOnExit();
    if (_observerAdded) {
      WidgetsBinding.instance.removeObserver(this);
      _observerAdded = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // paused：移动端切后台；hidden：窗口不可见/最小化（桌面端）。
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      saveOnExit();
    }
  }
}
