# Windows / Android 平台代码全面 Code Review 报告

- 日期：2026-10-01
- 范围：lib/ 共用核心逻辑（语料下载/路径/解析器/棋谱浏览/棋盘对弈）+ android/ + windows/ 平台配置与宿主代码
- 性质：**只审查不修码**。所有"建议修法"均标注对 Windows 端已验证行为的影响。
- 审查方法：逐文件人工审读 + 恶意 zip 实证测试（构造 `../`、反斜杠、盘符、绝对路径、UNC、符号链接、同名冲突、Windows 保留名条目，对 `CorpusDownloader.extractZip` 实际跑通，探针测试已删除、工作区已还原干净）。

## 总体结论

- **zip-slip 防护经实证有效**：词法校验（`..` 段 / 盘符段 / 绝对路径 / 反斜杠归一 / 符号链接拒绝）对全部 6 类穿越向量均拦截成功，未发生目录逃逸。
- **没有发现可远程利用的 P0 级漏洞**。不可信输入面（zip、XQF/PGN）的解析器边界处理总体扎实。
- 存在 **2 个 P0 观察级问题**（不丢数据但可致功能完全不可用/ANR）：全局输入锁泄漏、解压全量同步解压在 UI isolate。
- 规则层发现 1 处中国象棋规则错误：**困毙被判为和棋**（应为判负）。
- Android 平台配置整体干净（权限最小化、无 cleartext）；主要遗留是 release 用 debug 签名。
- Windows runner 为标准 Flutter 模板，无自定义攻击面。

---

## 一、分级发现清单

### P0（可被利用 / 崩溃丢数据级）

#### P0-1 全局棋盘输入锁泄漏：AI 思考中退出页面后，棋盘永久不可点击

- 位置：
  - `lib/features/board/view/human_vs_ai_page.dart:440`（早退分支未解锁）
  - `lib/features/board/view/ai_vs_ai_page.dart:45-50`（dispose 未解锁）
  - 锁本体：`lib/features/board/viewmodel/board_vm.dart:249-250`（`lockInput/unlockInput` 是全局 `boardViewModelProvider` 上的字段）
- 证据：
  ```dart
  // human_vs_ai_page.dart:440 —— mounted 为 false 或代数过期时直接 return
  if (!mounted || seq != _gameSeq) return; // 页面已离开或对局已重开/悔棋
  setState(() => _isAiThinking = false);
  viewModel.unlockInput();
  ```
  ```dart
  // ai_vs_ai_page.dart:45-50
  @override
  void dispose() {
    _seq++; // 作废仍在计算中的 AI 应手
    _nextMoveTimer?.cancel();
    super.dispose();          // ← 没有 unlockInput()
  }
  ```
- 影响场景：人机对战（或机器对战）中 AI 思考时按返回键 → `_triggerAiMove` 在 `!mounted` 处早退，`_inputLocked` 永远为 true。`_inputLocked` 挂在**全局** `boardViewModelProvider` 上，而双人对弈、再次进入人机对战都不会调用 `newGame()`（见 P1-2），`BoardViewModel.onTap` 第一行 `if (_inputLocked || state.isFinished) return;` 直接吞掉所有点击 → 棋盘彻底冻结，只能重启应用。
- 建议修法：页面 `dispose()` 中 `_gameSeq++; unlockInput()`；或在 `_triggerAiMove` 的早退分支统一走 `unlockInput()`。对 Windows 端影响：仅修复泄漏路径，正常对局行为不变（`newGame/newGameFromFen` 本来就会复位锁），无行为回退风险。

#### P0-2 语料解压在 UI isolate 全量同步解压，Android 有 ANR / OOM 风险

- 位置：`lib/features/puzzle/model/corpus_downloader.dart:108-110`
  ```dart
  static int extractZip(File zipFile, Directory targetDir) {
    final Uint8List bytes = zipFile.readAsBytesSync();   // 45.8MB
    final archive = ZipDecoder().decodeBytes(bytes);     // 解压后约 245MB，全部驻留内存
  ```
  调用链 `corpus_browser_page.dart:216` → `downloadAndExtract` → `extractZip` 全程在主 isolate。
- 影响场景：Android 上 245MB 的解压在 UI 线程执行数秒~十几秒 → ANR（用户可感知冻结，超 5 秒系统弹"应用无响应"）；同时峰值内存 ≈ zip 45.8MB + 解压后 245MB + Dart 堆放大，低内存设备可能 OOM 崩溃。Windows 桌面无 heap 上限，表现为短暂卡顿。
- 建议修法：`extractZip` 移入 `Isolate.run`（条目逐个流式解码，用 `InputFileStream`/`decodeStream` 避免 `readAsBytesSync` 整读），或至少逐条目 `entry.content` 惰性取内容。对 Windows 端影响：纯性能优化，功能结果一致；Windows 端当前"解压完成日志"语义不变。

---

### P1（功能缺陷）

#### P1-1 困毙被判为和棋（中国象棋规则应为判负）

