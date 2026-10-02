import '../board/model/board.dart';
import '../board/model/board_state.dart';
import '../board/model/move.dart';
import '../board/model/move_notation.dart';
import '../board/model/piece.dart';

/// 棋谱的求解状态（四期）。
///
/// 普通对战棋谱为 [none]；残局求解产生的棋谱为后三种之一，
/// 无解与超时的棋局同样入库，仅以标记区分。
enum SolveStatus {
  /// 普通对战棋谱（未参与求解）。
  none,

  /// 已破解：solutions 非空；唯一解与多条解以 solutions.length 区分。
  solved,

  /// 已证明无解（在求解深度上界内）。
  noSolution,

  /// 限时内未决（可能携带部分解）。
  timeout;

  String get label => switch (this) {
        SolveStatus.none => '对局',
        SolveStatus.solved => '已破解',
        SolveStatus.noSolution => '无解',
        SolveStatus.timeout => '未决(超时)',
      };
}

/// 一条棋谱记录。
///
/// [moves] 携带完整棋子/吃子信息（区别于 saved_games 的裸坐标），
/// 由 [initialFen] 起重放即可在任意界面复原整局。
class GameRecord {
  GameRecord({
    this.id,
    required this.title,
    required this.mode,
    required this.initialFen,
    required this.moves,
    this.result,
    this.redName,
    this.blackName,
    this.solveStatus = SolveStatus.none,
    this.solutions = const [],
    this.llmNote,
    this.note,
    this.createdAt,
  });

  final int? id;
  final String title;

  /// 归属模式：GameMode.name，或残局工作室的 'endgame'。
  final String mode;

  /// 初始局面（残局为摆盘/导入/识图产生的局面）。
  final String initialFen;

  /// 对局/主变走法，含棋子与吃子信息。
  final List<Move> moves;

  /// 对局结果（进行中保存为 null）。
  final GameResult? result;

  final String? redName;
  final String? blackName;

  final SolveStatus solveStatus;

  /// 破解走法集合：每条为 ICCS 着法序列（自 [initialFen] 起）。
  final List<List<String>> solutions;

  /// 大模型辅助求解的思路注释（仅记录已通过求解器验证的结论）。
  final String? llmNote;

  final String? note;
  final DateTime? createdAt;

  bool get isEndgame => mode == GameRecord.endgameMode;

  /// 是否为唯一解（solved 且只有一条破解走法）。
  bool get hasUniqueSolution =>
      solveStatus == SolveStatus.solved && solutions.length == 1;

  /// 终局 FEN：从 initialFen 重放 moves 得到；重放失败回退 initialFen。
  String get finalFen {
    final board = Board.fromFen(initialFen);
    for (final m in moves) {
      if (board.pieceAtP(m.from) == null) break;
      board.applyMove(Move(from: m.from, to: m.to));
    }
    return board.toFen();
  }

  /// 模式中文标签。
  String get modeLabel => modeLabelOf(mode);

  static const String endgameMode = 'endgame';

  static String modeLabelOf(String mode) => switch (mode) {
        'humanVsAi' => '人机对战',
        'humanVsHuman' => '双人对弈',
        'aiVsAi' => '机机对战',
        'humanVsLlm' => '人机(大模型)',
        'llmVsLlm' => '大模型对战',
        endgameMode => '残局破解',
        _ => mode,
      };

  // ---------------------------------------------------------------------------
  // 序列化（sqlite 行 <-> 对象）
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toRowJson() => {
        'id': id,
        'title': title,
        'mode': mode,
        'initialFen': initialFen,
        'moves': moves.map(_encodeMove).toList(),
        'result': result?.name,
        'redName': redName,
        'blackName': blackName,
        'solveStatus': solveStatus.name,
        'solutions': solutions,
        'llmNote': llmNote,
        'note': note,
        'createdAt': createdAt?.toIso8601String(),
      };

  Map<String, dynamic> _encodeMove(Move m) => {
        'f': [m.from.col, m.from.row],
        't': [m.to.col, m.to.row],
        'p': m.piece?.fen,
        'x': m.captured?.fen,
      };

  static Move decodeMoveJson(Map<String, dynamic> json) {
    final f = (json['f'] as List).cast<int>();
    final t = (json['t'] as List).cast<int>();
    Piece? pieceAt(String? ch) =>
        ch == null ? null : pieceFromFenChar(ch);
    return Move(
      from: Position(f[0], f[1]),
      to: Position(t[0], t[1]),
      piece: pieceAt(json['p'] as String?),
      captured: pieceAt(json['x'] as String?),
    );
  }

  /// 便捷构造：从一局对局的完整走法历史组装棋谱。
  ///
  /// [moves] 需为 BoardViewModel 维护的含棋子信息的历史；
  /// 初始 FEN 通过从终局逐步悔棋反推（自动存档链路只保存终局 FEN）。
  static GameRecord fromSession({
    String? title,
    required String mode,
    required String finalFen,
    required List<Move> moves,
    GameResult? result,
    String? redName,
    String? blackName,
    String? note,
    DateTime? createdAt,
  }) {
    return GameRecord(
      title: title ?? _defaultTitle(mode),
      mode: mode,
      initialFen: _initialFenFromEnd(finalFen, moves),
      moves: List.of(moves),
      result: result,
      redName: redName,
      blackName: blackName,
      note: note,
      createdAt: createdAt ?? DateTime.now(),
    );
  }

  static String _defaultTitle(String mode) {
    final now = DateTime.now();
    final pad = (int v) => v.toString().padLeft(2, '0');
    return '${now.year}-${pad(now.month)}-${pad(now.day)} ${modeLabelOf(mode)}';
  }

  /// 从终局反推初始 FEN：逆序悔棋。
  static String _initialFenFromEnd(String finalFen, List<Move> moves) {
    final board = Board.fromFen(finalFen);
    for (final m in moves.reversed) {
      if (board.pieceAtP(m.to) == null) break; // 数据不一致时尽早止损
      board.undoMove(Move(from: m.from, to: m.to, captured: m.captured));
    }
    return board.toFen();
  }

  /// 走法的中文记谱序列（"炮二平五"风格），用于分享文本与走法列表。
  ///
  /// 以 [initialFen] 起重放补齐棋子信息，残局/自定义开局同样适用。
  List<String> chineseNotations() {
    final filled = fillMovePieces(initialFen, moves);
    return [
      for (final m in filled)
        m.piece == null ? IccsFallback.format(m) : m.chineseNotation(m.piece!),
    ];
  }
}

/// 中文记谱的兜底（走子信息缺失时退回 ICCS）。
class IccsFallback {
  IccsFallback._();

  static String format(Move m) =>
      '${_cell(m.from)}${_cell(m.to)}';

  static String _cell(Position p) {
    final file = 'a'.codeUnitAt(0) + p.col;
    return '${String.fromCharCode(file)}${9 - p.row}';
  }
}

/// 对 [moves] 重放补齐棋子/吃子信息（求解器等产生的裸走法用）。
///
/// 不改变传入列表；遇到与局面不符的走法即截断（防御式）。
List<Move> fillMovePieces(String initialFen, List<Move> moves) {
  final board = Board.fromFen(initialFen);
  final filled = <Move>[];
  for (final m in moves) {
    final piece = board.pieceAtP(m.from);
    if (piece == null) break;
    final applied = board.applyMove(Move(from: m.from, to: m.to));
    filled.add(Move(
      from: applied.from,
      to: applied.to,
      piece: piece,
      captured: applied.captured,
    ));
  }
  return filled;
}
