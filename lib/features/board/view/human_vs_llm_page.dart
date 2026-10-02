import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/engine/llm_config.dart';
import '../../shared/engine/llm_config_store.dart';
import '../../shared/engine/llm_move_source.dart';
import '../../shared/engine/hybrid_llm_move_source.dart';
import '../../shared/engine/llm_settings.dart';
import '../../shared/engine/move_source.dart';
import '../../storage/game_mode.dart';
import '../../storage/repository.dart';
import '../../record/record_saver.dart';
import '../model/board_state.dart';
import '../model/move.dart';
import '../viewmodel/board_vm.dart';
import '../viewmodel/game_auto_save.dart';
import '../viewmodel/game_restore.dart';
import 'widgets/board_widget.dart';
import 'widgets/llm_config_editor.dart';
import 'widgets/side_panel.dart';

/// 人机对战（大模型）页面。
///
/// 玩家执红先行，黑方由用户配置的大模型控制（OpenAI 兼容端点）。
/// 模型只"提议"着法，最终合法性由 [BoardViewModel.playMove] 强校验；
/// 模型连续无效时按页面设置降级（内置 AI 兜底 / 判负）。
class HumanVsLlmPage extends ConsumerStatefulWidget {
  const HumanVsLlmPage({super.key, this.initialFen});

  /// 棋谱库"进入对战"的起始局面；为空时按标准开局并恢复存档。
  ///
  /// 非空时玩家仍执红、模型执黑：FEN 轮黑则模型先行。
  final String? initialFen;

  @override
  ConsumerState<HumanVsLlmPage> createState() => _HumanVsLlmPageState();
}

class _HumanVsLlmPageState extends ConsumerState<HumanVsLlmPage> {
  final LlmConfigStore _configStore = LlmConfigStore();
  final LlmSettingsStore _settingsStore = LlmSettingsStore();

  /// initState 捕获的全局 ViewModel 引用（dispose 时 ref 不可用）。
  late final BoardViewModel _viewModel;

  /// 黑方模型配置（initState 异步加载）。
  LlmConfig _blackConfig = const LlmConfig();

  /// 配置改动自动保存的防抖定时器。
  Timer? _autosaveTimer;

  /// 对局自动保存：离开页面/应用切后台时按全局开关落存档。
  late final GameAutoSave _autoSave;

  /// 对局设置。
  int _timeoutSeconds = 60;
  int _maxAttempts = 3;
  LlmFallback _fallback = LlmFallback.builtinAi;
  AdvisorMode _advisorMode = AdvisorMode.candidate;
  int _strengthBlend = 50;
  int _advisorDifficulty = 5;

  bool _isLlmThinking = false;

  /// 模型思路 / 错误说明（状态栏展示）。
  String _llmNote = '';

  /// 对局代数：新游戏后自增，使过期的模型回复作废。
  int _gameSeq = 0;

  static const _timeoutOptions = {
    30: '30 秒',
    60: '60 秒',
    120: '120 秒',
    180: '180 秒',
    300: '300 秒',
  };
  static const _attemptOptions = {1: '1 次', 3: '3 次', 5: '5 次'};
  static const _fallbackNames = {
    LlmFallback.builtinAi: '内置 AI 代走',
    LlmFallback.resign: '该方判负',
  };

