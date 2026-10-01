# VMware Ubuntu / macOS 虚拟机测试环境搭建流程

- 记录日期：2026-10-01
- 目的：在 VMware 虚拟机（Ubuntu / macOS）上跑通 ChineseChessUltra 桌面端
  冒烟（人机对战、残局、棋谱库语料链路），对齐 Windows 端已验证行为。
- 前提事实：
  - 项目当前平台目录仅 `android/` 与 `windows/`，**Linux/macOS 脚手架需先补**
    （见 §一）；所有 Dart 依赖（sqlite3_flutter_libs / path_provider /
    shared_preferences / file_picker / archive / fast_gbk）均官方支持
    Linux 与 macOS，无需改 pubspec。
  - 应用内下载器使用 Dart `HttpClient` 直连 GitHub Release，
    **不读 `http_proxy` 环境变量**——VM 内想走应用内下载必须透明代理
    （TUN 模式）；否则用手动拷贝语料（推荐，见 §四）。

---

## 一、主机侧准备（先做，两个 VM 共用）

1. **补平台脚手架**（在 Windows 主机项目根执行；`create` 不覆盖既有平台目录，安全）：

   ```bash
   flutter create --platforms=linux,macos .
   ```

   生成 `linux/`、`macos/` 两个目录，单独 commit（如
   `chore: 补充 linux/macos 平台脚手架供 VM 冒烟`）。VM 侧只需 clone/pull。

2. **准备语料拷贝源**（VM 内应用内下载不可用时的替代）：Windows 开发机已有
   完整语料（`E:\ssy_proj\qp`，经项目根 `corpus` 联接引用，约 233MB 解压后）。
   打包备用（**必须排除 `.git`**——qp 本身是 git 仓库，`.git` 占 45MB，
   对 VM 冒烟无用，且会被棋谱扫描误当作一个分类目录）：

   ```bash
   # Git Bash 下（路径写 /e/...；cmd 中可用 E:\ssy_proj\qp）
   tar -czf corpus.tar.gz --exclude='.git' -C /e/ssy_proj/qp .
   # 产物约 180MB；VM 解压前可校验无 .git 残留：
   # tar -tzf corpus.tar.gz | grep -c '\.git/'   # 应输出 0
   ```

3. **代码传输方式**（按优先级）：
   - 内部 git 远端 clone（最干净）；
   - `git bundle create ccu.bundle main` 拷入 VM 后 `git clone ccu.bundle`；
   - VMware 共享文件夹（见下），**但不要在 /mnt/hgfs 挂载点里构建**——
     9p 文件系统 I/O 慢且权限语义古怪，代码务必拷到 VM 本地目录（如 `~/src`）。

---

## 二、Ubuntu 虚拟机

### 2.1 VM 创建

| 项 | 建议值 |
|----|--------|
| 宿主 | VMware Workstation Pro/Player 17+（Windows） |
| 客户机 | Ubuntu 22.04 / 24.04 / 26.04 LTS Desktop（x86_64） |
| CPU / 内存 | 4 vCPU / 8 GB（GTK 构建吃内存） |
| 磁盘 | 60 GB（SDK + 构建 + 语料 245MB） |
| 网络 | NAT（默认 VMnet8）即可 |

### 2.2 系统内准备

```bash
# VMware 集成（剪贴板/共享文件夹/自适应分辨率）
sudo apt-get update
sudo apt-get install -y open-vm-tools open-vm-tools-desktop

# Flutter Linux 桌面官方依赖（clang 必须，gcc 不行）
# libstdc++ 开发包不写死版本：build-essential 会带上当前系统的
# libstdc++-<N>-dev（22.04 是 12，24.04 是 14，26.04 是 14/15），避免包名失配
sudo apt-get install -y build-essential clang cmake ninja-build pkg-config \
    libgtk-3-dev liblzma-dev
# 注：Ubuntu 26.04 桌面默认 Wayland 会话。Flutter Linux 嵌入层是 GTK3/X11，
# 经 XWayland 运行通常无碍；若窗口/输入异常，登录界面切 "Ubuntu on Xorg" 会话。
```

