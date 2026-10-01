# 中国象棋 App – 第三期需求与设计说明（LLM 对战）

## 一、总体目标

在二期"内置 AI 对战"的基础上，接入**大语言模型（LLM）**作为新的棋手来源：

1. **人 vs LLM 对战**：玩家与某个大模型对弈；
2. **LLM vs LLM 对战**：两个**不同**的大模型互弈（双方端点、API Key、模型 ID 均可独立配置）。

### 入口决策：两个独立新入口，不与单机 AI 页面合并

第 3 期提供两个**独立页面**：

| 入口 | 页面 | 说明 |
|---|---|---|
| 人机对战（内置 AI） | `HumanVsAiPage`（二期，保持不动） | 本地 Negamax 引擎，无需网络 |
| **人机对战（大模型）** | `HumanVsLlmPage`（三一新） | 玩家执红，LLM 执黑 |
| **大模型对战** | `LlmVsLlmPage`（三一新，**替换**二期假实现的 `AiVsAiPage`） | 红/黑双方各配一个 LLM 互弈 |
| 双人对弈 | `HumanVsHumanGamePage`（二期，保持不动） | — |

**理由**：
- 现有 `AiVsAiPage` 是二期占位假实现（从写死数组随机取子），直接替换不损失任何功能；
- 三个对战页面各自单一职责，互不干扰，避免"一个页面既选内置 AI 又配模型"的设置面板复杂化；
- 大模型调用链（HTTP、重试、超时）与本地引擎调用链（Isolate、毫秒级）生命周期完全不同，分开页面可让状态栏、错误提示各说各话。

**与单机 AI 的结合点收敛到代码层**：新增 `MoveSource`（棋手）抽象，`ChessAi`（内置引擎）与 `LlmMoveSource` 是两个实现；"结合"发生在共享这一个接口上，而非 UI 上。

### 技术选型（依据 `docs/llm_vs_llm_research.md` 调研结论）

- **路线 A：纯 Dart 自研 LLM 着法层**——项目已收敛为"零引擎二进制、纯 Dart 单 exe"形态，不引入 Python 侧车服务；
- 采用调研确认的业界标准架构：**LLM 只提议着法 → 规则引擎强校验 → 非法重试 → 失败降级**（DeepMind game_arena / llm-chess-arena 同构）；
- 采用 **"候选合法着法清单"交互**（llm_chess 方法论）：每手把当前局面全部合法着法列给模型选择，规避 Xiangqi-R1 论文实证的"通用大模型自由生成中国象棋着法合法率低"问题；
- Prompt 记法借鉴 Xiangqi-R1：FEN 局面 + 中文纵线记法历史 + 坐标着法输出；
- LLM 接入走 **OpenAI 兼容 `/chat/completions`**，天然支持智谱 GLM / DeepSeek / Kimi / OpenRouter / OpenAI 及任意兼容端点。

## 二、系统设计

### 2.1 模块结构

```
lib/features/
├── board/
│   ├── model/
│   │   └── move_notation.dart          # [新] 中文纵线记法扩展（自 board_vm.dart 抽出复用）
│   └── view/
│       ├── human_vs_llm_page.dart      # [新] 人 vs 大模型
│       ├── llm_vs_llm_page.dart        # [新] 大模型 vs 大模型
│       └── widgets/
│           └── llm_config_editor.dart  # [新] 单侧模型配置编辑卡（两页共用）
└── shared/engine/
    ├── move_source.dart                # [新] 棋手抽象 + 内置 AI 实现 + 合法着法工具
    ├── llm_config.dart                 # [新] 模型配置模型 + 安全存储 + 端点预设
    └── llm_move_source.dart            # [新] OpenAI 兼容客户端 + Prompt + 解析 + 重试降级
```

删除：`lib/features/board/view/ai_vs_ai_page.dart`（假实现）。

### 2.2 棋手抽象（`move_source.dart`）

