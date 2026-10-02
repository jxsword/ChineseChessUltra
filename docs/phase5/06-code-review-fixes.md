# 五期代码两轮复审记录与修复清单

> 日期：2026-10-02 · 分支：`feature/phase5-llm-strength`
> 方式：第一轮双代理并行深审（引擎/评估层 + 页面/工具层），修复后本人复核完成第二轮（验证修复正确性与残留扫描）。

## 第一轮发现（27 项，P1×13 / P2×14，均已确认成立）

### 已修复（P1 级，全部修复并补测试）

| # | 问题 | 修复 |
|---|---|---|
| 1 | `_looksLikeRepetition` 用"同侧同 from"判重复——红黑交替下几何上不可能，**死逻辑**（重复警示永不触发） | 改为互逆着法判定（红 A→B、黑 C→D、红 B→A、黑 D→C）；测试历史同步改为真实拉锯序列 |
| 2 | Hybrid 内部构造 LlmMoveSource 未传 `usePromptV2`——v2 提示配 4096 预算，思考型模型被截断后误判"模型失效" | 两处构造补 `usePromptV2: true` |
| 3 | 否决链 + `fallback=resign`：有合法着法却被判负；反向 candidate 模式又无视 resign | 区分"**参谋否决**"（始终由引擎最佳代走，fromFallback=true）与"**模型真失败**"（遵循 resign）；`lastReason` 在有效着法后置 null，文案不再出现 null |
| 4 | MatchRunner 质量评估深度口径失配（findBestMoveEx 总深 depth，evaluateMove 用同参数实为 depth+1）——`report.best` 自己都可能被记失误 | `evalDepth = qualityDepth - 1` 对齐口径 |
| 5 | `runSeries` 注释称红黑换边但从不换边 | 奇数局对调 |
| 6 | **配置丢失竞态**（human_vs_llm）：加载完成前退出，dispose 用空配置覆盖用户端点与 Key | `_configLoaded/_configsLoaded` 标志守卫（llm_vs_llm 同款竞态一并修复） |
| 7 | **llm_vs_llm 暂停→恢复竞态**：旧循环苏醒后通过双检查，两条循环并发驱动，可误判"着法未通过校验"终止对局 | 恢复时 `_gameSeq++` 作废旧循环 |
| 8 | **BoardWidget 动画窗口竞态**：onMoved 在未落子/重复落子时触发，人机页会让"黑方模型"走红方的回合 | 动画期间忽略点击；onMoved 仅在历史真正增长时触发 |
| 9 | human_vs_llm `fallback=resign`：对局**软死锁**（棋盘停在黑方，玩家无从下手） | 新增 `BoardViewModel.resign(loser)`，failed 分支显式写入胜负；llm_vs_llm `_onSideFailed` 同样写入（顺带修复"判负不产生对局结果"） |
| 10 | **设置互污染**：human 页整对象回写会把 llm_vs_llm 页的走棋间隔/红黑强度清回默认 | load 快照 + `copyWith` 只覆盖本页字段；两页 dispose/防抖均加双加载守卫 |
| 11 | systemV2 承诺的"评估分档"在 off/gate 清单中不存在 | `withBucketGuide` 参数：分档引导仅在候选模式（清单真带分桶）注入 |
| 12 | Hybrid 三处 `Isolate.run` 无兜底，受限环境直接判负 | `_searchReport/_evaluateCp` 包 try/catch 退化为同步计算（对齐 ChessAiMoveSource 行为） |
| 13 | CLI：`chessai-3` 是文档化默认却非 profile 键，会被静默替换成 LLM（评估失真）；`--suite` 忽略 `--games` | `chessai-<难度>` 显式解析；未知黑方报错退出；suite 使用 `--games`/`--difficulty` |

### 已修复（P2 级）

| # | 问题 | 修复 |
|---|---|---|
| 14 | llm_vs_llm `--red` 参数不生效 | chessai 对战分支尊重 `--red` 指定的 profile |
| 15 | MatchRunner `Future.timeout` 默认 5 分钟会切断 Hybrid 兜底链 | 默认提至 15 分钟（单手最坏路径 ≈ 12 分钟） |
| 16 | MatchRunner 质量评估在主 isolate 同步跑重搜索（Flutter 侧会卡 UI） | 包 `Isolate.run` |
| 17 | `evaluateMove` 不校验几何合法性（蹩腿/隔子伪非法会被打分） | 补 `legalMovesFor` 校验，doc 更新 |
| 18 | 否决被接受后 note 用被否决那手的陈旧分数 | `_askAgainWithVeto` 返回 (着法, 评分)，note 用新分 |
| 19 | studio FEN controller 在 build 内创建——泄漏 + 识图计时的整页 rebuild 每秒清空用户输入 | 提升为 State 字段并 dispose |
| 20 | 识图文案"超时上限 120 秒"与实际（120s×2 次）不符 | 文案修正 |
| 21 | launcher 执方 sheet await 后缺 `context.mounted` 检查 | 补齐 |
| 22 | 评估测试 `assumeTrue` 失败静默 Skip 会掩盖回归 | 改为硬断言 |
| 23 | 评估测试命中率断言的深度与被测 source 不一致（结构性不成立） | 测试侧报告与 source 同用 depth 2 |
| 24 | 两页 nextMove 无 try/catch（未预期异常会锁死页面/死循环） | human 页复位+提示；llm_vs_llm 页 `_onSideFailed` |
| 25 | `fromMapChecked` 对 timeout/maxAttempts 不 clamp（存 0 会秒失败/零重试） | clamp(5,600)/clamp(1,10)/clamp(0,60) |
| 26 | LlmConfigStore 拆分后页面导入遗漏 | 补齐（无遗漏经全仓 grep 验证） |
| 27 | 识图计时起点/黑先触发/存档隔离等第一轮之前的问题 | 前次已修，本轮回归验证 |

### 复审确认无问题的关键项
`_Search` 重构未改变 findBestMove 各难度行为（与 2134e91 逐行对比）；LlmConfigStore 拆分无遗漏导入；红黑 blend 按方传入正确；摆盘规则不误拦缺士象残局；replay 播放 Timer 生命周期正确；全库无凭据泄漏路径；hybrid Isolate 闭包均只捕获可发送对象。

## 第二轮结论
- 第一轮 27 项全部修复，回归 280 例全绿、analyze 0 error、tool 脚本 `dart run` 直接可用；
- 第二轮新增修复 3 项：llm_vs_llm 同款配置竞态、settings 回写竞态（两页）、`--red` 参数与单手超时上限；
- 复审未再发现新的 P0/P1 问题。
