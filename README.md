# 中国象棋 Ultra

一款跨平台（Windows / Android）的中国象棋单机对弈应用，基于 Flutter 3.x + Riverpod 3.x + sqlite3。

## 功能特性

### 第一期（当前版本）
- ✅ **跨平台运行**：支持 Windows 11（桌面）和 Android（移动端）
- ✅ **双人单机对弈**：红/黑方轮流在同一设备上走子，走法规则完整
- ✅ **走法规则引擎**：实现全部 7 种棋子走法（车/马/象/士/将/炮/兵），含马腿/象眼/炮隔子/将帅照面等特殊规则
- ✅ **输赢判定**：自动检测将军/将死/困毙，判定胜负或和棋
- ✅ **自动保存/恢复**：每次走子后保存到 SQLite，App 暂停/退出时强制保存，启动时恢复最近一局
- ✅ **悔棋功能**：支持双方各自撤销上一步走子（可连续悔棋）
- ✅ **新游戏/重新开始**：重置棋盘至初始布局
- ✅ **交互体验**：
  - 点击棋子选中，高亮合法走法
  - 走子动画（平滑移动）
  - 回合指示（红/黑）
  - 走法记录列表（中文记法）
  - 将军/胜负横幅提示

### 第二期（预留接口，未实现）
- ⬜ 残局棋谱导入（.pgn/.xqf/.che）与破解演示
- ⬜ AI 智能提示（接入 Pikafish 引擎）
- ⬜ 人机对战/机器对机器对战

## 技术栈

| 层级 | 技术/框架 | 说明 |
|------|-----------|------|
| UI 框架 | **Flutter 3.x** | CustomPainter 绘制棋盘，动画支持 |
| 状态管理 | **Riverpod 3.x** | Notifier/AsyncNotifier 模式 |
| 象棋规则引擎 | 自研 | 参照 shirne/chinese_chess 设计（GPL-2.0） |
| 持久化 | **sqlite3** + sqlite3_flutter_libs | 轻量级 SQLite，避免代码生成 |
| 测试 | flutter_test | 单元测试（走法/将死/FEN）+ widget 测试 |

## 快速开始

### 环境要求
- Flutter 3.22.0+ / Dart 3.3.0+
- Windows 11 或 Android 设备/模拟器

### 安装依赖
```bash
flutter pub get
```

### 运行
```bash
# Windows
flutter run -d windows

# Android
flutter run -d <device-id> # 或 flutter run
```

### 测试
```bash
flutter test
```

### 构建
```bash
# Windows
flutter build windows --release

# Android APK
flutter build apk --release
```

## 使用说明

1. **走子**：点击己方棋子 → 点击合法目标（高亮小圆点）。
2. **悔棋**：点击右侧面板"悔棋"按钮。
3. **新游戏**：点击"新游戏"按钮，确认后清空当前对局。
4. **保存/恢复**：应用在走子后/暂停时自动保存；启动时自动恢复最近一局。

## 单元测试覆盖

- ✅ FEN 编解码（初始局面/校验/互逆）
- ✅ 各棋子走法（车/马/炮/象/士/将/兵）
- ✅ 将军/将死判定
- ✅ BoardViewModel 状态管理
- ✅ SQLite DAO/Repository
- ✅ Widget 集成测试

已知限制：
- 困毙测试仅验证未被将军状态，完整困毙场面需通过实际对局 FEN 补充。

## 许可声明

本项目为非商业学习用途。
- 规则引擎设计参考 shirne/chinese_chess（GPL-2.0）。
- 二期预留 AI 引擎为 Pikafish（GPL-3.0）。
- 本项目代码采用 MIT 许可。

## 开发计划

- [x] 搭建 Flutter 项目 + MVVM 架构
- [x] 集成规则引擎 + UI 棋盘
- [x] 走子交互 + 动画 + 输赢判定
- [x] 持久化（sqlite3）+ 自动保存/恢复
- [x] 单元测试 + 集成测试
- [ ] 二期：残局导入 + AI 提示 + 人机对战

## 贡献

欢迎 Issue / Pull Request！

## 联系方式

- 项目地址：[E:/ssy_proj/ChineseChessUltra](.)
- 需求文档：srs.md
- 任务清单：task_v1.md

---

**版本**：1.0.0
**更新日期**：2026-07-20