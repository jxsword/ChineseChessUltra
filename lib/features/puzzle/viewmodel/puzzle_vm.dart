import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';

import '../../board/model/board.dart';
import '../../board/model/move.dart';
import '../model/puzzle_data.dart';

/// 残局演示 ViewModel
///
/// 演示时内部持有一块独立于对局 BoardViewModel 的 [Board]，
/// 按定时器逐条把破解走法（ICCS 字符串）应用到棋盘上，
/// 并通过 [PuzzleState.fen] / [PuzzleState.lastMove] 通知 UI 刷新。
class PuzzleViewModel extends Notifier<PuzzleState> {
  ParsedPuzzle? _puzzle;
  PuzzleDemoState _demoState = PuzzleDemoState.idle;

  /// 最近一次已应用到棋盘的走法下标；-1 表示尚未走子。
  int _currentMoveIndex = -1;
  String _currentSide = 'red';
  String? _error;
  Timer? _playTimer;
  PuzzleDemoParams _demoParams = const PuzzleDemoParams();

  /// 演示用棋盘（演示未初始化时为 null）。
  Board? _board;

  /// 最近一步演示走法（用于棋盘高亮）。
  Move? _lastMove;

  /// ICCS 走法字符串（如 "h2e2"、"h10g8"）的解析模式。
  static final RegExp _iccsPattern = RegExp(r'^([a-i])(\d{1,2})([a-i])(\d{1,2})$');

  @override
  PuzzleState build() {
    ref.onDispose(() {
      _playTimer?.cancel();
    });
    return const PuzzleState();
  }

  /// 演示棋盘（供只读渲染使用；未初始化时为 null）。
  Board? get board => _board;

  /// 初始化残局
  ///
  /// 重置演示进度与棋盘，但保留用户已选择的速度（含滑块自定义值），
  /// 避免每次点"播放"都把速度悄悄重置回默认。
  void initializePuzzle(ParsedPuzzle puzzle) {
    _puzzle = puzzle;
    _demoState = PuzzleDemoState.idle;
    _currentMoveIndex = -1;
    _currentSide = 'red';
    _error = null;
    _lastMove = null;
    _playTimer?.cancel();

    // 应用残局到演示棋盘
    try {
      _board = Board.fromFen(puzzle.initialFen);
    } catch (e) {
      _board = null;
      _error = '初始化残局失败: ${e.toString()}';
    }

    state = _composeState();
  }

  /// 开始演示
  void startDemo() {
    if (_puzzle == null || _demoState == PuzzleDemoState.playing) return;

    _demoState = PuzzleDemoState.playing;
    state = _composeState();
    _startTimer();
  }

  /// 暂停演示
  void pauseDemo() {
    if (_demoState != PuzzleDemoState.playing) return;

    _demoState = PuzzleDemoState.paused;
    _playTimer?.cancel();
    state = _composeState();
  }

  /// 继续演示
  void resumeDemo() {
    if (_demoState != PuzzleDemoState.paused || _puzzle == null) return;

    _demoState = PuzzleDemoState.playing;
    state = _composeState();
    _startTimer();
  }

  /// 停止演示
  void stopDemo() {
    _demoState = PuzzleDemoState.idle;
    _currentMoveIndex = -1;
    _currentSide = 'red';
    _lastMove = null;
    _playTimer?.cancel();
    // 重置演示棋盘到初始局面。
    final puzzle = _puzzle;
    if (puzzle != null) {
      try {
        _board = Board.fromFen(puzzle.initialFen);
      } catch (_) {
        _board = null;
      }
    }
    state = _composeState();
  }

  /// 设置演示速度
  void setDemoSpeed(PuzzleDemoParams params) {
    _demoParams = params;
    state = _composeState();
    if (_demoState == PuzzleDemoState.playing) {
      _startTimer();
    }
  }

  /// 设置自定义走子间隔（毫秒/步，供速度滑块调用）。
  void setCustomInterval(int intervalMs) {
    _demoParams = PuzzleDemoParams(moveInterval: intervalMs);
    state = _composeState();
    if (_demoState == PuzzleDemoState.playing) {
      _startTimer();
    }
  }