- 位置：`lib/features/board/viewmodel/board_vm.dart:93-98`
  ```dart
  if (_board.isCheckmate(turn)) {
    result = turn.isRed ? GameResult.blackWins : GameResult.redWins;
  } else if (_board.isStalemate(turn)) {
    result = GameResult.draw;   // ← 困毙（无子可动且未被将军）应判困毙方负
  }
  ```
- 证据：`board.dart:196-199` 中 `isStalemate(side)` 明确是"未被将军但无任何合法走法"。中国象棋规则（同国际象棋不同）：**无子可动即判负**，不存在"逼和"。
- 影响场景：人机/机器/双人任何模式走到一方无子可动 → 显示"对局结束：和棋"，胜负判定错误。Windows 端同样存在此问题（属共用逻辑的既有错误，非本次回归）。
- 建议修法：`isStalemate` 分支改为 `result = turn.isRed ? blackWins : redWins`。注意 `ChessAi` 引擎（ai_engine.dart:176-179）已按"困毙判负"计分（`-mateScore + ply`），UI 修正后与引擎一致。对 Windows 端影响：改变了"困毙"终局的显示结果——这是纠错而非回归；常规对局不受影响。

#### P1-2 残局对局终局后，全局棋盘状态残留（已知 bug 2，确认根因并扩展）

- 位置：`lib/features/board/view/human_vs_ai_page.dart:68-83`
  ```dart
  void initState() {
    super.initState();
    final initialFen = widget.initialFen;
    if (initialFen != null) { ... newGameFromFen(initialFen); ... }
  }
  ```
- 根因（确认）：`boardViewModelProvider` 是应用级全局单例，残局模式通过 `newGameFromFen` 写入了残局局面与终局 `result`；从残局详情页返回主页再进"人机对战"时 `initialFen == null`，`initState` **不做任何重置**，于是棋盘残留残局局面、"黑方胜！"横幅（`side_panel.dart` 的 `ResultBanner` 依赖 `state.result`）继续显示。
- 扩展影响（本次新发现）：与 P0-1 叠加后更糟——若退出残局时 AI 正在思考，输入锁同样残留，此时进"人机对战"是"残局局面 + 胜负横幅 + 棋盘点击全部无效"的完全冻结态。另外残局详情页（`puzzle_detail_page.dart:111`）每次进对局都会 `newGameFromFen`，掩盖了该 bug 在残局路径上的表现。
- 建议修法：`initState` 中 `initialFen == null` 时也调用 `viewModel.newGame()`（或 `restore` 逻辑）。对 Windows 端影响：进入无参"人机对战"必定是标准开局——与用户预期一致，不改变任何已验证流程。

#### P1-3 "保存棋局"假成功：人机/双人页面的保存按钮不保存任何数据

- 位置：
  - `lib/features/board/view/human_vs_ai_page.dart:402-410`
  - `lib/app/app.dart:426-431`（双人对弈页）
    ```dart
    void _saveGame() {
      // TODO: 实现保存棋局功能
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('棋局已保存'), backgroundColor: Colors.green));
    }
    ```
- 关联事实：真正的保存/恢复链路（sqlite + `BoardLifecycleNotifier`，`lib/features/board/view/board_page.dart:150-229`）是**死代码**——`BoardPage` 在整个 lib/ 中没有任何实例化点（grep 证据仅 `board_page.dart:12` 自身定义）。即 sqlite 存储层（game_dao/repository）当前在 UI 上完全不可达。
- 影响场景：用户点"保存棋局"看到绿色"棋局已保存"，实际什么都没发生——这是误导性 UI，比没有按钮更糟。
- 建议修法（三选一）：① 最小改动：把 SnackBar 改为"保存功能开发中"；② 接通 `BoardLifecycleNotifier.saveNow()`（注意其 `onStarted` 恢复逻辑与人机模式语义需适配）；③ 把保存按钮与 `share_plus` 一起做导出 PGN。对 Windows 端影响：①③ 无行为风险；② 需要处理全局 board VM 与保存/恢复的耦合（进入 BoardPage 才恢复的旧语义），建议先 ① 再规划 ②。

#### P1-4 语料下载无任何超时 + 进度框不可关闭：网络卡死时 UI 永久锁死

- 位置：`lib/features/puzzle/model/corpus_downloader.dart:58,64-67,87-91`
  ```dart
  final client = HttpClient();                       // 未设 connectionTimeout
  final request = await client.getUrl(...)           // 未 await .timeout
  await for (final chunk in response) { ... }        // 流中途停滞无超时
  ```
  `lib/features/puzzle/view/corpus_browser_page.dart:198-214`：`showDialog(barrierDismissible: false)` 且无返回按钮。
- 影响场景：`releases/latest/download/...` 需要代理环境（已知事实），直连时 TCP 连接或响应流中途停滞 → `await` 永不完成 → 非关闭式进度框永远挂着，只能杀进程。国内用户首启即触发的概率不低。
- 建议修法：`HttpClient()..connectionTimeout = 15s`；对流包 `response.timeout(...)` 或按块间超时兜底；对话框加"取消"按钮（通过 generation flag 使 `downloadAndExtract` 可取消）。对 Windows 端影响：只增加失败路径，成功路径不变。

