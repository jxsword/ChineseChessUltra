/// 残局数据模型。
///
/// 表示一个已解析的残局棋谱，包含初始局面、破解走法、元数据等信息。

import '../../board/model/move.dart';

/// 解析后的残局棋谱数据。
class ParsedPuzzle {
  /// 唯一标识符。
  final String id;

  /// 初始局面 FEN 字符串。
  final String initialFen;

  /// 破解走法序列（ICCS 坐标格式）。
  /// 
  /// 例如：["h3e3", "h9g7", "h3e7"] 表示红炮从 h3 移到 e3，黑马从 h9 移到 g7...
  final List<String>? solutionMoves;
  
  /// 获取破解走法序列（确保不为 null）。
  List<String> get moves => solutionMoves ?? <String>[];

  /// 残局标题。
  final String? title;

  /// 残局描述。
  final String? description;

  /// 棋谱来源（如"竹香斋·三集"、"适情雅趣"）。
  final String source;

  /// 棋谱格式（"xqf" / "pgn"）。
  final String format;

  /// 难度等级（1-5）。
  final int difficulty;

  /// 创建残局数据。
  const ParsedPuzzle({
    required this.id,
    required this.initialFen,
    this.solutionMoves,
    this.title,
    this.description,
    required this.source,
    required this.format,
    required this.difficulty,
  });

  /// 残局步数。
  int get moveCount => solutionMoves?.length ?? 0;

  /// 是否有破解走法。
  bool get hasSolution => solutionMoves != null && solutionMoves!.isNotEmpty;

