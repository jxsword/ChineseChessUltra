# 中国象棋 App – 第二期实现任务说明

## 一、总体目标

在**第一期已完成的基础功能**之上，实现第二期所有功能：

1. **残局棋谱导入**（支持 `.pgn` / `.xqf` 格式）
2. **破解演示**（点击“提示”按钮，按棋谱中记录的破解走法逐手演示）
3. **AI 智能提示**（接入 Pikafish 引擎，对当前局面计算最佳走法）
4. **人机对战**（玩家执一方，另一方由 AI 控制，可选择难度级别）
5. **机器对机器对战**（两个 AI 引擎自动对弈）

## 二、技术栈

| 层级 | 技术 |
|||
| 跨平台 UI | Flutter 3.x |
| 状态管理 | Riverpod 3.x（`flutter_riverpod`） |
| 象棋规则引擎 | shirne/chinese_chess（拷贝 `lib/` 目录代码，不做修改） |
| AI 引擎 | Pikafish（UCI 协议，Win/Android 二进制） |
| 持久化 | drift（SQLite） |
| 棋谱解析 | 自建 `PuzzleParser` 策略模式（支持 XQF / PGN） |

## 三、项目结构（Feature-First + MVVM）

```
lib/
├── main.dart
├── app/
│   ├── app.dart                    # MaterialApp + 主题
│   └── providers.dart              # 全局 Provider 注册
├── features/
│   ├── board/                      # 棋盘对弈（第一期已完成）
│   │   ├── view/
│   │   │   ├── board_page.dart
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
│   ├── puzzle/                     # 残局功能（二期核心）
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

## 四、第一期基础功能（必须完整实现，作为二期地基）

1. **跨平台**：Windows 11 + Android，先完成 Windows 测试，代码兼容 Android
2. **双人单机对弈**：红黑轮流走子，合法走法高亮，走子动画
3. **规则引擎**：直接拷贝 `shirne/chinese_chess` 的 `lib/` 目录到 `features/board/model/`，不做修改
4. **输赢判定**：使用引擎的 `isCheckmate()` 和 `isStalemate()` 方法
5. **自动保存/恢复**：每次走子后写入 drift 数据库（表结构见下文），App 生命周期 paused 时强制保存；启动时自动恢复最近一局
6. **悔棋**：支持双方各自撤销上一步走子（可连续悔棋）
7. **新游戏/重新开始**：重置棋盘至初始布局

**drift 数据库表结构**：

```sql
CREATE TABLE saved_games (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  fen TEXT NOT NULL,
  move_stack_json TEXT NOT NULL,   -- 走法序列 JSON
  created_at TEXT DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);
