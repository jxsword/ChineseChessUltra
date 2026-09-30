import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 提示策略接口
abstract class HintStrategy {
  /// 获取当前棋局的提示
  Future<String> getHint(String fen);
}

/// 默认提示策略实现
class DefaultHintStrategy implements HintStrategy {
  @override
  Future<String> getHint(String fen) async {
    // TODO: 实现实际的提示逻辑
    return '提示：分析当前棋局并给出建议';
  }
}

/// 提示策略提供者
final hintStrategyProvider = Provider<HintStrategy>((ref) {
  return DefaultHintStrategy();
});