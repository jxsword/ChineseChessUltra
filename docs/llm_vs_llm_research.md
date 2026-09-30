# 大模型互弈（LLM vs LLM）开源方案调研报告

> 调研日期：2026-10-01
> 需求背景：在二期"AI 互弈"功能（目前由本地 Pikafish 引擎驱动双方走子）基础上，扩展为**红黑双方分别接入不同的大模型（LLM）进行对战**。
> 调研方式：全网检索（GitHub、arXiv、官网、文档），所有候选均经搜索结果核实存在；个别未逐一打开仓库页的细节标注为"待核实"。

---

## 0. 核心结论（TL;DR）

1. **没有现成的"LLM vs LLM 下中国象棋"完整可复用产品**。成熟生态集中在国际象棋（LLM chess arena 一类）；中国象棋方向只有科研性质的 Xiangqi-R1 和规则库/引擎层。
2. 业界已收敛出一致的**参考架构**：`LLM 只负责"提议着法" → 规则引擎负责校验合法性 → 非法则重试/惩罚/判负 → 引擎（或裁判 LLM）负责终局判定`。代表：DeepMind game_arena、各 llm-chess-arena 项目。
3. 本项目**已有最关键的底座**：Pikafish（UCCI 引擎）桥接 + 自研走法校验。因此推荐 **"自研 LLM 对战层 + 借鉴成熟协议设计"** 路线，复用成本最低、最贴合 Flutter 架构；而非引入 Python 全家桶。
4. 若想快速出效果，可参考 `llm-chess-arena`（约数百行 Python，OpenRouter 多模型，python-chess 校验）做 Dart 平移——工作量集中在"把 python-chess 换成你已有的象棋规则/Pikafish 校验"。

---

## 1. 候选方案清单（10 个）

### 方案 1：google-deepmind/game_arena（Kaggle Game Arena 官方框架）⭐ 权威度最高

- **定位**：Google DeepMind 为 Kaggle Game Arena 开发的 LLM 竞技对战框架，o3 击败 Grok 4 的 AI 国际象棋表演赛（2025-08）即由此框架驱动。
- **核心机制**：LLM 两两 head-to-head 对战，开源游戏环境（棋类先行），支持文本输入棋盘状态、着法输出与合法性判定，配 TrueSkill/Elo 排行体系。
- **URL**：
  - 源码：https://github.com/google-deepmind/game_arena
  - 平台/官网：https://www.kaggle.com/benchmarks/kaggle/game-arena
  - 技术报告：https://arxiv.org/abs/2609.31473 （Game Arena: Strategic LLM Evaluation in Competitive Environments）
- **活跃度/License**：DeepMind 官方维护，Apache 类开源（以仓库 LICENSE 为准）；活跃度高。
- **技术栈**：Python。
- **LLM 接入**：多 provider 抽象（Gemini/OpenAI/Anthropic 等），可扩展自定义模型。
- **合法性校验**：游戏环境内置规则判定（非纯提示词）。
- **迁移象棋可行性**：架构与协议设计（环境抽象、对局状态机、评分）非常值得借鉴；游戏环境本身需换成中国象棋。
- **缺点**：Python 生态、面向大规模评测设计，对单个 Flutter 应用偏重；需要自建象棋环境适配层。

### 方案 2：llm-chess-arena 系列社区项目 ⭐ 架构最贴近需求、最容易平移

这一类是数量最多的"LLM vs LLM 下棋"社区实现，架构高度一致：

- **代表仓库**：
  - Gopi-Git001/llm-chess-arena：https://github.com/Gopi-Git001/llm-chess-arena
  - DeadPackets/LLMChessArena：https://github.com/DeadPackets/LLMChessArena
  - shenmali/LLM-Chess-Arena：https://github.com/shenmali/LLM-Chess-Arena
  - llm-chess-arena/llm-chess-arena（客户端版，支持 Groq/xAI/Gemini/OpenAI）：https://github.com/llm-chess-arena/llm-chess-arena
