import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';

/// 引擎视图模型
class EngineViewModel extends Notifier<EngineState> {
  @override
  EngineState build() {
    return const EngineState();
  }

  /// 初始化引擎
  Future<void> initialize() async {
    state = state.copyWith(
      isInitialized: true,
      isLoading: true,
    );

    try {
      // TODO: 实现引擎初始化逻辑
      await Future.delayed(const Duration(seconds: 1));
      state = state.copyWith(
        isLoading: false,
        isReady: true,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// 获取引擎建议
  Future<String> getBestMove(String fen) async {
    state = state.copyWith(
      isLoading: true,
    );

    try {
      // TODO: 实现获取最佳移动的逻辑
      await Future.delayed(const Duration(milliseconds: 500));
      String bestMove = 'h3e3'; // 示例
      state = state.copyWith(
        isLoading: false,
        lastMove: bestMove,
      );
      return bestMove;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
      throw e;
    }
  }

  /// 关闭引擎
  void shutdown() {
    state = const EngineState();
  }
}

/// 引擎状态
class EngineState {
  const EngineState({
    this.isInitialized = false,
    this.isReady = false,
    this.isLoading = false,
    this.lastMove = '',
    this.error = '',
  });

  final bool isInitialized;
  final bool isReady;
  final bool isLoading;
  final String lastMove;
  final String error;

  EngineState copyWith({
    bool? isInitialized,
    bool? isReady,
    bool? isLoading,
    String? lastMove,
    String? error,
  }) {
    return EngineState(
      isInitialized: isInitialized ?? this.isInitialized,
      isReady: isReady ?? this.isReady,
      isLoading: isLoading ?? this.isLoading,
      lastMove: lastMove ?? this.lastMove,
      error: error ?? this.error,
    );
  }
}