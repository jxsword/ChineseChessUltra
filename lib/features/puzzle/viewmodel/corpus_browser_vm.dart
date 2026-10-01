/// 本地棋谱库浏览 ViewModel。
///
/// 职责：扫描 corpus 语料分类、按分类懒解析 XQF 文件（分批 + 进度）、
/// 提供搜索 / 难度筛选 / 排序。PGN 大文件分类由页面层跳转到
/// [PgnFileBrowserPage] 处理。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model/corpus_paths.dart';
import '../model/corpus_scanner.dart';
import '../model/puzzle_data.dart';

/// 列表排序方式。
enum CorpusSortMode { name, moves, difficulty }

/// 浏览页状态。
class CorpusBrowserState {
  /// 语料目录是否存在（不存在时展示引导）。
  final bool corpusExists;

  /// 解析后的语料目录绝对路径（用于缺失引导展示/下载）。
  final String? corpusPath;

  final List<CorpusCategory> categories;

  /// 当前选中的分类下标；null = 未选择。
  final int? selectedCategory;

  /// 当前分类的文件条目（与 [puzzles] 对齐）。
  final List<CorpusEntry> entries;

  /// 与 [entries] 对齐的解析结果（解析中/失败为 null）。
  final List<ParsedPuzzle?> puzzles;

  /// 批量解析进度（0.0-1.0）；null 表示不在解析中。
  final double? progress;

  final String query;

  /// 仅显示残局/排局题（区别于全局对局）。
  final bool onlyEndgame;

  /// 难度筛选（1-5）；null = 全部。
  final int? difficultyFilter;

  final CorpusSortMode sortMode;

  const CorpusBrowserState({
    this.corpusExists = true,
    this.corpusPath,
    this.categories = const [],
    this.selectedCategory,
    this.entries = const [],
    this.puzzles = const [],
    this.progress,
    this.query = '',
    this.onlyEndgame = false,
    this.difficultyFilter,
    this.sortMode = CorpusSortMode.name,
  });

  /// 是否正在解析当前分类。
  bool get isLoading => progress != null;

  /// 解析完成的条目数。
  int get parsedCount => puzzles.where((p) => p != null).length;

  /// 搜索 + 难度筛选 + 排序后的可见列表（仅已解析成功的条目）。
  List<(CorpusEntry, ParsedPuzzle)> get visibleItems {
    final query = this.query.trim();
    final items = <(CorpusEntry, ParsedPuzzle)>[];
    for (var i = 0; i < entries.length; i++) {
      final puzzle = puzzles[i];
      if (puzzle == null) continue;
      if (difficultyFilter != null && puzzle.difficulty != difficultyFilter) {
        continue;
      }
      if (onlyEndgame && !puzzle.isEndgamePuzzle) {
        continue;
      }
      if (query.isNotEmpty &&
          !(puzzle.title ?? entries[i].displayName).contains(query)) {
        continue;
      }
      items.add((entries[i], puzzle));
    }
    switch (sortMode) {
      case CorpusSortMode.name:
        items.sort((a, b) => a.$1.displayName.compareTo(b.$1.displayName));
      case CorpusSortMode.moves:
        items.sort((a, b) => a.$2.moves.length.compareTo(b.$2.moves.length));
      case CorpusSortMode.difficulty:
        items.sort((a, b) {
          final d = a.$2.difficulty.compareTo(b.$2.difficulty);
          return d != 0 ? d : a.$2.moves.length.compareTo(b.$2.moves.length);
        });
    }
    return items;
  }

  CorpusBrowserState copyWith({
    bool? corpusExists,
    String? corpusPath,
    bool clearCorpusPath = false,
    List<CorpusCategory>? categories,
    int? selectedCategory,
    bool clearSelectedCategory = false,
    List<CorpusEntry>? entries,
    List<ParsedPuzzle?>? puzzles,
    double? progress,
    bool clearProgress = false,
    String? query,
    bool? onlyEndgame,
    int? difficultyFilter,
    bool clearDifficultyFilter = false,
    CorpusSortMode? sortMode,
  }) {
    return CorpusBrowserState(
      corpusExists: corpusExists ?? this.corpusExists,
      corpusPath: clearCorpusPath ? null : (corpusPath ?? this.corpusPath),
      categories: categories ?? this.categories,
      selectedCategory:
          clearSelectedCategory ? null : (selectedCategory ?? this.selectedCategory),
      entries: entries ?? this.entries,
      puzzles: puzzles ?? this.puzzles,
      progress: clearProgress ? null : (progress ?? this.progress),
      query: query ?? this.query,
      onlyEndgame: onlyEndgame ?? this.onlyEndgame,
      difficultyFilter:
          clearDifficultyFilter ? null : (difficultyFilter ?? this.difficultyFilter),
      sortMode: sortMode ?? this.sortMode,
    );
  }
}

