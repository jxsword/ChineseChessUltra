# 中国象棋 Ultra

## 项目概述

中国象棋 Ultra 是一款跨平台（Windows / Android / macOS / Linux）的中国象棋单机对弈应用，基于 Flutter + Riverpod + sqlite3 开发。支持双人对弈、内置 AI（Pikafish）人机与机器对战、残局棋谱，以及三期新增的 OpenAI 兼容大模型对战。

## 功能特性

### Phase 1（已完成）
- 跨平台支持：Windows + Android
- 双人单机对弈：红黑轮流走子，合法走法高亮，走子动画
- 规则引擎：直接拷贝 `shirne/chinese_chess` 的 `lib/` 目录，不做修改
- 输赢判定：使用引擎的 `isCheckmate()` 和 `isStalemate()` 方法
- 自动保存/恢复：每次走子后写入 sqlite3 数据库，App 生命周期 paused 时强制保存；启动时自动恢复最近一局
- 悔棋：支持双方各自撤销上一步走子（可连续悔棋）
- 新游戏/重新开始：重置棋盘至初始布局

### Phase 2（已完成）
- 📚 **残局棋谱导入**：支持 `.pgn` 和 `.xqf` 格式（GBK/GB18030 元数据解码）
- 🎬 **破解演示**：点击"提示"按钮，按棋谱中记录的破解走法逐手演示
- 🤖 **AI 智能提示**：接入 Pikafish 引擎，对当前局面计算最佳走法
- 👥 **人机对战**：玩家执一方，另一方由内置 AI 控制，可选择难度级别
- 🤖🤖 **机器对机器对战**：两个 AI 引擎自动对弈
- 📖 **语料库浏览**：内置棋谱语料浏览器，可从网络下载语料包（可取消进度框）并解压到本地语料目录，直接浏览棋局

### Phase 3（已完成）
- 🧠 **大模型对战**（OpenAI 兼容 `chat/completions` 端点）：
  - **人机（大模型）**：玩家执一方，另一方由大模型走子
  - **大模型互弈**：红黑各配一个模型接入点自动对弈，可设置每手间隔
- 🔐 **接入点配置**：红/黑双槽位独立配置 baseUrl、模型名、API Key
  - API Key 存入系统安全存储（`flutter_secure_storage`：Windows DPAPI、Android Keystore、Linux libsecret），不落明文偏好文件，不入代码仓库
  - 内置常用端点预设：智谱 GLM、DeepSeek、Kimi、OpenRouter、OpenAI、自定义
  - Key 仅掩码回显（`****xxxx`）
- ⚙️ **大模型对局参数**：请求超时、无效回复最大重试次数、每手间隔秒数、思维链开关（默认禁用 `enable_thinking`，避免思考型模型拖慢每手响应）
- 🛟 **降级策略**：模型持续失败时按配置降级到内置 AI（Pikafish）走子，保证对局不中断
- 💾 **存档按模式分桶**：人机、双人、机器、人机大模型、大模型互弈五种模式各存最近一局，互不覆盖；启动进入对应页面自动恢复
- 🔧 **全局设置**：自动保存开关（关闭后仅点击"保存棋局"按钮才落库）

### 工程化（已完成）
- 🏗️ **GitHub Actions CI**：Ubuntu 统一静态分析 + 全量测试门禁，通过后 macOS / Windows / Linux / Android 四平台并行构建
- 📦 **自动发布**：main 分支全平台构建通过后自动创建 GitHub Release（tag `v<版本>+build.<构建号>`），上传四平台 debug 产物

## 技术栈

| 层级 | 技术 |
|------|------|
| 跨平台 UI | Flutter 3.x（3.44.2 stable） |
| 状态管理 | Riverpod 2.x（`flutter_riverpod` + `riverpod_annotation`） |
| 象棋规则引擎 | shirne/chinese_chess（拷贝 `lib/` 目录代码，不做修改） |
| 内置 AI 引擎 | Pikafish（UCI 协议，Win/Android 二进制） |
| 大模型接入 | OpenAI 兼容 HTTP `chat/completions`（纯 Dart 实现，无 SDK 依赖） |
| 持久化 | sqlite3（直接使用，避免代码生成）+ `shared_preferences` |
| 凭据存储 | `flutter_secure_storage`（Windows DPAPI / Android Keystore / Linux libsecret） |
| 棋谱解析 | 自建 `PuzzleParser` 策略模式（支持 XQF / PGN，GBK 解码用 `fast_gbk`） |
| CI / 发布 | GitHub Actions（四平台构建 + 自动 Release） |

## 项目结构

