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
- 玩家固定执红；若残局的取胜方为黑，玩家只能执红体验（后续可加执子选择）。
- BoardViewModel 为全局共享 provider，从残局进入对战会重置正在进行的棋局
  （与"双人对弈/人机对战"入口互跳的既有行为一致）。
