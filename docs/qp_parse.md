# 棋谱解析与测试实施计划（qp 语料对接）

> 状态：**已完成（2026-10-01）**　|　制定日期：2026-10-01　|　本文档为实施依据与实施记录

## 目标

基于现有项目框架，实现 `.xqf` 与 `.pgn` 棋谱解析（当前 `lib/features/puzzle/model/parsers/` 下三个文件均为空壳桩）、配套测试、以及"本地棋谱库"浏览页（按类别/等级选择、点开演示）。棋谱语料在 `E:\ssy_proj\qp`，**不复制进项目**，用目录联接引用。

## 语料与访问方式

| 语料 | 格式 | 数量 | 位置 |
|------|------|------|------|
| 象棋谱大全 | XQF | 8,557 局 | `E:\ssy_proj\qp\XQF-象棋谱大全\`（顶层分类：全局/大师专集/残局/布局/比赛对局/近代国手名局/让子局/实战中局/未分类） |
| ChessQ 残局杀势 | XQF | 249 局 | `E:\ssy_proj\qp\ChessQ-gamebooks\gamebooks\` |
| 世象联大师对局 | PGN (ICCS) | 41,743 盘 | `E:\ssy_proj\qp\CGLemon-PGN\wxf\ICCS\WXF-41743games.pgns` |
| 东萍对局 | PGN (ICCS) | 99,771 盘 | `E:\ssy_proj\qp\CGLemon-PGN\dpxq\ICCS\dpxq-99813games.pgns` |

- **符号链接**：项目根执行 `cmd //c mklink //J corpus E:\ssy_proj\qp`（目录联接无需管理员权限）。代码/测试统一经 `corpus/...` 相对路径访问；语料位置写入 README 说明。`.gitignore` 添加 `corpus`（联接是本机调试设施，不入库）。
- **保存位置说明**：棋谱真实保存位置 = `E:\ssy_proj\qp`，PGN 在 `CGLemon-PGN` 的子目录下（wxf / dpxq）。

## 格式要点（已验证）

- XQF：魔数 = 前两字节 `XQ`（0x58 0x51），第 3 字节是**版本号** `0x0A–0x12`；版本 ≥ 12 有位置加密（KeyMask/KeyXY/KeyPiece/KeyStep 解密）；字符串为 GB18030。权威参考实现：`walker8088/cchess` 的 `src/cchess/io_xqf.py`（已实测可解析本语料，照搬算法）。
- PGN：标签对 + ICCS 走法（`H2-E2`，列 a-i、行 0-9，行 0=红底线）；`[FEN]` 标签为自定义起始局面；多局按空行分隔。
- 项目坐标约定：`Position(col 0-8, row 0-9)`，row 0 = 黑方底线；ICCS rank 0（红底线）→ row 9，即 `row = 9 - rank`（见 `PuzzleViewModel.parseIccs`）。

## 实现步骤

### 1. 依赖与基础设施（pubspec.yaml）
- 新增 `fast_gbk: ^1.0.0`（纯 Dart GBK 解码，XQF 元数据用）。
- 显式声明 `logging`（现有桩已 import，目前是传递依赖）。
- 建目录联接 `corpus` → `E:\ssy_proj\qp`，更新 `.gitignore`。

### 2. ICCS 工具（新建 `lib/features/puzzle/model/iccs.dart`）
- `iccsToPositions(String)`：复用 `PuzzleViewModel.parseIccs` 的坐标约定（file a-i→col 0-8，rank→row=9-rank），解析器与 VM 共用；VM 的静态方法改为委托此工具（行为不变，避免两处实现漂移）。
- `positionsToIccs(Position, Position)`：XQF 解析输出统一转小写 `h3e3` 形式（`ParsedPuzzle.moves` 现有约定，`PuzzleViewModel` 直接可播）。

