import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'dart:async';

import '../../shared/engine/pikafish_bridge.dart';
import '../../shared/engine/hint_strategy.dart';
import '../board/model/board.dart';
import '../board/model/move.dart';
import '../board/model/fen.dart';

part 'engine_vm.g.dart';

/// 引擎分析结果。
class AnalysisResult {
  /// 主要变例走法序列（PV lines）。
  final List<List<String>> pvMoves;
  
  /// 评分列表（正数表示红方优势，负数表示黑方优势）。
  final List<int> scores;
  
  /// 分析深度。
  final int depth;
  
  /// 分析耗时（毫秒）。
  final int elapsedMs;

  const AnalysisResult({
    required this.pvMoves,
    required this.scores,
    required this.depth,
    required this.elapsedMs,
  });

  /// 获取最佳走法（PV1 的第一步）。
  String? get bestMove {
    if (pvMoves.isEmpty || pvMoves[0].isEmpty) return null;
    return pvMoves[0][0];
  }

  /// 获取最佳走法的评分。
  int get bestScore {
    if (scores.isEmpty) return 0;
    return scores[0];
  }

  /// 获取评分差（和 PV2 的差值）。
  int get scoreMargin {
    if (scores.length < 2) return 0;
    return (scores[0] - scores[1]).abs();
  }

  /// 创建空结果。
  static const empty = AnalysisResult(
    pvMoves: [],
    scores: [],
    depth: 0,
    elapsedMs: 0,
  );

  /// 是否为空结果。
  bool get isEmpty => pvMoves.isEmpty;
}

/// 引擎状态。
enum EngineState {
  /// 未启动
  idle,
  
  /// 正在启动
  starting,
  
  /// 已就绪
  ready,
  
  /// 正在分析
  analyzing,
  
  /// 正在计算最佳走法
  thinking,
  
  /// 已停止
  stopped,
  
  /// 错误状态
  error,
}

/// 引擎配置。
class EngineConfig {
  /// 引擎二进制文件路径。
  final String binaryPath;
  
  /// 难度等级（1-5）。
  final int difficulty;
  
  /// 搜索深度。
  final int depth;
  
  /// ELO 评分（1200-3000）。
  final int elo;
  
  /// 是否限制强度。
  final bool limitStrength;
  
  /// 多 PV 数量。
  final int multipv;

  const EngineConfig({
    required this.binaryPath,
    this.difficulty = 3,
    this.depth = 18,
    this.elo = 2000,
    this.limitStrength = false,
    this.multipv = 3,
  });

  /// 创建默认配置。
  factory EngineConfig.defaultConfig() {
    return EngineConfig(
      binaryPath: 'assets/engines/pikafish',
      difficulty: 3,
      depth: 18,
      elo: 2000,
      limitStrength: false,
      multipv: 3,
    );
  }

  /// 根据难度创建配置。
  factory EngineConfig.fromDifficulty(int difficulty) {
    final config = switch (difficulty) {
      1 => EngineConfig(difficulty: 1, depth: 8, elo: 1200),
      2 => EngineConfig(difficulty: 2, depth: 12, elo: 1500),
      3 => EngineConfig(difficulty: 3, depth: 15, elo: 1800),
      4 => EngineConfig(difficulty: 4, depth: 18, elo: 2200),
      5 => EngineConfig(difficulty: 5, depth: 24, elo: 2800),
      _ => EngineConfig(difficulty: 3, depth: 18, elo: 2000),
    };
    return config;
  }

  /// 获取难度名称。
  String get difficultyName {
    switch (difficulty) {
      case 1:
        return '入门';
      case 2:
        return '初级';
      case 3:
        return '中级';
      case 4:
        return '高级';
      case 5:
        return '职业';
      default:
        return '未知';
    }
  }

  /// 创建副本并修改指定字段。
  EngineConfig copyWith({
    String? binaryPath,
    int? difficulty,
    int? depth,
    int? elo,
    bool? limitStrength,
    int? multipv,
  }) {
    return EngineConfig(
      binaryPath: binaryPath ?? this.binaryPath,
      difficulty: difficulty ?? this.difficulty,
      depth: depth ?? this.depth,
      elo: elo ?? this.elo,
      limitStrength: limitStrength ?? this.limitStrength,
      multipv: multipv ?? this.multipv,
    );
  }
}

/// 引擎 ViewModel（二期）。
///
/// 功能：
/// - 引擎生命周期管理
/// - 局面分析
/// - 最佳走法计算
/// - 提示策略实现
@riverpod
class EngineViewModel extends _$EngineViewModel {
  PikafishBridge? _bridge;
  EngineConfig _config = EngineConfig.defaultConfig();
  EngineState _engineState = EngineState.idle;
  String? _errorMessage;
  AnalysisResult _lastAnalysis = AnalysisResult.empty;
  
  // 分析结果缓存（FEN -> 结果）
  final Map<String, ({AnalysisResult result, DateTime timestamp})> _analysisCache = {};
  
  // 缓存有效期（30秒）
  static const Duration _cacheValidity = Duration(seconds: 30);

  @override
  EngineState build() {
    return _engineState;
  }