```dart
/// 一步棋的裁决结果。
enum MoveSourceStatus { ok, noLegalMove, failed }

class MoveSourceResult {
  final Move? move;        // ok 时非空
  final String? note;      // 模型思路 / 错误说明（UI 展示）
  final bool fromFallback; // 是否由内置 AI 兜底代走
  final MoveSourceStatus status;
}

abstract class MoveSource {
  String get displayName;  // 状态栏展示，如 "glm-4-flash（智谱）"
  Future<MoveSourceResult> nextMove(Board board, {List<Move> history = const []});
}
```

- `ChessAiMoveSource`：包装 `ChessAi.findBestMove`（Isolate 运行，难度可配），忽略 history；
- `LlmMoveSource`：见 2.4；
- 工具函数：`allLegalMoves(Board)`（当前走子方全量合法着法）、坐标编解码 `encodeCell/decodeCell`。

坐标约定（与项目棋盘一致）：列 `a-i` 对应 col 0-8（左→右），行 `0-9` 对应 row 0-9（**0 为黑方底线/棋盘顶部，9 为红方底线/棋盘底部**），着法写作 `起点-终点`（如 `h7-e7` 即"炮二平五"类走法）。

### 2.3 模型配置（`llm_config.dart`）

```dart
class LlmConfig {
  final String baseUrl;  // 如 https://open.bigmodel.cn/api/paas/v4
  final String apiKey;   // 用户在 UI 输入
  final String model;    // 模型 ID，如 glm-4-flash
  // toJson / fromJson（持久化用）
}
```

- **双槽位**：`红方配置`、`黑方配置` 独立存储；"人机对战（大模型）"使用黑方槽位（玩家默认执红）。
- **存储安全**：
  - API Key 属凭据：仅存入 **flutter_secure_storage**（Windows 下为 DPAPI 加密的密钥服务），**不落 shared_preferences、不进源码/示例/测试**；UI 中掩码显示（可切换明文）；
  - baseUrl / model 非敏感，随 Key 一并存 secure storage（简化为单 KV）。
- **端点预设**：智谱 GLM / DeepSeek / Kimi(Moonshot) / OpenRouter / OpenAI / 自定义，选择预设自动填充 baseUrl 与示例模型 ID（仅是端点地址，非凭据）。
- **连通性测试**：配置卡提供"测试连接"按钮，向端点发一条 `max_tokens=4` 的最小请求，反馈成功/失败原因。

### 2.4 LLM 着法客户端（`llm_move_source.dart`）

**Prompt 协议**（每手一次调用，非流式）：

- system：角色设定（执红/执黑棋手）+ 坐标约定 + "只能从合法着法清单中选择" + 严格输出格式（末行 `着法: 起点-终点`，可先给一句话思路）；
- user：当前 FEN、轮走方、最近 12 手中文纵线记法（如"炮二平五"）、**全量合法着法清单**（坐标串）；
- 失败重试时追加反馈："你上一次的回复无法解析/不在清单中，请只输出清单中的着法"。

**调用链**：

```
nextMove(board, history)
  ├─ 生成合法着法清单（空 → noLegalMove）
  ├─ 组装 Prompt → POST {baseUrl}/chat/completions（Bearer Key）
  │    · 流式 SSE 接收：超时为「空闲超时」（两次数据块的最大间隔），
  │      总耗时另有上限（空闲超时 × 4）；模型持续吐字不误判超时
  │    · max_tokens=4096：为思考型模型（Qwen3 等）的思维链留足预算
  │    · 可选 enable_thinking=false（配置卡「关闭思维链」开关）
  ├─ 解析回复（正则提取 `a0` 式坐标对；正文为空时退回思维链文本尽力提取）
  │    → 与合法清单比对
  ├─ 非法/解析失败/网络错误 → 重试（默认 3 次）
  └─ 全部失败 → 降级策略：
       ├─ builtinAi（默认）：内置 ChessAi（难度3）代走一手，note 标注"兜底"
       └─ resign：返回 failed，页面停止对局并提示判负
```

