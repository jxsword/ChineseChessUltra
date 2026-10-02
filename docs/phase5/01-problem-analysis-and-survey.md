# 大模型对弈棋力远弱于内置 AI：问题分析与全网调研报告

> 阶段：五期（LLM 棋力提升）· 报告 01
> 日期：2026-10-02
> 关联代码：`lib/features/shared/engine/llm_move_source.dart`、`llm_solve_assist.dart`、`ai_engine.dart`
> 关联文档：`docs/llm_vs_llm_research.md`（二期，聚焦"框架选型"；本报告聚焦"单手棋决策质量"）

---

## 0. 结论速览（TL;DR）

1. **结构性原因**：当前 LLM 走棋是"零搜索的一次性模式匹配"——模型在**一次前向推理**里从几十个裸坐标串中挑一个；而内置 AI 每手棋对**数千个局面**做深度 6 + 静态搜索（有效深度约 8-10）的极小化搜索。两者根本不是同一类计算，棋力差距是结构性的，与 qwen3-max 本身多强关系不大。
2. **表示层原因**：Prompt 用 FEN + 裸坐标清单（`b2-e2, h2-e2, …`），不含 ASCII 棋盘图、不含每个着法的棋子身份/吃子/将军/评价值信息。模型必须自己"在脑中解码 FEN"才能理解 `b2-e2` 是什么，这一步就大量出错。
3. **协议层原因**：系统提示词强制"只输出一行、禁止思考"，与推理型模型（Qwen3 系列）的工作方式直接冲突——要么思维链被掐断、要么正文为空退回解析思维链文本。
4. **业界共识**（本次全网调研确认）：**不要让 LLM 自己算着法，让 LLM 用引擎**。主流方案是"引擎出候选/评分 + LLM 拍板（或解释）"的混合架构；纯 Prompt 优化只能减少低级失误，无法弥补搜索深度的差距。
5. **推荐路线**：三级方案——P0 纯 Prompt/协议修复（立即见效、零新依赖）→ P1 引擎混合"参谋制"（核心方案，棋力可调）→ P2 自洽性投票/逐手引擎注解（可选增强）。详见报告 02。

---

## 1. 现状还原：当前一手棋的完整决策链

代码事实（`llm_move_source.dart:130-206`）：

```
每手棋：
  1. allLegalMoves(board)          → 40~80 个合法着法
  2. 编码为裸坐标串 b2-e2          → 丢失棋子身份/吃子/将军信息
  3. 组 Prompt：FEN 一行 + 最近 12 步中文记法 + 坐标清单
  4. system 要求"只回一行：着法: 起点-终点"，禁止任何解释/思考
  5. 一次 chat 调用（temperature 0.3，max_tokens 4096，Qwen3 可关闭思维链）
  6. 正则解析 + 白名单校验
  7. 失败重试 3 次（追加同样的清单）→ 仍失败则内置 AI 兜底
```

关键观察：

- **白名单只保证"合法"，不保证"不臭"**。模型在 40~80 个等价格式的字符串里自由挑选，没有任何一条信息告诉它哪个好哪个坏。送车和护卒在清单里长得一模一样。
- **FEN 一行棋盘对 LLM 极不友好**。国际象棋社区已有实验证据（见 §3.4）：仅给 FEN 的棋力显著低于给可视化棋盘图的；中国象棋 FEN 在通用模型训练语料中的占比又远低于国际象棋 PGN，`rnbakabnr/9/1c5c1/...` 这类串的"脑内解码"错误率更高。
- **对比：同仓库的残局求解辅助（`llm_solve_assist.dart`）反而给了 ASCII 棋盘图**——对弈主链路却没有，属于明显遗漏。
- **"禁止思考"与推理型模型冲突**。Qwen3-max 是思考型模型：`disableThinking` 打开时强行跳过推理（棋力大损）；关闭时思维链消耗 4096 token 预算，正文可能为空，代码退回 `_pickAnswer` 解析思维链文本（`llm_move_source.dart:367-371`）——这条兜底路径能解析出着法纯属运气。

## 2. 原因分析：为什么"很强的通用大模型"下不过"难度 6 的内置 AI"

### 2.1 算力结构：一次前向 vs 数千节点搜索

| 维度 | 内置 AI（`ai_engine.dart`） | LLM 现状 |
|---|---|---|
| 每手棋考察的局面数 | 数千个（αβ 剪枝后） | 1 次（模型"凭感觉"输出 1 个） |
| 前瞻深度 | 深度 6 + 吃子延伸（有效 8~10） | 0（无任何显式推演，除非思维链自发模拟，且极不可靠） |
| 评估函数 | 子力 + 简单位置项，逐节点计算 | 无；靠训练语料中的棋理"直觉" |
| 保证 | 必然不送吃（浅层看得见） | 无任何保证 |

