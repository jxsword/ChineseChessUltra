import 'package:flutter/material.dart';

import '../board/model/board.dart';
import '../board/model/move.dart';
import '../board/model/move_notation.dart';
import '../board/view/widgets/static_board_widget.dart';
import '../puzzle/model/iccs.dart';
import 'game_record.dart';

/// 棋谱重放视图：主变（对局走法）与各条破解之法均可逐步演示。
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

  @override
  void initState() {
    super.initState();
    if (widget.record.moves.isEmpty && widget.record.solutions.isNotEmpty) {
      _line = 0;
    }
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

    return Column(
      children: [
        Expanded(
          child: StaticBoardWidget(board: _boardAt(clampedPos), lastMove: lastMove),
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
                        moves.isEmpty ? '主变（无着法）' : '主变（${moves.length} 着）',
                      ),
                    ),
                    for (var i = 0; i < lineCount; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text('解法 ${i + 1}（${widget.record.solutions[i].length} 着）'),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
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
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.first_page),
              onPressed: clampedPos > 0 ? () => setState(() => _pos = 0) : null,
            ),
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed:
                  clampedPos > 0 ? () => setState(() => _pos--) : null,
            ),
            Text(
              '${moves.isEmpty ? 0 : clampedPos} / ${moves.length} 着',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: clampedPos < moves.length
                  ? () => setState(() => _pos++)
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.last_page),
              onPressed: clampedPos < moves.length
                  ? () => setState(() => _pos = moves.length)
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
          onSelected: (_) => setState(() => _pos = index + 1),
        );
      },
    );
  }
}
