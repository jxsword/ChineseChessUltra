# Android 构建环境交接文档

> 记录日期：2026-10-01　|　适用项目：ChineseChessUltra（Flutter 中国象棋应用）
> 背景：本机此前**无任何 Android 开发环境**（无 Android Studio / SDK / adb），
> 本次从零搭建至完成 `flutter build apk --release` 与模拟器冒烟验证。
> 相关验证结论见 `docs/qp_parse.md` 的"Android 工具链修复与模拟器冒烟验证"一节。

## 1. 基础软件与安装路径

| 组件 | 版本 | 安装路径 | 安装方式 |
|------|------|----------|----------|
| Flutter SDK | 3.44.2 stable（Dart 3.12.2） | `E:\dev\flutter` | 原有（zip 解压），国内镜像已配置（pub.flutter-io.cn / storage.flutter-io.cn） |
| JDK | Temurin **17.0.20-101** | `D:\scoop\apps\temurin17-jdk\current` | `scoop install temurin17-jdk`（scoop 位于 `D:\scoop`） |
| Android SDK 根目录 | — | `E:\dev\android-sdk` | 手动搭建（无 Android Studio，纯 cmdline-tools） |
| ├ cmdline-tools | 12.0（11076708） | `E:\dev\android-sdk\cmdline-tools\latest` | 腾讯镜像直下 zip 解压 |
| ├ platform-tools | 37.0.1（adb 等） | `E:\dev\android-sdk\platform-tools` | sdkmanager |
| ├ platforms | android-34 / 35 / 36 | `E:\dev\android-sdk\platforms\` | sdkmanager 装 36；34/35 为构建时 AGP 自动补装 |
| ├ build-tools | 36.0.0 | `E:\dev\android-sdk\build-tools\36.0.0` | sdkmanager |
| ├ emulator | 最新 | `E:\dev\android-sdk\emulator` | sdkmanager |
| ├ system-images | android-34;google_apis;x86_64（r14） | `E:\dev\android-sdk\system-images\` | sdkmanager |
| ├ NDK | 28.2.13676358 | `E:\dev\android-sdk\ndk\` | 构建时 AGP 自动安装（`flutter.ndkVersion`） |
| └ CMake | 3.22.1 / 28.2.13676358 | `E:\dev\android-sdk\cmake\` | 构建时 AGP 自动安装 |
| Gradle | 9.1.0（wrapper 发行版） | `C:\Users\ysm\.gradle\wrapper\dists\gradle-9.1.0-all\` | 首次构建时经腾讯镜像下载 |
| Gradle 用户主目录 | — | `C:\Users\ysm\.gradle`（默认 GRADLE_USER_HOME） | — |
| AVD 模拟器 | Pixel_7_API34（Pixel 7 机型 + API 34 google_apis x86_64） | `C:\Users\ysm\.android\avd\Pixel_7_API34.avd` | `avdmanager create avd` |
| 硬件加速 | WHPX（Windows 虚拟机平台） | 系统组件，已可用 | `emulator -accel-check` 验证通过 |

项目侧相关路径：

- Flutter 对 SDK 的指向：`flutter config --android-sdk E:\dev\android-sdk`
  （写入 Flutter 自身配置，与机器用户绑定，不在仓库内）。
- APK 产物：`build\app\outputs\flutter-apk\app-release.apk`（57.8MB）。
- 仓库内改动（已随 commit `bb09ffa` 提交）：`android/gradle.properties`
  （kotlin.incremental=false）、`android/build.gradle.kts`（子项目 compileSdk
  统一抬升 36）、`android/.gitignore`（忽略 .kotlin/）。

## 2. 环境变量（重要：按会话设置，未持久化）

本次所有环境变量均在 shell 会话内临时设置，**机器重启/新终端不自动生效**。
新会话执行 Android 相关操作前需先设置（建议后续用 `setx` 或系统设置持久化）：

```bat
:: Windows CMD（PowerShell 请用 $env: 写法）
setx JAVA_HOME "D:\scoop\apps\temurin17-jdk\current"
setx ANDROID_HOME "E:\dev\android-sdk"
```

构建期额外使用（仅命令行前缀，无需持久化）：

| 变量 | 值 | 用途 |
|------|----|------|
| `JAVA_HOME` | `D:\scoop\apps\temurin17-jdk\current` | flutter/gradle/avdmanager/sdkmanager 均需要 JDK 17+ |
| `ANDROID_HOME` | `E:\dev\android-sdk` | sdkmanager/avdmanager/emulator 的 SDK 定位（flutter 已由 config 指向，可不设） |
| `GRADLE_OPTS` | `-DsocksProxyHost=127.0.0.1 -DsocksProxyPort=10808` | Gradle 依赖解析走本地代理（见 §3：maven.google.com 直连不通） |
| `JDK_JAVA_OPTIONS` | `-DsocksProxyHost=127.0.0.1 -DsocksProxyPort=10808` | sdkmanager 装包走本地代理（腾讯镜像代理模式解析不到包） |

## 3. 网络与镜像策略（本次实测结论）

约定：**优先国内镜像，镜像不可用时走本地代理 `127.0.0.1:10808`（socks5）**。

| 下载内容 | 实际采用的源 | 说明 |
|----------|--------------|------|
| Flutter SDK / pub 包 | storage.flutter-io.cn / pub.flutter-io.cn | 原已配置 |
| cmdline-tools zip | `https://mirrors.cloud.tencent.com/AndroidSDK/commandlinetools-win-11076708_latest.zip` | 腾讯镜像直连可用 |
| sdkmanager 装包（platform/build-tools/emulator/system-images/licenses） | dl.google.com + **socks 代理**（JDK_JAVA_OPTIONS） | ⚠️ 腾讯镜像的 `--no_https --proxy=http --proxy_host=mirrors.cloud.tencent.com --proxy_port=443` 模式会报 "Failed to find package"，不可用 |
| Gradle 发行版 | `https://mirrors.cloud.tencent.com/gradle/gradle-9.1.0-all.zip` | 已回退仓库内 distributionUrl 到官方（镜像仅本地使用：临时改 `android/gradle/wrapper/gradle-wrapper.properties` 后构建，构建完还原） |
| Gradle Maven 依赖 | mavenCentral / gradlePluginPortal **直连可用**；google() 直连不通 → 用 GRADLE_OPTS socks 代理 | maven.google.com 直连实测 000 |
| GitHub（语料 Release 等） | **socks 代理**（模拟器内经宿主代理） | 直连 302 后资产域断连 |

