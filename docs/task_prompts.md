# 跨平台构建测试任务提示词（按 P0 → P1 → P2 顺序执行）

> 用法：每个任务开一个新会话，粘贴对应任务的完整提示词；
> 或直接说"执行 docs/task_prompts.md 中的任务 N"。

---

## 任务 1（P0）——Windows 本机 Android 构建 + 模拟器测试

```
项目：E:\ssy_proj\ChineseChessUltra（Flutter 中国象棋应用，main 分支）。
当前仅在 Windows 桌面端做过测试，本任务目标：修复 Android 工具链，完成 Android
release 构建并用模拟器做安装运行冒烟 + 棋谱下载全链路验证。

背景事实（已确认，勿重复调查）：
- `flutter doctor` 显示 Android toolchain [X]（原因未知，先 `flutter doctor -v` 诊断，
  常见原因：缺 cmdline-tools、licenses 未接受、JDK 版本）。
- 项目平台目录只有 android/ 与 windows/；无 .github/workflows。
- 棋谱语料：本地开发用目录联接 corpus → E:\ssy_proj\qp；应用内路径解析逻辑在
  lib/features/puzzle/model/corpus_paths.dart（优先级：用户设置 > legacy corpus >
  平台默认；Android 默认 = getExternalStorageDirectory()/corpus，即
  /storage/emulated/0/Android/data/<包名>/files/corpus）。
- 语料下载：lib/features/puzzle/model/corpus_downloader.dart 的
  CorpusDownloader.downloadAndExtract，URL 常量 CorpusPaths.downloadUrl =
  https://github.com/jxsword/qp-corpus/releases/latest/download/qp-corpus.zip
  （45.8MB，已发布并验证可匿名下载）；下载引导 UI 在 corpus_browser_page.dart
  （语料缺失时显示"下载棋谱库"按钮）；AndroidManifest 已加 INTERNET 权限。
- 模拟器上不存在 corpus 联接 → 棋谱库页应显示缺失引导（这是预期行为，正是
  我们要验证的入口）。
- 已知坑：Git Credential Manager 不支持 socks5 系统代理（推送时如遇
  "ServicePointManager 不支持 socks5"报错，改用
  git -c credential.helper= -c 'credential.https://github.com.helper=!gh auth git-credential' push）。

执行步骤：
1. `flutter doctor -v` 诊断 Android toolchain，修复到 [√]（装 SDK 组件/
   `flutter doctor --android-licenses` 等），修复方式记录下来。
2. `flutter build apk --release`，确认产物 build/app/outputs/flutter-apk/app-release.apk。
3. `flutter emulators` 查看可用 AVD；没有则用 avdmanager 创建（Pixel 7,
   API 34, x86_64），启动模拟器。
4. `flutter run --release`（或 adb install apk）在模拟器上启动应用，按以下冒烟
   清单逐项验证并记录结果：
   a) 主导航四个入口正常；
   b) 人机对战：走子、AI 应手（Isolate 计算）、悔棋、新游戏；
   c) 残局库：棋谱库页应显示"未找到棋谱语料"引导 + 当前路径
      （Android/data/<包名>/files/corpus）；
   d) 点"下载棋谱库"：下载进度 → 解压完成 → 自动重载出分类列表（应出现
      XQF-象棋谱大全/ChessQ-gamebooks/PGN 分类）；
   e) 勾选"仅看残局"→ 打开适情雅趣任一局 → 破解演示播放正常；
   f) 残局详情页"从残局始盘开始人机对战"（执红）→ 始盘为残局局面，AI 应手正常；
   g) 通关/失败对话框在终局时弹出；
   h) adb shell ls /storage/emulated/0/Android/data/<包名>/files/corpus 确认语料落位。
5. 发现 bug：先报告诊断（症状/定位/建议），经确认后再改代码。

验收标准：toolchain [√]；APK 构建成功；冒烟清单 a-h 全过或明确记录问题。
约束：不提交任何 token 字面量；不推送远程；不改动 Windows 已验证功能（除非修 bug）；
最后把修复与验证结果写入 docs/qp_parse.md 并提交（feat/fix 前缀 commit）。
```

---

## 任务 2（P1）——Android 真机全链路验证

