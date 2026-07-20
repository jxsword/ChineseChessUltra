import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chinese_chess_ultra/app/app.dart';
import 'package:chinese_chess_ultra/features/storage/game_dao.dart';
import 'package:chinese_chess_ultra/features/storage/repository.dart';

void main() {
  testWidgets('应用启动后显示标题与初始回合指示', (tester) async {
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
    // 回合指示
    expect(find.text('红方走棋'), findsOneWidget);
    // 操作按钮
    expect(find.text('悔棋'), findsOneWidget);
    expect(find.text('新游戏'), findsOneWidget);

    dao.dispose();
  });
}
