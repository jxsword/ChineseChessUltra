import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';

import '../../board/model/board.dart';
import '../../board/model/fen.dart';
import '../model/puzzle_data.dart';
import '../model/puzzle_parser.dart';
import '../../shared/engine/hint_strategy.dart';
import '../../shared/engine/pikafish_bridge.dart';

/// 残局演示 ViewModel
class PuzzleViewModel extends Notifier<PuzzleState> {
  ParsedPuzzle? _puzzle;
  PuzzleDemoState _demoState = PuzzleDemoState.idle;
  int _currentMoveIndex = 0;
  String _currentSide = 'red';
  String? _error;
  Timer? _playTimer;
  PuzzleDemoParams _demoParams = const PuzzleDemoParams();

  @override
  PuzzleState build() {
    return const PuzzleState();
  }

  /// 初始化残局
  void initializePuzzle(ParsedPuzzle puzzle) {
    _puzzle = puzzle;
    _demoState = PuzzleDemoState.idle;
    _currentMoveIndex = 0;
    _currentSide = 'red';
    _error = null;
    _demoParams = const PuzzleDemoParams();
    
    // 应用残局到棋盘
    if (puzzle.initialFen != null) {
      try {
        final board = Board.fromFen(puzzle.initialFen!);
        // TODO: 将棋盘状态同步到 BoardViewModel
      } catch (e) {
        _error = '初始化残局失败: ${e.toString()}';
      }
    }
    
    state = PuzzleState(
      puzzle: _puzzle,
      demoState: _demoState,
      currentMoveIndex: _currentMoveIndex,
      currentSide: _currentSide,
      error: _error,
    );
  }

  /// 开始演示
  void startDemo() {
    if (_puzzle == null || _demoState == PuzzleDemoState.playing) return;
    
    _demoState = PuzzleDemoState.playing;
    state = PuzzleState(
      puzzle: _puzzle,
      demoState: _demoState,
      currentMoveIndex: _currentMoveIndex,
      currentSide: _currentSide,
      error: _error,
    );
    
    _playTimer?.cancel();
    _playTimer = Timer.periodic(Duration(milliseconds: _demoParams.moveInterval), (timer) {
      if (_currentMoveIndex < _puzzle!.moves.length - 1) {
        _currentMoveIndex++;
        _currentSide = _currentSide == 'red' ? 'black' : 'red';
        state = PuzzleState(
          puzzle: _puzzle,
          demoState: _demoState,
          currentMoveIndex: _currentMoveIndex,
          currentSide: _currentSide,
          error: _error,
        );
      } else {
        _completeDemo();
      }
    });
  }

  /// 暂停演示
  void pauseDemo() {
    if (_demoState != PuzzleDemoState.playing) return;
    
    _demoState = PuzzleDemoState.paused;
    _playTimer?.cancel();
    state = PuzzleState(
      puzzle: _puzzle,
      demoState: _demoState,
      currentMoveIndex: _currentMoveIndex,
      currentSide: _currentSide,
      error: _error,
    );
  }

  /// 继续演示
  void resumeDemo() {
    if (_demoState != PuzzleDemoState.paused || _puzzle == null) return;
    
    _demoState = PuzzleDemoState.playing;
    state = PuzzleState(
      puzzle: _puzzle,
      demoState: _demoState,
      currentMoveIndex: _currentMoveIndex,
      currentSide: _currentSide,
      error: _error,
    );
    
    _playTimer?.cancel();
    _playTimer = Timer.periodic(Duration(milliseconds: _demoParams.moveInterval), (timer) {
      if (_currentMoveIndex < _puzzle!.moves.length - 1) {
        _currentMoveIndex++;
        _currentSide = _currentSide == 'red' ? 'black' : 'red';
        state = PuzzleState(
          puzzle: _puzzle,
          demoState: _demoState,
          currentMoveIndex: _currentMoveIndex,
          currentSide: _currentSide,
          error: _error,
        );
      } else {
        _completeDemo();
      }
    });
  }

  /// 停止演示
  void stopDemo() {
    _demoState = PuzzleDemoState.idle;
    _currentMoveIndex = 0;
    _currentSide = 'red';
    _playTimer?.cancel();
    state = PuzzleState(
      puzzle: _puzzle,
      demoState: _demoState,
      currentMoveIndex: _currentMoveIndex,
      currentSide: _currentSide,
      error: _error,
    );
  }

  /// 完成演示
  void _completeDemo() {
    _demoState = PuzzleDemoState.completed;
    _playTimer?.cancel();
    
    if (_demoParams.loop) {
      _currentMoveIndex = 0;
      _currentSide = 'red';
      _demoState = PuzzleDemoState.playing;
      state = PuzzleState(
        puzzle: _puzzle,
        demoState: _demoState,
        currentMoveIndex: _currentMoveIndex,
        currentSide: _currentSide,
        error: _error,
      );
    } else {
      state = PuzzleState(
        puzzle: _puzzle,
        demoState: _demoState,
        currentMoveIndex: _currentMoveIndex,
        currentSide: _currentSide,
        error: _error,
      );
    }
  }

  /// 设置演示速度
  void setDemoSpeed(PuzzleDemoParams params) {
    _demoParams = params;
    if (_demoState == PuzzleDemoState.playing) {
      _playTimer?.cancel();
      _playTimer = Timer.periodic(Duration(milliseconds: _demoParams.moveInterval), (timer) {
        if (_currentMoveIndex < _puzzle!.moves.length - 1) {
          _currentMoveIndex++;
          _currentSide = _currentSide == 'red' ? 'black' : 'red';
          state = PuzzleState(
            puzzle: _puzzle,
            demoState: _demoState,
            currentMoveIndex: _currentMoveIndex,
            currentSide: _currentSide,
            error: _error,
          );
        } else {
          _completeDemo();
        }
      });
    }
  }

  /// 设置演示模式
  void setDemoMode(bool loop) {
    _demoParams = PuzzleDemoParams(
      moveInterval: _demoParams.moveInterval,
      loop: loop,
    );
  }

  /// 获取错误信息
  String? get error => _error;

  /// 清理资源
  @override
  void dispose() {
    _playTimer?.cancel();
  }
}

/// 残局演示提供者
final puzzleViewModelProvider = NotifierProvider<PuzzleViewModel, PuzzleState>(
  PuzzleViewModel.new,
);