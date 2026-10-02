import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/engine/llm_config.dart';
import '../../shared/engine/llm_move_source.dart';
import '../../shared/engine/llm_settings.dart';
import '../../shared/engine/move_source.dart';
import '../../storage/game_mode.dart';
import '../../storage/repository.dart';
import '../../record/record_saver.dart';
import '../model/board_state.dart';
import '../model/move.dart';
import '../model/move_notation.dart';
import '../viewmodel/board_vm.dart';
import '../viewmodel/game_auto_save.dart';
import '../viewmodel/game_restore.dart';
import 'widgets/board_widget.dart';
import 'widgets/llm_config_editor.dart';
import 'widgets/side_panel.dart';

/// 大模型对战页面（三三核心）。
///
/// 红黑双方各接入一个可独立配置的大模型（OpenAI 兼容端点），
/// 由页面对局循环驱动互弈；模型只"提议"着法，合法性由
/// [BoardViewModel.playMove] 强校验，持续失败按设置降级。
class LlmVsLlmPage extends ConsumerStatefulWidget {
  const LlmVsLlmPage({super.key, this.initialFen});

  /// 棋谱库"进入对战"的起始局面；为空时按标准开局并恢复存档。
  final String? initialFen;

  @override
  ConsumerState<LlmVsLlmPage> createState() => _LlmVsLlmPageState();
}

class _LlmVsLlmPageState extends ConsumerState<LlmVsLlmPage> {
  final LlmConfigStore _configStore = LlmConfigStore();
  final LlmSettingsStore _settingsStore = LlmSettingsStore();

  /// initState 捕获的全局 ViewModel 引用（dispose 时 ref 不可用）。
  late final BoardViewModel _viewModel;

  LlmConfig _redConfig = const LlmConfig();
  LlmConfig _blackConfig = const LlmConfig();

  /// 配置改动自动保存的防抖定时器。
  Timer? _autosaveTimer;

  /// 对局自动保存：离开页面/应用切后台时按全局开关落存档。
  late final GameAutoSave _autoSave;

  /// 对局设置。
  int _timeoutSeconds = 60;
  int _maxAttempts = 3;
  LlmFallback _fallback = LlmFallback.builtinAi;
  int _intervalSeconds = 1;

  bool _isRunning = false;
  bool _isPaused = false;

  /// 状态栏主文案（当前思考方等）。
  String _statusText = '等待开始';

  /// 双方最近一次"思路/说明"。
  String _redNote = '';
  String _blackNote = '';

  /// 最后一步的中文记法。
  String _lastMoveText = '';

  /// 对局代数：新游戏/停止自增，使在途的模型回复作废。
  int _gameSeq = 0;

  static const _timeoutOptions = {
    30: '30 秒',
    60: '60 秒',
    120: '120 秒',
    180: '180 秒',
    300: '300 秒',
  };
  static const _attemptOptions = {1: '1 次', 3: '3 次', 5: '5 次'};
  static const _intervalOptions = {0: '不等待', 1: '1 秒', 2: '2 秒', 5: '5 秒'};
  static const _fallbackNames = {
    LlmFallback.builtinAi: '内置 AI 代走',
    LlmFallback.resign: '该方判负',
  };

