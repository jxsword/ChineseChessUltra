import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chinese_chess_ultra/features/board/view/widgets/board_layout.dart';
import 'package:chinese_chess_ultra/features/board/view/widgets/static_board_widget.dart';
import 'package:chinese_chess_ultra/features/record/game_record.dart';
import 'package:chinese_chess_ultra/features/record/record_repository.dart';
import 'package:chinese_chess_ultra/features/storage/game_dao.dart';
import 'package:chinese_chess_ultra/features/studio/endgame_studio_page.dart';

/// TC-SET / TC-FEN / TC-SOL（非视觉用例）：残局工作室自动化测试。
void main() {
  late GameDao dao;

  setUp(() {
    dao = GameDao.inMemory();
  });

  tearDown(() {
    dao.dispose();
  });

  Future<void> pumpStudio(WidgetTester tester) async {
    // 放大虚拟屏幕：保证摆盘页 ListView 全部子项（FEN 预览等）被构建、
    // 棋盘有足够点击精度（默认 800x600 下列表视口外子项不会构建）。
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recordRepositoryProvider.overrideWith(
            (ref) => RecordRepository(dao),
          ),
        ],
        child: const MaterialApp(home: EndgameStudioPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 点棋盘格位（StaticBoardWidget 内部用同一 BoardLayout 做命中检测）。
  Future<void> tapCell(WidgetTester tester, int col, int row) async {
    final rect = tester.getRect(find.byType(StaticBoardWidget));
    final layout = BoardLayout.fromSize(rect.size);
    await tester.tapAt(rect.topLeft + layout.offsetOf(col, row));
    await tester.pumpAndSettle();
  }

  Future<void> tapPalette(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).first);
    await tester.pumpAndSettle();
  }

  testWidgets('TC-SET-002/005 摆子后 FEN 预览实时更新', (tester) async {
    await pumpStudio(tester);
    await tapPalette(tester, '车');
    await tapCell(tester, 0, 5);
    expect(find.textContaining('R8'), findsOneWidget);

    await tapPalette(tester, '将');
    await tapCell(tester, 3, 0);
    await tapPalette(tester, '帅');
    await tapCell(tester, 4, 9);
    expect(find.textContaining('3k5'), findsOneWidget);
  });

  testWidgets('TC-SET 数量限制：第二个帅被拦截（放置时即校验）', (tester) async {
    await pumpStudio(tester);
    await tapPalette(tester, '帅');
    await tapCell(tester, 4, 9);
    await tapCell(tester, 3, 9); // 第二个红帅
    expect(find.textContaining('红方帅最多 1 枚'), findsOneWidget);
    // 棋盘上仍只有一枚帅（3,9 未落子）。
    expect(find.textContaining('3K'), findsNothing);
  });

  testWidgets('TC-SET 位置限制：士放九宫非斜线点被拦截，斜线点可放',
      (tester) async {
    await pumpStudio(tester);
    await tapPalette(tester, '仕');
    await tapCell(tester, 4, 7); // 九宫内但非斜线点
    expect(find.textContaining('士/仕只能放在九宫的 5 个斜线位置上'), findsOneWidget);

    await tapCell(tester, 4, 8); // 斜线点，合法
    expect(find.textContaining('4A4'), findsOneWidget); // 仕在 (4,8) → row8 '4A4'
  });

  testWidgets('TC-SET 相/象田字点校验：红相偶数排被拦截', (tester) async {
    await pumpStudio(tester);
    await tapPalette(tester, '相');
    await tapCell(tester, 0, 6); // 偶数排（6），田字不可达
    expect(find.textContaining('相只能放在己方半场 5/7/9 排'), findsOneWidget);

    await tapCell(tester, 0, 5); // 奇数排，合法
    expect(find.textContaining('B8'), findsOneWidget); // 相在 (0,5) → row5 'B8'
  });

  testWidgets('TC-SET-007 清空棋盘 / 初始局面', (tester) async {
    await pumpStudio(tester);
    await tapPalette(tester, '车');
    await tapCell(tester, 0, 5);
    await tester.tap(find.text('清空棋盘'));
    await tester.pumpAndSettle();
    expect(find.textContaining('9/9/9/9/9/9/9/9/9/9'), findsOneWidget);

    await tester.tap(find.text('初始局面'));
    await tester.pumpAndSettle();
    expect(find.textContaining('rnbakabnr'), findsOneWidget);
  });

  testWidgets('TC-SET-006/F1 空盘保存被拦截：必须有双方将帅', (tester) async {
    await pumpStudio(tester);
    await tester.tap(find.text('保存棋局'));
    await tester.pumpAndSettle();
    expect(find.textContaining('双方必须各有一个将/帅'), findsOneWidget);
    expect(dao.allRecords(), isEmpty);
  });

  testWidgets('TC-FEN-001/005 粘贴合法 FEN 载入并可保存/求解', (tester) async {
    await pumpStudio(tester);
    await tester.tap(find.text('FEN 导入'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      '3k5/9/9/9/R8/8R/9/9/9/4K4 w',
    );
    await tester.tap(find.text('解析并载入棋盘'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已载入'), findsOneWidget);
    // SnackBar 遮挡底部操作栏：等它消失再点"保存棋局"。
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // F1：保存棋局（未求解），落库 FEN 与输入一致。
    await tester.tap(find.text('保存棋局'));
    await tester.pumpAndSettle();
    expect(find.textContaining('棋局已保存到棋谱库'), findsOneWidget);
    final records = dao.allRecords();
    expect(records.length, 1);
    expect(records.single.solveStatus, SolveStatus.none);
    expect(records.single.isEndgame, isTrue);
    expect(records.single.initialFen,
        '3k5/9/9/9/R8/8R/9/9/9/4K4 w - - 0 1');
  });

  testWidgets('TC-FEN-003 非法 FEN 被拒绝', (tester) async {
    await pumpStudio(tester);
    await tester.tap(find.text('FEN 导入'));
    await tester.pumpAndSettle();
    // '4K5' 行共 10 列 → FEN 非法。
    await tester.enterText(find.byType(TextField), 'k8/9/9/9/9/9/9/9/9/4K5 w');
    await tester.tap(find.text('解析并载入棋盘'));
    await tester.pumpAndSettle();
    expect(find.textContaining('FEN 无效'), findsOneWidget);
  });

  testWidgets('TC-SOL-001/002 多解残局求解并自动入库',
      (tester) async {
    await pumpStudio(tester);
    await _importFen(tester, '3k5/9/9/9/R8/8R/9/9/9/4K4 w');
    await _solve(tester, dao, shallow: true);

    // 结果面板。
    expect(find.textContaining('已破解'), findsWidgets);
    // 自动入库为多解已破解。
    final records = dao.allRecords();
    expect(records.length, 1);
    expect(records.single.solveStatus, SolveStatus.solved);
    expect(records.single.solutions.length, greaterThanOrEqualTo(2));
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('TC-SOL-003 裸王无解：标记无解且仍入库', (tester) async {
    await pumpStudio(tester);
    await _importFen(tester, '3k5/9/9/9/9/9/9/9/9/4K4 w');
    await _solve(tester, dao, shallow: true);

    expect(find.textContaining('无解'), findsWidgets);
    final records = dao.allRecords();
    expect(records.length, 1);
    expect(records.single.solveStatus, SolveStatus.noSolution);
  }, timeout: const Timeout(Duration(minutes: 3)));
}

Future<void> _importFen(WidgetTester tester, String fen) async {
  await tester.tap(find.text('FEN 导入'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), fen);
  await tester.tap(find.text('解析并载入棋盘'));
  await tester.pumpAndSettle();
  // 导入成功的 SnackBar 悬浮在屏幕底部，会遮挡"保存棋局/AI 求破解"
  // 操作栏的点击：推进 5 秒虚拟时间让其自动消失。
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

/// 打开求解设置，选"浅（3 着内）"，开始求解并等待结果面板出现。
Future<void> _solve(WidgetTester tester, GameDao dao, {required bool shallow}) async {
  await tester.tap(find.text('AI 求破解'));
  await tester.pumpAndSettle(); // 求解设置对话框
  if (shallow) {
    await tester.tap(find.text('标准（5 着内）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('浅（3 着内）').last);
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('开始求解'));
  await tester.pump();

  // 求解在真实 Isolate 中运行：runAsync 短延时让 Isolate 真实推进，
  // pump 冲刷 FakeAsync 微任务队列驱动 _startSolve 的入库/结果面板。
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (dao.allRecords().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}
