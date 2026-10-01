import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'app/app.dart';

/// 应用入口。
///
/// sqlite3_flutter_libs 在 native 层已注册 sqlite3 dynamic library resolver，
/// 因此无需显式初始化。挂载 [ChineseChessApp] 即可。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 日志输出到 debugPrint：此前 Logger.root 未配置，所有诊断日志被静默丢弃。
  // release 下控制在 INFO 级别（含）以上，debug 全量输出。
  Logger.root.level = kReleaseMode ? Level.INFO : Level.ALL;
  Logger.root.onRecord.listen((record) {
    debugPrint('${record.level.name} [${record.loggerName}] ${record.message}');
    if (record.error != null) debugPrint('  error: ${record.error}');
    if (record.stackTrace != null) debugPrint('${record.stackTrace}');
  });
  runApp(
    const ProviderScope(
      child: ChineseChessApp(),
    ),
  );
}
