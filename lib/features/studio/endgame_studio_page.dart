import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../board/model/board.dart';
import '../board/model/fen.dart';
import '../board/model/move.dart';
import '../board/model/move_notation.dart';
import '../board/model/piece.dart';
import '../board/view/widgets/static_board_widget.dart';
import '../puzzle/model/iccs.dart';
import '../record/game_record.dart';
import '../record/record_repository.dart';
import '../shared/engine/llm_config.dart';
import '../shared/engine/llm_config_store.dart';
import '../shared/engine/llm_solve_assist.dart';
import '../shared/engine/move_source.dart';
import '../shared/engine/vision_board_reader.dart';
import '../solver/endgame_solver.dart';
import 'board_setup_rules.dart';
import 'assistant_config_dialog.dart';

/// 残局工作室：自己摆残局 / FEN 导入 / 图片 AI 识图，然后 AI 求破解。
///
/// 求解完成后（含无解/超时）自动把棋局与全部破解之法持久化为棋谱，
/// 以 [SolveStatus] 标记区分（docs/phase4/01 §3.4 状态机）。
class EndgameStudioPage extends ConsumerStatefulWidget {
  const EndgameStudioPage({super.key});

  @override
  ConsumerState<EndgameStudioPage> createState() => _EndgameStudioPageState();
}