#### P1-5 corpus 目录存在但为空 → 棋谱库死胡同（已知 bug 1，确认根因）

- 位置：`lib/features/puzzle/viewmodel/corpus_browser_vm.dart:160-171`
  ```dart
  if (!repo.exists) { ...展示下载引导...; return; }
  final categories = repo.scanCategories();   // 空目录 → []
  state = state.copyWith(corpusExists: true, categories: categories);
  ```
  页面侧 `corpus_browser_page.dart:54-60` 仅在 `!state.corpusExists` 时渲染 `_CorpusMissingGuide`。
- 根因（确认）：`corpusExists` 的语义是"目录存在"而非"语料可用"。下载失败残留的空目录（来源见 P1-6）使 `exists == true`，UI 进入"请选择分类"且分类条为空的死胡同，下载引导永不再出现。
- 建议修法：`scanCategories()` 结果为空时视同缺失（`corpusExists: false` + 展示引导），或在缺失引导中增加"目录存在但为空"分支。对 Windows 端影响：legacy 联接目录（开发期）非空，正常路径不受影响；只有空语料目录这一异常态的 UI 会变化。

#### P1-6 下载/解压失败残留半成品目录（已知 bug 3，确认根因 + 连带分析）

- 位置与链路：
  1. `corpus_downloader.dart:36` `await targetDir.create(recursive: true)` —— **下载开始前**就创建目标目录，任何后续失败都留下空目录；
  2. 实证测试：解压中途抛异常（同名"先文件后目录"冲突 `PathExistsException`、Windows 保留名 `NUL`/`CON` `PathNotFoundException`，见 §三）时，`extractZip` 直接向上抛，**已解压的文件全部残留**；磁盘写满同理（`writeAsBytesSync` 抛出）。`finally` 只删临时 zip（corpus_downloader.dart:42-47），不回收半成品；
  3. 失败仅 `corpus_browser_page.dart:237-243` SnackBar 一闪 → 空目录/半成品目录触发 P1-5。
- 连带结论：**问题 3 应与问题 1 一并修**。单修 1（空目录判缺失）会把"半成品目录"从死胡同变成重复下载引导，但残留文件会在再次解压时与新 zip 混合（同名覆盖、旧垃圾保留），仍不干净。建议组合：① 下载前不在目标目录创建（临时 zip 移到系统临时目录即可，见 P2-3）；② 解压改为"解压到 `targetDir.tmp-<ts>` 临时目录，全部成功后再原子 rename 替换目标目录，失败则整体删除临时目录"；③ 失败提示用常驻 Dialog/页面态而非 SnackBar。
- 对 Windows 端影响：Windows 默认目录 `Documents/ChineseChessUltra/corpus` 由下载器创建，改后失败时不再留下空壳目录，成功路径无变化；legacy 联接路径不受影响（不重建已存在目录）。

---

### P2（健壮性 / 体验 / 纵深防御）

#### P2-1 SSRF 校验存在解析绕过面（当前不可利用，纵深防御修复）

- 位置：`lib/features/puzzle/model/corpus_paths.dart:41-88`
- 分析（逐项核对）：
  - 十进制/十六进制整数 IP（`2130706433`、`0x7f000001`）：不匹配 `^(\d{1,3}\.){3}\d{1,3}$`，**放行**；
  - IPv4-mapped IPv6 环回 `::ffff:127.0.0.1`：`h == '::1'` 不命中、`startsWith('fe8'/'fc'/'fd')` 不命中，**放行**；
  - 八进制分段 `0177.0.0.1`：`int.parse` 按十进制解析 177，172 类私有段判断失真，**可能放行**；
  - DNS 重绑定：校验发生在解析前（词法校验 host），连接时才做 DNS 解析，无 pinning，**理论可绕过**。
- 缓解事实：`isDownloadUrlAllowed` 的唯一调用点传入的是编译期常量 `CorpusPaths.downloadUrl`（github.com），用户无法注入 URL → 当前**不可利用**。但该方法作为"公共校验器"存在，未来一旦接通用户自定义源即成为漏洞。
- 建议修法：校验时先 `Uri.parse` → `InternetAddress.lookup(host)` 逐个结果 IP 判段（把校验挪到"解析后、连接前"仍留 TOCTOU 窗口，彻底方案是自定义 `HttpClientConnection` 校验对端 IP）；或至少补 `::ffff:0:0/96`、十进制/十六进制、八进制形式的拒绝。对 Windows 端影响：无（常量 URL 校验结果不变）。

#### P2-2 下载内容无完整性校验（供应链投毒面）

- 位置：`corpus_downloader.dart:77-98`（只校验 HTTP 200 与逐跳 https），无哈希/大小/魔数校验。
- 影响：GitHub Release 被换包（账号被盗/Release 被篡改）即直接解压任意文件进语料目录——虽不执行代码，但可投毒残局库（XQF/PGN 内容可携带误导性棋谱、标题注入 UI）；配合 P2-3 的 zip 炸弹可撑爆磁盘。
- 建议修法：在 `CorpusPaths` 中固化期望的 SHA-256（随版本更新）或至少校验 zip 魔数 `PK\x03\x04` 与期望大小区间；zip 条目数/总解压大小上限（防炸弹）。对 Windows 端影响：无。

