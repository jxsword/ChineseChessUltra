# 中国象棋 Ultra

## 项目概述

中国象棋 Ultra 是一款跨平台（Windows / Android / macOS / Linux）的中国象棋单机对弈应用，基于 Flutter + Riverpod + sqlite3 开发。支持双人对弈、内置 AI（Pikafish）人机与机器对战、残局棋谱，三期新增 OpenAI 兼容大模型对战，四期新增棋谱库、残局工作室（摆盘/导入/识图）与 AI 求破解。

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

### Phase 4（已完成）
- 📖 **棋谱库**：所有对战模式可在对局中"保存为棋谱"（含完整走法、中文记谱、元数据），棋谱库统一管理、逐手重放、删除、导出 PGN 与分享文本（剪贴板复制 / 文件导出）
- 🧩 **残局工作室**：
  - **自己摆残局**：点选放子/取子、切换行棋方、实时 FEN 预览与局面合法性校验（双王、自将等）
  - **FEN 导入**：粘贴完整 FEN 或仅棋盘字段，校验后载入可视化微调
  - **AI 识图导入**：选择棋盘图片，多模态大模型（如 GLM-4.5V）识别为坐标/FEN，识别结果强制经可视化人工校正后使用
  - 这类残局初始只有当前局面，不带任何走法或破解信息
- ♟️ **AI 求破解**：自研迭代加深 AND/OR 杀棋求解器（纯 Dart，Isolate 运行，置换表 + 将军/吃子排序）
  - 枚举全部"主要变着"破解走法（对方每种防着一条线路），标注唯一解/多条解
  - 可证明深度上界内**无解**；限时未决单独标记——四种状态的棋局全部自动持久化为棋谱
  - **大模型 Hybrid 辅助**（可选）：模型提议首选着与思路注释，仅当被求解器验证为必胜着法才写入棋谱（模型启发式、引擎裁判）
- 🔗 **棋谱 → 对战/演示联动**：棋谱库中"对局"棋谱（未分胜负）与无解/未决残局可一键进入 4 种对战模式（人机 AI/双人/人机大模型/大模型对战）从保存局面继续，黑先局面自动应手，棋谱来源不写自动存档；已破解残局在详情页支持自动播放破解演示（暂停/单步/调速）；已分胜负对局仅查看/导出
- 📚 **调研文档**：`docs/phase4/` 残局求解算法对比（含 mermaid 流程图/数据交互图/状态机）与大模型求解框架、提示词模板、识图方案调研

### Phase 5（已完成）
- 🧠 **引擎参谋制**：每手棋本地引擎（纯 Dart ChessAi）先搜出带评分的候选报告，再让大模型拍板
  - **候选模式**：Prompt 只给引擎 Top-K 短名单（附分数分桶：最佳/均势 → 致命），模型从中选一
  - **护航模式**：模型全量清单自由选，相对引擎最佳损失超阈值（丢大子/被杀）时行使一票否决，再问一次仍不行由引擎最佳代走
  - **strengthBlend 棋力旋钮**（0~100）调节名单宽度/否决阈值；"大模型对战"红黑双方可各配各的强度
- 📝 **Prompt v2**：棋盘 ASCII 图 + 着法逐条注解（中文记法/吃子/将军）+ 放开"分析"段 + 整局历史与重复警示 + 8192 token 预算；v1 协议保留作评估基线
- 📊 **能力评估**：MatchRunner 无头对局框架（胜负/手数/耗时/失误率/兜底率）+ `tool/llm_match_runner.dart` CLI（基线/P0/候选/护航四档对比，密钥走环境变量）；CI 内置确定性弱模型对抗测试
- ⚙️ 设置面板新增"引擎参谋/参谋强度/参谋深度"（人机大模型与大模型对战页独立持久化）

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
│   │   ├── llm_solve_assist.dart        # 求解辅助提示词 + 提议解析（四期）
│   │   ├── vision_board_reader.dart     # 多模态识图 → FEN（四期）
│   │   └── hint_strategy.dart           # 提示策略接口
│   ├── record/                     # 棋谱库（四期）
│   │   ├── game_record.dart             # 棋谱模型 + SolveStatus 求解标记
│   │   ├── record_repository.dart       # 棋谱仓储 Provider
│   │   ├── record_saver.dart            # "保存为棋谱"公共入口 + 分享
│   │   ├── pgn_writer.dart              # PGN / 分享文本导出
│   │   ├── board_view_replay.dart       # 棋谱逐手重放视图
│   │   ├── record_library_page.dart     # 棋谱库列表 + 详情页
│   │   └── clipboard_guard.dart         # 剪贴板封装
│   ├── solver/                     # 残局求解器（四期）
│   │   └── endgame_solver.dart          # 迭代加深 AND/OR 杀棋搜索
│   ├── studio/                     # 残局工作室（四期）
│   │   ├── endgame_studio_page.dart     # 摆盘 / FEN 导入 / 识图 + 求解
│   │   └── assistant_config_dialog.dart # 研究助手模型配置
│   └── storage/
│       ├── game_mode.dart               # 对局模式枚举（存档分桶）
│       ├── game_dao.dart                # sqlite3 DAO（saved_games + game_records）
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

### 5. 配置研究助手模型（Phase 4，可选）

1. 在主页进入"残局工作室"，点击右上角调参图标
2. 填写 OpenAI 兼容端点、模型 ID 与 API Key（Key 仅存系统安全存储）
3. 棋盘图片识图需选择**视觉模型**（如 glm-4.5v）；纯文本模型仅可用于求解辅助

### 6. 主要功能

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

#### 棋谱库（Phase 4）
- 对局中点击"保存为棋谱"入库；棋谱库支持筛选（对局/已破解/无解/未决）、逐手重放、解法演示
- 支持导出 PGN（复制 / 文件）与中文记谱分享文本（复制）

#### 棋谱库联动（Phase 4 扩展）
- 详情页/列表菜单"进入对战"：从保存局面继续对战；已分胜负棋谱无入口
- 详情页播放控制条：破解演示自动播放（暂停/重置/0.5×~2× 调速）

#### 残局工作室（Phase 4）
- 摆盘 / FEN 导入 / 图片识图三种入口构造残局，识图结果经人工校正后使用
- 点击"AI 求破解"：可选限时、搜索深度与大模型辅助
- 求解结束（含无解/超时）棋局与全部破解走法自动入库，结果面板给出中文记谱线路

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