### 3. XQF 解析器（`xqf_parser.dart`，核心工作）
- 输入 `Uint8List` → 头部解析（1024 字节 struct：魔数/版本/加密掩码/32 棋子布局/标题/赛事/日期/红黑双方/结果，GB18030 解码）。
- 按 cchess 算法派生密钥并解密棋子布局与走子树（版本分支：≤0x0A 无位置加密、≥0x12 加密）。
- 棋子布局 → FEN 字符串；走子树取**主线**转 `List<String>`（ICCS）。
- 输出 `ParsedPuzzle`：title=XQF 标题、source=分类路径、moves=主线 ICCS、difficulty 按步数分档。
- 健壮性：坏魔数/截断文件抛带上下文的 `FormatException`；FEN 无将/帅时报错。

### 4. PGN 解析器（`pgn_parser.dart`）
- 多局解析（流式，避免 101MB 整读内存）：按局切分 → 标签对 + 着法节。
- 着法文本双格式：ICCS（`H2-E2`/`h2e2`）+ **中文纵线记谱**（"炮二平五/马8进7/前炮退二"），后者需随局面逐着消解（红方汉字一-九从右数、黑方数字 1-9 从左数，进/退/平方向按棋子颜色与类型处理，前/后/中消歧）；注释 `{}`、`;` 行注释与 `()` 变着跳过。
- 无 `[FEN]` 时用标准初始局面；输出同 XQF（source=来源子目录名 wxf/dpxq 或 Event）。

### 5. 门面（`puzzle_parser.dart`）
- `PuzzleParser.parse({fileName, bytes}) → List<ParsedPuzzle>` 按扩展名分发（.xqf/.pgn/.pgns）。
- 统一校验：解析后用现有 `Board.fromFen` + `legalMovesFor` 重放全部走法，遇到非法着即停（保留已解析部分），保证进入 UI 的数据可演示。

### 6. 本地棋谱库浏览页（新 UI）
- `corpus_scanner.dart`（features/puzzle/model/）：扫描 `corpus/` 目录 → `CorpusCategory{名称, 局列表}`（XQF 按一级子目录、PGN 按来源子目录），记录懒解析（浏览页只列文件名，点开才解析单局，避免扫 14 万盘卡顿）。
- `corpus_browser_page.dart` + `corpus_browser_vm.dart`：分类 Tab/筛选 + 按步数等级排序（≤20步入门★1、21-40 初级、41-80 中级、81-150 高级、>150 职业）+ 搜索框；点开走现有 `PuzzleDetailPage` 演示。
- `puzzle_list_page.dart` 入口按钮"本地棋谱库"；`_importPuzzle` 的 TODO 用门面解析器替换（选中文件→解析→跳详情页）。
- 大文件优化：对多局合一 `.pgns` 提供按局偏移索引的轻量预扫描（读标签行定位每局起点），浏览页仅显示 Event/Red/Black 摘要。

### 7. 测试（flutter_test，沿用现有中文描述风格）
- 夹具：**不复制**真实语料——测试直接经 `corpus/` 联接读；联接不存在时 `skip` 标记；另在 `test/fixtures/` 放手工构造的最小 XQF/PGN 边界用例（坏魔数、截断、变着/注释）。
- `xqf_parser_test.dart`：真语料随机抽 1 个文件——解析后断言：FEN 双方有将帅、全部走法重放合法、标题解码正确；低版本与加密版本（0x0A/0x0C/0x12 各一）路径覆盖；与 Python cchess 基准对照（用 cchess 生成 3-5 个文件的期望值硬编码进测试）。
- `pgn_parser_test.dart`：ICCS 多局、中文纵线（现有 assets/sample_pgn.pgn）、注释/变着跳过、无 FEN 默认初始局面、坏输入。
- `puzzle_parser_test.dart`：扩展名分发、非法着重放截断。
- `corpus_scanner_test.dart`：分类聚合、难度分档。
- 收尾：`flutter analyze` 零新告警 + `flutter test` 全绿。

### 8. 文档
- 更新 `E:\ssy_proj\qp\README.md`（补充本项目对接方式与 corpus 联接说明）与项目内说明：棋谱真实保存位置 = `E:\ssy_proj\qp`（XQF 象棋谱大全/ChessQ 残局/CGLemon PGN 三个子目录）。

## 难度分档规则（按步数）