```
lib/
├── main.dart
├── app/
│   ├── app.dart                    # MaterialApp + 主题 + 主页导航 + 全局设置
├── features/
│   ├── board/                      # 棋盘对弈
│   │   ├── view/
│   │   │   ├── board_page.dart          # 双人对弈
│   │   │   ├── human_vs_ai_page.dart    # 人机对战（内置 AI）
│   │   │   ├── ai_vs_ai_page.dart       # 机器对战
│   │   │   ├── human_vs_llm_page.dart   # 人机（大模型）对战
│   │   │   ├── llm_vs_llm_page.dart     # 大模型互弈
│   │   │   └── widgets/
│   │   │       ├── board_painter.dart / board_widget.dart / board_layout.dart
│   │   │       ├── side_panel.dart      # 走法记录等侧栏
│   │   │       └── llm_config_editor.dart  # 大模型接入点配置编辑器
│   │   ├── viewmodel/
│   │   │   ├── board_vm.dart            # Notifier<BoardState>
│   │   │   └── engine_vm.dart           # AI 引擎视图模型
│   │   └── model/
│   │       ├── board.dart / fen.dart / move.dart
│   ├── puzzle/                     # 残局与语料
│   │   ├── view/
│   │   │   ├── puzzle_list_page.dart        # 残局选关列表
│   │   │   ├── puzzle_detail_page.dart      # 单局演示页
│   │   │   ├── corpus_browser_page.dart     # 语料目录浏览 + 在线下载
│   │   │   └── corpus_pgn_browser_page.dart # PGN 棋谱浏览
│   │   └── model/parsers/               # XQF / PGN 解析器
│   ├── settings/
│   │   └── global_settings.dart         # 全局设置（自动保存开关）
│   ├── shared/engine/                   # 走子来源抽象
│   │   ├── ai_engine.dart / engine_view_model.dart
│   │   ├── pikafish_bridge.dart         # UCI 通信封装
│   │   ├── move_source.dart             # 走子来源接口
│   │   ├── llm_move_source.dart         # 大模型走子来源（含降级）
│   │   ├── llm_config.dart              # 接入点配置 + 安全存储
│   │   ├── llm_settings.dart            # 大模型对局参数
│   │   └── hint_strategy.dart           # 提示策略接口
│   └── storage/
│       ├── game_mode.dart               # 对局模式枚举（存档分桶）
│       ├── game_dao.dart                # sqlite3 DAO
│       └── repository.dart              # 仓储层
└── shared/constants.dart
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
flutter run -d windows   # 或 -d <android-device>
```

### 2. 添加新残局

1. 将 `.xqf` 或 `.pgn` 文件放入 `assets/puzzles/` 目录
2. 在残局选关页面点击"导入残局文件"按钮
3. 选择要导入的文件
4. 导入成功后即可在残局列表中看到新添加的残局

### 3. 配置内置 AI 引擎（Pikafish）

1. 下载对应平台的 Pikafish 二进制文件：
   - Windows：`pikafish.exe`
   - Android：`libpikafish.so`
2. 将文件放入 `assets/engines/` 目录
3. 在 `EngineViewModel` 中配置正确的路径

### 4. 配置大模型对战（Phase 3）

1. 在主页进入"人机（大模型）"或"大模型对战"页面
2. 点击配置卡片，选择预设端点（智谱 GLM / DeepSeek / Kimi / OpenRouter / OpenAI）或自定义
3. 填写 baseUrl、模型名与 API Key（Key 仅存系统安全存储，界面掩码回显）
4. 按需调整对局参数：超时秒数、最大重试次数、每手间隔、是否禁用思维链
5. 红黑两侧可配置不同接入点；模型不可用时按降级策略回落内置 AI

### 5. 主要功能

#### 双人对弈
- 红黑轮流走子，支持悔棋、新游戏、保存棋局、分享棋局、走法记录

#### 人机对战（内置 AI）
- 选择执棋方（红方/黑方）与难度级别（入门/初级/中级/高级/职业）
- AI 自动思考走子，可获取提示

#### 机器对战
- 观看两个 Pikafish 引擎自动对弈，可调整速度、查看实时局面与走法记录

#### 人机（大模型） / 大模型互弈
- 大模型按 OpenAI 兼容协议请求走子，无效回复自动重试
- 大模型互弈模式可设置每手间隔秒数，观察模型对弈过程

#### 残局选关 / 语料库
- 残局演示页支持播放控制（播放、暂停、单步）、走法记录与教练解说
- 语料库页面支持从网络下载棋谱语料包（可取消），解压后直接浏览棋局

#### 存档
- 五种对局模式各存最近一局，互不覆盖；进入对应页面自动恢复
- 主页全局设置可开关"自动保存棋局"

## CI 与发布

- 推送到 `main` 或提交 PR 触发 [`.github/workflows/ci.yml`](.github/workflows/ci.yml)
- 门禁：Ubuntu 上 `flutter analyze`（error/warning 卡关）+ `flutter test`
- 门禁通过后 macOS / Windows / Linux / Android 四平台并行构建 debug 产物
- main 分支全平台通过后自动发布 GitHub Release（`v<版本>+build.<构建号>`），附四平台产物

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

### 添加新的走子来源

大模型对战的走子逻辑实现 `MoveSource` 接口（参见 `llm_move_source.dart`：请求 / 校验 / 重试 / 降级），即可接入新的对弈后端。

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
