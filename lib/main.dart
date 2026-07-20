import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';

/// 应用入口。
///
/// sqlite3_flutter_libs 在 native 层已注册 sqlite3 dynamic library resolver，
/// 因此无需显式初始化。挂载 [ChineseChessApp] 即可。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: ChineseChessApp(),
    ),
  );
}
