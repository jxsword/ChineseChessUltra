import 'package:flutter/material.dart';

import '../features/puzzle/view/puzzle_list_page.dart';
import '../features/board/view/human_vs_ai_page.dart';
import '../features/board/view/human_vs_human_page.dart';
import '../features/board/view/human_vs_llm_page.dart';
import '../features/board/view/llm_vs_llm_page.dart';
import '../features/board/model/board_state.dart';
import '../features/board/view/widgets/board_widget.dart';
import '../features/record/record_library_page.dart';
import '../features/studio/endgame_studio_page.dart';
import '../features/settings/global_settings.dart';

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
      home: const MainNavigationPage(),
    );
  }
}

/// 主导航页面（二期 + 三三全局设置入口）。
///
/// 功能：
/// - 提供主要功能入口
/// - 残局选关
/// - 人机对战（内置 AI / 大模型）
/// - 大模型对战
/// - 双人对弈
/// - 全局设置（自动保存棋局开关）
class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  @override
  void initState() {
    super.initState();
    // 启动即加载持久化设置，棋盘页退出触发保存时读到的是真实开关值。
    GlobalSettings.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('中国象棋 Ultra'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _showGlobalSettings(context),
            tooltip: '全局设置',
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildNavigationButton(
              context,
              '残局选关',
              const Icon(Icons.grid_on),
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const PuzzleListPage(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildNavigationButton(
              context,
              '人机对战',
              const Icon(Icons.computer),
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const HumanVsAiPage(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildNavigationButton(
              context,
              '人机对战（大模型）',
              const Icon(Icons.psychology),
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const HumanVsLlmPage(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildNavigationButton(
              context,
              '大模型对战',
              const Icon(Icons.smart_toy),
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const LlmVsLlmPage(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildNavigationButton(
              context,
              '双人对弈',
              const Icon(Icons.people),
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const HumanVsHumanGamePage(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildNavigationButton(
              context,
              '残局工作室（摆盘/导入/求解）',
              const Icon(Icons.extension),
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const EndgameStudioPage(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildNavigationButton(
              context,
              '棋谱库',
              const Icon(Icons.menu_book),
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const RecordLibraryPage(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 全局设置弹窗：自动保存开关（改动即持久化）。
  Future<void> _showGlobalSettings(BuildContext context) async {
    // 打开前加载持久化值，避免展示进程内过期缓存。
    await GlobalSettings.instance.load();
    if (!context.mounted) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '全局设置',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SwitchListTile(
                      title: const Text('自动保存棋局'),
                      subtitle: const Text(
                        '离开棋盘或应用切后台时自动保存当前棋局；'
                        '关闭后仅点击棋盘页"保存棋局"按钮才保存。',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: GlobalSettings.instance.autoSave,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (value) {
                        GlobalSettings.instance.setAutoSave(value);
                        setSheetState(() {});
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 构建导航按钮。
  Widget _buildNavigationButton(
    BuildContext context,
    String title,
    Icon icon,
    VoidCallback onPressed,
  ) {
    return SizedBox(
      width: 200,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: icon,
        label: Text(title),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}
