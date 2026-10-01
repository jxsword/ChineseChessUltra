import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/engine/ai_engine.dart';
import '../model/board_state.dart';
import '../model/move.dart';
import '../model/piece.dart';
import '../viewmodel/board_vm.dart';
import '../view/widgets/board_widget.dart';
import '../view/widgets/side_panel.dart';

/// 人机对战页面。
///
/// 玩家执 [playerSide]（默认红方），AI 执对方棋子。玩家走子完成后
/// （[BoardWidget.onMoved] 回调），在独立 Isolate 中用内置引擎计算应手
/// 并落到棋盘上。
///
/// 传入 [initialFen]（如残局闯关）时以该局面开局：轮走方由 FEN 决定，
/// 若开局即轮到 AI，AI 会先行一步。玩家获胜/失败时（残局模式）弹通关提示。
class HumanVsAiPage extends ConsumerStatefulWidget {
  const HumanVsAiPage({
    super.key,
    this.initialFen,
    this.playerSide = Side.red,
  });

  /// 可选的起始局面（默认为标准开局）。
  final String? initialFen;

  /// 玩家执子方（默认红方）。
  final Side playerSide;

  @override
  ConsumerState<HumanVsAiPage> createState() => _HumanVsAiPageState();
}

class _HumanVsAiPageState extends ConsumerState<HumanVsAiPage> {
  bool _isAiThinking = false;

  /// 全局棋盘 VM 引用（dispose 中需解锁，避免再使用 ref）。
  late final BoardViewModel _boardViewModel;

  /// AI 难度（1-5，对应内置引擎搜索强度）。
  int _difficulty = 3;

  /// 对局代数：新游戏/悔棋后自增，使过期的 AI 计算结果作废。
  int _gameSeq = 0;

  /// 残局模式结果弹窗是否已展示（防重入）。
  bool _resultDialogShown = false;

  static const _difficultyNames = {1: '初级', 2: '中级', 3: '高级', 4: '专家', 5: '大师'};

  /// 玩家执子方。
  Side get _playerSide => widget.playerSide;

  /// AI 执子方。
  Side get _aiSide => _playerSide.opponent;

  String get _playerSideName => _playerSide == Side.red ? '红' : '黑';
  String get _aiSideName => _aiSide == Side.red ? '红' : '黑';

  /// 当前是否轮到 AI 走子。
  bool _isAiTurn() {
    final isRedTurn = ref.read(boardViewModelProvider.notifier).board.isRedTurn;
    return (_aiSide == Side.red) == isRedTurn;
  }