  /// 获取难度显示文本。
  String get difficultyText {
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

  /// 获取难度星级显示。
  String get difficultyStars {
    return List.filled(difficulty, '★').join() + List.filled(5 - difficulty, '☆').join();
  }

  /// 创建副本并修改指定字段。
  ParsedPuzzle copyWith({
    String? id,
    String? initialFen,
    List<String>? solutionMoves,
    String? title,
    String? description,
    String? source,
    String? format,
    int? difficulty,
  }) {
    return ParsedPuzzle(
      id: id ?? this.id,
      initialFen: initialFen ?? this.initialFen,
      solutionMoves: solutionMoves ?? this.solutionMoves,
      title: title ?? this.title,
      description: description ?? this.description,
      source: source ?? this.source,
      format: format ?? this.format,
      difficulty: difficulty ?? this.difficulty,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ParsedPuzzle &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'ParsedPuzzle(id: $id, title: $title, source: $source, format: $format, difficulty: $difficulty)';
  }
}

/// 残局分组信息。
class PuzzleGroup {
  /// 分组名称（如"竹香斋·初集"、"适情雅趣"）。
  final String name;

  /// 分组中的残局列表。
  final List<ParsedPuzzle> puzzles;

  /// 分组描述。
  final String? description;

  /// 分组图标。
  final String? iconEmoji;

  /// 创建残局分组。
  const PuzzleGroup({
    required this.name,
    required this.puzzles,
    this.description,
    this.iconEmoji,
  });

  /// 残局数量。
  int get puzzleCount => puzzles.length;

  /// 平均难度。
  double get averageDifficulty {
    if (puzzles.isEmpty) return 0;
    final total = puzzles.fold<int>(0, (sum, p) => sum + p.difficulty);
    return total / puzzles.length;
  }

  /// 获取指定难度的残局。
  List<ParsedPuzzle> puzzlesByDifficulty(int difficulty) {
    return puzzles.where((p) => p.difficulty == difficulty).toList();
  }

  /// 按难度排序的残局列表。
  List<ParsedPuzzle> get sortedPuzzles {
    final sorted = List<ParsedPuzzle>.from(puzzles);
    sorted.sort((a, b) => a.difficulty.compareTo(b.difficulty));
    return sorted;
  }

  @override
  String toString() {
    return 'PuzzleGroup(name: $name, puzzleCount: $puzzleCount, averageDifficulty: ${averageDifficulty.toStringAsFixed(1)})';
  }
}

/// 残局演示状态。
enum PuzzleDemoState {
  /// 未开始
  idle,

  /// 正在播放
  playing,

  /// 暂停
  paused,

  /// 播放完成
  completed,

  /// 播放错误
  error,
}

/// 残局演示参数。
class PuzzleDemoParams {
  /// 走子动画时长（毫秒）。
  final int moveDuration;

  /// 走子间隔时长（毫秒）。
  final int moveInterval;

  /// 是否自动播放。
  final bool autoPlay;

  /// 是否循环播放。
  final bool loop;

  /// 播放速度倍率。
  final double speedMultiplier;

  /// 创建演示参数。
  const PuzzleDemoParams({
    this.moveDuration = 600,
    this.moveInterval = 800,
    this.autoPlay = false,
    this.loop = false,
    this.speedMultiplier = 1.0,
  });

  /// 计算实际走子间隔。
  int get interval => (moveInterval / speedMultiplier).round();

  /// 创建副本并修改指定字段。
  PuzzleDemoParams copyWith({
    int? moveDuration,
    int? moveInterval,
    bool? autoPlay,
    bool? loop,
    double? speedMultiplier,
  }) {
    return PuzzleDemoParams(
      moveDuration: moveDuration ?? this.moveDuration,
      moveInterval: moveInterval ?? this.moveInterval,
      autoPlay: autoPlay ?? this.autoPlay,
      loop: loop ?? this.loop,
      speedMultiplier: speedMultiplier ?? this.speedMultiplier,
    );
  }

  /// 慢速播放参数。
  static const slow = PuzzleDemoParams(speedMultiplier: 0.5);

  /// 正常播放参数。
  static const normal = PuzzleDemoParams(speedMultiplier: 1.0);

  /// 快速播放参数。
  static const fast = PuzzleDemoParams(speedMultiplier: 2.0);
}


/// 残局状态类。
class PuzzleState {
  final ParsedPuzzle? puzzle;
  final PuzzleDemoState demoState;
  final int currentMoveIndex;
  final String currentSide;
  final String? error;

  /// 演示当前局面 FEN（演示未初始化时为 null）。
  final String? fen;

  /// 最近一步演示走法（用于棋盘高亮起止点）。
  final Move? lastMove;

  /// 当前演示参数（供速度下拉框回显）。
  final PuzzleDemoParams demoParams;

  const PuzzleState({
    this.puzzle,
    this.demoState = PuzzleDemoState.idle,
    this.currentMoveIndex = 0,
    this.currentSide = 'red',
    this.error,
    this.fen,
    this.lastMove,
    this.demoParams = PuzzleDemoParams.normal,
  });

  PuzzleState copyWith({
    ParsedPuzzle? puzzle,
    PuzzleDemoState? demoState,
    int? currentMoveIndex,
    String? currentSide,
    String? error,
  }) {
    return PuzzleState(
      puzzle: puzzle ?? this.puzzle,
      demoState: demoState ?? this.demoState,
      currentMoveIndex: currentMoveIndex ?? this.currentMoveIndex,
      currentSide: currentSide ?? this.currentSide,
      error: error ?? this.error,
    );
  }
}

/// 残局演示进度信息。
class PuzzleDemoProgress {
  /// 当前步数（从 0 开始）。
  final int currentMove;

  /// 总步数。
  final int totalMoves;

  /// 当前走法（ICCS 坐标）。
  final String? currentMoveString;

  /// 播放状态。
  final PuzzleDemoState state;

  /// 错误信息（仅在 error 状态下有效）。
  final String? errorMessage;

  /// 创建进度信息。
  const PuzzleDemoProgress({
    required this.currentMove,
    required this.totalMoves,
    this.currentMoveString,
    required this.state,
    this.errorMessage,
  });

  /// 是否是第一步。
  bool get isFirstMove => currentMove == 0;

  /// 是否是最后一步。
  bool get isLastMove => currentMove >= totalMoves - 1;

  /// 播放进度（0.0 - 1.0）。
  double get progress => totalMoves > 0 ? currentMove / totalMoves : 0.0;

  /// 创建副本并修改指定字段。
  PuzzleDemoProgress copyWith({
    int? currentMove,
    int? totalMoves,
    String? currentMoveString,
    PuzzleDemoState? state,
    String? errorMessage,
  }) {
    return PuzzleDemoProgress(
      currentMove: currentMove ?? this.currentMove,
      totalMoves: totalMoves ?? this.totalMoves,
      currentMoveString: currentMoveString ?? this.currentMoveString,
      state: state ?? this.state,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  String toString() {
    return 'PuzzleDemoProgress(currentMove: $currentMove/$totalMoves, state: $state)';
  }
}