Gary Marcus 团队与多个独立评测（§3.1）反复验证：LLM 没有可靠的**内部棋盘世界模型**——它不是"看棋盘、算变化"，而是"检索语料中相似的文字模式"。一步棋的棋力 ≈ 搜索深度 × 评估质量，LLM 两项都缺。

### 2.2 表示层：裸坐标清单是最差的信息载体

`b2-e2` 对人类棋手毫无意义，对 LLM 同样如此——它必须先从 FEN 反查出 b2 上是什么子，再做决策。调研中 maxim-saplin/llm_chess 与社区实验（§3.4）的共同结论：

- FEN-only prompt 的棋力显著低于"棋盘图 + FEN"双表示；
- 把合法着法按"棋子 + 中文记法 + 吃子 + 将军"标注后，模型选择的合理性显著上升；
- 着法越抽象（炮二平五这类中文记法），模型越容易与坐标系脱钩。

### 2.3 协议层：单样本、低温度、禁止思考

- temperature 0.3 + 单次采样：无 self-consistency，一次"直觉"定生死；
- "禁止输出任何解释/推理"直接把推理型模型最强的能力（长思维链推演）关在了门外；
- max_tokens 4096 对 Qwen3 思维链偏紧，正文被截断后走"解析思维链"的脆弱路径。

### 2.4 为什么"模型本身很强"帮不上忙

qwen3-max 的强体现在：世界知识（棋理谚语、开局套路）、中文理解、长思维链推理。但：

1. **知识 ≠ 计算**。"当头炮马来跳"是知识；算出"车八进七之后 5 层内有对杀先手"是计算。前者 LLM 有，后者必须显式搜索。
2. **通用 LLM 的中国象棋语料稀薄**。Xiangqi-R1（§3.5）实测：未经专项训练的通用模型在中国象棋上着法合法率都成问题，遑论棋力。
3. **即使国际象棋方向最强的通用模型**（经大量 PGN 语料预训练）也只是"业余高段"水平，且非法着法率不可忽视（§3.1）。中国象棋只会更差。

> 结论：这不是"换更强模型"能解决的问题，而是**架构问题**。模型越强，越应该让它做它擅长的事（策略选择、局面解释、风格偏好），把逐手战术计算交给确定性搜索。

## 3. 全网调研：现有解决方案对比

### 3.1 问题确认类研究（为什么 LLM 下不好棋）

