# 中国象棋 Ultra - Phase 2

## 项目概述

中国象棋 Ultra 是一款跨平台（Windows/Android）的中国象棋单机对弈应用，基于 Flutter + Riverpod + SQLite3 开发。

## 功能特性

### Phase 1（已完成）
- 跨平台支持：Windows 11 + Android
- 双人单机对弈：红黑轮流走子，合法走法高亮，走子动画
- 规则引擎：直接拷贝 `shirne/chinese_chess` 的 `lib/` 目录，不做修改
- 输赢判定：使用引擎的 `isCheckmate()` 和 `isStalemate()` 方法
- 自动保存/恢复：每次走子后写入 drift 数据库，App 生命周期 paused 时强制保存；启动时自动恢复最近一局
- 悔棋：支持双方各自撤销上一步走子（可连续悔棋）
- 新游戏/重新开始：重置棋盘至初始布局

### Phase 2（新增）
- 📚 **残局棋谱导入**：支持 `.pgn` 和 `.xqf` 格式
- 🎬 **破解演示**：点击"提示"按钮，按棋谱中记录的破解走法逐手演示
- 🤖 **AI 智能提示**：接入 Pikafish 引擎，对当前局面计算最佳走法
- 👥 **人机对战**：玩家执一方，另一方由 AI 控制，可选择难度级别
- 🤖🤖 **机器对机器对战**：两个 AI 引擎自动对弈

## 技术栈

| 层级 | 技术 |
|------|------|
| 跨平台 UI | Flutter 3.x |
| 状态管理 | Riverpod 3.x（`flutter_riverpod`） |
| 象棋规则引擎 | shirne/chinese_chess（拷贝 `lib/` 目录代码，不做修改） |
| AI 引擎 | Pikafish（UCI 协议，Win/Android 二进制） |
| 持久化 | drift（SQLite） |
| 棋谱解析 | 自建 `PuzzleParser` 策略模式（支持 XQF / PGN） |

## 项目结构

```
lib/
├── main.dart
├── app/
│   ├── app.dart                    # MaterialApp + 主题
│   └── providers.dart              # 全局 Provider 注册
├── features/
│   ├── board/                      # 棋盘对弈
│   │   ├── view/
│   │   │   ├── board_page.dart
│   │   │   ├── human_vs_ai_page.dart # 人机对战
│   │   │   ├── ai_vs_ai_page.dart   # 机器对战
│   │   │   └── widgets/
│   │   │       ├── board_painter.dart
│   │   │       ├── piece_widget.dart
│   │   │       └── hint_overlay.dart
│   │   ├── viewmodel/
│   │   │   ├── board_vm.dart       # Notifier<BoardState>
│   │   │   └── engine_vm.dart      # AsyncNotifier（二期新增）
│   │   └── model/
│   │       ├── board.dart          # 棋盘状态
│   │       ├── fen.dart            # FEN 编解码
│   │       └── move.dart           # 走法表示
│   ├── puzzle/                     # 残局功能
│   │   ├── view/
│   │   │   ├── puzzle_list_page.dart    # 残局选关列表
│   │   │   └── puzzle_detail_page.dart  # 单局演示页
│   │   ├── viewmodel/
│   │   │   └── puzzle_vm.dart
│   │   └── model/
│   │       ├── puzzle_parser.dart       # 抽象解析器接口
│   │       ├── parsers/
│   │       │   ├── xqf_parser.dart      # XQF 解析器
│   │       │   └── pgn_parser.dart      # PGN 解析器
│   │       └── puzzle_data.dart         # ParsedPuzzle 模型
│   └── storage/
│       ├── dao/
│       │   └── game_dao.dart       # drift DAO
│       └── repository.dart         # 仓储层
├── shared/
│   ├── engine/
│   │   ├── pikafish_bridge.dart    # UCI 通信封装
│   │   └── hint_strategy.dart      # 提示策略接口
│   └── constants.dart
```

## 使用说明

### 1. 运行项目

```bash
# 克隆项目
git clone <repository-url>
cd chinese_chess_ultra

# 安装依赖
flutter pub get

# 运行
flutter run
```

### 2. 添加新残局

1. 将 `.xqf` 或 `.pgn` 文件放入 `assets/puzzles/` 目录
2. 在残局选关页面点击"导入残局文件"按钮
3. 选择要导入的文件
4. 导入成功后即可在残局列表中看到新添加的残局

### 3. 配置 AI 引擎

1. 下载对应平台的 Pikafish 二进制文件：
   - Windows：`pikafish.exe`
   - Android：`libpikafish.so`
2. 将文件放入 `assets/engines/` 目录
3. 在 `EngineViewModel` 中配置正确的路径

### 4. 主要功能

#### 残局选关
- 在主页面点击"残局选关"
- 浏览不同来源的残局（竹香斋、适情雅趣等）
- 支持搜索和难度筛选
- 点击残局卡片进入演示页面

#### 残局演示
- 在演示页面点击"提示"按钮获取破解走法
- 使用播放控制按钮（播放、暂停、单步）控制演示
- 查看走法记录和教练解说
- 调整播放速度和循环播放选项

#### 人机对战
- 在主页面点击"人机对战"
- 选择执棋方（红方/黑方）
- 选择难度级别（入门/初级/中级/高级/职业）
- 开始对弈，AI 会自动思考并走子

#### 机器对战
- 在主页面点击"机器对战"
- 观看两个 AI 引擎自动对弈
- 调整对弈速度
- 查看实时局面和走法记录

#### 双人对弈
- 在主页面点击"双人对弈"
- 红黑轮流走子
- 支持悔棋和新游戏

## 开发指南

### 添加新的棋谱格式解析器

1. 在 `features/puzzle/model/parsers/` 目录下创建新的解析器
2. 实现 `PuzzleParser` 接口
3. 在 `PuzzleParserFactory` 中注册解析器

```dart
// 示例：添加新的解析器
class NewFormatParser implements PuzzleParser {
  @override
  Set<String> get supportedExtensions => {'new'};
  
  @override
  Future<ParsedPuzzle> parse(dynamic rawData) async {
    // 解析逻辑
    return ParsedPuzzle(...);
  }
}

// 注册解析器
PuzzleParserFactory.instance.register('new', () => NewFormatParser());
```

### 添加新的提示策略

1. 实现 `HintStrategy` 接口
2. 在需要的地方使用

```dart
// 示例：自定义提示策略
class CustomHintStrategy implements HintStrategy {
  @override
  Future<String?> getHint() async {
    // 自定义提示逻辑
    return null;
  }
}

// 使用
final strategy = CustomHintStrategy();
puzzleVm.setHintStrategy(strategy);
```

### 配置 AI 引擎

在 `EngineViewModel` 中配置引擎参数：

```dart
// 设置难度
await engineVm.setDifficulty(4); // 高级

// 设置搜索深度
await engineVm.updateConfig(
  EngineConfig(depth: 20, elo: 2400)
);
```

## 测试

运行测试：

```bash
flutter test
```

## 贡献

欢迎提交 Issue 和 Pull Request！

## 许可证

[MIT License](LICENSE)
