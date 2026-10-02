import 'dart:async';

import 'package:flutter/material.dart';

import '../board/model/board.dart';
import '../board/model/move.dart';
import '../board/model/move_notation.dart';
import '../board/view/widgets/static_board_widget.dart';
import '../puzzle/model/iccs.dart';
import 'game_record.dart';

/// 棋谱重放视图：主变（对局走法）与各条破解之法均可逐步演示，
/// 支持自动播放（破解演示）。
class ReplayBoardView extends StatefulWidget {
  const ReplayBoardView({super.key, required this.record});

  final GameRecord record;

  @override
  State<ReplayBoardView> createState() => _ReplayBoardViewState();
}

class _ReplayBoardViewState extends State<ReplayBoardView> {
  /// 当前展示的线路：-1 = 主变（对局走法），>=0 = 解法序号。
  int _line = -1;

  /// 线路内已演示的着数（0 = 初始局面）。
  int _pos = 0;

  /// 演示播放状态（破解演示）。
  bool _playing = false;

  /// 播放速度倍率（步进间隔 = 基础间隔 / 倍率）。
  double _speed = 1.0;

  Timer? _playTimer;

  static const _baseInterval = Duration(milliseconds: 900);

  @override
  void initState() {
    super.initState();
    // 残局类（无对局走法、有解法）默认进入第一条解法，便于直接演示。
    if (widget.record.moves.isEmpty && widget.record.solutions.isNotEmpty) {
      _line = 0;
    }
  }

  @override
  void dispose() {
    _playTimer?.cancel();
    super.dispose();
  }

  void _stopPlaying() {
    _playTimer?.cancel();
    _playTimer = null;
    if (_playing && mounted) setState(() => _playing = false);
  }

  void _togglePlaying() {
    if (_playing) {
      _stopPlaying();
      return;
    }
    // 已到线路尽头：从头播放。
    if (_pos >= _moves.length) {
      setState(() => _pos = 0);
    }
    setState(() => _playing = true);
    _scheduleTick();
  }

  void _scheduleTick() {
    _playTimer?.cancel();
    _playTimer = Timer(_baseInterval * (1 / _speed), () {
      if (!mounted || !_playing) return;
      if (_pos >= _moves.length) {
        _stopPlaying();
        return;
      }
      setState(() => _pos++);
      if (_pos >= _moves.length) {
        _stopPlaying();
      } else {
        _scheduleTick();
      }
    });
  }

  /// 当前线路的走法（含棋子信息）。
  List<Move> get _moves {
    if (_line < 0) return widget.record.moves;
    if (_line >= widget.record.solutions.length) return const [];
    final iccsList = widget.record.solutions[_line];
    final raw = <Move>[];
    for (final code in iccsList) {
      final parsed = Iccs.parse(code);
      if (parsed == null) continue;
      raw.add(Move(from: parsed.from, to: parsed.to));
    }
    return fillMovePieces(widget.record.initialFen, raw);
  }

  /// 重放第 [n] 着后的棋盘。
  Board _boardAt(int n) {
    final board = Board.fromFen(widget.record.initialFen);
    final moves = _moves;
    for (var i = 0; i < n && i < moves.length; i++) {
      final m = moves[i];
      if (board.pieceAtP(m.from) == null) break;
      board.applyMove(Move(from: m.from, to: m.to));
    }
    return board;
  }

  @override
  Widget build(BuildContext context) {
    final moves = _moves;
    final clampedPos = _pos.clamp(0, moves.length);
    final lastMove = clampedPos == 0 ? null : moves[clampedPos - 1];
    final lineCount = widget.record.solutions.length;
    final hasMoves = moves.isNotEmpty;

    return Column(
      children: [
        Expanded(
          child: StaticBoardWidget(
              board: _boardAt(clampedPos), lastMove: lastMove),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Text('线路: ', style: Theme.of(context).textTheme.bodySmall),
              Expanded(
                child: DropdownButton<int>(
                  value: _line.clamp(-1, lineCount - 1),
                  isExpanded: true,
                  items: [
                    DropdownMenuItem(
                      value: -1,
                      child: Text(
                        // 主变标签始终取棋谱主变的着数，不受当前线路影响。
                        widget.record.moves.isEmpty
                            ? '主变（无着法）'
                            : '主变（${widget.record.moves.length} 着）',
                      ),
                    ),
                    for (var i = 0; i < lineCount; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text(
                            '解法 ${i + 1}（${widget.record.solutions[i].length} 着）'),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    _stopPlaying();
                    setState(() {
                      _line = value;
                      _pos = 0;
                    });
                  },
                ),
              ),
            ],
          ),
        ),
        // 演示播放控制条：有走法的线路可自动播放。
        if (hasMoves)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: _playing ? '暂停' : '播放演示',
                icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                onPressed: _togglePlaying,
              ),
              IconButton(
                tooltip: '重置',
                icon: const Icon(Icons.replay),
                onPressed: () {
                  _stopPlaying();
                  setState(() => _pos = 0);
                },
              ),
              PopupMenuButton<double>(
                tooltip: '播放速度',
                initialValue: _speed,
                onSelected: (speed) {
                  setState(() => _speed = speed);
                  if (_playing) _scheduleTick(); // 立即按新速度重排
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 0.5, child: Text('0.5×')),
                  PopupMenuItem(value: 1.0, child: Text('1×')),
                  PopupMenuItem(value: 2.0, child: Text('2×')),
                ],
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    '${_speed}×',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.first_page),
              onPressed: clampedPos > 0
                  ? () {
                      _stopPlaying();
                      setState(() => _pos = 0);
                    }
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: clampedPos > 0
                  ? () {
                      _stopPlaying();
                      setState(() => _pos--);
                    }
                  : null,
            ),
            Text(
              '$clampedPos / ${moves.length} 着',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: clampedPos < moves.length
                  ? () {
                      _stopPlaying();
                      setState(() => _pos++);
                    }
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.last_page),
              onPressed: clampedPos < moves.length
                  ? () {
                      _stopPlaying();
                      setState(() => _pos = moves.length);
                    }
                  : null,
            ),
          ],
        ),
        SizedBox(
          height: 72,
          child: _notationList(moves, clampedPos),
        ),
      ],
    );
  }

  /// 中文记谱序列（横向滚动，当前着高亮）。
  Widget _notationList(List<Move> moves, int clampedPos) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      itemCount: moves.length,
      separatorBuilder: (_, __) => const SizedBox(width: 4),
      itemBuilder: (context, index) {
        final move = moves[index];
        final piece = move.piece;
        final text = piece == null
            ? '${move.from.col},${move.from.row}->${move.to.col},${move.to.row}'
            : move.chineseNotation(piece);
        return ChoiceChip(
          label: Text(
            '${index ~/ 2 + 1}.${index.isOdd ? '..' : ''} $text',
            style: const TextStyle(fontSize: 12),
          ),
          selected: index < clampedPos,
          onSelected: (_) {
            _stopPlaying();
            setState(() => _pos = index + 1);
          },
        );
      },
    );
  }
}