## 4. 常用命令速查

```bash
# 环境自检（应全 √）
export JAVA_HOME="D:\scoop\apps\temurin17-jdk\current"
flutter doctor

# 构建 release APK（依赖走本地代理）
export GRADLE_OPTS="-DsocksProxyHost=127.0.0.1 -DsocksProxyPort=10808"
flutter build apk --release
# 产物：build\app\outputs\flutter-apk\app-release.apk

# 创建 AVD（已建过，可跳过；名字 Pixel_7_API34）
"$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager.bat" create avd \
  -n Pixel_7_API34 -k "system-images;android-34;google_apis;x86_64" -d pixel_7

# 启动模拟器（直连 GitHub 下载场景必须挂代理；10.0.2.2 = 宿主环回）
"$ANDROID_HOME/emulator/emulator.exe" -avd Pixel_7_API34 \
  -no-snapshot -no-boot-anim -gpu auto -http-proxy socks5://10.0.2.2:10808 &

# 等待启动完成
"$ANDROID_HOME/platform-tools/adb.exe" wait-for-device shell \
  'while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done'

# 安装 / 日志
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb shell am start -n com.ssy.chinesechess.chinese_chess_ultra/.MainActivity
adb logcat -s flutter
```

## 5. 已知坑（务必阅读）

1. **sdkmanager 腾讯镜像代理模式不可用**：报 "Failed to find package 'platform-tools'"
   且退出码仍为 0（易误判成功）。装包一律走 socks 代理 + 官方源，并核对目录
   真实生成。
2. **Kotlin 增量编译缓存损坏（Windows）**：表现为 "Could not close incremental
   caches"（多个插件模块复现）。已在 `android/gradle.properties` 用
   `kotlin.incremental=false` 规避；如移除此行后构建失败属预期，恢复即可。
3. **file_picker 8.3.7 compileSdk 偏低**：已由根 build.gradle.kts 统一抬升到 36；
   若将来升级 file_picker 到 9/10.x（有破坏性 API 变更），可移除该 afterEvaluate 块。
4. **Git Credential Manager 不支持 socks5 系统代理**：推送报
   "ServicePointManager 不支持 socks5" 时改用
   `git -c credential.helper= -c 'credential.https://github.com.helper=!gh auth git-credential' push`。
5. **模拟器/真机直连 GitHub Release 大概率失败**：语料下载（45.8MB）需代理环境；
   模拟器用 `-http-proxy socks5://10.0.2.2:10808`，实测约 110KB/s。
6. **MSYS/Git Bash 路径转换**：`adb shell ls /storage/...` 会被转成本地盘符路径，
   需 `export MSYS_NO_PATHCONV=1` 或对整条命令加引号。

## 6. 冒烟验证状态（交接时）

- 冒烟清单 a-h 全过（详见 `docs/qp_parse.md`），已确认 3 个待修问题：
  ① 空 corpus 目录导致棋谱库死胡同；② 残局终局状态泄漏到普通人机对战；
  ③ 语料下载失败提示弱（SnackBar 一闪 + 残留空目录触发问题①）。
- 待办：Android 真机验证、CI 三平台矩阵（见 `docs/task_prompts.md`）。
