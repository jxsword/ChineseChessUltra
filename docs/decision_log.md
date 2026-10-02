# 决策记录（Decision Records）

## DR-001 2026-10-02 四期残局破解：自研 Dart 求解器 + 多模态识图 + 全模式棋谱库 [状态: 生效]
- 背景: 四期需实现棋谱库、残局摆盘/导入（含 AI 识图）与求破解；求解器方案、识图路线、棋谱覆盖范围需在候选间抉择。
- 选项与权衡: 求解器——自研 Dart AND/OR 迭代加深(可枚举多解/证明无解/限时，纯 Dart 跨平台；深度受算力限制) vs 接入 Pikafish(棋力最强；多解枚举与无解证明需自封装、二进制分发重) vs 两者都做(工作量最大)；
  识图——多模态大模型 API(集成最快，复用 LLM 配置体系；准确率依赖模型，配人工校正兜底) vs 本地 CV/OCR(可控但需原生依赖与模型文件，不适合本期)；
  棋谱范围——全模式手动保存+独立棋谱库(推荐) vs 仅残局类入库 vs 对局自动入库(记录爆炸需清理策略)。
  ← 未选中项（Pikafish、本地 CV、仅残局/自动入库）保留为后续演进路线，见 docs/phase4/01、02。
- 结论: 三项均采用推荐方案；求解器落地 `lib/features/solver/`，识图落地 `vision_board_reader.dart`+人工校正，棋谱库落地 `lib/features/record/`。
- 理由: 残局场景子少分支小，迭代加深 AND/OR 在端侧算力内够用且"枚举多解/证明无解/限时"是硬需求，评分式引擎无法满足；多模态 API 复用三期 OpenAI 兼容通道，零原生依赖；手动保存+独立库与现有每模式自动存档互不干扰。
- 影响: lib/features/{record,solver,studio}、shared/engine/{llm_config,llm_solve_assist,vision_board_reader}.dart、storage/game_dao.dart(game_records 表)、docs/phase4/*、docs/phase4/03 测试方案。
- 记录时间 / 会话: 2026-10-02 / 四期实现会话（计划经用户批准）