class _EndgameStudioPageState extends ConsumerState<EndgameStudioPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  /// 编辑中的棋盘（10×9 矩阵，row 0 为黑方底线）。
  List<List<Piece?>> _grid = _emptyGrid();
  bool _redTurn = true;

  /// 摆盘面板当前选中的棋子（null 且非橡皮模式时点击为取走棋子）。
  Piece? _selectedPiece;
  bool _eraser = false;

  /// 图片识图的状态提示。
  bool _readingImage = false;
  String? _visionMessage;

  /// 识图已用时（秒），识别期间每秒刷新。
  Timer? _visionTimer;
  int _visionElapsed = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _visionTimer?.cancel();
    super.dispose();
  }

  static List<List<Piece?>> _emptyGrid() => List.generate(
        10,
        (_) => List<Piece?>.filled(9, null),
        growable: false,
      );

  String get _currentFen => Fen.build(board: _grid, isRedTurn: _redTurn);

  List<String> _validate() {
    final problems = <String>[];
    if (!Fen.isValid(_currentFen)) {
      problems.add('FEN 格式非法（每行列数必须为 9）');
      return problems;
    }
    var redKing = 0;
    var blackKing = 0;
    for (final row in _grid) {
      for (final piece in row) {
        if (piece?.kind == PieceKind.king) {
          piece!.side.isRed ? redKing++ : blackKing++;
        }
      }
    }
    if (redKing != 1 || blackKing != 1) {
      problems.add('双方必须各有一个将/帅（红 $redKing / 黑 $blackKing）');
    }
    if (problems.isNotEmpty) return problems;
    // 全盘棋子位置与数量合法性（FEN 导入/识图载入的棋盘同样校验）。
    final counts = <Piece, int>{};
    for (var row = 0; row < 10; row++) {
      for (var col = 0; col < 9; col++) {
        final piece = _grid[row][col];
        if (piece == null) continue;
        counts[piece] = (counts[piece] ?? 0) + 1;
        final issue = BoardSetupRules.placementIssue(piece, col, row);
        if (issue != null) {
          problems.add('($col,$row) ${piece.label}：$issue');
        }
      }
    }
    final countIssue = BoardSetupRules.countIssue(counts);
    if (countIssue != null) problems.add(countIssue);
    if (problems.isNotEmpty) return problems;
    final board = Board.fromFen(_currentFen);
    // 轮走方的对手不应正被将军（否则说明上一手未解除将军，局面非法）。
    if (board.isCheck(board.turn.opponent)) {
      problems.add('轮走方行棋前对方已被将军，局面非法');
    }
    if (!board.hasAnyLegalMoveFor(board.turn)) {
      problems.add('轮走方已无着可走（该局面已分胜负）');
    }
    return problems;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('残局工作室'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: '研究助手模型配置',
            onPressed: () => showAssistantConfigDialog(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 5,
            child: StaticBoardWidget(
              board: Board.fromFen(_currentFen),
              onCellTap: _onCellTap,
            ),
          ),
          Expanded(
            flex: 5,
            child: _buildControlArea(),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 摆盘编辑
  // ---------------------------------------------------------------------------

  void _onCellTap(int col, int row) {
    setState(() {
      if (_eraser) {
        _grid[row][col] = null;
        return;
      }
      final piece = _selectedPiece;
      if (piece != null) {
        final occupant = _grid[row][col];
        // 位置合法性：放置时即校验（九宫/士象斜线/兵卒底线等）。
        final issue = BoardSetupRules.placementIssue(piece, col, row);
        if (issue != null) {
          _toast(issue);
          return;
        }
        // 数量合法性：同格同子为替换（数量不变），否则校验上限。
        final countIssue = BoardSetupRules.countIssueForPlacement(
          piece,
          _countKind(piece),
          occupant: occupant,
        );
        if (countIssue != null) {
          _toast(countIssue);
          return;
        }
        _grid[row][col] = piece;
        return;
      }
      // 未选棋子：点击已有棋子为取走。
      _grid[row][col] = null;
    });
  }

  int _countKind(Piece piece) {
    var count = 0;
    for (final row in _grid) {
      for (final p in row) {
        if (p != null && p.kind == piece.kind && p.side == piece.side) {
          count++;
        }
      }
    }
    return count;
  }

  Widget _buildControlArea() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '摆盘'),
            Tab(text: 'FEN 导入'),
            Tab(text: '图片识图'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildSetupTab(),
              _buildFenTab(),
              _buildVisionTab(),
            ],
          ),
        ),
        _buildActionBar(),
      ],
    );
  }

  Widget _buildSetupTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            Text('行棋方: ', style: Theme.of(context).textTheme.titleSmall),
            Expanded(
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('红方')),
                  ButtonSegment(value: false, label: Text('黑方')),
                ],
                selected: {_redTurn},
                onSelectionChanged: (selection) =>
                    setState(() => _redTurn = selection.first),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildPalette(Side.red, '红子'),
        _buildPalette(Side.black, '黑子'),
        Row(
          children: [
            ChoiceChip(
              label: const Icon(Icons.cleaning_services, size: 18),
              selected: _eraser,
              onSelected: (v) => setState(() {
                _eraser = v;
                if (v) _selectedPiece = null;
              }),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () => setState(() => _grid = _emptyGrid()),
              icon: const Icon(Icons.delete_sweep),
              label: const Text('清空棋盘'),
            ),
            TextButton.icon(
              onPressed: () => setState(() {
                _grid = Fen.parseBoard(Fen.initial);
                _redTurn = true;
              }),
              icon: const Icon(Icons.restart_alt),
              label: const Text('初始局面'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '当前 FEN: ${_currentFen.split(' ').first}（${_redTurn ? '红' : '黑'}方行棋）',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildPalette(Side side, String label) {
    final pieces = [
      PieceKind.king,
      PieceKind.advisor,
      PieceKind.minister,
      PieceKind.knight,
      PieceKind.rook,
      PieceKind.cannon,
      PieceKind.pawn,
    ].map((kind) => Piece(kind: kind, side: side)).toList();
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: Wrap(
            spacing: 4,
            children: [
              for (final piece in pieces)
                ChoiceChip(
                  label: Text(piece.label),
                  selected: !_eraser && _selectedPiece == piece,
                  onSelected: (selected) => setState(() {
                    _selectedPiece = selected ? piece : null;
                    if (selected) _eraser = false;
                  }),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // FEN 导入
  // ---------------------------------------------------------------------------

  Widget _buildFenTab() {
    final controller = TextEditingController();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '粘贴 FEN（或仅棋盘部分）',
            hintText:
                'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: () => _importFen(controller.text),
          icon: const Icon(Icons.download),
          label: const Text('解析并载入棋盘'),
        ),
        const SizedBox(height: 8),
        const Text(
          '说明：完整 FEN 或仅棋盘字段均可；轮走方取 FEN 第二字段，'
          '缺省按红方处理。载入后可在摆盘页微调。',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  void _importFen(String raw) {
    var fen = raw.trim();
    if (fen.isEmpty) return;
    if (fen.split(RegExp(r'\s+')).length == 1) {
      fen = '$fen ${_redTurn ? 'w' : 'b'}';
    }
    if (!Fen.isValid(fen)) {
      _toast('FEN 无效，请检查格式');
      return;
    }
    setState(() {
      _grid = Fen.parseBoard(fen);
      _redTurn = Fen.parseTurn(fen);
    });
    _toast('已载入（${_redTurn ? '红' : '黑'}方行棋），可在摆盘页微调');
  }

  // ---------------------------------------------------------------------------
  // 图片识图（多模态大模型）
  // ---------------------------------------------------------------------------

  Widget _buildVisionTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        FilledButton.tonalIcon(
          onPressed: _readingImage ? null : _pickAndReadImage,
          icon: _readingImage
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.image_search),
          label: const Text('选择棋盘图片并识别'),
        ),
        if (_readingImage)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '识别中… 已用时 $_visionElapsed 秒'
              '（一般 5~20 秒；大图或思考型模型会更久，超时上限 120 秒）',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => showAssistantConfigDialog(context),
          icon: const Icon(Icons.tune),
          label: const Text('配置识图模型（需视觉模型）'),
        ),
        if (_visionMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _visionMessage!,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 8),
        const Text(
          '识别结果会载入上方棋盘，请人工核对每个棋子后再求解'
          '（模型可能漏识别或错认棋子）。建议使用棋盘截图或正俯拍照片。',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Future<void> _pickAndReadImage() async {
    setState(() {
      _readingImage = true;
      _visionMessage = null;
    });
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      final bytes = picked?.files.single.bytes;
      // 计时从"图片已选中"开始：文件浏览期间不计入。
      if (bytes != null) {
        setState(() => _visionElapsed = 0);
        _visionTimer?.cancel();
        _visionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() => _visionElapsed++);
        });
        await _readImage(bytes);
      }
    } on Object catch (e) {
      if (mounted) setState(() => _visionMessage = '识图失败：$e');
    } finally {
      _visionTimer?.cancel();
      if (mounted) setState(() => _readingImage = false);
    }
  }

  Future<void> _readImage(Uint8List bytes) async {
    final config = await LlmConfigStore().loadAssistant();
    if (!config.isConfigured) {
      setState(() => _visionMessage = '请先配置研究助手模型（需视觉模型）');
      return;
    }
    try {
      final result = await VisionBoardReader()
          .readBoard(config: config, imageBytes: bytes);
      if (!mounted) return;
      setState(() {
        _grid = Fen.parseBoard(result.fen);
        _redTurn = Fen.parseTurn(result.fen);
        _visionMessage =
            '识别到 ${result.pieceCount} 枚棋子（${_redTurn ? '红' : '黑'}方行棋），'
            '已载入棋盘，请人工核对后再求解';
      });
    } on Object catch (e) {
      if (mounted) setState(() => _visionMessage = '识图失败：$e');
    }
  }

  // ---------------------------------------------------------------------------
  // 求解与入库
  // ---------------------------------------------------------------------------

  Widget _buildActionBar() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _saveUnsolvedRecord,
              icon: const Icon(Icons.bookmark_add_outlined),
              label: const Text('保存棋局'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: _startSolve,
              icon: const Icon(Icons.psychology_alt),
              label: const Text('AI 求破解'),
            ),
          ),
        ],
      ),
    );
  }

  /// 手动保存当前残局（未求解状态直接入库；求解后另有自动入库）。
  Future<void> _saveUnsolvedRecord() async {
    final problems = _validate();
    if (problems.isNotEmpty) {
      _toast(problems.join('；'));
      return;
    }
    try {
      final now = DateTime.now();
      final pad = (int v) => v.toString().padLeft(2, '0');
      final record = GameRecord(
        title:
            '${now.month}-${pad(now.day)} ${_redTurn ? '红' : '黑'}方残局（未求解）',
        mode: GameRecord.endgameMode,
        initialFen: _currentFen,
        moves: const [],
        solveStatus: SolveStatus.none,
        createdAt: now,
      );
      final repo = await ref.read(recordRepositoryProvider.future);
      repo.save(record);
      if (!mounted) return;
      _toast('棋局已保存到棋谱库（未求解）');
    } on Object {
      if (!mounted) return;
      _toast('保存失败：本地存储不可用');
    }
  }

  Future<void> _startSolve() async {
    final problems = _validate();
    if (problems.isNotEmpty) {
      _toast(problems.join('；'));
      return;
    }
    final fen = _currentFen;
    final options = await _showSolveOptions();
    if (options == null || !mounted) return;

    final progress = _SolveProgress.show(context);
    String? llmNote;
    if (options.useLlm) {
      llmNote = await _runLlmAssist(fen, options);
    }

    SolveResult result;
    try {
      result = await EndgameSolver.solve(
        fen,
        timeLimit: options.timeLimit,
        maxPlies: options.maxPlies,
      );
    } on Object catch (e) {
      progress.close();
      if (mounted) _toast('求解失败：$e');
      return;
    }
    progress.close();
    if (!mounted) return;

    final recordId = await _persistRecord(fen, result, llmNote);
    if (!mounted) return;
    _showSolveResult(fen, result, llmNote, recordId);
  }

  /// 大模型辅助（Hybrid）：模型提议首着与思路，求解器验证后才写入注释。
  Future<String?> _runLlmAssist(String fen, _SolveOptions options) async {
    final config = await LlmConfigStore().loadAssistant();
    if (!config.isConfigured) return null;
    try {
      final (proposal, message) =
          await LlmSolveAssist(config: config).propose(
        Board.fromFen(fen),
      );
      final code = proposal?.firstMoveCode;
      if (code == null) {
        return '大模型辅助未给出有效提议（$message）';
      }
      // extract 返回 "h2-e2" 格式；解析前归一化掉分隔符。
      final normalized = code.replaceAll(RegExp(r'[^a-i0-9]'), '');
      if (normalized.length != 4) {
        return '大模型辅助未给出有效提议（$message）';
      }
      final from = decodeCell(normalized.substring(0, 2));
      final to = decodeCell(normalized.substring(2, 4));
      if (from == null || to == null) return null;
      final verified = EndgameSolver.isWinningFirstMove(
        fen: fen,
        firstMove: Move(from: from, to: to),
        plies: options.maxPlies,
        timeLimit: options.timeLimit,
      );
      final idea = proposal?.idea;
      return verified
          ? '大模型首选 $code（已验证为必胜着法）'
              '${idea == null ? '' : '；思路: $idea'}'
          : '大模型首选 $code 未通过求解器验证，已忽略'
              '${idea == null ? '' : '；思路: $idea'}';
    } on Object catch (e) {
      return '大模型辅助调用失败：$e';
    }
  }

  Future<_SolveOptions?> _showSolveOptions() {
    var timeLimit = const Duration(seconds: 30);
    var maxPlies = 9;
    var useLlm = false;
    return showDialog<_SolveOptions>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('求解设置'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<Duration>(
                initialValue: const Duration(seconds: 30),
                decoration: const InputDecoration(labelText: '限时'),
                items: const [
                  DropdownMenuItem(
                      value: Duration(seconds: 10), child: Text('10 秒')),
                  DropdownMenuItem(
                      value: Duration(seconds: 30), child: Text('30 秒')),
                  DropdownMenuItem(
                      value: Duration(seconds: 60), child: Text('1 分钟')),
                  DropdownMenuItem(
                      value: Duration(minutes: 3), child: Text('3 分钟')),
                ],
                onChanged: (v) => setDialogState(() => timeLimit = v!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: 9,
                decoration: const InputDecoration(
                  labelText: '搜索深度（求解方着数）',
                ),
                items: const [
                  DropdownMenuItem(value: 5, child: Text('浅（3 着内）')),
                  DropdownMenuItem(value: 9, child: Text('标准（5 着内）')),
                  DropdownMenuItem(value: 13, child: Text('深（7 着内，较慢）')),
                ],
                onChanged: (v) => setDialogState(() => maxPlies = v!),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('大模型辅助'),
                subtitle: const Text(
                  '模型提议首着，求解器验证后写入注释',
                  style: TextStyle(fontSize: 12),
                ),
                value: useLlm,
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => setDialogState(() => useLlm = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                _SolveOptions(
                  timeLimit: timeLimit,
                  maxPlies: maxPlies,
                  useLlm: useLlm,
                ),
              ),
              child: const Text('开始求解'),
            ),
          ],
        ),
      ),
    );
  }

  /// 求解结论自动落库：solved/noSolution/timeout 全部持久化。
  Future<int?> _persistRecord(
    String fen,
    SolveResult result,
    String? llmNote,
  ) async {
    try {
      final record = GameRecord(
        title: _recordTitle(result),
        mode: GameRecord.endgameMode,
        initialFen: fen,
        moves: const [],
        solveStatus: switch (result.status) {
          EndgameSolveStatus.solved => SolveStatus.solved,
          EndgameSolveStatus.noSolution => SolveStatus.noSolution,
          EndgameSolveStatus.timeout => SolveStatus.timeout,
        },
        solutions: [
          for (final solution in result.solutions)
            [
              for (final m in solution.moves) Iccs.format(m.from, m.to) ?? '',
            ].where((s) => s.isNotEmpty).toList(),
        ],
        llmNote: llmNote,
        createdAt: DateTime.now(),
      );
      final repo = await ref.read(recordRepositoryProvider.future);
      return repo.save(record);
    } on Object {
      return null;
    }
  }

  String _recordTitle(SolveResult result) {
    final now = DateTime.now();
    final pad = (int v) => v.toString().padLeft(2, '0');
    final statusLabel = switch (result.status) {
      EndgameSolveStatus.solved => result.unique ? '唯一解' : '多解',
      EndgameSolveStatus.noSolution => '无解',
      EndgameSolveStatus.timeout => '未决',
    };
    return '${now.month}-${pad(now.day)} ${_redTurn ? '红' : '黑'}方残局（$statusLabel）';
  }

  void _showSolveResult(
    String fen,
    SolveResult result,
    String? llmNote,
    int? recordId,
  ) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        switch (result.status) {
                          EndgameSolveStatus.solved => Icons.emoji_events,
                          EndgameSolveStatus.noSolution => Icons.block,
                          EndgameSolveStatus.timeout => Icons.hourglass_bottom,
                        },
                        color: switch (result.status) {
                          EndgameSolveStatus.solved => Colors.amber,
                          EndgameSolveStatus.noSolution => Colors.red,
                          EndgameSolveStatus.timeout => Colors.orange,
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          switch (result.status) {
                            EndgameSolveStatus.solved => result.unique
                                ? '已破解（唯一解）'
                                : '已破解（${result.solutions.length} 条破解走法）',
                            EndgameSolveStatus.noSolution =>
                              '无解（${result.searchedPlies} 半着内已证明）',
                            EndgameSolveStatus.timeout => '限时内未找到解法',
                          },
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '用时 ${(result.elapsed.inMilliseconds / 1000.0).toStringAsFixed(1)}s，'
                    '已保存到棋谱库${recordId == null ? '失败' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (llmNote != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      llmNote,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (result.status == EndgameSolveStatus.solved &&
                      result.solutions.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('对方已被将死/困毙，无需再走。'),
                    ),
                  for (var i = 0; i < result.solutions.length; i++) ...[
                    const SizedBox(height: 8),
                    Text(
                      '解法 ${i + 1}（${_redTurn ? '红' : '黑'}方先行）:',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      _chineseLine(fen, result.solutions[i].moves),
                      style: const TextStyle(height: 1.4),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 解法线路的中文记谱（"炮二平五 马8进7 ..."）。
  String _chineseLine(String fen, List<Move> moves) {
    final filled = fillMovePieces(fen, moves);
    return [
      for (final m in filled)
        m.piece == null ? '' : m.chineseNotation(m.piece!),
    ].where((s) => s.isNotEmpty).join('  ');
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

/// 求解设置。
class _SolveOptions {
  const _SolveOptions({
    required this.timeLimit,
    required this.maxPlies,
    required this.useLlm,
  });

  final Duration timeLimit;
  final int maxPlies;
  final bool useLlm;
}

/// 求解进度弹窗：计时展示，完成时关闭。
class _SolveProgress {
  _SolveProgress._(this._context) {
    _watch.start();
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _elapsed.value = _elapsedText;
    });
    showDialog<void>(
      context: _context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('求解中…'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
              ValueListenableBuilder<String>(
                valueListenable: _elapsed,
                builder: (context, value, _) => Text('已用时 $value'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  factory _SolveProgress.show(BuildContext context) => _SolveProgress._(context);

  final BuildContext _context;
  final Stopwatch _watch = Stopwatch();
  late final Timer _timer;
  bool _closed = false;
  final ValueNotifier<String> _elapsed = ValueNotifier('0.0s');

  String get _elapsedText =>
      '${(_watch.elapsed.inMilliseconds / 1000.0).toStringAsFixed(1)}s';

  void close() {
    if (_closed) return;
    _closed = true;
    _timer.cancel();
    _elapsed.dispose();
    Navigator.of(_context, rootNavigator: true).pop();
  }
}
