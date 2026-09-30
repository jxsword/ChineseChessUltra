import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chinese_chess_ultra/app/app.dart';
import 'package:chinese_chess_ultra/features/storage/game_dao.dart';
import 'package:chinese_chess_ultra/features/storage/repository.dart';

void main() {
  testWidgets('应用启动后显示标题与主导航入口', (tester) async {
    // 用内存 SQLite 替代文件数据库，避免测试环境依赖 path_provider。
    final dao = GameDao.inMemory();
    final repo = GameRepository(dao);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gameRepositoryProvider.overrideWith((ref) => repo),
        ],
        child: const ChineseChessApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    // 标题
    expect(find.text('中国象棋 Ultra'), findsOneWidget);
    // 主导航入口（二期主导航页）
    expect(find.text('残局选关'), findsOneWidget);
    expect(find.text('人机对战'), findsOneWidget);
    expect(find.text('机器对战'), findsOneWidget);
    expect(find.text('双人对弈'), findsOneWidget);

    dao.dispose();
  });
}
