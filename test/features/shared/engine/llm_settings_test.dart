import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chinese_chess_ultra/features/shared/engine/llm_move_source.dart';
import 'package:chinese_chess_ultra/features/shared/engine/llm_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LlmSettingsStore（对局设置持久化）', () {
    test('默认值加载（无任何存档）', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await LlmSettingsStore().load();
      expect(settings.timeoutSeconds, 60);
      expect(settings.maxAttempts, 3);
      expect(settings.fallback, LlmFallback.builtinAi);
      expect(settings.intervalSeconds, 1);
    });

    test('保存后加载往返一致', () async {
      SharedPreferences.setMockInitialValues({});
      final store = LlmSettingsStore();
      await store.save(const LlmGameSettings(
        timeoutSeconds: 180,
        maxAttempts: 5,
        fallback: LlmFallback.resign,
        intervalSeconds: 2,
      ));
      final settings = await store.load();
      expect(settings.timeoutSeconds, 180);
      expect(settings.maxAttempts, 5);
      expect(settings.fallback, LlmFallback.resign);
      expect(settings.intervalSeconds, 2);
    });

    test('fallbackIndex 越界回落默认', () async {
      SharedPreferences.setMockInitialValues({
        'llm_settings_fallbackIndex': 99,
      });
      final settings = await LlmSettingsStore().load();
      expect(settings.fallback, LlmFallback.builtinAi);
    });

    test('toMap 覆盖全部字段', () {
      const settings = LlmGameSettings(
        timeoutSeconds: 30,
        maxAttempts: 1,
        fallback: LlmFallback.resign,
        intervalSeconds: 5,
      );
      final map = settings.toMap();
      expect(map['timeoutSeconds'], 30);
      expect(map['maxAttempts'], 1);
      expect(map['fallbackIndex'], LlmFallback.resign.index);
      expect(map['intervalSeconds'], 5);
    });
  });
}