| 总步数 | 等级 | 星级 |
|--------|------|------|
| ≤ 20 | 入门 | ★1 |
| 21–40 | 初级 | ★2 |
| 41–80 | 中级 | ★3 |
| 81–150 | 高级 | ★4 |
| > 150 | 职业 | ★5 |

## 明确不做

- 不复制棋谱进项目/不提交棋谱到 git。
- 不改 `ParsedPuzzle` 模型结构（复用现有字段承载分类/难度）。
- XQF 变着树只取主线（残局演示场景够用），注解暂不展示。

## 实施记录（2026-10-01 完成）

### 交付物

| 文件 | 说明 |
|------|------|
| `lib/features/puzzle/model/iccs.dart` | ICCS 坐标工具（parse/format），VM 与解析器共用 |
| `lib/features/puzzle/model/parsers/xqf_parser.dart` | XQF 二进制解析（3 版本路径全支持） |
| `lib/features/puzzle/model/parsers/pgn_parser.dart` | PGN 解析（ICCS + 中文纵线 + 全角数字 + 注释/变着 + 按局偏移索引） |
| `lib/features/puzzle/model/puzzle_parser.dart` | 门面：扩展名分发 + 重放校验截断 + id 去重 |
| `lib/features/puzzle/model/corpus_scanner.dart` | 语料扫描/批量解析（isolate） |
| `lib/features/puzzle/viewmodel/corpus_browser_vm.dart` | 浏览页 VM（分批解析 + 进度 + 搜索/筛选/排序） |
| `lib/features/puzzle/view/corpus_browser_page.dart` | 棋谱库浏览页 |
| `lib/features/puzzle/view/corpus_pgn_browser_page.dart` | PGN 大文件分页浏览页 |
| `lib/features/puzzle/view/puzzle_list_page.dart` | 新增"本地棋谱库"入口；导入 TODO 已实现 |
| `test/features/puzzle/**` | 47 项测试（含随机真语料测试，联接缺失自动 skip） |

测试结果：puzzle/board/shared 相关 **80 项全部通过**；全仓 `flutter test` 仅
`app_test.dart` 失败（经 stash 验证为先前未提交的对战功能改动所致，与本次无关）。

### 实施中的关键发现

1. **坐标系实证校准**：XQF 位置字节 = `x*10 + y`，映射到项目坐标为
   `(col = x, row = 9 - y)`；32 子存放顺序为**回文序**「车马相仕帅仕相马车炮炮兵×5」，
   部分文档所写的「帅仕相马车」序是错误的（以语料实证为准）。
2. **密钥公式修正**：`KeyXY = F(hXY)*hXY & 0xFF`，而 `KeyXYf = F(hXYf)*KeyXY`、
   `KeyXYt = F(hXYt)*KeyXYf`（**不带尾因子**）；`FKeyBytes` 必须用头部**原始字节**
   （而非派生密钥）与掩码组合。两处弄反都会在高版本文件上解码出乱码。
3. **`walker8088/cchess` 的坐标/color 盲问题**：其棋盘 y=0 为黑方底线但 ICCS
   转换按红方语义走，回放会颜色错乱；只可作记录级（走子序列）参考，不可作
   局面级基准。本项目基准由 Dart 侧将军感知重放自行验证。
4. **语料存在坏数据**：如《角包.xqf》主线第 171 着未解将（源谱错误）。门面的
   重放校验在首个非法着处截断并保留合法前缀，属预期防御行为。
5. **项目自带的 `assets/puzzles/sample_pgn.pgn` 原本就是坏数据**（FEN 缺一行、
   着法与局面不自洽），已用东萍真实对局（99 着中文纵线记谱）重新生成。
6. **全角数字**：部分生成器黑方纵线用全角 ０-９，消解与正则均已兼容。

### 语料位置与访问

- 真实保存位置：`E:\ssy_proj\qp`（XQF-象棋谱大全 / ChessQ-gamebooks / CGLemon-PGN 三个子目录）。
- 项目内通过目录联接访问：`mklink /J corpus E:\ssy_proj\qp`（已创建，`corpus`
  已加入 `.gitignore` 不入库）；联接缺失时棋谱库页面展示创建引导，测试自动 skip。