| 来源 | 核心发现 |
|---|---|
| [Why LLMs Can't Play Chess（Nico Westerdale）](https://www.nicowesterdale.com/blog/why-llms-cant-play-chess) | 顶级推理模型在国际象棋上仅"弱俱乐部"水平；评测需用 Komodo Dragon 等引擎做 Elo 锚定 |
| [Fluent but Wrong: LLMs, Chess, and Internal Models](https://www.informationdifference.com/fluent-but-wrong-llms-chess-and-internal-models) | 四大主流模型全部停留在弱棋手水平：语言流利 ≠ 内部棋盘模型 |
| [Palisade Research: specification gaming（arXiv 2502.13295）](https://arxiv.org/abs/2502.13295)（[MIT Tech Review 报道](https://www.technologyreview.com/2025/03/05/1112819/ai-reasoning-models-can-cheat-to-win-chess-games)） | 让 o1-preview/o3/R1 与 Stockfish 对弈，模型打不过就"改文件作弊"——正面证实 LLM 正当手段赢不了引擎；对我们的启示：白名单校验必须保留 |
| [maxim-saplin/llm_chess 排行榜](https://github.com/maxim-saplin/llm_chess)（[论文 arXiv 2512.01992](https://arxiv.org/html/2512.01992v1)） | 50+ 模型系统评测：有合法着法工具 vs 无工具棋力差异显著；"给候选清单让模型选"是可行交互模式 |

### 3.2 混合架构类（业界共识方案）⭐

| 来源 | 方案要点 | 实测效果 |
|---|---|---|
| [Use LLMs to use chess engines, not to play chess](https://edjohnsonwilliams.co.uk/blog/2025-06-11-use-llms-to-use-chess-engines-not-to-play-chess) | 引用 Apple 推理极限研究，主张 LLM 编排引擎而非亲自下 | — |
| [Agentic ChessMate（Tredence）](https://www.tredence.com/blog/agentic-chess-against-stockfish-10) | LLM agent + 工具调用引擎分析，逐手决策 | agent 流水线 ≈2000 Elo，击败削弱版 Stockfish 10 |
| [DeepMind game_arena](https://github.com/google-deepmind/game_arena) | Kaggle Game Arena 官方框架：LLM 对战 + 环境强校验 | o3 vs Grok 4 表演赛即由此驱动 |
| 社区 llm-chess-arena 系列（[例](https://github.com/shenmali/LLM-Chess-Arena)） | python-chess 为事实源，非法重试/判负；部分加 Stockfish 逐手评估、裁判 LLM 解说 | 架构与本项目现有一致，差别在"引擎逐手评估"这一层 |

**共识架构**：`引擎/环境 = 事实源与战术大脑；LLM = 提议者/选择者/解说者；校验层 = 裁判`。本项目一期的"模型提议 + 本地校验"已完成右半边，缺的是**左半边的引擎战术输入**。

### 3.3 搜索增强类

| 来源 | 方案要点 | 对本项目适用性 |
|---|---|---|
| [Grandmaster-Level Chess Without a Search（DeepMind, arXiv 2402.04494）](https://arxiv.org/html/2402.04494v1)（[官方代码](https://github.com/google-deepmind/searchless_chess)） | Transformer 用 Stockfish 16 蒸馏的动作值做监督训练，无搜索达 Lichess blitz 2895 Elo | **训练路线，不适用于 API 调用型模型**；但"把引擎评价值注入输入"的思想可降级为 Prompt 层注解（见 P2 方案） |
| [Mastering Board Games by External and Internal Planning（arXiv 2412.12119）](https://arxiv.org/html/2412.12119v1) | 模型作为 MCTS 的价值/策略先验，外部搜索控制器引导 | 通用框架；本项目本地引擎本身就是成熟搜索，套 LLM-MCTS 成本高收益低 |
| [LATS / Tree Search for LM Agents（arXiv 2407.01476）](https://arxiv.org/html/2407.01476v4) | LLM 同时充当策略与价值估计器的树搜索 | 每手棋需数十次 LLM 调用，延迟与成本爆炸；仅适合作纯研究方向 |
| [Language Models can Self-Improve at State-Value Estimation（NeurIPS 2025）](https://neurips.cc/virtual/2025/poster/117628) | LLM 自我改进的局面估值用于树搜索 | 同上，研究性路线 |

### 3.4 Prompt 工程类（低成本改进）

| 来源 | 要点 |
|---|---|
| [Don't use FEN to play chess with LLMs（Raku Advent）](https://raku-advent.blog/2024/12/04/day-4-dont-use-forsyth-edwards-notation-to-play-chess-with-llms) | 仅 FEN 表示对 LLM 不友好，应辅以可视化棋盘 |
| [Playing chess with LLMs（Nicholas Carlini）](https://nicholas.carlini.com/writing/2023/chess-llm.html) | 经典实验：GPT-3.5/4 连"一步杀"都要看表示形式；表示方式直接决定成败 |
| [llm_chess 的 prompt 变体实验](https://github.com/maxim-saplin/llm_chess) | 候选着法列表 + 多轮选择；self-consistency/多数投票可提升稳定性 |
| [LLM Chess 基准（arXiv 2512.01992）](https://arxiv.org/html/2512.01992v1) | 系统性验证：指令遵循与推理泛化共同决定棋力 |

### 3.5 中国象棋专项

| 来源 | 要点 |
|---|---|
| [Xiangqi-R1（arXiv 2507.12215）](https://arxiv.org/html/2507.12215v1)（[GitHub](https://github.com/isyuhaochen/Xiangqi-R1)） | SFT + GRPO 强化学习训练 7B 象棋专模型，自对弈 + 合法性奖励：合法率 +18%、分析准确率 +22%。**训练路线，不适用本项目 API 模式，但证明"通用模型 + 规则奖励微调"有效** |
| [Mastering Chinese Chess AI Without Search（arXiv 2410.04865）](https://arxiv.org/abs/2410.04865) | 无搜索象棋 AI（模仿学习 + 估值网络），与 DeepMind 思路同源 |
| [VinXiangQi](https://blog.csdn.net/gitblog_00460/article/details/162299804)、[免费象棋 AI 助手（Pikafish 多实例）](https://blog.csdn.net/gitblog_01101/article/details/162602103) | 视觉识别 + Pikafish 引擎深度 15-20 分析的实战工具，印证"引擎出着法"是象棋侧的成熟生产力路线 |

### 3.6 调研总结：五条路线横向对比

| 路线 | 代表 | 棋力上限 | 成本/延迟 | 对本项目适配度 |
|---|---|---|---|---|
| A. 纯 Prompt 优化（棋盘图、着法标注、放开思考） | §3.4 | 低~中（减少送吃级失误，战术盲区仍在） | 零新依赖 | ⭐⭐⭐⭐ 作 P0 立即做 |
| B. 引擎混合：引擎候选/评分 + LLM 拍板或护航 | §3.2（业界共识） | 高（≈引擎棋力减一个小量，且可调） | 每手多一次本地搜索（毫秒级） | ⭐⭐⭐⭐⭐ **核心方案 P1** |
| C. Self-consistency 投票（采样 k 次取多数） | §3.4 | 中（稳定性↑，强度仍受限于模型分布） | 每手 k 次 API 调用 | ⭐⭐⭐ 可选 P2 |
| D. 逐手引擎注解进 Prompt（评分分桶文字化） | DeepMind 思想降级 | 中高 | 一次本地搜索 + 更多 token | ⭐⭐⭐⭐ P1 的增强项 |
| E. 专项微调（Xiangqi-R1 路线）/ 蒸馏训练 | §3.5 / §3.3 | 最高（但需训练基础设施） | 极高（GPU 训练 + 自建数据） | ⭐ 超出本项目范围，记录备查 |

> **推荐组合**：P0（A 全量）+ P1（B 的"参谋制"混合，内置 D 的评分注解）+ P2（C 作为可开关选项）。E 不做，文档存档。

## 4. 对本项目的具体诊断清单

| # | 问题 | 代码位置 | 影响 |
|---|---|---|---|
| 1 | 对弈 Prompt 无 ASCII 棋盘图（残局求解反而有） | `llm_move_source.dart:35-62` | 模型被迫解码 FEN，位置理解错误 |
| 2 | 合法清单为裸坐标，无棋子/吃子/将军/评价值标注 | `llm_move_source.dart:168-171` | 模型在等价字符串中盲选，无法权衡 |
| 3 | 系统提示禁止思考，与 Qwen3 推理模式冲突；`disableThinking` 打开时棋力骤降 | `llm_move_source.dart:18-33, 258-261` | 推理型模型最强能力被关掉 |
| 4 | temperature 0.3 单样本，无投票机制 | `llm_move_source.dart:255` | 一次直觉定生死 |
| 5 | 历史仅 12 步，无全局长链、无重复局面警示 | `llm_move_source.dart:43-57` | 长对局中模型失去全局观 |
| 6 | 模型选中"合法但致命"的着法无任何拦截 | `nextMove` 全流程 | 白名单只管合法不管质量 |
| 7 | 重试只是重复贴清单，不带失败着法的后果分析 | `llm_move_source.dart:198-203` | 重试成功率低且无学习信号 |

以上每一条在报告 02 中都有对应修复设计。

---

## 附：主要参考链接

- Palisade Research, *Demonstrating specification gaming in reasoning models* — https://arxiv.org/abs/2502.13295
- DeepMind, *Grandmaster-Level Chess Without a Search* — https://arxiv.org/abs/2402.04494 / https://github.com/google-deepmind/searchless_chess
- Xiangqi-R1 — https://arxiv.org/abs/2507.12215 / https://github.com/isyuhaochen/Xiangqi-R1
- maxim-saplin/llm_chess — https://github.com/maxim-saplin/llm_chess
- google-deepmind/game_arena — https://github.com/google-deepmind/game_arena
- Use LLMs to use chess engines — https://edjohnsonwilliams.co.uk/blog/2025-06-11-use-llms-to-use-chess-engines-not-to-play-chess
- Agentic ChessMate — https://www.tredence.com/blog/agentic-chess-against-stockfish-10
- Tree Search for Language Model Agents — https://arxiv.org/abs/2407.01476
- Mastering Board Games by External and Internal Planning — https://arxiv.org/abs/2412.12119
- Don't use FEN to play chess with LLMs — https://raku-advent.blog/2024/12/04/day-4-dont-use-forsyth-edwards-notation-to-play-chess-with-llms
- Nicholas Carlini, Playing chess with LLMs — https://nicholas.carlini.com/writing/2023/chess-llm.html
- MIT Technology Review 对 Palisade 研究的报道 — https://www.technologyreview.com/2025/03/05/1112819/ai-reasoning-models-can-cheat-to-win-chess-games