  /// 初始化引擎。
  Future<void> initialize([EngineConfig? config]) async {
    if (config != null) {
      _config = config;
    }

    _engineState = EngineState.starting;
    state = _engineState;

    try {
      _bridge = PikafishBridge();
      await _bridge!.start(_config.binaryPath);
      
      // 配置引擎参数
      if (_config.limitStrength) {
        await _bridge!.sendCommand('setoption name UCI_LimitStrength value true');
        await _bridge!.sendCommand('setoption name UCI_Elo value ${_config.elo}');
      }
      
      await _bridge!.sendCommand('isready');
      
      _engineState = EngineState.ready;
      state = _engineState;
    } catch (e) {
      _engineState = EngineState.error;
      _errorMessage = '引擎初始化失败: $e';
      state = _engineState;
      rethrow;
    }
  }

  /// 停止引擎。
  Future<void> shutdown() async {
    await _bridge?.shutdown();
    _bridge = null;
    _engineState = EngineState.idle;
    state = _engineState;
    _analysisCache.clear();
  }

  /// 分析当前局面。
  Future<AnalysisResult> analyzePosition(Board board, {int? depth, int? multipv}) async {
    if (_engineState != EngineState.ready) {
      throw StateError('引擎未就绪: $_engineState');
    }

    _engineState = EngineState.analyzing;
    state = _engineState;

    try {
      final fen = board.toFen();
      
      // 检查缓存
      final cached = _analysisCache[fen];
      if (cached != null) {
        final age = DateTime.now().difference(cached.timestamp);
        if (age < _cacheValidity) {
          _lastAnalysis = cached.result;
          _engineState = EngineState.ready;
          state = _engineState;
          return cached.result;
        }
      }

      final actualDepth = depth ?? _config.depth;
      final actualMultipv = multipv ?? _config.multipv;

      final result = await _bridge!.analyze(fen, depth: actualDepth, multipv: actualMultipv);
      
      // 缓存结果
      _analysisCache[fen] = (result: result, timestamp: DateTime.now());
      
      // 清理过期缓存
      _cleanupCache();
      
      _lastAnalysis = result;
      _engineState = EngineState.ready;
      state = _engineState;
      
      return result;
    } catch (e) {
      _engineState = EngineState.error;
      _errorMessage = '分析失败: $e';
      state = _engineState;
      rethrow;
    }
  }

  /// 计算最佳走法。
  Future<String> getBestMove(Board board, {int? depth}) async {
    if (_engineState != EngineState.ready) {
      throw StateError('引擎未就绪: $_engineState');
    }

    _engineState = EngineState.thinking;
    state = _engineState;

    try {
      final fen = board.toFen();
      final actualDepth = depth ?? _config.depth;

      final move = await _bridge!.bestMove(fen, depth: actualDepth);
      
      _engineState = EngineState.ready;
      state = _engineState;
      
      return move;
    } catch (e) {
      _engineState = EngineState.error;
      _errorMessage = '计算最佳走法失败: $e';
      state = _engineState;
      rethrow;
    }
  }

  /// 停止当前计算。
  Future<void> stop() async {
    if (_bridge != null) {
      await _bridge!.stop();
    }
    _engineState = EngineState.ready;
    state = _engineState;
  }

  /// 更新引擎配置。
  Future<void> updateConfig(EngineConfig config) async {
    _config = config;
    
    if (_engineState == EngineState.ready) {
      // 重启引擎以应用新配置
      await shutdown();
      await initialize(_config);
    }
  }

  /// 设置难度。
  Future<void> setDifficulty(int difficulty) async {
    final newConfig = EngineConfig.fromDifficulty(difficulty);
    await updateConfig(newConfig);
  }

  /// 获取引擎状态。
  EngineState get engineState => _engineState;

  /// 获取错误信息。
  String? get errorMessage => _errorMessage;

  /// 获取引擎配置。
  EngineConfig get config => _config;

  /// 获取最后一次分析结果。
  AnalysisResult get lastAnalysis => _lastAnalysis;

  /// 是否已就绪。
  bool get isReady => _engineState == EngineState.ready;

  /// 是否正在计算。
  bool get isThinking => _engineState == EngineState.thinking || _engineState == EngineState.analyzing;

  /// 是否有错误。
  bool get hasError => _engineState == EngineState.error;

  /// 清理过期缓存。
  void _cleanupCache() {
    final now = DateTime.now();
    _analysisCache.removeWhere((key, value) {
      final age = now.difference(value.timestamp);
      return age > _cacheValidity;
    });
  }

  @override
  void dispose() {
    shutdown();
    super.dispose();
  }
}

/// 引擎提示策略实现。
class EngineHintStrategy implements HintStrategy {
  final Ref ref;
  final EngineViewModel engineVm;

  EngineHintStrategy(this.ref, this.engineVm);

  @override
  Future<String?> getHint() {
    if (!engineVm.isReady) {
      return Future.value(null);
    }

    // 获取最后一次分析结果的最佳走法
    return Future.value(engineVm.lastAnalysis.bestMove);
  }

  /// 为指定局面计算提示。
  Future<String?> getHintForPosition(Board board) async {
    if (!engineVm.isReady) {
      return null;
    }

    try {
      final result = await engineVm.analyzePosition(board);
      return result.bestMove;
    } catch (e) {
      return null;
    }
  }
}