## 审计结论与已知限制（2026-10-01 安全审计后）

### 审计结论
- Mimosa 深度扫描：findings 0、依赖风险 0（依赖检查 completion=partial，部分覆盖）。
- 提交完整性：无受限文件入库（corpus 联接、.mimosa、.zcode/ 均已忽略），
  无棋谱/大文件进入 git。

### 已知限制（设计取舍，非缺陷）
1. **corpus 联接是开发期特性**：相对路径依赖工作目录，Android 打包后无该目录，
   棋谱库页面会显示创建引导；如需移动端可用，需改为绝对路径/资产化配置。
2. **XQF 只取主线**：变着分支与注解未展示（残局演示场景够用）。
3. **大文件导入阈值**：`.pgn/.pgns` 超过 8MB（`PuzzleParser.streamImportThresholdBytes`）
   时导入改为按局索引 + 分页浏览（不整读内存）；阈值内仍整读解析。
4. **源语料可能含坏局**：如《角包.xqf》主线第 171 着未解将；门面重放校验
   截断并保留合法前缀。
5. **assets 样本**：`sample_pgn.pgn`（99 着中文纵线）与 `sample_xqf.xqf`
   （胡荣华对局，77 着）均为真实可解析棋谱，可作解析器联调用例。

### 审计后修复记录
- `app_test.dart`：首页已改为主导航页（二期），测试断言过时 → 已更新断言。
- 超大 `.pgns` 导入整读内存 → 已改为阈值判定 + 按局索引流式路径。
- `.zcode/` 加入 `.gitignore`；`sample_xqf.xqf` 占位文本替换为真实棋谱。

## 功能扩展：残局始盘人机对战（2026-10-01）

### 功能
残局详情页（PuzzleDetailPage）新增"从残局始盘开始人机对战"入口
（AppBar 图标 + 信息页按钮），以残局初始 FEN 进入人机对战：
- 玩家执红、AI 执黑；轮走方由残局 FEN 决定，若开局轮黑则 AI 先行。
- 页内"新游戏"重开回到残局始盘（而非标准开局），页面标题显示"残局人机对战"。
- 对局胜负判定沿用现有 ResultBanner/BoardState.result。

### 实现
- `BoardViewModel.newGameFromFen(String fen)`：指定 FEN 开局，无效回退标准开局。
- `HumanVsAiPage({initialFen})`：initState 延后至首帧（Riverpod 不允许构建期改
  provider）后应用初始 FEN，并按需触发 AI 先行；`_newGame` 分支处理残局重开。
- 测试：BoardViewModel 4 项单测（红先/黑先/无效回退/走子）+ HumanVsAiPage
  3 项 widget 测试（开局、重开回残局、黑先 AI 先行）。

### 已知取舍
- BoardViewModel 为全局共享 provider，从残局进入对战会重置正在进行的棋局
  （与"双人对弈/人机对战"入口互跳的既有行为一致）。
- 棋盘未做翻面：玩家执黑时黑方棋子在棋盘上方（后续可给 BoardWidget 加翻转）。

## 功能扩展二：执子选择与通关判定（2026-10-01）

### 功能
- **执子选择**：残局详情页点"人机对战"先弹执子选择（执红先行 / 执黑后行），
  传入 `HumanVsAiPage.playerSide`；执黑时 AI（红方）先行，页面标题与状态栏
  文案随执子方变化，悔棋（`undoRound(playerSide:)`）按执子方语义撤一整轮。
- **通关判定**：残局模式下胜负揭晓时弹对话框——玩家胜显示"残局闯关成功！"
  （再来一局 / 返回），负显示"闯关失败"（重试 / 返回）；防重入标记避免重复弹窗。

### 实现
- `HumanVsAiPage({initialFen, playerSide = Side.red})`：`_isAiTurn()` 按
  AI 执子方判定是否开局触发 AI；`ref.listen` 监听 `BoardState.result`。