- **核心机制**：两个 LLM 各执一色，通过 OpenRouter/OpenAI 兼容 API 提议着法；**python-chess 永远是事实源（source of truth）**，非法着法触发重试/惩罚/判负；有的加了第三方"裁判 LLM"复盘打分、Stockfish 逐手评估、WebSocket 实时直播。
- **URL**：见上；无独立官网（README 即文档）。
- **活跃度/License**：多为个人项目，Star 数十~数百，License 需逐仓库确认。
- **技术栈**：Python（FastAPI/Flask + WebSocket）或纯前端。
- **LLM 接入**：**OpenRouter / OpenAI 兼容 API** —— 天然支持 GLM、DeepSeek、Kimi 等任何兼容端点，换模型只改配置。
- **合法性校验**：规则引擎强校验（python-chess）。
- **迁移象棋可行性**：★★★★★ 思路和代码结构可直接平移：把 python-chess 换成项目已有的象棋规则校验/Pikafish；把 OpenRouter 调用换成 Dart 的 HTTP 客户端即可。
- **缺点**：单仓库质量参差、维护不保证；仅国际象棋。

### 方案 3：TextArena（LeonGuertler/TextArena）⭐ 游戏环境抽象最完善

- **定位**：开源的 LLM 竞技/合作文本游戏框架（100+ 游戏，含国际象棋），OpenAI Gym 风格接口，配 TrueSkill 在线排行榜与 RL 训练支持。
- **URL**：
  - 源码：https://github.com/LeonGuertler/TextArena
  - 官网/排行榜：https://www.textarena.ai
  - 文档：https://www.textarena.ai/docs/first-game
  - 论文：https://arxiv.org/abs/2504.11442
- **活跃度/License**：学术+社区双驱动，活跃；MIT 类许可（以仓库为准）。
- **技术栈**：Python，PyPI 可装（`pip install textarena`）。
- **LLM 接入**：多 provider agent 封装（OpenAI 兼容、本地模型均可）。
- **合法性校验**：环境内置判定；对局协议为标准文本回合制（观察→行动→反馈）。
- **迁移象棋可行性**：其 **环境接口设计（`env.step()` / 观察-动作循环 / 双方 agent 解耦）** 是最值得照抄的抽象；中国象棋可作为新 env 实现。
- **缺点**：Python 库，不能直接进 Flutter；面向评测而非"产品化的对局界面"。

### 方案 4：maxim-saplin/llm_chess（LLM Chess Leaderboard）⭐ 提示词/交互设计参考

- **定位**：知名 LLM 棋力基准（已测 50+ 模型），方法论独特：**把"候选合法着法列表"作为选项给 LLM 多轮对话选择**，而非让模型自由生成着法，同时统计"合法着法率"。
- **URL**：
  - 源码：https://github.com/maxim-saplin/llm_chess
  - 排行榜：https://maxim-saplin.github.io/llm_chess/
  - 论文：https://arxiv.org/html/2512.01992v1
- **活跃度/License**：个人长期维护，活跃（2026 仍在更新）。
- **技术栈**：Python 脚本（llm_chess.py）+ 静态站点。
- **LLM 接入**：OpenAI 兼容端点（可测任意兼容模型）。
- **合法性校验**：python-chess；支持"带/不带合法着法工具"两种模式对比。
- **迁移象棋可行性**：**"给出候选合法着法让模型选"** 的交互模式对提高对局质量极有参考价值（本项目的 Pikafish 恰好能生成候选着法，可形成"引擎出候选 + LLM 拍板"的混合模式）。
- **缺点**：评测脚本性质，无对局 UI；仅国际象棋。

### 方案 5：MotiaDev/chessarena-ai（ChessArena.ai）⭐ 产品化直播形态参考

- **定位**：基于 Motia 工作流引擎构建的开源 LLM 象棋竞技直播平台（chessarena.ai），LLM 排行榜 + 逐手实时流式更新，社区名局如 Groq Llama 3.3 vs xAI Grok。
- **URL**：
  - 源码：https://github.com/MotiaDev/chessarena-ai
  - 官网：https://www.chessarena.ai/about