### 2.3 Flutter SDK（国内镜像）

```bash
sudo apt-get install -y curl unzip xz-utils git
# 镜像环境变量写入 ~/.bashrc
cat >> ~/.bashrc <<'EOF'
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
export PUB_HOSTED_URL=https://pub.flutter-io.cn
EOF
source ~/.bashrc

# 下载稳定版 linux tarball（<version> 取法见下方说明）
cd ~/development
curl -O https://storage.flutter-io.cn/flutter_infra_release/releases/stable/linux/flutter_linux_3.44.2-stable.tar.xz
tar xf flutter_linux_3.44.2-stable.tar.xz
echo 'export PATH="$HOME/development/flutter/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc

flutter doctor   # 目标：Linux toolchain 一行无红
```

**`<version>` 取法**（三选一，约 1.5GB/个，注意磁盘与流量）：

1. **与主机 SDK 对齐（推荐）**：在 Windows 主机跑 `flutter --version`，VM 装同一
   版本，避免两端行为差异。本机当前为 **3.44.2**（文档即按此写死）。
2. **查镜像的版本清单**（`current_release.stable` 即最新稳定版）：

   ```bash
   curl -s https://storage.flutter-io.cn/flutter_infra_release/releases/releases_linux.json \
     | grep -B2 -A4 '"hash"' | grep -o '"version": "[^"]*"' | head -5
   # 或直接浏览 https://flutter-io.cn 首页展示的最新 stable 版本号
   ```

3. **macOS 同理**：URL 中 `linux` 换 `macos`，文件名按 CPU 选
   `flutter_macos_arm64_*`（Apple Silicon / VM 常见）或 `flutter_macos_x64_*`。

### 2.4 获取代码与运行

```bash
mkdir -p ~/src && cd ~/src
git clone <repo> ChineseChessUltra   # 或 git bundle 方式
cd ChineseChessUltra
flutter pub get
flutter run -d linux --release   # 首次跑 debug 亦可
```

### 2.5 语料就位（二选一）

- **手动拷贝（推荐）**：把 §一.2 的 corpus.tar.gz 传入 VM 后：

  ```bash
  mkdir -p ~/Documents/ChineseChessUltra
  tar xzf corpus.tar.gz -C ~/Documents/ChineseChessUltra/corpus
  ```

  对应 `CorpusPaths.defaultDirectory()` 的桌面默认路径，应用自动识别。
- **应用内选择目录**：棋谱库页 → "选择其他棋谱目录" 指向任意已放置语料的目录
  （开发期也可在项目根建 `corpus/` 目录模拟 Windows legacy 联接，`flutter run`
  的 CWD 是项目根，会被优先命中）。

---

## 三、macOS 虚拟机

> **合规提示（先读）**：Apple EULA 仅允许在 Apple 硬件上运行 macOS 客户机。
> Windows 宿主 + VMware Workstation 需要 unlocker 补丁且不受 VMware 官方支持。
> 合规路径是 **Apple 硬件上的 VMware Fusion**（或物理 Mac 直接测）。以下流程
> 按已具备合规 macOS 客机环境编写， unlocker 细节不在本文展开。

### 3.1 VM 创建

| 项 | 建议值 |
|----|--------|
| 客户机 | macOS 13 Ventura / 14 Sonoma（Apple 官方 InstallAssistant 或恢复镜像） |
| CPU / 内存 | 4 vCPU / 8 GB |
| 磁盘 | 80 GB（Xcode 本体 + 组件约 30-40GB） |
| 工具 | VMware Tools（darwin.iso，随 Workstation 附带）或省略 |

### 3.2 开发链