  @override
  void dispose() {
    _gameSeq++; // 作废仍在计算中的 AI 应手
    // AI 思考中离开页面时锁尚未释放，必须在此兜底解锁，
    // 否则全局输入锁泄漏导致棋盘永久不可点击。
    _boardViewModel.unlockInput();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _boardViewModel = ref.read(boardViewModelProvider.notifier);
    final initialFen = widget.initialFen;
    // Riverpod 不允许在 widget 树构建期间修改 provider，延后到首帧后。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (initialFen != null) {
        _boardViewModel.newGameFromFen(initialFen);
        // 开局即轮到 AI：让 AI 先行。
        if (_isAiTurn() && ref.read(boardViewModelProvider).result == null) {
          _triggerAiMove();
        }
      } else {
        // 无参进入（如从残局对局返回主页后再进）必须重置全局棋盘，
        // 清掉残局局面 / 胜负横幅 / 输入锁残留。
        _boardViewModel.newGame();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // 残局模式：胜负揭晓时弹通关 / 惜败提示。
    if (widget.initialFen != null) {
      ref.listen<BoardState>(boardViewModelProvider, (prev, next) {
        if (prev?.result != null || next.result == null) return;
        if (_resultDialogShown) return;
        _resultDialogShown = true;
        final playerWon =
            (next.result == GameResult.redWins) == (_playerSide == Side.red);
        _showPuzzleResultDialog(playerWon);
      });
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initialFen != null
            ? '残局人机对战（玩家执$_playerSideName方）'
            : '人机对战',),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _newGame,
            tooltip: '新游戏',
          ),
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
                      Expanded(
                        flex: 7,
                        child: _buildBoardArea(),
                      ),
                      Expanded(
                        flex: 3,
                        child: _buildSidePanel(),
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _buildBoardArea(),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: _buildSidePanel(),
                    ),
                  ],
                );
              },
            ),
          ),
          _buildAiStatus(),
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
            // 胜负结果横幅（对局结束时显示）。
            ResultBanner(state: state),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '对战设置',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildAiLevelSelector(),
                    const SizedBox(height: 16),
                    _buildActionButtons(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '走法记录',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Expanded(child: MoveRecordsList(state: state)),
          ],
        ),
      ),
    );
  }

  Widget _buildAiLevelSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'AI 难度',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButton<int>(
          value: _difficulty,
          items: [
            for (final level in _difficultyNames.keys)
              DropdownMenuItem(value: level, child: Text(_difficultyNames[level]!)),
          ],
          onChanged: _isAiThinking
              ? null
              : (value) {
                  if (value != null) {
                    setState(() => _difficulty = value);
                  }
                },
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        ElevatedButton.icon(
          icon: const Icon(Icons.refresh),
          label: const Text('新游戏'),
          onPressed: _newGame,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 40),
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          icon: const Icon(Icons.undo),
          label: const Text('悔棋'),
          onPressed: _isAiThinking ? null : _undoMove,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 40),
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          icon: const Icon(Icons.save),
          label: const Text('保存棋局'),
          onPressed: _saveGame,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 40),
          ),
        ),
      ],
    );
  }

  Widget _buildAiStatus() {
    final state = ref.watch(boardViewModelProvider);
    final String text;
    final Color color;
    if (state.result != null) {
      text = switch (state.result!) {
        GameResult.redWins => '对局结束：红方获胜',
        GameResult.blackWins => '对局结束：黑方获胜',
        GameResult.draw => '对局结束：和棋',
      };
      color = Colors.blue;
    } else if (_isAiThinking) {
      text = 'AI 正在思考...';
      color = Colors.orange;
    } else if (state.isCheck) {
      final checkedSide = state.isRedTurn ? '红' : '黑';
      text = '等待玩家（$_playerSideName方）走棋（$checkedSide方被将军！）';
      color = Colors.red;
    } else {
      text = '等待玩家（$_playerSideName方）走棋';
      color = Colors.green;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      color: color.withValues(alpha: 0.08),
      child: Row(
        children: [
          Icon(
            _isAiThinking ? Icons.hourglass_empty : Icons.check_circle,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (_isAiThinking)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.orange,
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 对局控制
  // ---------------------------------------------------------------------------

  /// 残局模式：对局结束后弹通关 / 惜败提示。
  void _showPuzzleResultDialog(bool playerWon) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          playerWon ? Icons.emoji_events : Icons.sentiment_dissatisfied,
          size: 48,
          color: playerWon ? Colors.amber : Colors.grey,
        ),
        title: Text(playerWon ? '残局闯关成功！' : '闯关失败'),
        content: Text(playerWon
            ? '恭喜你执$_playerSideName方取得胜利，可再来一局或返回残局。'
            : '再接再厉，可以重试或换一种攻杀思路。',),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _newGame();
            },
            child: Text(playerWon ? '再来一局' : '重试'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              Navigator.of(context).pop(); // 返回残局详情页
            },
            child: const Text('返回'),
          ),
        ],
      ),
    );
  }

  void _newGame() {
    _gameSeq++; // 作废仍在计算中的 AI 应手
    _resultDialogShown = false;
    final viewModel = ref.read(boardViewModelProvider.notifier);
    final initialFen = widget.initialFen;
    if (initialFen != null) {
      // 残局闯关：重开仍回到残局起始局面。
      viewModel.newGameFromFen(initialFen);
    } else {
      viewModel.newGame();
    }
    if (_isAiTurn()) {
      // 开局即轮到 AI（如黑先残局 / 玩家执黑）：AI 先行。
      setState(() => _isAiThinking = false);
      _triggerAiMove();
      return;
    }
    setState(() => _isAiThinking = false);
  }

  void _undoMove() {
    _gameSeq++; // 作废仍在计算中的 AI 应手（防御性，正常悔棋时 AI 不在思考）
    ref.read(boardViewModelProvider.notifier).undoRound(playerSide: _playerSide);
  }

  void _saveGame() {
    // TODO: 实现保存棋局功能（接通 sqlite 链路后再改回成功提示）。
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('保存功能开发中')),
    );
  }

  /// 玩家走子完成后的回调：对局未结束则轮到 AI 应手。
  void _onMoveFinished() {
    final state = ref.read(boardViewModelProvider);
    if (state.result != null) return;
    _triggerAiMove();
  }

  /// 在独立 Isolate 中计算 AI 应手，避免阻塞 UI。
  Future<void> _triggerAiMove() async {
    final viewModel = ref.read(boardViewModelProvider.notifier);
    // 必须在 await 前完成：棋盘快照与难度值要能被发送到 Isolate。
    final boardSnapshot = viewModel.board.copy();
    final difficulty = _difficulty;
    final seq = _gameSeq;

    viewModel.lockInput();
    setState(() => _isAiThinking = true);

    Move? bestMove;
    try {
      bestMove = await Isolate.run(
        () => ChessAi.findBestMove(boardSnapshot, difficulty: difficulty),
      );
    } on Object {
      // Isolate 不可用时（极少数平台限制）退化为同步计算。
      bestMove = ChessAi.findBestMove(boardSnapshot, difficulty: difficulty);
    }

    if (!mounted || seq != _gameSeq) {
      // 页面已离开或对局已重开/悔棋：无条件解锁，避免全局输入锁泄漏
      // （重开路径本就会复位锁，此处多解一次无害）。
      viewModel.unlockInput();
      return;
    }

    setState(() => _isAiThinking = false);
    viewModel.unlockInput();

    // null 通常意味着 AI 已无合法走法（将死/困毙），结果由棋盘状态呈现。
    if (bestMove == null) return;
    final applied = viewModel.playMove(bestMove.from, bestMove.to);
    assert(() {
      if (!applied) {
        // ignore: avoid_print
        print('AI 应手被拒绝: $bestMove');
      }
      return true;
    }());
  }
}