/// 浏览页 ViewModel（手动 provider，与项目现有风格一致）。
class CorpusBrowserViewModel extends Notifier<CorpusBrowserState> {
  /// 防止切分类后旧解析任务覆盖新状态。
  int _generation = 0;

  SharedPreferences? _prefs;

  /// 当前生效的语料仓库（load 后可用）。
  CorpusRepository? _repo;

  @override
  CorpusBrowserState build() {
    return const CorpusBrowserState();
  }

  /// 初始化：解析语料目录（用户设置 > legacy 联接 > 平台默认）并扫描分类。
  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final userPath = _prefs!.getString(CorpusPaths.userPathPrefKey);
    final dir = await CorpusPaths.resolveDirectory(userSetting: userPath);
    final repo = CorpusRepository(root: dir);
    _repo = repo;

    if (!repo.exists) {
      state = state.copyWith(
        corpusExists: false,
        corpusPath: dir.path,
        categories: const [],
        clearSelectedCategory: true,
        entries: const [],
        puzzles: const [],
        clearProgress: true,
      );
      return;
    }
    final categories = repo.scanCategories();
    state = state.copyWith(
      corpusExists: true,
      corpusPath: dir.path,
      categories: categories,
    );
    if (categories.isNotEmpty) {
      await selectCategory(0);
    }
  }

  /// 桌面端：选择自定义棋谱目录并持久化，然后重新加载。
  Future<void> pickCustomDirectory(String directoryPath) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setString(CorpusPaths.userPathPrefKey, directoryPath);
    await load();
  }

  /// 选择分类；PGN 大文件分类只记录选中（页面层跳转），不批量解析。
  Future<void> selectCategory(int index) async {
    final category = state.categories[index];
    state = state.copyWith(
      selectedCategory: index,
      entries: const [],
      puzzles: const [],
      clearProgress: true,
    );
    if (category.kind != CorpusKind.xqfDirectory) return;

    final repo = _repo ?? CorpusRepository();
    final entries = repo.listXqfEntries(category);
    state = state.copyWith(
      entries: entries,
      puzzles: List<ParsedPuzzle?>.filled(entries.length, null),
      progress: 0.0,
    );
    if (entries.isEmpty) {
      state = state.copyWith(clearProgress: true);
      return;
    }

    final generation = ++_generation;
    // 分批在后台 isolate 解析，避免长列表一次解析阻塞且可渐进展示。
    const batchSize = 128;
    final puzzles = List<ParsedPuzzle?>.filled(entries.length, null);
    for (var start = 0; start < entries.length; start += batchSize) {
      final end = (start + batchSize).clamp(0, entries.length);
      final chunk = entries.sublist(start, end);
      final results = await CorpusRepository.parseXqfBatch(chunk);
      if (generation != _generation) return; // 已切换分类，丢弃
      for (var i = 0; i < results.length; i++) {
        puzzles[start + i] = results[i];
      }
      state = state.copyWith(
        puzzles: List.of(puzzles),
        progress: end / entries.length,
      );
    }
    if (generation == _generation) {
      state = state.copyWith(puzzles: puzzles, clearProgress: true);
    }
  }

  void setQuery(String query) => state = state.copyWith(query: query);

  void setOnlyEndgame(bool value) =>
      state = state.copyWith(onlyEndgame: value);

  void setDifficultyFilter(int? difficulty) => state = state.copyWith(
      difficultyFilter: difficulty, clearDifficultyFilter: difficulty == null);

  void setSortMode(CorpusSortMode mode) =>
      state = state.copyWith(sortMode: mode);
}

/// 全局 provider（应用生命周期内保留语料解析缓存）。
final corpusBrowserProvider =
    NotifierProvider<CorpusBrowserViewModel, CorpusBrowserState>(
  CorpusBrowserViewModel.new,
);