  @override
  void initState() {
    super.initState();
    _viewModel = ref.read(boardViewModelProvider.notifier);
    _autoSave = GameAutoSave(
      mode: GameMode.llmVsLlm,
      viewModel: _viewModel,
      // 棋谱来源不写自动存档。
      canSave: () => widget.initialFen == null,
    );
    _loadConfigs();
    _loadSettings();
    // 进入页面恢复上局存档（无存档则开新局），消除全局棋盘残留歧义。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _restoreOrNewGame();
    });
  }

  /// 恢复大模型对战存档；无存档则开新局。
  /// 恢复后不自动续跑对局，由用户点"开始"从当前局面继续。
  /// 棋谱来源（initialFen 非空）不参与存档：直接载入局面，点"开始"续战。
  Future<void> _restoreOrNewGame() async {
    if (widget.initialFen != null) {
      _viewModel.newGameFromFen(widget.initialFen!);
      return;
    }
    await _autoSave.attach(() async {
      try {
        return await ref.read(gameRepositoryProvider.future);
      } on Object {
        return null; // 存储不可用：对局照常进行，只是不落存档。
      }
    });
    if (!mounted) return;
    final repo = _autoSave.repository;
    if (repo == null) {
      _viewModel.newGame();
      return;
    }
    await restoreOrNewGame(
      repo: repo,
      viewModel: _viewModel,
      mode: GameMode.llmVsLlm,
    );
  }

  /// 手动保存当前棋局（"保存棋局"按钮，不受全局自动保存开关限制）。
  Future<void> _saveGameManually() async {
    if (_autoSave.repository == null) {
      await _autoSave.attach(() async {
        try {
          return await ref.read(gameRepositoryProvider.future);
        } on Object {
          return null;
        }
      });
    }
    final ok = _autoSave.saveManual();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '棋局已保存' : '保存失败：本地存储不可用'),
        backgroundColor: ok ? Colors.green : Colors.red,
      ),
    );
  }

  Future<void> _loadSettings() async {
    final settings = await _settingsStore.load();
    if (!mounted) return;
    setState(() {
      _timeoutSeconds = settings.timeoutSeconds;
      _maxAttempts = settings.maxAttempts;
      _fallback = settings.fallback;
      _intervalSeconds = settings.intervalSeconds;
    });
  }

  /// 配置或设置变化后防抖自动保存，无需手动点击保存。
  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 800), () {
      _saveConfigs(showFeedback: false);
      _settingsStore.save(LlmGameSettings(
        timeoutSeconds: _timeoutSeconds,
        maxAttempts: _maxAttempts,
        fallback: _fallback,
        intervalSeconds: _intervalSeconds,
      ));
    });
  }

  Future<void> _loadConfigs() async {
    final red = await _configStore.loadRed();
    final black = await _configStore.loadBlack();
    if (!mounted) return;
    setState(() {
      _redConfig = red;
      _blackConfig = black;
    });
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    // 离开页面：按全局"自动保存"开关触发棋局保存。
    _autoSave.dispose();
    _saveConfigs(showFeedback: false);
    _settingsStore.save(LlmGameSettings(
      timeoutSeconds: _timeoutSeconds,
      maxAttempts: _maxAttempts,
      fallback: _fallback,
      intervalSeconds: _intervalSeconds,
    ));
    // 对局中途离开页面时解锁棋盘输入，避免全局 ViewModel 残留锁定。
    _viewModel.unlockInput();
    super.dispose();
  }

  Future<void> _saveConfigs({bool showFeedback = true}) async {
    try {
      await _configStore.saveRed(_redConfig);
      await _configStore.saveBlack(_blackConfig);
      if (!mounted || !showFeedback) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('双方模型配置已保存'), backgroundColor: Colors.green),
      );
    } on Object {
      if (!mounted || !showFeedback) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存失败：安全存储不可用'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('大模型对战'),
        actions: [
          IconButton(
            icon: Icon(_isRunning && !_isPaused ? Icons.pause : Icons.play_arrow),
            onPressed: _isRunning ? _togglePause : _start,
            tooltip: _isRunning ? (_isPaused ? '继续' : '暂停') : '开始对战',
          ),
          IconButton(
            icon: const Icon(Icons.stop),
            onPressed: _isRunning ? _stop : null,
            tooltip: '停止',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _newGame,
            tooltip: '新游戏',
          ),
          RecordSaver.button(context, ref, mode: GameMode.llmVsLlm),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: OrientationBuilder(
              builder: (context, orientation) {
                final isPortrait = orientation == Orientation.portrait;
                if (isPortrait) {
                  return Column(
                    children: [
                      Expanded(flex: 7, child: _buildBoardArea()),
                      Expanded(flex: 3, child: _buildSidePanel()),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(flex: 3, child: _buildBoardArea()),
                    const SizedBox(width: 12),
                    Expanded(flex: 1, child: _buildSidePanel()),
                  ],
                );
              },
            ),
          ),
          _buildStatusArea(),
        ],
      ),
    );
  }

  Widget _buildBoardArea() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 600,
          constraints.maxHeight.isFinite ? constraints.maxHeight : 600,
        );
        return Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            // 双方均为自动走子，无需响应棋盘点击回调。
            child: BoardWidget(),
          ),
        );
      },
    );
  }

  Widget _buildSidePanel() {
    final state = ref.watch(boardViewModelProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ResultBanner(state: state),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LlmConfigEditor(
                      title: '红方模型',
                      titleColor: Colors.red,
                      config: _redConfig,
                      onChanged: (config) {
                        setState(() => _redConfig = config);
                        _scheduleAutosave();
                      },
                    ),
                    const SizedBox(height: 12),
                    LlmConfigEditor(
                      title: '黑方模型',
                      titleColor: Colors.black,
                      config: _blackConfig,
                      onChanged: (config) {
                        setState(() => _blackConfig = config);
                        _scheduleAutosave();
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildGameSettings(),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.save),
                      label: const Text('立即保存'),
                      onPressed: () => _saveConfigs(),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 40),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '走法记录',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Expanded(child: MoveRecordsList(state: state)),
          ],
        ),
      ),
    );
  }

  Widget _buildGameSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '对局设置',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        _buildDropdownTile(
          label: '空闲超时',
          value: _timeoutSeconds,
          items: _timeoutOptions,
          onChanged: (value) {
            setState(() => _timeoutSeconds = value);
            _scheduleAutosave();
          },
        ),
        _buildDropdownTile(
          label: '无效回复重试',
          value: _maxAttempts,
          items: _attemptOptions,
          onChanged: (value) {
            setState(() => _maxAttempts = value);
            _scheduleAutosave();
          },
        ),
        _buildDropdownTile(
          label: '模型持续失败时',
          value: _fallback,
          items: _fallbackNames,
          onChanged: (value) {
            setState(() => _fallback = value);
            _scheduleAutosave();
          },
        ),
        _buildDropdownTile(
          label: '走棋间隔',
          value: _intervalSeconds,
          items: _intervalOptions,
          onChanged: (value) {
            setState(() => _intervalSeconds = value);
            _scheduleAutosave();
          },
        ),
      ],
    );
  }

  Widget _buildDropdownTile<T>({
    required String label,
    required T value,
    required Map<T, String> items,
    required ValueChanged<T> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(width: 110, child: Text(label, style: const TextStyle(fontSize: 13))),
        Expanded(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            items: [
              for (final entry in items.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (item) {
              if (item != null) onChanged(item);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatusArea() {
    final state = ref.watch(boardViewModelProvider);
    final resultText = switch (state.result) {
      GameResult.redWins => '对局结束：红方获胜',
      GameResult.blackWins => '对局结束：黑方获胜',
      GameResult.draw => '对局结束：和棋',
      null => null,
    };
    final mainText = resultText ?? _statusText;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.05),
        border: Border(
          top: BorderSide(color: Colors.blue.withOpacity(0.2)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                _isRunning && !_isPaused
                    ? Icons.smart_toy
                    : (state.result != null ? Icons.emoji_events : Icons.check_circle),
                color: _isRunning && !_isPaused ? Colors.blue : Colors.green,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  mainText,
                  style: TextStyle(
                    color: _isRunning && !_isPaused ? Colors.blue : Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (_isRunning && !_isPaused)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue),
                ),
            ],
          ),
          if (_redNote.isNotEmpty)
            _noteLine('红方：', _redNote, Colors.red),
          if (_blackNote.isNotEmpty)
            _noteLine('黑方：', _blackNote, Colors.black87),
          if (_lastMoveText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '最后走法: $_lastMoveText',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }

  Widget _noteLine(String label, String note, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        '$label$note',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: color),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 对局循环
  // ---------------------------------------------------------------------------

  void _start() {
    if (!_redConfig.isConfigured || !_blackConfig.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先为红黑双方填写端点地址与模型 ID'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() {
      _isRunning = true;
      _isPaused = false;
    });
    // 自动对局期间锁定棋盘点击，防止人为干预局面。
    ref.read(boardViewModelProvider.notifier).lockInput();
    _runLoop();
  }

  void _togglePause() {
    if (!_isRunning) return;
    setState(() {
      _isPaused = !_isPaused;
      _statusText = _isPaused ? '已暂停' : '继续对局…';
    });
    if (!_isPaused) _runLoop();
  }

  void _stop() {
    _gameSeq++;
    ref.read(boardViewModelProvider.notifier).unlockInput();
    setState(() {
      _isRunning = false;
      _isPaused = false;
      _statusText = '已停止';
    });
  }

  void _newGame() {
    _gameSeq++;
    setState(() {
      _isRunning = false;
      _isPaused = false;
      _statusText = '等待开始';
      _redNote = '';
      _blackNote = '';
      _lastMoveText = '';
    });
    if (widget.initialFen != null) {
      _viewModel.newGameFromFen(widget.initialFen!);
      return;
    }
    _viewModel.newGame();
  }

  /// 对局主循环：红黑交替请模型应手。
  ///
  /// 通过 [_gameSeq] 代数实现取消；暂停在两手之间生效（在途请求返回后搁置）。
  Future<void> _runLoop() async {
    final seq = _gameSeq;
    while (mounted && seq == _gameSeq && _isRunning && !_isPaused) {
      final state = ref.read(boardViewModelProvider);
      if (state.isFinished) {
        ref.read(boardViewModelProvider.notifier).unlockInput();
        setState(() => _isRunning = false);
        return;
      }

      final viewModel = ref.read(boardViewModelProvider.notifier);
      final isRedTurn = state.isRedTurn;
      final config = isRedTurn ? _redConfig : _blackConfig;
      setState(() {
        _statusText =
            '${isRedTurn ? '红方' : '黑方'}（${config.model.trim()}）思考中…';
      });

      // await 前快照棋盘与历史。
      final boardSnapshot = viewModel.board.copy();
      final history = List<Move>.from(state.moveHistory);
      final source = LlmMoveSource(
        config: config,
        timeout: Duration(seconds: _timeoutSeconds),
        maxAttempts: _maxAttempts,
        fallback: _fallback,
      );
      final result = await source.nextMove(boardSnapshot, history: history);

      // 请求在途期间可能已停止/暂停/重开：作废本次结果。
      if (!mounted || seq != _gameSeq) return;
      if (_isPaused) {
        setState(() => _statusText = '已暂停（模型回复已作废，继续后重新思考）');
        return;
      }

      switch (result.status) {
        case MoveSourceStatus.ok:
          final move = result.move!;
          final applied = viewModel.playMove(move.from, move.to);
          if (!applied) {
            // nextMove 内部已按合法清单校验，此处为极端兜底：终止本方。
            _onSideFailed(isRedTurn, '着法未通过最终校验');
            return;
          }
          final piece = move.piece;
          final notation = piece == null
              ? '${move.from}→${move.to}'
              : move.chineseNotation(piece);
          setState(() {
            _lastMoveText = '${isRedTurn ? '红方' : '黑方'} $notation';
            if (result.fromFallback) {
              _setNote(isRedTurn, result.note ?? '已由内置 AI 兜底走子');
            } else if (result.note != null && result.note!.isNotEmpty) {
              _setNote(isRedTurn, result.note!);
            }
          });
          final interval = _intervalSeconds;
          if (interval > 0) {
            await Future<void>.delayed(Duration(seconds: interval));
            if (!mounted || seq != _gameSeq || _isPaused) return;
          }
        case MoveSourceStatus.noLegalMove:
          // 棋局已分出胜负，下一轮循环检测 isFinished 后退出。
          setState(() => _statusText = '该方已无合法着法');
          return;
        case MoveSourceStatus.failed:
          _onSideFailed(isRedTurn, result.note ?? '未知原因');
          return;
      }
    }
  }

  void _setNote(bool isRed, String note) {
    if (isRed) {
      _redNote = note;
    } else {
      _blackNote = note;
    }
  }

  void _onSideFailed(bool isRed, String reason) {
    _gameSeq++;
    ref.read(boardViewModelProvider.notifier).unlockInput();
    setState(() {
      _isRunning = false;
      _statusText = '${isRed ? '红方' : '黑方'}走子失败，对局终止';
      _setNote(isRed, reason);
    });
  }
}
