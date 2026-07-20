# 中国象棋跨平台应用 – 需求设计文档 V1.0

---

## 一、概述

### 1.1 产品目标
开发一款支持 **Windows 11** 和 **Android** 双端的中国象棋应用，提供流畅的双人单机对弈体验，并具备棋局自动保存/恢复、残局导入与破解演示、AI 智能提示等进阶功能。首期聚焦基础对弈功能，二期引入 AI 与残局玩法。

### 1.2 受众
- 中国象棋爱好者（休闲娱乐、残局研究）
- 开发者（学习 Flutter 跨平台 + 象棋引擎集成）

### 1.3 术语表
| 术语 | 说明 |
|------|------|
| FEN | Forsyth–Edwards Notation，标准局面记录格式 |
| PGN | Portable Game Notation，标准棋谱格式 |
| UCI | Universal Chess Interface，引擎通信协议 |
| MVVM | Model-View-ViewModel 架构模式 |
| Riverpod | Flutter 状态管理框架 |

---

## 二、功能需求

### 2.1 第一期（核心基础）
| ID | 功能 | 描述 | 优先级 |
|----|------|------|--------|
| F01 | 跨平台运行 | 支持 Windows 11（桌面）和 Android（移动端），先完成 Windows 测试，代码架构兼容 Android | P0 |
| F02 | 双人单机对弈 | 红方/黑方轮流在同一设备上触摸/鼠标操作，走子符合中国象棋规则 | P0 |
| F03 | 走法规则引擎 | 实现全部 7 种棋子走法（车、马、象、士、将、炮、兵），含马腿、象眼、炮隔子、将帅照面、兵过河变化 | P0 |
| F04 | 输赢判定 | 自动检测将军、应将、将死、困毙，判定胜负或和棋（长将/长捉等复杂和棋规则暂不实现） | P0 |
| F05 | 棋局自动保存与恢复 | 暂停/退出时自动保存当前局面及走法历史，下次启动恢复完整棋局（含悔棋栈） | P0 |
| F06 | 悔棋 | 支持双方各自撤销上一步走子（可连续悔棋） | P1 |
| F07 | 新游戏/重新开始 | 重置棋盘至初始布局 | P1 |

### 2.2 第二期（进阶功能）
| ID | 功能 | 描述 | 优先级 |
|----|------|------|--------|
| F08 | 残局棋谱导入 | 支持导入 .pgn / .xqf / .che 等格式的残局文件，解析初始局面与破解走法序列 | P1 |
| F09 | 破解演示 | 点击“提示”按钮，按棋谱中记录的破解走法逐手演示（红黑交替，高亮落子位置） | P1 |
| F10 | AI 智能提示 | 接入 Pikafish 引擎，对当前局面计算最佳走法，提供“提示”功能（引擎实时分析） | P2 |
| F11 | 人机对战 | 玩家执一方，另一方由 AI 控制（可选择 AI 难度级别） | P2 |
| F12 | 机器对机器对战 | 两个 AI 引擎自动对弈（可指定不同引擎或相同引擎的不同参数），用于测试或观赏 | P3 |

---

## 三、技术选型

| 层级 | 技术/框架 | 选择理由 |
|------|-----------|----------|
| 跨平台 UI | **Flutter 3.x** | 一套代码覆盖 Win/Android，CustomPainter 适合棋盘绘制，动画支持好 |
| 状态管理 | **Riverpod 3.x** | MVVM 天然适配，AsyncNotifier 处理引擎异步调用，无 BuildContext 依赖 |
| 象棋规则引擎 | **shirne/chinese_chess** (GPL-2.0) | 最成熟的 Dart 中国象棋规则实现，含走法生成、将军检测、困毙判负，直接拷贝 lib/ 目录代码（非商用学习可忽略许可） |
| 输赢判定 | 复用上述引擎中的 `isCheckmate()` / `isStalemate()` 方法 | 无需额外开发，覆盖将死/困毙 |
| AI 引擎（二期） | **Pikafish** (GPL-3.0) | 当前最强开源中国象棋引擎，UCI 协议，支持 Win/Android 二进制，可离线运行 |
| 持久化 | **drift** (SQLite) | 轻量、支持迁移，存储棋局记录（FEN + 走法栈 JSON） |
| 棋谱解析（二期） | 自建策略模式，参考 ElephantEye 的 XQFTOOLS | 可扩展支持多种格式 |