```

## 五、第二期功能详细需求

### 5.1 残局棋谱导入

- **支持格式**：`.xqf`（象棋演播室）、`.pgn`（中国象棋变种）
- **解析器架构**：策略模式 + 工厂
  - 抽象 `PuzzleParser` 接口，方法 `Future<ParsedPuzzle> parse(dynamic rawData)`
  - 工厂 `PuzzleParserFactory` 根据文件扩展名返回对应解析器
  - 初始化时注册：`register('xqf', () => XqfPuzzleParser())`、`register('pgn', () => PgnPuzzleParser())`
- **ParsedPuzzle 模型**：

```dart
class ParsedPuzzle {
  final String id;
  final String initialFen;
  final List<String>? solutionMoves; // 破解走法序列（ICCS 坐标）
  final String? title;
  final String? description;
  final String source;           // 来源（如"竹香斋·三集"）
  final String format;           // "xqf" / "pgn"
  final int difficulty;          // 1-5
}
```

- **XQF 解析要点**：
  - 文件头 1KB：32 字节固定顺序棋子布局 → 转为 FEN
  - `0x40` 处 `0x03` 为残局类型
  - 走法记录从 `0x400` 开始，每步 8 字节 + 变长评注
  - 评注文本中提取“【变 N】马三进一 士 4 进 5”等中文纵线走法，转为 ICCS 坐标存入 `solutionMoves`
- **PGN 解析**：可使用 `bishop` 包的 `Variant.xiangqi` 加载，提取 FEN 和走法序列

### 5.2 破解演示

- **入口**：在残局详情页或对弈页面点击“提示”按钮
- **数据来源**：优先使用棋谱自带的 `solutionMoves`；若无，则调用 Pikafish 计算最佳变例（见 5.3）
- **演示方式**：
  - 逐手动画播放（红黑交替），每步高亮落子位置
  - 走子间隔 600ms，停顿 400ms
  - 可暂停/继续/调速
  - 显示当前步数/总步数
- **变例分支**：如果棋谱中有多个变例，在分岔点显示分支选择按钮，用户可切换观看不同分支

### 5.3 AI 智能提示（Pikafish 引擎）

- **引擎通信**：`PikafishBridge` 封装 UCI 协议
  - `start(String binaryPath)`：启动子进程，发送 `uci`、`isready`
  - `analyze(String fen, {int depth = 18, int multipv = 3})` → 返回 `AnalysisResult`
  - `AnalysisResult` 包含 `List<List<String>> pvMoves` 和 `List<int> scores`
- **难度调节**：通过 `UCI_LimitStrength` + `UCI_Elo`（1200~3000）或 `depth`（8~24）
- **提示按钮逻辑**（`engine_vm.dart`）：
  1. 获取当前局面 FEN
  2. 调用 `analyze(fen, depth: 18, multipv: 3)`
  3. 取 PV1 的第一手作为“下一步提示”
  4. 返回给 UI 高亮显示
- **缓存**：对相同 FEN 的提示结果可缓存 30 秒

### 5.4 人机对战

- **模式选择**：在开始新游戏时选择“双人对弈”或“人机对战”
- **AI 走子**：轮到 AI 时，调用 `PikafishBridge.bestMove(fen, depth: 12)` 获取走法，然后自动执行走子动画
- **难度选择**：提供 3-5 档难度（如“入门/业余/进阶/高手/职业”），对应不同 `depth` 或 `UCI_Elo`
- **玩家可执红或执黑**：在开始前选择
- **AI 思考动画**：显示“AI 思考中…”并禁用棋盘交互

### 5.5 机器对机器对战

- **模式入口**：独立页面或设置中的“自动对弈”
- **实现方式**：
  - 创建两个 `PikafishBridge` 实例（可指定不同二进制或相同）
  - 每个实例可配置不同 `UCI_Elo` 或 `depth`
  - 轮流调用 `bestMove(fen)`，每步更新棋盘状态
  - 走子间隔 800ms（可调），可加速/减速
- **观战体验**：
  - 实时显示当前局面、走法记录
  - 可选显示引擎评分曲线
  - 对局结束后显示结果和统计
- **额外趣味**：可让两个 AI 在每步后输出“棋评”（通过 LLM，可选，本期可预留接口但不强制实现）

## 六、接口与扩展点（预留）

- `HintStrategy` 抽象接口：`Future<List<String>> getHintMoves(String fen)`
  - 实现类：`PuzzleSolutionHintStrategy`（棋谱自带变例）、`PikafishHintStrategy`（引擎实时计算）
  - 组合策略：`CompositeHintStrategy`（先棋谱后引擎）
- `LLMBridge` 抽象接口（可选，用于未来 LLM 解说）：`Future<String> chat(String prompt)`
- `PuzzleParserFactory` 可注册更多格式解析器

## 七、UI 原型

### 残局选关页面（PuzzleListPage）

```
┌─────────────────────────┐
│  ♟ 残局选关              │
├─────────────────────────┤
│  ▸ 竹香斋·初集  (48 局）   │
│  ▸ 竹香斋·二集  (56 局）   │
│  ▸ 竹香斋·三集  (92 局）   │
│  ▸ 适情雅趣    (551 局）   │
│  ▸ 江湖百局    (100 局）   │
│  ▸ 实用残局·第三集       │
│      ├─ 车兵类 (48)     │
│      ├─ 炮兵类 (32)     │
│      └─ 马兵类 (24)     │
└─────────────────────────┘
```

点击来源 → 进入卡片网格，每张卡片显示：
- 小棋盘缩略图（CustomPainter 画 3-4 枚关键子）
- 标题、难度星级、破解手数

### 残局演示页面（PuzzleDetailPage）

```
┌─────────────────────────┐
│  竹香斋·三集 第 47 局      │
├─────────────────────────┤
│  ┌──────────────┐       │
│  │  棋盘区域      │       │
│  │  （走子动画）   │       │
│  └──────────────┘       │
│  ◀ ▶ 步数：3/12        │
│  [提示] [自动播放]      │
│  走法记录：│
│  1. 炮二平五  马 8 进 7    │
│  2. 马二进三  车 9 平 8    │
│  ...                   │
│  教练解说（可折叠）      │
│  “炮镇中路是关键。..”    │
└─────────────────────────┘
```

### 人机对战设置页面

```
┌─────────────────────────┐
│  新游戏                  │
├─────────────────────────┤
│  模式：[人机对战]        │
│  执棋：● 红方 ○ 黑方    │
│  难度：⭐⭐⭐☆☆ 业余     │
│  [开始对弈]              │
└─────────────────────────┘
```

### 机器对战页面

```
┌─────────────────────────┐
│  机器对战                │
├─────────────────────────┤
│  引擎 A: Pikafish Elo 1800│
│  引擎 B: Pikafish Elo 2600│
│  步时：3 秒              │
│  [开始] [暂停] [加速]    │
│  当前局面 + 走法记录     │
│  评分曲线（可选）         │
└─────────────────────────┘
```

## 八、开发顺序建议

1. **第一期基础**：规则引擎 + 棋盘 UI + 自动保存（约 5 天）
2. **Pikafish 桥**：UCI 通信封装 + 难度调节（约 2 天）
3. **残局解析**：XQF / PGN 解析器 + 工厂（约 2 天）
4. **残局选关 UI**：分组列表 + 卡片网格（约 1.5 天）
5. **破解演示**：逐手动画 + 变例分支（约 1.5 天）
6. **人机对战**：模式切换 + AI 走子 + 难度选择（约 2 天）
7. **机器对战**：双引擎 + 观战 UI（约 2 天）
8. **集成测试 + 打磨**（约 2 天）

总计约 18 天，可并行部分。

## 九、输出要求

- 生成完整的 Flutter 项目文件夹，包含 `pubspec.yaml`、所有 Dart 源文件、资源文件
- 包含 `assets/engines/` 目录（放置 Pikafish 二进制文件，可先用占位文件，后续替换）
- 包含 `assets/puzzles/` 目录（放置示例残局文件，至少 3 个 `.xqf` 和 3 个 `.pgn` 用于测试）
- 提供 `README.md` 说明如何运行、如何添加新残局、如何切换引擎
- 代码注释充分，关键接口和类有文档注释