- `temperature=0.3`（代码内常量，v1 不暴露 UI）；
- 回复中的"思路"一句话作为 `note` 透出，供状态栏/思考过程展示；
- baseUrl 归一化：去尾斜杠后拼 `/chat/completions`；若用户已填完整路径则直接使用。

### 2.5 页面行为

**HumanVsLlmPage**（复用人机对战页骨架）：
- 进入即开新局；玩家执红点击走子（`BoardWidget.onMoved`）；
- 玩家走子后：锁输入 → 状态栏"模型思考中…" → `LlmMoveSource.nextMove` → `playMove` 落子 → 解锁；
- 侧栏：黑方模型配置卡 + 对局设置（单步超时/重试次数/兜底策略）+ 保存配置 + 走法记录；
- 模型最终失败：状态栏显示错误，解锁输入，允许"新游戏"重开（v1 不做棋盘判负标记）。

**LlmVsLlmPage**（全新实现，替换假页面）：
- 侧栏：红方配置卡 + 黑方配置卡 + 对局设置（单步超时/重试/兜底/走棋间隔）+ 保存配置；
- AppBar 播放/暂停/停止/新游戏；对局循环由页面驱动（不依赖 `onMoved`）：
  ```
  while 运行中:
    state 已结束 → 停
    取当前走子方 → 状态栏"红方（model）思考中"
    source.nextMove(board.copy(), history) → playMove 校验落子
    结果 note 更新到状态栏 → 间隔延时 → 下一手
  ```
- `_gameSeq` 代数机制取消过期请求（新游戏/停止自增）；暂停在两手之间生效；
- 双方最终失败（resign 策略或网络异常）→ 循环停止，状态栏说明。

**复用不改动**：`BoardViewModel`（含 `playMove` 强校验、胜负判定）、`BoardWidget`、`ResultBanner`、`MoveRecordsList`、`ChessAi`。

### 2.6 安全与合规要点

- 源码、示例、测试中**不得出现任何可用凭据字面量**；示例端点/模型 ID 仅为公开地址与名称；
- API Key 仅从密钥服务（flutter_secure_storage）读写；日志/调试输出不打印 Key；
- 无内置任何模型 Key；未配置 Key 时调用会得到明确错误提示。

## 三、分步实现安排

| 步骤 | 内容 | 产出 |
|---|---|---|
| 0 基础层 | move_notation 抽取、MoveSource 抽象、LlmConfig+安全存储 | shared/engine 三文件 |
| 1 人 vs LLM | LlmMoveSource 客户端 + HumanVsLlmPage + 入口 | 可与任意兼容模型对弈 |
| 2 LLM vs LLM | LlmVsLlmPage（替换假页）+ 双侧配置 + 对局循环 | 双模型互弈 |
| 3 测试验证 | 单元测试（解析/坐标/Prompt/配置序列化）+ analyze + build | 全绿 |

## 四、验收标准

1. `flutter analyze` 无错误；`flutter test` 通过；`flutter build windows --debug` 成功；
2. 不配置任何 Key 时进入页面有明确"未配置"提示，不崩溃；
3. 配置一个 OpenAI 兼容端点后：人 vs LLM 能完整对弈至胜负分出；非法回复可自动重试（状态栏可见）；
4. 配置两个不同端点/模型后：大模型对战能完整对弈，走法记录正常滚动，暂停/停止/新游戏即时生效；
5. 全程源码无任何 API Key 字面量。

## 五、本期不做（后续迭代候选）

- 模型流式输出（SSE）与逐 token 思考展示；
- 中文纵线记法（"炮二平五"）的解析回退（v1 仅坐标格式 + 重试）；
- 对局存档持久化 / 复盘回放、模型 Elo 排位赛（可参考 game_arena）；
- 移动端网络适配调优；多轮 system 上下文缓存以省 token。
