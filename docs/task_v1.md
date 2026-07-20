请根据以下要求实现一个中国象棋 Flutter 应用。

### 任务依据
- 项目需求文档已保存在 `docs/srs.md` 文件中，请首先完整阅读该文件。
- 严格按照文档中描述的**第一期功能**（跨平台 Win11/Android、双人单机对弈、走法规则引擎、输赢判定、棋局自动保存与恢复）实现。
- 技术选型：Flutter 3.x + Riverpod 3.x + shirne/chinese_chess 规则引擎（直接拷贝其 lib/ 目录代码，无需自行实现走法逻辑）+ drift (SQLite) 持久化。

### 具体要求
1. **项目结构**：采用 MVVM 架构，Feature-First 组织（board / storage / puzzle 等目录），参考 docs/srs.md 中的目录树。
2. **规则引擎**：将 shirne/chinese_chess 项目的 `lib/` 下规则相关文件（board.dart, piece.dart, fen.dart 等）直接复制到 `features/board/model/`，不做修改。
3. **输赢判定**：直接使用引擎提供的 `isCheckmate()` 和 `isStalemate()` 方法。
4. **UI**：使用 CustomPainter 绘制 9×10 棋盘，支持鼠标/触控选中棋子、高亮合法走法、走子动画。右侧面板显示回合指示、走法记录列表、悔棋按钮、新游戏按钮。
5. **自动保存**：每次走子后写入 drift 数据库（表结构见 docs/srs.md），App 生命周期 paused 时强制保存；启动时自动恢复最近一局。
6. **平台适配**：先完成 Windows 桌面版本（可运行 exe），代码架构兼容 Android（响应式布局，竖屏时棋盘居中，面板折叠到底部）。
7. **代码质量**：所有 ViewModel 使用 Riverpod Notifier/AsyncNotifier，UI 组件为 ConsumerWidget；提供必要的单元测试（至少测试走法合法性和将死判定）。
8. **输出**：生成完整的 Flutter 项目文件夹，包含 `pubspec.yaml`、所有 Dart 源文件、资源文件（如有）、以及运行说明 README.md。

### 注意事项
- 规则引擎代码来自 shirne/chinese_chess（GPL-2.0），本项目为非商用学习，可忽略许可问题。
- 不要实现第二期功能（残局导入、AI 提示等），但需在代码中预留接口（如 PuzzleParser 抽象类、HintStrategy 接口）。
- 确保代码能在 Windows 上直接 `flutter run -d windows` 编译运行。