- **活跃度/License**：Motia 官方示例项目，较活跃。
- **技术栈**：TypeScript/JS（Motia + WebSocket 流式）。
- **LLM 接入**：多 provider。
- **迁移象棋可行性**：其"实时对局直播 + 排行榜 + 逐手解说"的产品形态与本项目 AiVsAiPage 的演进方向吻合；TS 代码比 Python 更接近 Dart 的异步模型，易读易借鉴。
- **缺点**：依赖 Motia 平台概念；仅国际象棋；示例项目定位，非长期库。

### 方案 6：Xiangqi-R1（isyuhaochen/Xiangqi-R1）⭐ 唯一的中国象棋 + LLM 专项

- **定位**：科研开源（论文 arXiv:2507.12215）：通过 SFT + GRPO 强化学习（DeepSeek-R1 同款方法）训练 7B 模型专门下中国象棋，自对弈训练、合法性奖励。
- **URL**：
  - 源码：https://github.com/isyuhaochen/Xiangqi-R1
  - 论文：https://arxiv.org/html/2507.12215v1
- **核心机制**：FEN 棋盘 + UCCI 着法格式训练；规则奖励（非法着法惩罚、胜负奖励）；长思维链后输出 UCCI 着法。相对通用 LLM，着法合法率 +18%、分析准确率 +22%。
- **活跃度**：科研性质，Python，约 15 star；所用规则库为 `cchess`（稍作修改）。
- **迁移象棋可行性**：**直接复用价值有限**（需要自己跑 RL 训练 7B 模型），但两点极有价值：① 证明"通用 LLM 直接下中国象棋合法率低"是普遍痛点；② 其 UCCI 记法 + FEN 的 Prompt 模板与奖励设计可直接借鉴到我们的提示词协议。
- **缺点**：模型需自托管（7B，本地 GPU 或云 GPU）；非对战平台。

### 方案 7：Microsoft AutoGen「Conversational Chess」官方示例 ⭐ 多智能体范式参考

- **定位**：AutoGen 官方 Notebook：两个对话智能体（红/黑）对弈，带 `make_move` 工具与嵌套聊天（裁判 agent 校验），且有**非 OpenAI 模型版本**（双方可配不同 provider）。
- **URL**：
  - 官方文档：https://microsoft.github.io/autogen/0.2/docs/notebooks/agentchat_nested_chats_chess_altmodels/
  - 源码：https://github.com/microsoft/autogen
- **活跃度/License**：微软官方，极活跃；MIT（代码示例部分以仓库为准）。
- **技术栈**：Python。
- **核心机制**：LLM 之间以"对话"推进对局，裁判 agent + 工具调用（board screenshot 校验）保证合法性。
- **迁移象棋可行性**：值得借鉴的是**"棋手 agent + 裁判 agent + 工具调用"的职责划分**；框架本身不宜引入本项目（太重）。
- **缺点**：框架依赖重；国际象棋；对话式推进较慢、token 成本高。

### 方案 8：Fairy-Stockfish + pyffish ⭐ 象棋规则/引擎底座（国际通用）

- **定位**：Stockfish 衍生的**棋类变体引擎**，原生支持中国象棋（Xiangqi）、将棋、韩国将棋等，UCI 协议；Python 绑定 `pyffish` 提供走法生成/校验/FEN。
- **URL**：
  - 源码：https://github.com/fairy-stockfish/Fairy-Stockfish
  - 文档：仓库 README + variants.ini（官方文档载体）；在线对弈应用 https://www.pychess.org （由其驱动）
- **活跃度/License**：GPL-3.0，社区活跃（pychess.org 生产使用）。
- **迁移象棋可行性**：本项目已有 Pikafish（更强的中国象棋专用引擎），Fairy-Stockfish 的增量价值主要在 `variants.ini` 的变体配置思路与 pyffish 的"引擎当规则库"用法；若未来要支持"翻棋/揭棋"等变体，它几乎是唯一选择。
- **缺点**：C++ 引擎，License GPL-3.0 需注意分发合规；与现有 Pikafish 功能重叠。