---

## 四、架构设计

### 4.1 总体分层（Clean Architecture + MVVM）

```
┌─────────────────────────────────────────────┐
│                Presentation Layer            │
│  (Widgets / Pages / CustomPainters)         │
│  ─── 监听 ViewModel (Riverpod Providers)    │
├─────────────────────────────────────────────┤
│                ViewModel Layer              │
│  (Notifiers / AsyncNotifiers)               │
│  ─── 管理 BoardState, EngineState, PuzzleState│
├─────────────────────────────────────────────┤
│                Domain Layer                 │
│  (象棋规则引擎 / FEN/PGN 模型 / 引擎桥抽象)    │
│  ─── 纯 Dart 无 UI 依赖                      │
├─────────────────────────────────────────────┤
│                Data Layer                   │
│  (DAO / Repository / 文件 IO / 引擎进程)      │
│  ─── drift SQLite / Pikafish UCI 管道        │
└─────────────────────────────────────────────┘
```

### 4.2 模块划分（Feature-First）

```
lib/
├── main.dart
├── app/
│   ├── app.dart                    # MaterialApp + 主题
│   └── providers.dart              # 全局 Provider 注册
├── features/
│   ├── board/                      # 棋盘对弈功能
│   │   ├── view/
│   │   │   ├── board_page.dart
│   │   │   └── widgets/
│   │   │       ├── board_painter.dart
│   │   │       ├── piece_widget.dart
│   │   │       └── hint_overlay.dart   # 提示走法高亮
│   │   ├── viewmodel/
│   │   │   ├── board_vm.dart       # Notifier<BoardState>
│   │   │   └── engine_vm.dart      # AsyncNotifier（二期）
│   │   └── model/
│   │       ├── board.dart          # 棋盘状态（FEN/走法栈）
│   │       ├── fen.dart            # FEN 编解码
│   │       └── move.dart           # 走法表示
│   ├── puzzle/                     # 残局功能（二期）
│   │   ├── view/
│   │   ├── viewmodel/
│   │   │   └── puzzle_vm.dart
│   │   └── model/
│   │       ├── puzzle_parser.dart  # 抽象解析器
│   │       └── parsers/            # 具体解析器实现
│   └── storage/
│       ├── dao/
│       │   └── game_dao.dart       # drift DAO
│       └── repository.dart         # 仓储层
├── shared/
│   ├── engine/
│   │   ├── pikafish_bridge.dart    # UCI 通信封装（二期）
│   │   └── hint_strategy.dart      # 提示策略接口（二期）
│   └── constants.dart
```

### 4.3 关键数据模型

```dart
// board_state.dart (位于 board/model/)
class BoardState {
  final String fen;                 // 当前局面 FEN
  final List<Move> moveHistory;     // 走法历史（用于悔棋/重播）
  final bool isRedTurn;             // 当前轮到哪方
  final bool isCheck;               // 是否将军
  final GameResult? result;         // 对局结果（null 进行中）
}

enum GameResult { redWins, blackWins, draw }

class Move {
  final String from;  // e.g., "h2"
  final String to;    // e.g., "h5"
  final String piece; // 棋子标识
}
```

---

## 五、核心模块设计

### 5.1 象棋规则引擎（复用 shirne/chinese_chess）

- **来源**：拷贝 `shirne/chinese_chess/lib/` 下的 `board.dart`, `piece.dart`, `rules.dart`, `fen.dart` 等文件到 `features/board/model/` 目录。
- **集成方式**：直接引用类和方法，不做二次封装，保持最小修改。
- **输赢判定**：引擎提供 `Board.isCheckmate()` 和 `Board.isStalemate()`，前者表示将死，后者表示困毙（无合法走法）。
- **特殊规则**：长将/长捉等复杂和棋规则一期不实现，二期可通过引擎（Pikafish）的 UCI 反馈“draw”来间接处理。

### 5.2 棋局自动保存与恢复

- **保存时机**：每次走子后写入 drift 数据库，或在 App 生命周期 `didChangeAppLifecycleState(AppLifecycleState.paused)` 时强制保存。
- **数据表设计**：

```sql
CREATE TABLE saved_games (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  fen TEXT NOT NULL,
  move_stack_json TEXT NOT NULL,   -- 走法序列 JSON
  created_at TEXT DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);
```

