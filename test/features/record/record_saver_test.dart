import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chinese_chess_ultra/features/board/model/move.dart';
import 'package:chinese_chess_ultra/features/board/viewmodel/board_vm.dart';
import 'package:chinese_chess_ultra/features/record/game_record.dart';
import 'package:chinese_chess_ultra/features/record/record_repository.dart';
import 'package:chinese_chess_ultra/features/record/record_saver.dart';
import 'package:chinese_chess_ultra/features/storage/game_dao.dart';
import 'package:chinese_chess_ultra/features/storage/game_mode.dart';

/// TC-REC-001~010：对局中"保存为棋谱"与分享（record_saver.dart）。
void main() {
  late GameDao dao;

  setUp(() {
    dao = GameDao.inMemory();
  });

  tearDown(() {
    dao.dispose();
  });

  testWidgets('TC-REC-002/003 保存对话框：留空标题自动生成，落库含完整走法',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recordRepositoryProvider.overrideWith(
            (ref) => RecordRepository(dao),
          ),
        ],
        child: const MaterialApp(home: _Harness()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.bookmark_add_outlined));
    await tester.pumpAndSettle();
    expect(find.text('保存为棋谱'), findsOneWidget);

    // 标题留空 → 自动生成。
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.textContaining('棋谱已保存'), findsOneWidget);
    final records = dao.allRecords();
    expect(records.length, 1);
    expect(records.single.mode, GameMode.humanVsHuman.name);
    expect(records.single.moves.length, 1);
    expect(records.single.title, contains('双人对弈'));
  });

  testWidgets('TC-REC-003 填写标题与备注后保存', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recordRepositoryProvider.overrideWith(
            (ref) => RecordRepository(dao),
          ),
        ],
        child: const MaterialApp(home: _Harness()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.bookmark_add_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '棋谱标题（留空自动生成）'),
      '测试谱1',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '备注（可选）'),
      '备注内容',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final record = dao.allRecords().single;
    expect(record.title, '测试谱1');
    expect(record.note, '备注内容');
  });

  testWidgets('TC-REC-010 存储不可用时提示失败且不崩溃', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recordRepositoryProvider.overrideWith(
            (ref) => _ThrowingRepository(),
          ),
        ],
        child: const MaterialApp(home: _Harness()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.bookmark_add_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.textContaining('保存失败'), findsOneWidget);
  });

  testWidgets('TC-REC-009 分享棋局：剪贴板得到中文记谱文本', (tester) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = call.arguments['text'] as String;
        }
        return null;
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recordRepositoryProvider.overrideWith(
            (ref) => RecordRepository(dao),
          ),
        ],
        child: const MaterialApp(home: _Harness()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.share));
    await tester.pumpAndSettle();

    expect(clipboard, isNotNull);
    expect(clipboard!, contains('【中国象棋 Ultra 棋谱】'));
    expect(clipboard!, contains('炮二平五'));
  });
}

/// 最小宿主页：AppBar 挂"保存为棋谱"与"分享"按钮，进入时走一步炮二平五。
class _Harness extends ConsumerStatefulWidget {
  const _Harness();

  @override
  ConsumerState<_Harness> createState() => _HarnessState();
}

class _HarnessState extends ConsumerState<_Harness> {
  @override
  void initState() {
    super.initState();
    // 炮二平五（合法走法），产生一条含棋子信息的走法历史。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(boardViewModelProvider.notifier)
          .playMove(const Position(7, 7), const Position(4, 7));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          RecordSaver.button(context, ref, mode: GameMode.humanVsHuman),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => shareCurrentGame(context, ref),
          ),
        ],
      ),
      body: const SizedBox(),
    );
  }
}

class _ThrowingRepository extends RecordRepository {
  _ThrowingRepository() : super(GameDao.inMemory());

  @override
  int save(GameRecord record) => throw Exception('db locked');
}