### 方案 9：中国象棋规则库（cchess / python-chinese-chess / xiangqi.js）⭐ 校验层备选

- **python-chinese-chess**（windshadow233）：https://github.com/windshadow233/python-chinese-chess —— 仿 python-chess API 的纯 Python 象棋库，GPL-3.0。Xiangqi-R1 等项目可用的校验底座。
- **cchess**：https://pub.dev/packages/cchess —— pub.dev 上的 Dart 象棋相关包（成熟度待核实）。
- **xiangqi.js**（lengyanyu258）：https://github.com/lengyanyu258/xiangqi.js —— chess.js 风格的 JS 象棋库（走法生成/校验、将军/将死/和棋判定），另有其衍生 xqwlight 轻量引擎。
- **Dart 生态现状**：pub.dev 上**没有**公认成熟的中国象棋规则库（dartchess 等仅国际象棋）。但本项目已自研棋规与 Pikafish 桥接，此短板影响不大；xiangqi.js 适合作为"补齐棋规盲区"（如和棋判定、重复局面）的对拍参照。

### 方案 10：lichess-bot（协议桥接参考）

- **定位**：Lichess 官方机器人桥（Python）：把本地引擎（UCI/UCCI/USI/自制）接入 Lichess Bot API，与人类/其他 bot 对弈。
- **URL**：
  - 源码：https://github.com/lichess-bot-devs/lichess-bot
  - 配置文档：https://github.com/lichess-bot-devs/lichess-bot/wiki/Configure-lichess-bot
  - Bot API：https://lichess.org/api#tag/Bot
- **迁移象棋可行性**：本项目是本地 UI 对战，不需要 Lichess 接入；但其**"引擎桥"分层（API 流 → 着法翻译 → 引擎进程 → bestmove 回传）** 与本项目 pikafish_bridge 同构，其超时、重连、棋钟处理可作工程参考。
- **备注**：若未来想"把 LLM 包装成一个引擎进程（说 UCCI 协议的 stdout 程序）"，即可无缝复用现有 pikafish_bridge——这是一个零侵入的集成技巧：**LLM 着法代理 = 一个实现 UCCI 子集的本地进程**。

---

## 2. 对比矩阵

| # | 方案 | 复用成本 | 中国象棋适配 | Flutter 集成路径 | 多模型互弈 | 合法性保障 | 活跃度/风险 | License |
|---|------|---------|------------|----------------|-----------|-----------|------------|---------|
| 1 | DeepMind game_arena | 中（借鉴架构） | 需自建环境 | 不可直接嵌入（Python 评测框架） | ✅ 原生 | 环境强校验 | 高/低 | Apache 类 |
| 2 | llm-chess-arena 系列 | **低（可平移）** | 换校验器即可 | 参考→Dart 重写 | ✅ OpenRouter | python-chess 强校验 | 中/中 | 逐仓确认 |
| 3 | TextArena | 中 | 需写新 env | 不可直接嵌入 | ✅ | 环境校验 | 高/低 | 宽松 |
| 4 | llm_chess | 低（借鉴交互） | 需换校验器 | 参考→Dart 重写 | ✅ OpenAI 兼容 | python-chess | 中高/低 | 宽松 |
| 5 | chessarena-ai | 低（借鉴产品形态） | 需换棋种 | TS→Dart 参考好 | ✅ | 引擎校验 | 中/中 | 待确认 |
| 6 | Xiangqi-R1 | 高（需训练/自托管模型） | **原生 UCCI** | 模型走 OpenAI 兼容端点 | 单模型为主（可对不同模型） | cchess 校验 | 低/中（科研） | 待确认 |
| 7 | AutoGen 棋类示例 | 中 | 需换校验器 | 不可直接嵌入 | ✅ 双 provider | 裁判 agent+工具 | 极高/低 | MIT |
| 8 | Fairy-Stockfish/pyffish | 中 | **原生** | 引擎/规则库（C++/Python） | N/A（底座） | 引擎级 | 高/低（GPL） | GPL-3.0 |
| 9 | 象棋规则库（cchess 等） | 低 | **原生** | xiangqi.js 可对拍；cchess 待核实 | N/A（底座） | 规则库 | 中/中 | 多为 GPL/MIT |
| 10 | lichess-bot | 低（借鉴桥接） | 支持 UCCI | 进程桥模式可复用 | N/A（桥） | 引擎级 | 高/低 | 待确认 |