```bash
# 1) Homebrew（国内镜像安装脚本，见 gitee/brew 镜像页）
/bin/bash -c "$(curl -fsSL https://gitee.com/cunkai/HomebrewCN/raw/master/Homebrew.sh)"

# 2) Xcode（完整版，App Store 或 developer.apple.com，约 12GB）
xcode-select --install                      # CLT（flutter doctor 需要它存在）
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -runFirstLaunch                  # 需要用 Apple ID 登录一次并同意许可

# 3) CocoaPods
brew install cocoapods

# 4) Flutter（macOS tarball + 同 §2.3 的镜像环境变量，写 ~/.zshrc）
cd ~/development
curl -O https://storage.flutter-io.cn/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_<version>-stable.tar.xz
# Intel 客机用 flutter_macos_x64_*
tar xf flutter_macos_*.tar.xz
echo 'export PATH="$HOME/development/flutter/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc

flutter doctor   # 目标：[!] macOS development 无红（Xcode 签名警告可忽略）
```

### 3.3 获取代码、语料与运行

- 代码：主机与 VM 同网段 `scp -r`，或共享文件夹后拷到 `~/src`（同 Ubuntu 原则）。
- 语料：放 `~/Documents/ChineseChessUltra/corpus`，或棋谱库页"选择其他棋谱目录"。
  **App Sandbox 坑**：Flutter macOS 模板默认开启 App Sandbox，
  `getApplicationDocumentsDirectory()` 返回的是**容器路径**
  `~/Library/Containers/<bundle-id>/Data/Documents`，手动放文件请放在该容器
  Documents 下，或干脆用"选择其他棋谱目录"指向任意可读位置。

```bash
cd ~/src/ChineseChessUltra
flutter pub get
flutter run -d macos
```

---

## 四、两个 VM 统一的冒烟清单（对齐 Windows 已验证项）

1. **人机对战**：开局落子 → AI 应手 → 悔棋 → 新游戏；
2. **P0-1**：AI 思考中返回主页再进人机对战 → 棋盘可点击；
3. **P1-2**：残局详情 → 人机对局 → 返回主页 → 再进人机对战 = 标准开局无横幅；
4. **P1-1**：构造困毙局面 → 终局显示"某方获胜"而非"和棋"；
5. **棋谱库**：分类条/搜索/难度筛选/演示正常（对应 §2.5 / §3.3 语料就位）；
6. **P1-4/P1-6 下载链路**（仅当 VM 内配好透明代理时测）：
   断网 → 常驻失败对话框（非 SnackBar）→ 不留空目录；下载中取消 → 零残留；
   成功 → staging 目录 `corpus.tmp-*` 消失、分类正常。
   **不配透明代理则跳过本项**（应用内下载直连 GitHub，环境变量代理无效）；
7. **P1-3**：保存按钮提示"保存功能开发中"。

## 五、常见坑速查

| 现象 | 原因 / 解法 |
|------|-------------|
| 应用内下载直连失败，设了 `http_proxy` 也没用 | Dart `HttpClient` 不读环境变量代理；用 TUN 透明代理或手动拷语料（§2.5） |
| Linux 构建 CMake 报 GTK 头缺失 | 漏装 `libgtk-3-dev` / `clang`；按 §2.2 清单补齐 |
| 在共享文件夹里构建极慢或权限报错 | 把代码拷到 VM 本地目录再构建，hgfs 只作传输 |
| macOS `flutter doctor` 卡在 Xcode 许可 | `sudo xcodebuild -license accept` + `-runFirstLaunch` |
| macOS 找不到手动放置的语料 | App Sandbox 容器路径，见 §3.3；或用应用内选目录 |
| `flutter create` 提示已存在平台 | 正常，create 不覆盖 `android/`/`windows/`/`linux/`/`macos/` |
| VM 内 pub get 慢 | 确认 `PUB_HOSTED_URL`/`FLUTTER_STORAGE_BASE_URL` 已写入对应 shell 配置 |
| 切宿主再切回后 Ubuntu 黑屏（SSH 仍可连） | vmwgfx + GNOME Wayland 已知问题：强制 Xorg——`/etc/gdm3/custom.conf` 设 `WaylandEnable=false` 后重启（验证 `echo $XDG_SESSION_TYPE` 输出 x11）；仍偶发则关机后取消 VM 显示设置的"加速 3D 图形" |