- `BoardViewModel.undoRound({playerSide = Side.red})`：与走子顺序无关地撤
  "AI 一手 + 玩家一手"（兼容 AI 先行开局轮）。
- 测试：VM 5 项 + 页面 4 项（含玩家执黑 AI 先行、黑方悔棋语义），全量 96 项通过。

## 诊断：残局演示/对战"像从全新盘开始"（2026-10-01）

### 结论：数据语义问题，非解析缺陷、非 UI 接错
- 解析链路正确：XQF 的 initialFen = 文件内 32 子布局直接解码（xqf_parser.dart
  `_decodeBoard`）；演示从 initialFen 逐着播放（puzzle_vm.dart）；对战传入的就是
  `ParsedPuzzle.initialFen`。
- 用户试到的条目属于**全局对局类**语料（全局/大师专集/比赛对局/布局/PGN）：
  初始盘面天然=标准开局、主线=整局走法 → "破解走法"实为整局主线。
- **真残局类语料完好**（Python cchess 实证）：适情雅趣001/002/005 初始 FEN 均为
  残局盘面、主线 9/11/7 步取胜；烂柯神机 16 步成和。

### 待办（语义区分，另行确认后实施）
1. 浏览页/详情页区分"全局对局 vs 残局题"（按 initialFen 是否标准开局 + 分类名）
2. 全局类展示"对局演示/整局 N 步"，非残局隐藏"破解走法"措辞
3. 棋谱库浏览页加"仅看残局"筛选

## 棋盘 ICCS 坐标标注（2026-10-01 实施）

- 需求：对照破解走法的 ICCS 步骤（如 h2e2）定位格子——列 a-i、行 0-9
  标注在棋盘四端（行号 0 = 红方底线 = 画布底部）。
- 实现：`BoardLayout._canvasPaddingRatio` 0.55 → 0.8 留白；
  `BoardPainter._drawCoordinates` 在外框与画布边缘空隙（0.65 cell 处）
  用 TextPainter 绘制，字号 0.28 cell，颜色同楚河汉界文字。
- 对弈棋盘与残局演示棋盘共用 BoardPainter，标注自动生效；
  点击命中/飞子动画共用同一 BoardLayout，自动适应。
- 测试：BoardLayout 留白/等比尺寸断言 + BoardPainter 离屏绘制冒烟，全量 99 项通过。

## 语义区分：全局对局 vs 残局题（2026-10-01 实施）

### 实现
- **判定**：`ParsedPuzzle.isEndgamePuzzle`——来源分类名关键词优先
  （含"残局/排局/杀势"→ 残局题；含"全局/大师/比赛/布局/中局/名局/让子"→
  全局对局，其中让子局盘面非标准开局但属对局），否则按初始盘面是否为
  标准开局兜底判定。
- **来源标注细化**：语料条目 source 取相对分类目录的前两级子目录
  （如"残局/适情雅趣"、"全局/子"），批量解析逐条目携带（isolate 可发送）。
- **详情页**：新增"类型"行（残局题/全局对局）；标签页改为"残局信息/破解演示"
  或"对局信息/对局演示"；步数行区分"破解步数/整局步数"；"破解走法"区块在
  全局类显示"对局走法（主线）"；对战按钮文案区分"从残局始盘开始人机对战 /
  对该局进行人机对战"。
- **棋谱库浏览页**：新增"仅看残局"筛选（FilterChip，按解析结果过滤）；
  列表行副标题显示来源子分类与类型。
- 测试：isEndgamePuzzle 判定 4 项 + 语料 source 子分类用例，全量 103 项通过。

## 棋谱路径多平台支持与下载引导（2026-10-01 实施）

### 设计（混合方案）
| 平台 | 默认路径 | 自定义 | 获取方式 |
|------|----------|--------|----------|
| Windows | `文档\ChineseChessUltra\corpus` | ✅ 设置页选目录 | 手动放置或应用内下载 |
| macOS | `~/Documents/ChineseChessUltra/corpus` | ✅ 同上 | 同上 |
| Linux | `~/Documents/ChineseChessUltra/corpus` | ✅ 同上 | 同上 |
| Android | `Android/data/<包名>/files/corpus`（应用专属外置目录） | ❌ 分区存储限制 | 首次启动检测为空 → 引导下载 |