  /// 设置演示模式
  void setDemoMode(bool loop) {
    _demoParams = _demoParams.copyWith(loop: loop);
  }

  /// 启动（或以新速度重启）走子定时器。
  ///
  /// 间隔按速度倍率换算：慢速 0.5x → 1600ms，正常 1x → 800ms，快速 2x → 400ms。
  void _startTimer() {
    final puzzle = _puzzle;
    if (puzzle == null) return;
    _playTimer?.cancel();
    _playTimer = Timer.periodic(Duration(milliseconds: _demoParams.interval), (_) {
      _onTick();
    });
  }

  /// 定时器心跳：应用下一步走法，或结束/循环演示。
  void _onTick() {
    final puzzle = _puzzle;
    if (puzzle == null || _demoState != PuzzleDemoState.playing) return;

    if (_currentMoveIndex + 1 < puzzle.moves.length) {
      _currentMoveIndex++;
      _currentSide = _currentSide == 'red' ? 'black' : 'red';
      _applyCurrentMove();
      state = _composeState();
    } else {
      _completeDemo();
    }
  }

  /// 把当前步的 ICCS 走法应用到演示棋盘。
  ///
  /// 数据与局面不一致（坐标越界、起点无棋子）时跳过该步，避免崩溃。
  void _applyCurrentMove() {
    final board = _board;
    final puzzle = _puzzle;
    if (board == null || puzzle == null) return;
    if (_currentMoveIndex >= puzzle.moves.length) return;

    final parsed = parseIccs(puzzle.moves[_currentMoveIndex]);
    if (parsed == null) return;

    final mover = board.pieceAtP(parsed.from);
    if (mover == null) return;

    final applied = board.applyMove(Move(from: parsed.from, to: parsed.to));
    _lastMove = Move(
      from: applied.from,
      to: applied.to,
      piece: mover,
      captured: applied.captured,
    );
  }

  /// 解析 ICCS 走法字符串为起止坐标。
  ///
  /// 坐标系：文件 a-i 对应列 0-8（红方视角从左到右），
  /// 行号 0-9（0 为红方底线、9 为黑方底线）；
  /// 兼容个别记谱把黑方底线写成 10 的情况。
  static ({Position from, Position to})? parseIccs(String iccs) {
    final match = _iccsPattern.firstMatch(iccs);
    if (match == null) return null;

    Position? parseSquare(String file, String rankStr) {
      final rank = int.tryParse(rankStr);
      if (rank == null || rank > 10) return null;
      final col = file.codeUnitAt(0) - 'a'.codeUnitAt(0);
      if (col < 0 || col > 8) return null;
      final row = rank >= 10 ? 0 : 9 - rank;
      if (row < 0 || row > 9) return null;
      return Position(col, row);
    }

    final from = parseSquare(match.group(1)!, match.group(2)!);
    final to = parseSquare(match.group(3)!, match.group(4)!);
    if (from == null || to == null) return null;
    return (from: from, to: to);
  }

  /// 完成演示
  void _completeDemo() {
    _demoState = PuzzleDemoState.completed;
    _playTimer?.cancel();

    if (_demoParams.loop) {
      _currentMoveIndex = -1;
      _currentSide = 'red';
      _lastMove = null;
      _demoState = PuzzleDemoState.playing;
      // 循环播放时重置演示棋盘到初始局面。
      final puzzle = _puzzle;
      if (puzzle != null) {
        try {
          _board = Board.fromFen(puzzle.initialFen);
        } catch (_) {
          _board = null;
        }
      }
      state = _composeState();
    } else {
      state = _composeState();
    }
  }

  /// 汇总当前演示状态。
  PuzzleState _composeState() {
    return PuzzleState(
      puzzle: _puzzle,
      demoState: _demoState,
      currentMoveIndex: _currentMoveIndex,
      currentSide: _currentSide,
      error: _error,
      fen: _board?.toFen(),
      lastMove: _lastMove,
      demoParams: _demoParams,
    );
  }

  /// 获取错误信息
  String? get error => _error;
}

/// 残局演示提供者
final puzzleViewModelProvider = NotifierProvider<PuzzleViewModel, PuzzleState>(
  PuzzleViewModel.new,
);