  @override
  void initState() {
    super.initState();
    _viewModel = ref.read(boardViewModelProvider.notifier);
    _autoSave = GameAutoSave(
      mode: GameMode.humanVsLlm,
      viewModel: _viewModel,
    );
    _loadConfig();
    _loadSettings();
    // 进入页面恢复上局存档（无存档则开新局），消除全局棋盘残留歧义。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _restoreOrNewGame();
    });
  }

  /// 恢复大模型人机对弈存档；无存档则开新局。
  ///
  /// 棋谱来源（initialFen 非空）不参与存档：直接开局，轮黑则模型先行。
  Future<void> _restoreOrNewGame() async {
    if (widget.initialFen != null) {
      _viewModel.newGameFromFen(widget.initialFen!);
      if (!_viewModel.current.isRedTurn && !_viewModel.current.isFinished) {
        _triggerLlmMove();
      }
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
    final outcome = await restoreOrNewGame(
      repo: repo,
      viewModel: _viewModel,
      mode: GameMode.humanVsLlm,
    );
    if (!mounted || outcome != RestoreOutcome.restored) return;
    // 恢复后若轮到黑方（上次退出时模型还没应手），续上模型思考。
    if (!_viewModel.current.isRedTurn && !_viewModel.current.isFinished) {
      _triggerLlmMove();
    }
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
      _advisorMode = settings.advisorMode;
      _strengthBlend = settings.strengthBlend;
      _advisorDifficulty = settings.advisorDifficulty;
    });
  }

  /// 配置或设置变化后防抖自动保存，无需手动点击保存。
  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 800), () {
      _saveConfig(showFeedback: false);
      _settingsStore.save(LlmGameSettings(
        timeoutSeconds: _timeoutSeconds,
        maxAttempts: _maxAttempts,
        fallback: _fallback,
        advisorMode: _advisorMode,
        strengthBlend: _strengthBlend,
        advisorDifficulty: _advisorDifficulty,
      ));
    });
  }

  Future<void> _loadConfig() async {
    final config = await _configStore.loadBlack();
    if (!mounted) return;
    setState(() => _blackConfig = config);
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    // 离开页面：按全局"自动保存"开关触发棋局保存。
    _autoSave.dispose();
    _saveConfig(showFeedback: false);
    _settingsStore.save(LlmGameSettings(
      timeoutSeconds: _timeoutSeconds,
      maxAttempts: _maxAttempts,
      fallback: _fallback,
      advisorMode: _advisorMode,
      strengthBlend: _strengthBlend,
      advisorDifficulty: _advisorDifficulty,
    ));
    // 模型思考途中离开页面时解锁棋盘输入，避免全局 ViewModel 残留锁定。
    _viewModel.unlockInput();
    super.dispose();
  }

  Future<void> _saveConfig({bool showFeedback = true}) async {
    try {
      await _configStore.saveBlack(_blackConfig);
      if (!mounted || !showFeedback) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('模型配置已保存'), backgroundColor: Colors.green),
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
        title: const Text('人机对战（大模型）'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _newGame,
            tooltip: '新游戏',
          ),
          RecordSaver.button(context, ref, mode: GameMode.humanVsLlm),
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
            child: BoardWidget(onMoved: _onMoveFinished),
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
                      title: '黑方模型（对手）',
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
                      onPressed: () => _saveConfig(),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 40),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.bookmark),
                      label: const Text('保存棋局'),
                      onPressed: _saveGameManually,
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
          enabled: !_isLlmThinking,
          onChanged: (value) {
            setState(() => _timeoutSeconds = value);
            _scheduleAutosave();
          },
        ),
        _buildDropdownTile(
          label: '无效回复重试',
          value: _maxAttempts,
          items: _attemptOptions,
          enabled: !_isLlmThinking,
          onChanged: (value) {
            setState(() => _maxAttempts = value);
            _scheduleAutosave();
          },
        ),
        _buildDropdownTile(
          label: '模型持续失败时',
          value: _fallback,
          items: _fallbackNames,
          enabled: !_isLlmThinking,
          onChanged: (value) {
            setState(() => _fallback = value);
            _scheduleAutosave();
          },
        ),
        _buildDropdownTile(
          label: '引擎参谋',
          value: _advisorMode,
          items: const {
            AdvisorMode.off: '关闭（纯大模型）',
            AdvisorMode.candidate: '候选模式（引擎出名单）',
            AdvisorMode.gate: '护航模式（引擎否决）',
          },
          enabled: !_isLlmThinking,
          onChanged: (value) {
            setState(() => _advisorMode = value);
            _scheduleAutosave();
          },
        ),
        if (_advisorMode != AdvisorMode.off) ...[
          _buildDropdownTile(
            label: '参谋强度',
            value: _strengthBlend,
            items: const {
              0: '0（最严/最稳）',
              25: '25',
              50: '50（均衡）',
              75: '75',
              100: '100（最自由）',
            },
            enabled: !_isLlmThinking,
            onChanged: (value) {
              setState(() => _strengthBlend = value);
              _scheduleAutosave();
            },
          ),
          _buildDropdownTile(
            label: '参谋深度',
            value: _advisorDifficulty,
            items: const {1: '快（2 层）', 3: '中（4 层）', 5: '强（6 层）'},
            enabled: !_isLlmThinking,
            onChanged: (value) {
              setState(() => _advisorDifficulty = value);
              _scheduleAutosave();
            },
          ),
        ],
      ],
    );
  }

  Widget _buildDropdownTile<T>({
    required String label,
    required T value,
    required Map<T, String> items,
    required ValueChanged<T> onChanged,
    bool enabled = true,
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
            onChanged: enabled
                ? (item) {
                    if (item != null) onChanged(item);
                  }
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusArea() {
    final state = ref.watch(boardViewModelProvider);
    final (text, color, icon) = _statusOf(state);
    return Container(
      padding: const EdgeInsets.all(16),
      color: color.withOpacity(0.08),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ),
          if (_isLlmThinking)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
            ),
        ],
      ),
    );
  }

  (String, Color, IconData) _statusOf(BoardState state) {
    if (state.result != null) {
      final text = switch (state.result!) {
        GameResult.redWins => '对局结束：红方获胜',
        GameResult.blackWins => '对局结束：黑方获胜',
        GameResult.draw => '对局结束：和棋',
      };
      return (text, Colors.blue, Icons.emoji_events);
    }
    if (_isLlmThinking) {
      final model = _blackConfig.model.trim();
      final label = model.isEmpty ? '大模型' : model;
      return ('黑方 $label 正在思考…', Colors.orange, Icons.hourglass_empty);
    }
    if (_llmNote.isNotEmpty) {
      return (_llmNote, Colors.deepPurple, Icons.psychology);
    }
    if (state.isCheck) {
      return ('轮到你走棋（红方被将军！）', Colors.red, Icons.warning_amber);
    }
    return ('轮到你走棋（红方）', Colors.green, Icons.check_circle);
  }

  // ---------------------------------------------------------------------------
  // 对局控制
  // ---------------------------------------------------------------------------

  void _newGame() {
    _gameSeq++; // 作废仍在途中的模型回复
    setState(() {
      _isLlmThinking = false;
      _llmNote = '';
    });
    if (widget.initialFen != null) {
      _viewModel.newGameFromFen(widget.initialFen!);
      if (!_viewModel.current.isRedTurn && !_viewModel.current.isFinished) {
        _triggerLlmMove();
      }
      return;
    }
    _viewModel.newGame();
  }

  /// 玩家走子完成：轮到黑方模型应手。
  void _onMoveFinished() {
    final state = ref.read(boardViewModelProvider);
    if (state.result != null) return;
    _triggerLlmMove();
  }

  Future<void> _triggerLlmMove() async {
    final viewModel = ref.read(boardViewModelProvider.notifier);
    // await 前快照：棋盘、历史与代数。
    final boardSnapshot = viewModel.board.copy();
    final history = List<Move>.from(ref.read(boardViewModelProvider).moveHistory);
    final seq = _gameSeq;

    setState(() {
      _isLlmThinking = true;
      _llmNote = '';
    });
    viewModel.lockInput(); // 模型思考期间锁定棋盘，防止替对方走子

    final source = HybridLlmMoveSource(
      config: _blackConfig,
      advisorMode: _advisorMode,
      strengthBlend: _strengthBlend,
      advisorDifficulty: _advisorDifficulty,
      timeout: Duration(seconds: _timeoutSeconds),
      maxAttempts: _maxAttempts,
      fallback: _fallback,
    );
    final result = await source.nextMove(boardSnapshot, history: history);

    if (!mounted || seq != _gameSeq) return;
    setState(() => _isLlmThinking = false);
    viewModel.unlockInput();

    switch (result.status) {
      case MoveSourceStatus.ok:
        final move = result.move!;
        final applied = viewModel.playMove(move.from, move.to);
        setState(() {
          _llmNote = result.fromFallback
              ? (result.note ?? '已由内置 AI 兜底走子')
              : '黑方走子完成';
        });
        if (!applied) {
          setState(() => _llmNote = '黑方着法未通过校验，被拒绝');
        }
      case MoveSourceStatus.noLegalMove:
        // 无合法着法意味着已分出胜负，结果由棋盘状态呈现。
        setState(() => _llmNote = '');
      case MoveSourceStatus.failed:
        setState(() => _llmNote = '黑方走子失败：${result.note ?? '未知原因'}');
    }
  }
}
