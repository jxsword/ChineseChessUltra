import '../../features/board/model/move.dart';

/// 提示策略抽象接口（二期）。
///
/// 定义了"如何决定下一步提示走法"的策略接口，便于：
/// - [PuzzleSolutionHintStrategy]：优先按残局预录的破解走法演示
/// - [EngineHintStrategy]：调用 Pikafish 实时计算最佳走法
/// - [CompositeHintStrategy]：组合多种策略
abstract class HintStrategy {
  /// 返回当前局面下的最佳/建议走法。
  /// 
  /// 返回 ICCS 坐标格式的走法字符串（如 "h3e3"）。
  /// 无建议返回 null。
  Future<String?> getHint();
  
  /// 获取走法评分（可选）。
  /// 
  /// 返回走法的评分（centipawn），正数表示红方优势，负数表示黑方优势。
  Future<int?> getHintScore();
}

/// 基于预录残局破解走法的提示策略（二期）。
class PuzzleSolutionHintStrategy implements HintStrategy {
  PuzzleSolutionHintStrategy(this.solution, {this.currentIndex = 0});

  /// 破解走法序列（ICCS 坐标格式）。
  final List<String> solution;
  
  /// 当前走法索引。
  int currentIndex;

  @override
  Future<String?> getHint() async {
    if (currentIndex >= solution.length) return null;
    return solution[currentIndex];
  }

  @override
  Future<int?> getHintScore() async {
    // 预录走法没有评分信息
    return null;
  }
  
  /// 前进到下一步。
  void advance() {
    currentIndex++;
  }
  
  /// 重置到起始位置。
  void reset() {
    currentIndex = 0;
  }
  
  /// 检查是否还有提示。
  bool hasNext => currentIndex < solution.length;
}

/// 基于引擎的提示策略（二期）。
class EngineHintStrategy implements HintStrategy {
  EngineHintStrategy(this.getEngineHint);

  /// 获取引擎提示的函数。
  final Future<String?> Function() getEngineHint;

  @override
  Future<String?> getHint() async {
    return getEngineHint();
  }

  @override
  Future<int?> getHintScore() async {
    // 引擎策略需要提供评分信息
    return null; // 需要从引擎结果中提取
  }
}

/// 组合提示策略（二期）。
/// 
/// 依次尝试多种策略，优先使用第一种可用的策略。
class CompositeHintStrategy implements HintStrategy {
  CompositeHintStrategy(this.strategies);

  /// 策略列表（按优先级排序）。
  final List<HintStrategy> strategies;

  @override
  Future<String?> getHint() async {
    for (final strategy in strategies) {
      final hint = await strategy.getHint();
      if (hint != null) {
        return hint;
      }
    }
    return null;
  }

  @override
  Future<int?> getHintScore() async {
    for (final strategy in strategies) {
      final score = await strategy.getHintScore();
      if (score != null) {
        return score;
      }
    }
    return null;
  }
}

/// 缓存提示策略（二期）。
/// 
/// 对相同 FEN 的提示结果进行缓存，避免重复计算。
class CachedHintStrategy implements HintStrategy {
  CachedHintStrategy(
    this._innerStrategy,
    this._currentFenGetter, {
    Duration cacheDuration = const Duration(seconds: 30),
  }) : _cacheDuration = cacheDuration;

  final HintStrategy _innerStrategy;
  final String Function() _currentFenGetter;
  final Duration _cacheDuration;
  
  final Map<String, ({String hint, int? score, DateTime timestamp})> _cache = {};

  @override
  Future<String?> getHint() async {
    final fen = _currentFenGetter();
    final cached = _cache[fen];
    
    // 检查缓存是否有效
    if (cached != null) {
      final age = DateTime.now().difference(cached.timestamp);
      if (age < _cacheDuration) {
        return cached.hint;
      } else {
        _cache.remove(fen);
      }
    }
    
    // 计算新提示
    final hint = await _innerStrategy.getHint();
    if (hint != null) {
      final score = await _innerStrategy.getHintScore();
      _cache[fen] = (hint: hint, score: score, timestamp: DateTime.now());
    }
    
    return hint;
  }

  @override
  Future<int?> getHintScore() async {
    final fen = _currentFenGetter();
    final cached = _cache[fen];
    
    if (cached != null) {
      return cached.score;
    }
    
    return await _innerStrategy.getHintScore();
  }
  
  /// 清除所有缓存。
  void clearCache() {
    _cache.clear();
  }
  
  /// 清除过期缓存。
  void cleanup() {
    final now = DateTime.now();
    _cache.removeWhere((key, value) {
      final age = now.difference(value.timestamp);
      return age > _cacheDuration;
    });
  }
}

/// 空提示策略（无提示）。
class EmptyHintStrategy implements HintStrategy {
  const EmptyHintStrategy();

  @override
  Future<String?> getHint() async => null;

  @override
  Future<int?> getHintScore() async => null;
}