import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chinese_chess_ultra/app/app.dart';
import 'package:chinese_chess_ultra/features/record/record_library_page.dart';
import 'package:chinese_chess_ultra/features/record/record_repository.dart';
import 'package:chinese_chess_ultra/features/storage/game_dao.dart';
import 'package:chinese_chess_ultra/features/studio/endgame_studio_page.dart';

/// TC-REG-003：主页四期新入口可进入；既有入口仍在。
void main() {
  testWidgets('主页含全部功能入口，棋谱库与残局工作室可进入', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final dao = GameDao.inMemory();
    addTearDown(dao.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recordRepositoryProvider.overrideWith((ref) => RecordRepository(dao)),
        ],
        child: const ChineseChessApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    // 既有入口（三期回归）。
    expect(find.text('残局选关'), findsOneWidget);
    expect(find.text('人机对战'), findsOneWidget);
    expect(find.text('人机对战（大模型）'), findsOneWidget);
    expect(find.text('大模型对战'), findsOneWidget);
    expect(find.text('双人对弈'), findsOneWidget);
    // 四期新入口。
    expect(find.text('残局工作室（摆盘/导入/求解）'), findsOneWidget);
    expect(find.text('棋谱库'), findsOneWidget);

    // 进入残局工作室。
    await tester.tap(find.text('残局工作室（摆盘/导入/求解）'));
    await tester.pumpAndSettle();
    expect(find.byType(EndgameStudioPage), findsOneWidget);
    expect(find.byIcon(Icons.tune), findsOneWidget); // 模型配置入口
    expect(find.text('保存棋局'), findsOneWidget);
    expect(find.text('AI 求破解'), findsOneWidget);

    // 返回主页 → 进入棋谱库。
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('棋谱库'));
    await tester.pumpAndSettle();
    expect(find.byType(RecordLibraryPage), findsOneWidget);
    // 空库引导文案。
    expect(find.textContaining('暂无棋谱'), findsOneWidget);
  });
}