#### P2-3 临时 zip 落在 `targetDir.parent`

- 位置：`corpus_downloader.dart:81-83`
  ```dart
  final tempFile = File('${targetDir.parent.path}...corpus-download-<ms>.zip');
  ```
- 影响：Android 上落在应用外置 files/（`Android/data/<包名>/files/`，同区还可能被用户经电脑/文件管理器看到）；桌面端落在 `Documents/ChineseChessUltra/`（用户目录），写失败风险（如用户自选目录的父目录只读，见 P2-4）；同毫秒并发下载理论上同名互踩。
- 建议修法：用 `Directory.systemTemp`（Android 上为应用 cache 目录，权限内且自动可清理）。对 Windows 端影响：无（临时文件位置用户不可见为更优）。

#### P2-4 用户自定义语料目录接受任意路径，无防护性检查

- 位置：`corpus_paths.dart:92-94` + `corpus_browser_vm.dart:184-188`
- 影响：桌面端 `pickCustomDirectory` 可选 `C:\` 之类巨型目录 → `scanCategories`/`listXqfEntries` 用 `listSync(recursive: true, followLinks: true)` 全盘递归（含符号链接环，Windows 目录联接也会被跟进）→ 长时间无响应；语料文件本身即该目录下任意 XQF/PGN（解析面扩大但解析器已设防）。另 `followLinks: true` 在含环的目录树上是死循环风险（Windows 上目录联接 + followLinks 组合尤其危险）。
- 建议修法：递归扫描改 `followLinks: false`（Windows 联接目录除外则显式特判），并给扫描加深度/条目上限；自选目录时提示影响。对 Windows 端影响：legacy 联接 `corpus → E:\ssy_proj\qp` 依赖 `followLinks` 才能扫描——**此条修改需保留 legacy 目录这一特例**，否则破坏 Windows 开发期行为。

#### P2-5 PGN 流式扫描对超长行内存放大

- 位置：`pgn_parser.dart:479-495`（`pending.addAll(chunk.sublist(segStart))` 无上限）
- 影响：恶意/畸形 `.pgns`（单行 100MB、无换行）→ `pending` 增长到全文件大小，且跨 chunk 反复拷贝 O(n²)；导入路径（`puzzle_list_page.dart:254-318`）允许用户选任意本地文件 → 内存暴涨。
- 建议修法：`pending` 超过阈值（如 8MB）时把该行按"非标签行"直接计为 moves 行（不必保真内容），或截断。对 Windows 端影响：正常语料（换行规整）不受影响。

#### P2-6 PGN 变着剥离嵌套括号为 O(n²)

- 位置：`pgn_parser.dart:202-207`（`while(true) replaceAll(_innermostVarPattern)` 每轮全文扫描替换）
- 影响：深度嵌套恶意 PGN（如 10k 层括号）单局解析 CPU 放大；在 `parsePgnGameAt` 的 isolate 内执行 → UI 不卡但该局"正在解析棋局…" SnackBar（1 分钟超时）期间白等。
- 建议修法：单遍栈式剥括号。对 Windows 端影响：无。

#### P2-7 Windows 保留设备名与尾随点/空格文件名未过滤（实证）

- 位置：`corpus_downloader.dart:124-139`（segments 只拒绝 `:` 与 `.`）
- 实证：条目名 `NUL`/`CON` → `writeAsBytesSync` 抛 `PathNotFoundException (errno 161)`，中断整个解压（残废目录）；`conflict` 文件后再来 `conflict/inner.txt` 目录 → `PathExistsException` 同样中断。
- 建议修法：段名命中 `CON|PRN|AUX|NUL|COM1-9|LPT1-9`（不区分大小写、含 `CON.txt` 形式）与尾随 `.`/空格时跳过；文件/目录冲突异常 catch 后跳过该条目并计数，不中断整体。对 Windows 端影响：仅增强，正常语料无此类名。

#### P2-8 release 包使用 debug 签名

- 位置：`android/app/build.gradle.kts:31-34`（`signingConfig = signingConfigs.getByName("debug")`）
- 影响：debug keystore 是公开模板产物，任何人都可用同 key 签出同包名 APK；用户侧"覆盖安装"需同签名，公开 key 意味着任何人都能构造可覆盖安装的仿冒包（需用户确认安装，但绕过了签名校验的意义）；也无法发布到应用商店。
- 建议修法：正式分发前生成私有 keystore 并走 key.properties 注入（不入库）。对 Windows 端影响：无。

#### P2-9 `share_plus` / `permission_handler` 为死依赖

- 位置：`pubspec.yaml:27,30`；grep 证据：lib/ 内零引用（分享按钮 `app.dart:433-440` 是 TODO 假提示）。
- 影响：Windows 端 generated_plugin_registrant 因此注册了 `PermissionHandlerWindowsPlugin`、`SharePlusWindowsPluginCApi`、`UrlLauncherWindows` 三个用不到的原生插件（`windows/flutter/generated_plugin_registrant.cc`），扩大无谓的原生面与安装体积。
- 建议修法：实现分享前从 pubspec 移除（或至少注释），重新 `flutter pub get`。对 Windows 端影响：减少插件注册项，已验证功能均不依赖它们，无回退风险。

---

### P3（建议 / 低危）

| # | 位置 | 问题 | 建议 |
|---|------|------|------|
| P3-1 | `lib/main.dart` + 全项目 | `Logger.root` 从未配置，所有 `Logger('...').warning/info` **静默丢弃**——诊断信息全无（副作用：也不会打印语料路径，隐私面反而干净） | main 里配置 `Logger.root.onRecord` 输出到 debugPrint；release 控制在 INFO 以下 |
| P3-2 | `android/app/src/main/AndroidManifest.xml` | `android:allowBackup` 未设置，默认 true：SharedPreferences（语料路径）与 sqlite 对局记录可被 adb backup 提取。数据不敏感，属加固项 | 加 `android:allowBackup="false"` 或 fullBackupContent 规则 |
| P3-3 | `corpus_paths.dart:95-96` | legacy `Directory('corpus')` 是**相对路径**，依赖进程 CWD：`flutter run` 时是项目根（可用），双击 exe 启动时 CWD 是 exe 目录 → legacy 联接失效落到文档目录。行为不一致 | 以可执行文件位置或项目根锚定；或在命中 legacy 时打日志 |
| P3-4 | `corpus_downloader.dart:60` | 重定向逐跳校验已做（好），但 Location 相对解析 `Uri.parse(current).resolve(location)` 后 fragment/ userinfo 未清洗，纵深上可在日志中暴露 | 无紧迫性，保持现状可接受 |
| P3-5 | `board_vm.dart:158-160` | `restore()` 用 `Future.microtask` 延迟赋值 state，若期间 provider 重建会抛 unmounted 异常（当前该 Notifier 无依赖，实际风险低） | 改为同步赋值或 try-catch |
| P3-6 | `human_vs_ai_page.dart:88-96` | `ref.listen` 在 `if (widget.initialFen != null)` 条件内调用——widget 参数不可变所以当前安全，但是 Riverpod 反模式 | 移到 build 顶层，回调内自判 |
| P3-7 | `puzzle_vm.dart:138-145` | `puzzleViewModelProvider` 是应用级单例，离开演示页后 `Timer.periodic` 继续跑完整个残局（浪费电量） | 页面 dispose 时 `pauseDemo()`/`stopDemo()` |
| P3-8 | `corpus_browser_page.dart:350` | 引导按钮文案"约 150MB"与实际（zip 45.8MB / 解压 245MB）不符 | 修正文案 |
| P3-9 | `ai_engine.dart:435-437` 等两处 | `Isolate.run` 失败时退化为**主 isolate 同步计算**，高级别下 UI 冻结最长 5s | 直接报错即可，不必退化 |
| P3-10 | `xqf_parser.dart:130` | XQF 只取主线，变着分支（0x40 标志）未消费——功能取舍非缺陷；注解长度字段已做边界保护（`_readInt32` 越界返 0，行 357-363），无死循环（每轮至少消费 4 字节） | 保持现状；如需变着支持再扩展 |
| P3-11 | `android/build.gradle.kts` afterEvaluate bumpSdk | 对所有含 android 扩展的插件子项目统一抬 compileSdk——写法正确（先注册 afterEvaluate 再 `evaluationDependsOn(":app")`），只影响编译 SDK 声明、不改运行时行为 | 无需修改（构建期已知项，非问题） |
| P3-12 | `windows/runner/*` | 标准 Flutter 模板（COM 初始化、消息循环、插件注册、字体重载），无自定义攻击面；`GetCommandLineArguments` 有 `wcsnlen` 上界保护（CWE-126 已处理） | 无需修改 |

---

## 二、安全面覆盖矩阵（逐项结论）

| # | 安全面清单项 | 结论 | 依据 |
|---|-------------|------|------|
| 1 | 网络 zip（文件名+内容） | **安全（文件名穿越）/ 有风险（内容与体积）** | zip-slip 实证全拦截（§三）；但无哈希校验（P2-2）、无 zip 炸弹上限、解压中断残留（P1-6）、保留名中断（P2-7） |
| 2 | 本地语料文件（XQF/PGN） | **安全** | XQF：魔数/长度前缀/32 字节布局/走子循环均有边界保护（xqf_parser.dart:72,169-178,300-345,357-363），每轮循环至少消费 4 字节无死循环，annoteLen 异常值只前跳不回跳；PGN：解析失败逐局跳过（pgn_parser.dart:76-84）、FEN 非法抛 FormatException 被上层捕获（puzzle_parser.dart:96-98）、`_validateAndDedupe` 重放校验截断非法着法。剩余风险仅 P2-5/P2-6 的资源放大 |
| 3 | 用户自定义语料目录 | **有风险（低）** | 接受任意路径 + `followLinks:true` 递归（P2-4）；只读不写，泄露面为零 |
| 4 | SharedPreferences 存的路径 | **安全** | 仅存 `corpus.userPath` 一个键（corpus_paths.dart:25），无敏感项；读取后仅用于目录解析 |
| 5 | zip-slip 实证 | **安全** | 6 类向量（`../`、`..\`、嵌套、盘符、绝对路径、UNC）+ 符号链接条目全部拦截，实测零逃逸（§三） |
| 6 | 解压目标逃逸（非词法） | **未覆盖（理论）** | 词法重组后不经过 `canonicalize`/真实路径断言；NTFS 短名（`PROGRA~1`）、8.3 名、ADS（已挡 `:`）未测。当前写入目标固定为应用自有目录，实际暴露小 |
| 7 | 保存棋局写路径可否操控 | **安全** | sqlite 走固定应用目录（game_dao），无用户可控文件名；且当前 UI 保存链路死代码（P1-3），无写路径暴露 |
| 8 | SSRF 校验绕过面 | **有风险（当前不可利用）** | P2-1：十进制/十六进制 IP、`::ffff:127.0.0.1`、DNS 重绑定均可绕过；但 URL 为编译期常量，无用户注入点 |
| 9 | 下载无签名/哈希的供应链 | **有风险** | P2-2：GitHub Release 换包即投毒语料库（不执行代码，可污染残局内容与磁盘） |
| 10 | AndroidManifest cleartext | **安全** | 未设置 `usesCleartextTraffic`，targetSdk 28+ 默认禁止明文；下载 URL 本身 https |
| 11 | 隐私：SharedPreferences/日志/外部存储 | **安全** | 无敏感项；Logger 未配置不输出任何路径（P3-1）；corpus 在 `Android/data/<包名>/files/corpus`，Android 11+ 其他应用不可读（文件管理器经 SAF 例外，含用户主动行为） |
| 12 | 依赖 CVE | **基本安全（有一项历史家族风险已缓解）** | archive 3.6.1：Dart archive 包历史上报过 zip-slip 类问题（Ostorlab 研究），本项目自实现解压校验且实测拦截；file_picker 8.3.7 / permission_handler 11.4.0 / share_plus 12.0.2 / sqlite3 2.x 均为较新版本，未发现本项目用法触及的已知 CVE；后两者目前是死依赖（P2-9） |

---

## 三、zip-slip 实证测试记录

对 `CorpusDownloader.extractZip`（corpus_downloader.dart:108-143）构造恶意 zip 实测（Windows，archive 3.6.1，`flutter test` 一次性探针，测后已删除）：

| 恶意条目名 | 预期行为 | 实测结果 |
|-----------|---------|---------|
| `../escape.txt` | 拒绝（含 `..` 段） | ✅ 拦截，无逃逸文件 |
| `..\escape.txt` | 归一为 `/` 后拒绝 | ✅ 拦截 |
| `a/../../escape.txt` | 拒绝 | ✅ 拦截 |
| `C:\escape.txt` | 拒绝（盘符段含 `:`） | ✅ 拦截 |
| `/abs.txt` | 拒绝（绝对路径） | ✅ 拦截 |
| `\\evil\share\f.txt`（UNC） | 归一后 `//evil/...` 以 `/` 开头拒绝 | ✅ 拦截 |
| 符号链接条目（mode 0xA1FF + nameOfLinkedFile） | 拒绝 | ✅ 拦截 |
| `conflict` 文件 + `conflict/inner.txt` 目录 | — | ❌ `PathExistsException` 中断整个解压，已解压条目残留 |
| `CON` / `NUL` 保留名 | — | ❌ `PathNotFoundException (errno 161)` 中断解压 |

结论：穿越防护**真实有效**；异常中断 + 残留是真实缺陷（已列 P1-6 / P2-7）。

---

## 四、已知 3 个 bug 的根因确认

| 已知 bug | 根因确认 | 报告条目 |
|---------|---------|---------|
| 1. corpus 目录存在但为空 → "请选择分类"死胡同 | **确认**。`corpus_browser_vm.dart:160` 只判 `repo.exists`（目录存在性），空目录 `scanCategories()` 返回 `[]` 后仍置 `corpusExists: true`，页面侧（corpus_browser_page.dart:54）只在 `!corpusExists` 时显示下载引导 | P1-5 |
| 2. 残局终局后进"人机对战"残留残局局面与"黑方胜！"横幅 | **确认**。全局 `boardViewModelProvider` 状态跨页面存活；`human_vs_ai_page.dart:68-83` 的 `initState` 仅在 `initialFen != null` 时 `newGameFromFen`，无参进入不重置。横幅来自 `side_panel.dart` 的 `ResultBanner`（读 `state.result`） | P1-2（并叠加 P0-1 锁泄漏可致棋盘冻结） |
| 3. 下载失败仅 SnackBar 一闪 + 残留空目录 | **确认并扩展**。`corpus_downloader.dart:36` 在下载前就 `targetDir.create(recursive: true)`；失败路径（网络异常 / 解压中断，后者含实证的同名冲突与保留名）残留空目录或半成品；失败仅 `corpus_browser_page.dart:237-243` SnackBar。**应与问题 1 一并修**：单修 1 只会把死胡同变重复引导，半成品混合残留仍在；建议组合"临时目录解压 + 成功后原子替换 + 失败清理 + 常驻失败提示" | P1-6（连带 P0-2、P1-4、P2-7） |

---

## 五、平台侧结论

### Android
- Manifest 仅 `INTERNET` 权限，最小化 ✅；`MainActivity` 为空壳 FlutterActivity ✅；无 exported 组件风险（仅 LAUNCHER activity）。
- `allowBackup` 默认 true（P3-2）；`debuggable` release 构建默认 false ✅；cleartext 默认禁止 ✅。
- release 签名用 debug keystore（P2-8）——发布前必须换。
- 未启用 R8 混淆/资源收缩（Flutter 模板默认），单机应用影响有限，分发前可选加固。
- gradle `afterEvaluate` compileSdk 抬升写法经审读无副作用（P3-11）；`kotlin.incremental=false` 为已知有意保留。

### Windows
- runner（main.cpp / flutter_window.cpp / win32_window.cpp / utils.cpp）为标准模板：消息循环、插件注册、`WM_FONTCHANGE` 重载字体均常规；命令行参数有长度上界保护；无自定义文件对话框边界问题（file_picker 走标准 IFileDialog）。
- `data/` 资源目录随 exe 分发，无敏感内容。
- 唯一注意点：P3-3（legacy corpus 相对路径依赖 CWD），建议后续锚定路径。

---

## 六、修复记录（2026-10-01）

按本报告修复范围执行，共 4 个本地 commit（未推送）。验证基线：`flutter analyze`
无新增 warning（且 info 总数低于审查前基线 128 条）；`flutter test` 123 项全过
（含本轮新增 20 项回归测试）；Windows release/debug 构建通过；Android release
APK 构建并在 Pixel_7_API34 模拟器完成交互冒烟。

### 第一批（commit `5c7c3de`）

| 条目 | 修复 | 验证 |
|------|------|------|
| P0-1 全局输入锁泄漏 | `human_vs_ai_page.dart`：`_triggerAiMove` 早退分支无条件 `unlockInput()`；`dispose()` 兜底 `_gameSeq++ + unlockInput()`。`ai_vs_ai_page.dart`：`dispose()` 仅运行态（非暂停）解锁 | 新增 widget 回归测试：注入锁状态→退出页面→棋盘可选中；**灵敏度已实证**（临时还原旧代码时测试失败，恢复修复后通过）。测试环境 `Isolate.run` 不可用走同步退化，无法制造真实思考窗口，dispose 兜底通过注入锁状态覆盖；早退分支解锁为无条件调用、代码路径直观 |
| P0-2 解压阻塞 UI isolate | `corpus_downloader.dart`：`extractZip` 改 `InputFileStream` 流式打开 + 条目内容按需惰性解码（不再 `readAsBytesSync` 全量读），整体经 `Isolate.run` 在后台 isolate 执行；zip-slip 词法校验逐字节保留 | 恢复报告 §三全部 zip-slip 探针为永久回归测试（`..`、反斜杠、盘符、绝对路径、UNC、符号链接全拦截）；Android 冒烟全程解压阶段 UI 无卡顿 |

### 第二批（commit `4533748`）

| 条目 | 修复 | 验证 |
|------|------|------|
| P1-1 困毙判负 | `board_vm.dart` `isStalemate` 分支改为判困毙方负（与引擎 -mateScore 语义对齐） | 新增双向困毙 FEN 回归测试（黑困毙→红胜、红困毙→黑胜），均非 draw |
| P1-2 残局状态残留 | `human_vs_ai_page.dart` `initState`：`initialFen == null` 时 postFrame 调用 `newGame()` 重置全局棋盘 | 新增 widget 测试：残局对局→无参进入人机对战→FEN 恢复标准开局、无胜负横幅；Android/Windows 冒烟复验 |
| P1-3 保存假成功 | `human_vs_ai_page.dart` + `app.dart` 的 `_saveGame` SnackBar 改为"保存功能开发中"（sqlite 接入为新功能，本次不做） | 代码审查 + 全平台构建 |
| P1-4 下载超时/不可取消 | `HttpClient.connectionTimeout = 15s`；响应流 30s 块间超时；`downloadAndExtract` 增加 `isCancelled` 轮询（各阶段间），抛 `CorpusDownloadCancelled`；进度框加"取消"按钮并实时刷新进度 | Android 模拟器实测：断网→DNS 失败即弹常驻失败对话框；下载中点"取消"→"已取消下载"，files/ 与 cache 零残留 |
| P1-5 空目录死胡同 | `corpus_browser_vm.load()`：`scanCategories()` 为空时视同缺失（corpusExists=false 回下载引导） | 新增 VM 测试：空目录/不存在→false，有分类→true 并自动选中 |
| P1-6 半成品残留 | 临时 zip 移至 `Directory.systemTemp`；下载前不再创建目标目录；解压先落 `corpus.tmp-<ts>` 临时目录（与目标同 parent，rename 不跨设备），全部成功后删旧目录并 rename 替换，任何失败整体删除临时目录；失败提示由 SnackBar 改为常驻对话框（含原因与"重试"） | 新增 `extractZipAtomic` 测试：失败时临时目录清理且旧目录完好、成功后原子替换；Android 实测断网失败后 `files/` 目录为空 |
| P2-7 保留名/条目异常 | 条目名命中 Windows 保留名（CON/PRN/AUX/NUL/COM1-9/LPT1-9，不区分大小写、含扩展名形式）或尾随 `.`/空格→跳过；单条目 `FileSystemException` catch 后跳过计数，不中断整体；完成提示说明跳过数 | 新增测试：7 类保留名/尾随点空格条目全跳过且正常条目落地；同名"先文件后目录"冲突不中断 |
| P3-8 下载按钮文案 | "约 150MB"→"约 45MB，解压后约 245MB" | Android 冒烟截图确认 |

### 第三批（commit `dbe6606` + `63fdb7a`）

| 条目 | 修复 | 验证 |
|------|------|------|
| P2-1 SSRF 加固 | `corpus_paths.dart`：`::ffff:0:0/96` 还原 v4 判段（点分十进制与两组十六进制）；十进制/十六进制整数 IP 拒绝；八进制分段（前导 0）拒绝；**修正 `0177.0.0.1` 因 4 位数字段落空 `\d{1,3}` 被放行的漏洞**（模式放宽为 `\d+` + 数值范围校验）；形式存疑的 mapped 段一律拒绝。常量 URL 校验结果不变 | 新增 9 项绕过形式回归测试（mapped 环回/私有、整数 IP、超范围整数、八进制；mapped 公网地址仍放行） |
| P2-2 下载完整性 | zip 魔数 `PK\x03\x04` + 大小区间 [1MB, 512MB] 校验；SHA-256 留 TODO（语料发布流程未定） | 代码审查；`extractZipAtomic` 失败路径测试覆盖损坏输入 |
| P2-5 超长行防护 | `pgn_parser.dart` `scanGameOffsets`：单行 pending 超 8MB 按"非标签行"（moves 行）处理并丢弃剩余内容，行边界语义保持正确 | 新增测试：9MB 无换行畸形行 + 正常局→索引正确、不累积 |
| P2-9 死依赖 | pubspec 移除 `share_plus`、`permission_handler`；`flutter pub get` 后 `windows/flutter/generated_plugin_registrant.cc` 仅剩 sqlite3 注册 | 构建通过 + 生成文件核对 |
| P3-1 Logger 配置 | `main.dart` 配置 `Logger.root.onRecord` → debugPrint（release 限 INFO 以上） | Windows 启动日志可见 |

### 平台冒烟结果

- **Windows**：`flutter build windows`（debug）通过；应用启动渲染正常（主页截图验证）；legacy `corpus` 联接真实扫描通过（5 分类、2 个 PGN 大文件识别）。交互式 GUI 冒烟受宿主环境窗口焦点限制无法自动化，相应断言由页面级 widget 测试覆盖（人机开局/AI 应手/悔棋/新游戏/残局流程/锁释放/状态重置，均为既有 + 新增测试）。
- **Android（Pixel_7_API34，经宿主代理）**：release APK 构建安装启动正常；首启棋谱库下载引导与 P3-8 文案正确；断网→常驻失败对话框（含 SocketException 原因、重试/关闭）且**不残留空目录**（bug 1/3 修复验证）；下载中可取消（"已取消下载"，临时产物零残留）；完整下载解压成功后分类扫描正常；人机对战可正常落子对局。
- **未修项**（维持报告结论）：P1-3 sqlite 接入、P2-4（legacy 联接特例需单独设计）、P2-6、P2-8（待用户提供 keystore）、P2-3 之外的其余 P3；P3-3（legacy 相对路径 CWD 依赖）仍开放。

### 与报告建议修法的实现差异

1. **P1-6 原子替换对 legacy 联接目录的特例**：报告未提及。实现中若目标目录是目录联接（`FileSystemEntityType.link`），不做"删除+rename 替换"（避免递归删除语义风险与破坏开发期联接），退化为直接解压（旧行为）；常规目录走 staging 原子替换。已实证 Dart 的 `deleteSync(recursive: true)` 不穿透 Windows junction（删联接不删目标），但保守起见仍保留特例。
2. **P1-4 取消粒度**：取消标志在"各阶段间 + 下载流每个 chunk"轮询；解压（isolate 内）运行中不可中断，取消在其完成后的替换前生效——报告中未要求 isolate 内中断，可接受。
3. **P2-2 大小区间**：报告建议"期望大小区间"，实现取 [1MB, 512MB]（当前包 45.8MB，留足版本演进余量）；SHA-256 按指示留 TODO 未固化。
4. **extractZip 返回值**：由 `int` 改为 `({int extracted, int skipped})` 记录（承载 P2-7 跳过计数），`downloadAndExtract` 返回 `CorpusDownloadResult`——报告建议"完成提示中说明跳过条目"所需。