---

## 3. 三条可选技术路线与选型策略

### 路线 A：自研 LLM 对战层（推荐）★★★★★
- **做法**：在现有 `ai_engine.dart` 抽象下新增 `LlmEngine` 实现：OpenAI 兼容 HTTP 调用（支持 GLM/DeepSeek/Kimi/OpenRouter 等，仅 baseURL+key+model 三项可配），提示词协议借鉴 Xiangqi-R1（FEN + 中文纵线/UCCI 着法）与 llm_chess（**附带 Pikafish 生成的候选合法着法列表供选择**）；合法性校验直接复用现有棋规 + Pikafish，非法着法重试 N 次后降级（Pikafish 兜底或判负）。
- **优点**：零新依赖、贴合 Flutter/Riverpod、双方模型天然可不同、API 成本可控。
- **缺点**：自研工作量（估 3-5 个文件：LLM 客户端、着法解析、重试策略、AiVsAi 配置面板）。
- **借鉴来源**：方案 2 的重试/判负策略、方案 4 的候选着法交互、方案 6 的 Prompt 模板、方案 10 的"LLM 包装成 UCCI 进程"零侵入思路。

### 路线 B：平移 llm-chess-arena 架构 ★★★☆
- **做法**：以方案 2 为蓝图做 Dart 重写（对局编排器 + WebSocket/流式 UI 已有雏形）。
- **优点**：有现成代码逻辑对照，踩坑少。
- **缺点**：仍是自研为主，方案 2 本身无象棋规则层，增益与路线 A 相近。

### 路线 C：Python 侧车服务（TextArena / game_arena / AutoGen）★★
- **做法**：本地跑 Python 服务负责 LLM 对局编排，Flutter 通过 HTTP/WS 对接。
- **优点**：直接复用成熟框架的评测/多模型能力。
- **缺点**：破坏"单exe绿色分发"（本项目引擎二进制随 assets 分发）；部署、打包、维护成本显著上升；仅当未来要做"模型排行榜/批量对局"时才值得。

### 推荐结论
**主选路线 A**，并把方案 1/2/4/6/10 的具体设计点作为实现蓝本；Pikafish 从"对弈引擎"升级为"规则裁判 + 候选着法生成器"，LLM 负责"拍板 + 可选解说"。若后续要加模型排位赛（Elo/TrueSkill），再评估引入 game_arena 的评分模块设计。

---

## 4. 风险清单

1. **通用大模型下中国象棋合法率偏低**（Xiangqi-R1 论文实证）→ 必须做强校验 + 重试 + 候选着法注入，否则对局经常崩。
2. **成本与时延**：LLM 每手一次 API 调用，长局成本可观；需支持思考时长限制、流式状态展示（现有 `_aiStatus` 可复用）。
3. **API 稳定性/Key 管理**：双模型 = 双 Key，需要本地安全存储与失效降级。
4. **合规**：Fairy-Stockfish/cchess 等为 GPL，若引入需注意分发；路线 A 仅调 API 不引依赖，无此问题。
5. **候选项目的 License 与活跃度以仓库当前状态为准**，本报告 Star/维护状态为调研时点快照，集成前需二次确认。

---

## 5. 附录：调研过程中一并核实的相关事实

- python-chess **不支持**中国象棋（仅国际象棋及其变体）——不要选它做象棋校验。
- Kaggle Game Arena 2025-08 上线，o3 夺得 AI 国际象棋表演赛冠军（决赛胜 Grok 4）；2026 年榜单头部已更替为 Gemini 3 系列，项目扩展到扑克、狼人杀等游戏。
- Dart/Flutter 生态缺成熟中国象棋规则库，主流做法是 FFI 接引擎或移植 xiangqi.js——本项目已自研棋规，属领先状态。