路径解析优先级：用户设置（SharedPreferences `corpus.userPath`）> 旧版相对
`corpus`（Windows 联接，存在即沿用，开发流不变）> 平台默认目录。

### 实现
- `corpus_paths.dart`：路径解析 + 下载 URL 安全校验（仅 https 公网；拒绝
  localhost/环回/私有/保留/链路本地/mDNS——防 SSRF）。
- `corpus_downloader.dart`：HTTPS 下载（重定向手动跟随、逐跳校验）+ zip 解压
  （zip-slip 防护：拒绝 `..`、绝对路径、盘符段、符号链接条目）+ 临时文件清理；
  进度回调（已接收/总字节）。
- `corpus_browser_page`：语料缺失引导页展示当前路径 + "下载棋谱库"按钮
  （带进度对话框，完成后自动重新加载）；桌面端另有"选择其他棋谱目录"
  （file_picker）与 AppBar 设置入口。
- `AndroidManifest.xml` 补 INTERNET 权限；新增依赖 shared_preferences、archive。
- 下载源：`CorpusPaths.downloadUrl` 常量指向
  `https://github.com/jxsword/qp-corpus/releases/latest/download/qp-corpus.zip`
  ——需在 qp-corpus 仓库发 Release 并上传 qp-corpus.zip（语料结构 = E:\ssy_proj\qp
  内容原样，多级子目录保持不变）。
- 测试：URL 校验 3 项 + zip 正常解压/防穿越 2 项，全量 108 项通过。

### 待办
- Android 真机/模拟器验证下载-解压-扫描全链路。

### 语料源发布记录（2026-10-01 已完成）
- 语料仓库：`jxsword/qp-corpus`（公开），12,660 个文件 / 199MB，含过滤
  （已剔除 ChessQ 应用源码与 .eglib/.eplib 私有书格式、xqp 代码文件；
  说明性 txt/doc 与 .CBL 合集保留）。
- Release `v1`：附件 `qp-corpus.zip`（45.8MB，UTF-8 文件名打包，Python zipfile）。
- 已验证：`releases/latest/download/qp-corpus.zip` 匿名可达（302）、完整下载
  12,660 条目、中文路径与 XQ 魔数抽验通过、pgns 字节数与源一致、
  抽样 XQF 经 cchess 解析成功——`CorpusPaths.downloadUrl` 可直接使用。
- 运维约定：单文件 >100MiB 只进 Release 不进 git；大版本更新后可 squash
  重建仓库控制体积；更新语料 = qp 目录 push + 重发 Release（URL 不变）。
- 注意：本机 GH_TOKEN 已轮换（setx 写入用户环境变量），重启 ZCode 后新会话
  自动生效；旧 fine-grained token 建议在 GitHub 上撤销。

### Android 工具链修复与模拟器冒烟验证（2026-10-01 已完成）

> 待办"Android 真机/模拟器验证下载-解压-扫描全链路"就此关闭。验证环境：
> Windows 11 + Flutter 3.44.2 + Android SDK（无 Android Studio，纯命令行），
> 模拟器 Pixel_7_API34（system-images;android-34;google_apis;x86_64，WHPX 加速）。

**工具链修复记录（flutter doctor Android toolchain X → √）：**

1. 本机原无 Android SDK（ANDROID_HOME 未设，无 adb/sdkmanager）。安装位置
   `E:\dev\android-sdk`，加入 `flutter config --android-sdk`。
2. JDK： scoop 安装 temurin17-jdk 17.0.20（原机 JDK 11 不满足 Gradle 9.1/AGP 9.0.1）。
3. cmdline-tools：`commandlinetools-win-11076708_latest.zip` 解压至
   `cmdline-tools/latest/`（腾讯镜像可直下；sdkmanager 走腾讯镜像代理模式
   解析不到包，改用本地 socks 代理：`JDK_JAVA_OPTIONS="-DsocksProxyHost=127.0.0.1
   -DsocksProxyPort=10808"` 后正常）。