- **恢复流程**：启动时查询最新一条记录（或上次未结束的对局），反序列化走法栈，依次 replay 到当前局面，同时恢复悔棋栈。

### 5.3 残局导入与破解演示（二期预留接口）

采用**策略模式**，已在前面回答中详细设计，此处不再赘述。关键点：

- 抽象 `PuzzleParser` 接口，通过 `PuzzleParserFactory` 注册扩展。
- 抽象 `HintStrategy` 接口，支持棋谱变例优先、引擎实时分析后备。
- 在 `puzzle_vm.dart` 中注入策略对象，点击“提示”时调用 `getHintMoves()`。

### 5.4 AI 引擎通信（二期预留接口）

- 使用 `dart:io` 的 `Process.start` 启动 Pikafish 二进制（Windows 下为 `.exe`，Android 下为 ELF 可执行文件）。
- 遵循 UCI 协议：发送 `position fen ...` → `go depth 18 multipv 3` → 解析 stdout 中的 `info depth ... pv ...` 行。
- 封装为 `PikafishBridge` 单例（Provider），提供 `analyze(FEN, depth)` 异步方法。
- 人机对战模式下，AI 走子直接调用 `bestmove` 结果。

---

## 六、UI 原型示意（第一期）

### 6.1 主界面布局（Windows 桌面）

```
┌──────────────────────────────────────────┐
│  标题栏：中国象棋                           │
├──────────────────────────────────────────┤
│  ┌──────────────┐   ┌──────────────────┐ │
│  │  棋盘区域      │   │  右侧面板        │ │
│  │  (9×10网格)   │   │  - 当前回合指示   │ │
│  │               │   │  - 走法记录列表    │ │
│  │               │   │  - 悔棋按钮       │ │
│  │               │   │  - 新游戏按钮      │ │
│  │               │   │  - 保存/载入（隐藏）│ │
│  └──────────────┘   └──────────────────┘ │
├──────────────────────────────────────────┤
│  底部状态栏：将军提示 / 对局结果 / 时间      │
└──────────────────────────────────────────┘
```

- 棋盘使用 `CustomPainter` 绘制，棋子为圆形，红黑区分。
- 触摸/点击棋子选中，再点击目标格走子（合法走法高亮圆点）。
- 走子动画：棋子平滑移动到目标位置。

### 6.2 Android 适配

- 响应式布局：竖屏时棋盘居中，右侧面板折叠到底部或抽屉。
- 手势优化：长按棋子显示候选走法，滑动取消。

---

## 七、开发计划

| 阶段 | 任务 | 预估工时 |
|------|------|----------|
| 1.1 | 搭建 Flutter 项目，配置 Riverpod，创建基础工程结构 | 1天 |
| 1.2 | 拷贝 shirne 规则引擎代码，编写单元测试验证走法正确性 | 2天 |
| 1.3 | 实现棋盘 UI（CustomPainter + 交互），绑定 ViewModel | 3天 |
| 1.4 | 实现走子逻辑、将军检测、输赢判定 | 1天 |
| 1.5 | 实现悔棋功能 | 0.5天 |
| 1.6 | 集成 drift，实现自动保存/恢复 | 1.5天 |
| 1.7 | Windows 平台打包测试，修复适配问题 | 1天 |
| 1.8 | Android 平台适配（触控、屏幕尺寸） | 1天 |
| **合计** | **第一期** | **约11天** |
| 2.1 | 设计 PuzzleParser/HintStrategy 接口，实现 PGN 解析器 | 2天 |
| 2.2 | 实现残局导入 UI 及破解演示动画 | 2天 |
| 2.3 | 集成 Pikafish 引擎，封装 UCI 桥 | 2天 |
| 2.4 | 实现 AI 提示、人机对战、机器对战 | 3天 |
| **合计** | **第二期** | **约9天** |

---

## 八、附录

### A. 参考资源链接
- shirne/chinese_chess: https://github.com/shirne/chinese_chess
- Pikafish: https://github.com/Pikafish-org/Pikafish
- Riverpod: https://riverpod.dev
- drift: https://drift.simonbinder.eu

### B. 许可声明
本项目为非商业学习用途，规则引擎代码来源于 shirne/chinese_chess（GPL-2.0），AI 引擎使用 Pikafish（GPL-3.0）。若后续转为商业发布，需替换为宽松许可的实现或获得授权。

---

**文档版本**：V1.0  
**最后更新**：2026-07-19  
**负责人**：jsword