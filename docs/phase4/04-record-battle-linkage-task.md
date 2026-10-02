# 四期扩展任务书：棋谱库 → 对战/演示联动

> 日期：2026-10-02 · 分支：`feature/phase4-record-solver`（完成后一次性合并 main 触发发布）
> 前置：四期主功能（棋谱库、残局工作室、AI 求破解）已交付。

## 1. 需求背景

四期交付后：所有对战界面可存棋谱入库，但棋谱库中"对局"类棋谱只能查看；只有残局工作室入口产生的棋局能求解并入自动库；已破解棋局无演示功能；无解/未决残局无对战测试入口。本任务打通"棋谱 → 对战/演示"闭环。

## 2. 需求拆解

| # | 需求 | 规则 |
|---|---|---|
| R1 | 对局棋谱进入对战 | 只提供"**从保存局面继续**"（起点 = `record.finalFen`，由 initialFen 重放 moves 得到，`GameRecord.finalFen` 已实现）。~~重玩整局~~（用户裁剪：不做） |
| R2 | 已破解残局破解演示 | 详情页对每条解法自动播放：播放/暂停、单步、重置、速度 0.5×/1×/2×，到线路尽头自停 |
| R3 | 无解/未决残局进入对战测试 | 起点 = `record.initialFen`（moves 为空，行棋方由 FEN 决定） |
| R4 | 模式覆盖 | 人机(内置 AI)、双人对弈、人机(大模型)、大模型对战；`aiVsAi` 无页面不提供 |
| R5 | 进入后行为 | 黑先局面自动触发 AI/大模型应手；棋谱来源**不写自动存档**（canSave 机制）；行棋方由起点 FEN 决定 |
| R6 | 已分胜负的对局棋谱 | 仅查看/导出，不提供对战入口（终局无"继续"语义） |

## 3. 实现清单

### T1 启动器 `lib/features/record/record_battle_launcher.dart`
- `launchBattle(BuildContext, GameRecord)`：计算起点 FEN（R1/R3 规则）→ BottomSheet 选模式 → 人机 AI 附执方选择 → push 对应页面传 `initialFen`（人机页另传 `playerSide`）。

### T2 对战页参数化（参数为空 = 现行为）
| 页面 | 改动 | 照抄模式 |
|---|---|---|
| `HumanVsHumanGamePage`（app.dart:244） | 加 `initialFen`；`_restoreOrNewGame` 有参走 `newGameFromFen` 并跳过 restore；`GameAutoSave` 加 `canSave`；`_newGame` 按 FEN 分支 | human_vs_ai_page.dart:96-103 |
| `HumanVsLlmPage` | 加 `initialFen`（玩家执红、LLM 执黑；FEN 轮黑 → postFrame 自动 `_triggerLlmMove()`）；`_newGame` 按 FEN 分支；GameAutoSave 加 canSave | 恢复续走模式 human_vs_llm_page.dart:113-117 |
| `LlmVsLlmPage` | 加 `initialFen`；initState/_newGame 走 `newGameFromFen`；恢复路径跳过；GameAutoSave 加 canSave | human_vs_ai_page.dart:98-107 |

### T3 入口与演示
- `RecordDetailPage` AppBar"进入对战"（对局未分胜负/无解/未决显示；已破解、已分胜负不显示）。
- `ReplayBoardView` 播放控制条（R2）。
- `RecordLibraryPage` 列表菜单加"进入对战"快捷项。

### T4 测试与文档
- 单测：launcher 起点/入口分支；播放推进/自停；三页带 FEN 进入（残局来源不写存档、LLM 黑先触发）；全量零回归。
- 更新 docs/phase4/03 手动测试方案、README。

## 4. 验收标准
1. 对局棋谱（未分胜负）与无解/未决残局：一键进入 4 模式，局面/行棋方正确；黑先时 AI/大模型自动应手；不污染各模式自动存档。
2. 已破解残局：详情页自动播放演示，可暂停/单步/调速。
3. 已分胜负对局：无对战入口，查看/导出不受影响。
4. analyze 0 错误、全量测试通过。
