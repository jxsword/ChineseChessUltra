import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../model/puzzle_data.dart';
import 'puzzle_detail_page.dart';

/// 残局选关列表页面
class PuzzleListPage extends ConsumerStatefulWidget {
  const PuzzleListPage({super.key});

  @override
  ConsumerState<PuzzleListPage> createState() => _PuzzleListPageState();
}

class _PuzzleListPageState extends ConsumerState<PuzzleListPage> {
  // 示例残局数据
  final List<ParsedPuzzle> _puzzles = [
    ParsedPuzzle(
      id: 'puzzle_001',
      initialFen: 'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1',
      solutionMoves: ['h2e2', 'h9g7', 'e3e4', 'b9c7', 'e4e5', 'c7d5', 'e5e6'],
      title: '炮打三军',
      description: '经典的残局杀法演示',
      source: '适情雅趣',
      format: 'xqf',
      difficulty: 2,
    ),
    ParsedPuzzle(
      id: 'puzzle_002',
      initialFen: 'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1',
      solutionMoves: ['h2e2', 'c6c5', 'e3e4', 'c5c4', 'e4e5', 'c4d4', 'e5e6'],
      title: '马炮争功',
      description: '马炮配合的精妙杀法',
      source: '竹香斋',
      format: 'pgn',
      difficulty: 3,
    ),
    ParsedPuzzle(
      id: 'puzzle_003',
      initialFen: 'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1',
      solutionMoves: ['a3a4', 'b9c7', 'a4a5', 'h9g7', 'a5a6', 'g7f5', 'a6b6'],
      title: '单车破士象',
      description: '单车残局的基本杀法',
      source: '象棋经典',
      format: 'xqf',
      difficulty: 1,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('残局选关'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _importPuzzle,
            tooltip: '导入残局',
          ),
        ],
      ),
      body: _buildPuzzleList(),
    );
  }

  Widget _buildPuzzleList() {
    if (_puzzles.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.extension_off,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              '暂无残局',
              style: TextStyle(fontSize: 18),
            ),
            SizedBox(height: 8),
            Text(
              '点击右上角导入按钮添加残局',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _puzzles.length,
      itemBuilder: (context, index) {
        final puzzle = _puzzles[index];
        return _buildPuzzleCard(puzzle);
      },
    );
  }

  Widget _buildPuzzleCard(ParsedPuzzle puzzle) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: InkWell(
        onTap: () => _onPuzzleSelected(puzzle),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      puzzle.title ?? '残局${puzzle.id}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  _buildDifficultyBadge(puzzle.difficulty),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                puzzle.source ?? '未知来源',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              if (puzzle.description != null) ...[
                const SizedBox(height: 8),
                Text(
                  puzzle.description!,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '走法: ${puzzle.moveCount} 步',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                  Text(
                    puzzle.format.toUpperCase(),
                    style: TextStyle(
                      fontSize: 12,
                      color: _getFormatColor(puzzle.format),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDifficultyBadge(int difficulty) {
    Color color;
    switch (difficulty) {
      case 1:
        color = Colors.green;
        break;
      case 2:
        color = Colors.blue;
        break;
      case 3:
        color = Colors.orange;
        break;
      case 4:
        color = Colors.red;
        break;
      case 5:
        color = Colors.purple;
        break;
      default:
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(
        '${'★' * difficulty}${'☆' * (5 - difficulty)}',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _getFormatColor(String format) {
    switch (format.toLowerCase()) {
      case 'xqf':
        return Colors.blue;
      case 'pgn':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  void _onPuzzleSelected(ParsedPuzzle puzzle) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PuzzleDetailPage(puzzle: puzzle),
      ),
    );
  }

  void _importPuzzle() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xqf', 'pgn'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        // TODO: 实现实际的文件解析逻辑
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已导入文件: ${file.name}'),
            action: SnackBarAction(
              label: '查看',
              onPressed: () {
                // TODO: 解析并显示导入的残局
              },
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('导入失败: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}