```
项目：E:\ssy_proj\ChineseChessUltra（main 分支）。前置：Android 工具链已修复、
模拟器冒烟已通过（见 docs/qp_parse.md）。本任务：Android 真机上完成全链路验证。

准备：
1. 真机开启开发者模式 + USB 调试，`adb devices` 确认；或无线配对
   `adb pair <ip:port>`。
2. 使用任务 1 构建的 app-release.apk（`flutter build apk --release` 重新构建亦可）。

验证清单（逐项记录）：
a) adb install -r 安装并启动；
b) 首启进入棋谱库页：确认显示的语料路径为真机上的
   /storage/emulated/0/Android/data/<实际包名>/files/corpus
   （用 adb shell pm dump 或 `adb shell ls` 核实）；
c) 点"下载棋谱库"：真实网络下载 45.8MB 语料包 → 解压 → 自动重载分类；
   分别在 Wi-Fi 与移动数据下各试一次（弱网可开飞行模式中途打断，验证失败
   提示友好、无残留损坏目录）；
d) adb shell 确认语料文件落位、目录结构与 qp-corpus 仓库一致（残局/适情雅趣等
   中文子目录正常）；
e) 残局演示 + 始盘人机对战全流程（执红、执黑各一局，执黑时 AI 红方先行）；
f) file_picker 导入棋谱：从手机存储选一个 .xqf/.pgn 导入演示（SAF 路径验证）；
g) 卸载应用 → adb 确认 Android/data/<包名>/ 目录随之清除（应用专属目录语义）；
h) 重新安装 → 重复下载流程，确认全链路可重复。

约束与验收：问题先诊断后修复（经确认）；结果（含机型/Android 版本）写入
docs/qp_parse.md 并提交；不推送远程。
```

---

## 任务 3（P2）——GitHub Actions 三平台构建矩阵

```
项目：E:\ssy_proj\ChineseChessUltra（main 分支，远程 origin）。本任务：建立
GitHub Actions 三平台（windows/linux/macos）构建矩阵，跑全量测试（含真实语料）
并上传三平台构建产物。

背景事实：
- 语料仓库 jxsword/qp-corpus（**公开**）与主仓库同账号；Release v1 附件
  qp-corpus.zip 已验证。CI 语料获取方式：actions/checkout 二次检出
  （repository: jxsword/qp-corpus, path: corpus, 公开仓库免 token）到仓库根的
  corpus/ 目录——测试用例对 corpus 的存在性有 skip 守卫，检出后真实语料用例
  自动启用（全量 108 项，Windows 本地全绿）。
- 项目当前只有 android/、windows/ 平台目录；flutter 版本 3.44.2 stable。
- 解析器/语料读取用相对路径 corpus/...，flutter test 的 CWD 是仓库根，
  Linux runner 上语义一致。
- 本机 GH_TOKEN 有效（gh 已登录 jxsword）；已知 GCM 不支持 socks5 系统代理，
  如推送遇阻用
  git -c credential.helper= -c 'credential.https://github.com.helper=!gh auth git-credential' push。

执行步骤：
1. 本地生成平台目录并提交：`flutter create --platforms=linux,macos .`（检查
   生成的 linux/ macos/ 无破坏性变更，正常提交）；macos/Runner 的
   DebugProfile.entitlements 与 ReleaseEntitlements.entitlements 确认包含
   com.apple.security.files.user-selected.read-only（file_picker 需要，
   缺则补上）。
2. 编写 .github/workflows/ci.yml：
   - 触发：push 到 main + 手动 workflow_dispatch；
   - matrix: os = [windows-latest, ubuntu-latest, macos-latest]；
   - 步骤：checkout 主仓库 → checkout jxsword/qp-corpus 到 corpus/ →
     setup-java（Android 构建需要）→ subosito/flutter-action@v2
     （flutter-version: 3.44.2, channel: stable）→ flutter pub get →
     flutter test（真实语料用例在此执行）→ 按 OS 构建产物：
     * windows: flutter build windows + flutter build apk --release（windows
       runner 可同时出 Android 包）
     * linux: flutter build linux --release
     * macos: flutter build macos --release --no-codesign
   - 上传 artifacts（actions/upload-artifact@v4，按 OS 命名：apk /
     windows-zip / linux-bundle / macos-app）；
   - 加超时（macos 40min、其他 25min）与 pub 缓存。
3. 提交 workflow 与平台目录前先展示文件内容给用户确认；提交并推送 main。
4. 观察 Actions 运行结果：失败则读日志修复迭代，直到三平台全绿。
5. 下载 artifacts 抽验：APK 可安装性（由用户在设备侧复核）、bundle 目录完整。

验收标准：三平台 CI 全绿；artifacts 齐全可下载；全量测试含真实语料用例
（确认日志中语料测试未 skip——如 run 日志能看到 corpus 相关用例执行）。
约束：不提交 token 字面量（公开仓库 CI 无需任何 secret）；每次推送前先本地
flutter test + analyze 确认；过程与结论写入 docs/qp_parse.md。
```

---

## 不在本轮范围
- 残局通关持久化（数据库记录闯关进度）、棋盘翻转（执黑视角）——如需要另行规划。
