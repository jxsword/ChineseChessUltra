import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chinese_chess_ultra/features/puzzle/model/corpus_paths.dart';
import 'package:chinese_chess_ultra/features/puzzle/viewmodel/corpus_browser_vm.dart';

void main() {
  test('语料目录存在但为空 → 视同缺失（corpusExists=false，回到下载引导）', () async {
    final tmp = Directory.systemTemp.createTempSync('corpus_vm_empty');
    addTearDown(() => tmp.deleteSync(recursive: true));
    SharedPreferences.setMockInitialValues({
      CorpusPaths.userPathPrefKey: tmp.path,
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(corpusBrowserProvider.notifier).load();

    final state = container.read(corpusBrowserProvider);
    expect(state.corpusExists, isFalse, reason: '空目录不应进入"请选择分类"死胡同');
    expect(state.corpusPath, tmp.path);
    expect(state.categories, isEmpty);
  });

  test('语料目录不存在 → corpusExists=false', () async {
    final missing = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'corpus_vm_missing_${DateTime.now().microsecondsSinceEpoch}');
    addTearDown(() {
      if (missing.existsSync()) missing.deleteSync(recursive: true);
    });
    SharedPreferences.setMockInitialValues({
      CorpusPaths.userPathPrefKey: missing.path,
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(corpusBrowserProvider.notifier).load();

    expect(container.read(corpusBrowserProvider).corpusExists, isFalse);
  });

  test('语料目录有分类子目录 → 正常扫描（corpusExists=true）', () async {
    final tmp = Directory.systemTemp.createTempSync('corpus_vm_ok');
    addTearDown(() => tmp.deleteSync(recursive: true));
    Directory('${tmp.path}${Platform.pathSeparator}XQF-测试分类').createSync();
    SharedPreferences.setMockInitialValues({
      CorpusPaths.userPathPrefKey: tmp.path,
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(corpusBrowserProvider.notifier).load();

    final state = container.read(corpusBrowserProvider);
    expect(state.corpusExists, isTrue);
    expect(state.categories, isNotEmpty);
    expect(state.selectedCategory, 0);
  });
}