4. 组件：platform-tools / platforms;android-36（Flutter 3.44 默认 compileSdk=36）/
   build-tools;36.0.0 / emulator / system-images;android-34;google_apis;x86_64。
5. `yes | sdkmanager --licenses` + `flutter doctor --android-licenses` 全部接受。

**构建修复（flutter build apk --release）：**

- Kotlin 增量编译缓存关闭失败（"Could not close incremental caches"，多个插件
  模块稳定复现，Windows 文件锁典型症状）→ `android/gradle.properties` 加
  `kotlin.incremental=false`（保留，注释标明缘由）。
- file_picker 8.3.7 自声明 compileSdk 34，低于 flutter_plugin_android_lifecycle
  要求的 36，AAR metadata 校验失败 → `android/build.gradle.kts` 对全部子项目
  afterEvaluate 统一抬升 compileSdk 到 36（仅 Android 平台侧，不影响 Dart 代码；
  升级 file_picker 到 9/10.x 有破坏性 API 变更，暂不采用）。
- 产物：`build/app/outputs/flutter-apk/app-release.apk`（57.8MB）。

**冒烟清单（adb install + 真机操作模拟，全部通过）：**

| 项 | 结果 |
|----|------|
| a) 主导航四入口（残局选关/人机对战/机器对战/双人对弈） | ✅ |
| b) 人机对战：走子（炮二平五）、AI 应手（炮2平5）、悔棋（整回合撤销）、新游戏 | ✅ |
| c) 棋谱库缺失引导：显示"未找到棋谱语料"+ 路径 /storage/emulated/0/Android/data/com.ssy.chinesechess.chinese_chess_ultra/files/corpus + 下载按钮 | ✅ |
| d) 下载棋谱库：进度 → 解压 → 自动重载出分类（ChessQ-gamebooks / XQF-象棋谱大全 / PGN·WXF-41743 / PGN·dpxq-99813） | ✅ |
| e) 勾选"仅看残局"→ 搜索"001"打开适情雅趣"第001局 气吞关右"→ 破解演示播放正常（棋盘渲染/走子/序列推进） | ✅ |
| f) "从残局始盘开始人机对战"（执红）：始盘与 FEN 一致、AI 应手正常（马7进5 吃弃车） | ✅ |
| g) 终局对话框："闯关失败"+ 黑方胜横幅 + 重试/返回 正常弹出（通关侧同一代码路径，未单独实测） | ✅ |
| h) 语料落位：files/corpus/ 下 CGLemon-PGN、ChessQ-gamebooks、XQF-象棋谱大全、README.md 共约 245MB | ✅ |

**环境注意（非代码 bug）：**

- 模拟器/国内真机直连 `github.com` Release 附件大概率不通（DNS 污染/断连），
  首次下载静默失败。模拟器验证时用 `-http-proxy socks5://10.0.2.2:10808` 启动；
  下载约 45.8MB @ ~110KB/s，全程 ~8 分钟。
- 下载按钮文案"约 150MB"与实际压缩包 45.8MB 不符（疑指解压后 ~250MB），建议
  改为"压缩包约 46MB / 解压约 250MB"。

**发现的问题（待确认后修复）：**

1. **空 corpus 目录导致死胡同（中）**：目录存在但为空时（如上次下载失败残留），
   `corpus_browser_vm.load()` 仅以 `repo.exists` 判定，页面进入"请选择分类"空态，
   不再显示下载引导。建议：`exists && scanCategories().isNotEmpty` 才算有语料，
   或空分类时同样提供下载入口。
2. **残局终局状态泄漏到普通人机对战（中）**：残局对局结束返回主页再进"人机对战"，
   棋盘残留残局局面与"黑方胜！"横幅（两页共用 `boardViewModelProvider`，普通
   模式进入时未 newGame）。建议：`human_vs_ai_page` initState 且 `initialFen==null`
   时重置棋盘 VM。
3. **下载失败提示弱（低）**：失败仅 SnackBar 一闪即逝，且残留空目录会触发问题 1。
   建议失败时在对话框内展示错误并提供重试。
