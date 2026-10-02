# 五期实现报告：LLM 棋力提升（P0 Prompt v2 + P1 引擎参谋制）

> 日期：2026-10-02 · 分支：`feature/phase5-llm-strength`
> 前置：`docs/phase5/01`（分析调研）、`docs/phase5/02`（方案设计）、DR-002。

## 1. 已实现内容

### P0 —— Prompt v2（`llm_move_source.dart`，`usePromptV2: true` 启用）

| 改动 | 说明 |
|---|---|
| 棋盘 ASCII 图 | 复用 `MoveAnnotation.asciiBoard`（行号 0-9/列标 a-i），模型直接"看见"局面 |
| 着法逐条注解 | `a6-a4(车九进二,吃车)` —— 中文记法/吃子/将军，全部本地规则生成 |
| 放开分析段 | 回复格式改为「分析: ≤100 字」+ 最后一行「着法: …」，解析器优先取「着法:」标记 |
| token 预算 | 4096 → 8192（仅 v2） |
| 历史扩整局 | 中文记法 ≤60 着；检测到末尾来回重复时注入"长将判负"警示 |
| 重试反馈升级 | 回显无效着法与原因 |
| 基线保留 | `usePromptV2: false`（默认）完整保留 v1 协议，供能力对比 |

### P1 —— 引擎参谋制（`hybrid_llm_move_source.dart` 新模块）

- **引擎报告**：`ChessAi.findBestMoveEx`（根节点全窗口，Top-K 分数为真实分差）+ `evaluateMove`（单着评估）。
- **候选模式**：Prompt 只给引擎 Top-K（K = 3 + blend/20，3~8），LLM 从中选一；清单每行附分桶（最佳/均势、略亏、明显亏、大亏、致命）。
- **护航模式**：LLM 全量清单自由选；所选着法相对最佳损失 > 否决阈值（80 + 3.2×blend 厘兵）→ 带理由再问一次 → 仍超阈值则引擎最佳代走（note 如实记录）。
- **strengthBlend 旋钮**：调节名单宽度/否决阈值；blend=100 护航不否决。
- **兜底链**：LLM 失效 → 引擎最佳代走（fromFallback=true），永不卡死；`AdvisorMode.off` 等价 P0。
- **设置**：`LlmGameSettings` 新增 advisorMode / strengthBlend / advisorDifficulty / redStrengthBlend / blackStrengthBlend（持久化，旧档缺省回落默认）。
- **页面接线**：人机(大模型)与"大模型对战"两页的 MoveSource 换为 Hybrid；设置面板新增"引擎参谋/参谋强度/参谋深度"；**大模型对战红黑双方可各配各的强度**，对局中注解展示参谋评分。

## 2. 能力评估方法与测试

### CI 自动化（无网络，`test/features/shared/engine/strength_evaluation_test.dart`）

1. **战术命中率**：3 个固定战术局面（吃车/双车杀/中线）上，"选尾"弱模型 + Hybrid 候选模式命中引擎 Top-3 比例 = 100%，基线严格更低（确定性断言）。
2. **对局质量**：`MatchRunner` 短局（40 手）对抗 ChessAi(d1)：Hybrid 失误数（逐手引擎分差 >250 厘兵）≤ 基线。
3. **大模型对战场景**：候选 vs 护航两 Hybrid 互打短局正常完成，棋谱可追溯。

### 真实模型评估器（`tool/llm_match_runner.dart`）

```bash
LLM_BASE_URL=https://dashscope.aliyuncs.com/compatible-mode/v1 \
LLM_MODEL=qwen3.8-max LLM_API_KEY=sk-xxx \
flutter run tool/llm_match_runner.dart --suite --games 2 --blend 50
```

- `--suite`：基线/P0/候选/护航四档各对抗内置 AI（难度 3，红黑换边）；
- 单场：`--profile X --red X --black chessai-3`（人 vs 大模型，引擎代打）或 `--red X --black Y`（大模型对战）；
- 指标：胜负、手数、每手耗时、失误率（>250 厘兵占比）、兜底率，JSON 输出。

**建议对比矩阵**：基线 v1 / P0 / P0+候选(blend 50) / P0+护航(blend 50)，各 ≥2 局×红黑换边，对比失误率与胜负——预期 P1 档失误率显著下降且不劣于基线对局体验。

### 手动验收

见 `docs/phase4/03-windows-manual-test-plan.md` TC-STR 段（注解展示、模式切换、blend 生效）。

## 3. 设计决策与偏差

- **enable_thinking 保持由用户配置**（对 02 稿的修订，见 DR-002）：实测 qwen3.8-max 开思维链 60~115s/手，对局不可接受；"放开思考"收益由 v2 正文"分析:"段承载。
- **findBestMoveEx 根节点全窗口**：剪枝模式下非最佳分支返回边界值，会破坏否决阈值计算；全窗口保证 Top-K 分数为真实分差（迭代加深 + 5s 上限控时）。
- **P2a 自洽投票**：按 02 稿留档不做（每手 k 次调用成本×k）。

## 4. 已知限制

- 参谋搜索（候选模式）与 LLM 调用串行，每手增加 0.1~5s（深度档可调）。
- 长将/长捉规则仍未完整实现（重复局面仅靠 Prompt 警示缓解）。
- Pikafish 未接入（设计决策，见 02 稿）；如需更强参谋可后续接入 UCI 引擎替换 `ChessAi.findBestMoveEx`。
