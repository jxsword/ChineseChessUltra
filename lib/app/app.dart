import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/board/view/board_page.dart';

/// 应用根 Widget。
class ChineseChessApp extends StatelessWidget {
  const ChineseChessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '中国象棋 Ultra',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF8D6E63),
        fontFamilyFallback: const ['Microsoft YaHei', 'PingFang SC', 'serif'],
      ),
      home: const BoardPage(),
    );
  }
}
