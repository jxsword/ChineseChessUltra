# Android 模拟器使用 Windows 代理配置指南

> 记录日期：2026-10-01　|　适用：ChineseChessUltra 项目开发/冒烟验证
> 实测环境：Windows 11 + Android SDK（`E:\dev\android-sdk`，无 Android Studio）+
> AVD `Pixel_7_API34`（API 34 google_apis x86_64）+ 本地代理客户端（v2rayN 类，
> 混合端口 `127.0.0.1:10808`，同时接受 socks5 与 http 代理协议——已分别实测）。

## 1. 为什么需要配置（背景与原理）

模拟器网络是独立 NAT 网段，**不会继承 Windows 系统代理**：

```
模拟器 guest (10.0.2.15) ──NAT──> 宿主物理网卡（直连出网）
                     10.0.2.2 = 宿主环回 127.0.0.1 的别名
```

直接后果：

- guest 内所有流量**直连出网**，Windows 上运行的代理客户端完全不被使用；
- 国内网络下 GitHub Release（本项目棋谱语料包 45.8MB）、Google 系域名
  大概率**超时/断连**（实测语料下载首次静默失败，约 2 分钟后回到缺失态）；
- DNS 污染在 guest 侧同样存在（如 `www.google.com` 解析到 `2001::1`）。

所有方案的本质都是：让 guest 的 TCP 流量经 `10.0.2.2`（= 宿主 127.0.0.1）
交给代理客户端转发。

**前置条件**：宿主代理客户端已运行并监听端口。若客户端只监听 `127.0.0.1`
也没关系——`10.0.2.2` 到宿主侧呈现的就是环回地址。确认端口语义（v2rayN 默认
10808=socks/混合、10809=http），混合端口两种协议都可用（本机 10808 已实测）。

## 2. 方案 A：emulator 启动参数 `-http-proxy`（推荐，已验证 ✅）

在模拟器**网络层**透明代理全部 TCP 连接（含 HTTPS，CONNECT 隧道方式），
guest 内应用无感知，**对 Flutter/Dart 应用同样生效**——本次棋谱语料
45.8MB 下载全链路即用此方案完成。

```bash
E:\dev\android-sdk\emulator\emulator.exe -avd Pixel_7_API34 \
  -no-snapshot -no-boot-anim -gpu auto \
  -http-proxy socks5://10.0.2.2:10808
```

- 代理地址写法：`socks5://10.0.2.2:10808` 或 `http://10.0.2.2:10809`（按客户端
  实际协议/端口）。**必须用 `10.0.2.2`，不能写 `127.0.0.1`**（那会指向 guest 自己）。
- 作用范围：仅本次启动的该模拟器实例；关闭后失效。
- 局限：guest 的 DNS 解析仍在 guest/模拟器 DNS 完成（走宿主 DNS）。代理转发的
  是"连接目标 IP"，因此**DNS 已被污染的域名（如 google.com → 2001::1）依然
  连不上**——这是预期行为；GitHub 等未被污染域名不受影响。
- 实测速率：经此方案下载语料 ~110KB/s（对比直连完全失败）。

### 便捷化：写个启动脚本（避免每次敲参数）

`E:\dev\android-sdk\run_emu_proxy.bat`（自建，不入库）：

```bat
@echo off
set ANDROID_HOME=E:\dev\android-sdk
set JAVA_HOME=D:\scoop\apps\temurin17-jdk\current
start "" /b "E:\dev\android-sdk\emulator\emulator.exe" -avd Pixel_7_API34 ^
  -no-snapshot -no-boot-anim -gpu auto ^
  -http-proxy socks5://10.0.2.2:10808
```

> 其余启动参数（快照/GPU/端口/`-writable-system` 等）与日常管理命令见
> `docs/android_emulator_cli_and_root.md`。

## 3. 方案 B：模拟器 Extended Controls 图形界面

模拟器窗口右侧工具条 `…`（Extended Controls）→ **Settings → Proxy**：

1. 选择 **Manual proxy configuration**；
2. Host name 填 `10.0.2.2`，Port 填代理端口（如 `10808`）；
3. 保存后立即生效，无需重启模拟器。

说明：这是官方提供的持久化入口（按 AVD 保存），适合不想用命令行的场景；
本次未逐一验证其存储细节，可靠性以方案 A（命令行，实测通过）为准。

## 4. 方案 C：Android 系统全局代理（有限适用，已实测 ⚠️）

```bash
adb shell settings put global http_proxy 10.0.2.2:10808
# 清除（恢复直连）：
adb shell settings put global http_proxy :0
```

实测结果：设置后系统网络探测 HTTP/HTTPS 均 204 通过（logcat 可见
`Proxy-Connection` 头），**遵守系统代理的应用**（Chrome、WebView、系统组件、
多数 Java/Kotlin 应用）走代理正常。

**重要局限**：本应用（Flutter/Dart）的 `HttpClient` **不读取 Android 系统代理**，
因此此方案对"棋谱语料下载"无效；只适合调试浏览器访问等场景。同理它只支持
http 代理语义（`host:port`，不支持 socks5 scheme，但混合端口可直接填）。
设置持久化在 userdata 中，重启模拟器仍在，用完记得清除。

## 5. 不可行方案（实测记录，勿再踩）

**AVD `config.ini` 写 `http.proxy` 键**：无效。在
`C:\Users\ysm\.android\avd\Pixel_7_API34.avd\config.ini` 中添加

```ini
http.proxy = socks5://10.0.2.2:10808
```

后不带 `-http-proxy` 启动，模拟器启动日志仍显示 `http_proxy: None`（3 种写法
含转义均不解析）。该键不被当前模拟器版本读取，代理必须经启动参数或
Extended Controls 设置。

## 6. 验证方法

```bash
# 1) 看系统探测是否走通（经代理应出现 ret=204 与 Proxy-Connection 头）
adb logcat -d | grep PROBE
# 期望（代理生效）：PROBE_HTTP ... ret=204；无代理直连时为
#   SocketTimeoutException（且 DNS 常见污染地址 2001::1）

# 2) 宿主侧确认模拟器在连代理端口
netstat -ano | findstr "emulator" | findstr "10808"

# 3) 应用内真实验证：棋谱库页 → 下载棋谱库 → 应出现进度并最终重载出分类列表
```

## 7. 方案选择建议

| 场景 | 推荐方案 |
|------|----------|
| 应用内下载棋谱语料（Flutter/Dart 流量） | **方案 A**（`-http-proxy` 启动参数） |
| 日常使用模拟器上网/调试浏览器 | 方案 A 或 B（B 免命令行） |
| 临时给某个系统组件走代理做对比调试 | 方案 C（记得用完 `:0` 清除） |
| 希望每次启动自动带代理 | 方案 A + §2 启动脚本（bat） |

## 8. 注意事项

1. 代理客户端必须已在宿主运行，否则 guest 全部连接失败（比直连更糟）——
   排查顺序：宿主 `curl -x socks5h://127.0.0.1:10808 https://github.com` 通，
   再看模拟器侧。
2. `-http-proxy` 透明代理 TCP；UDP（如 QUIC/HTTP3）不走代理，个别应用可能
   回落或异常，属正常。
3. 方案 A 下 DNS 污染域名仍不可达（见 §2 局限）；如需彻底解决需在代理客户端
   开启远程 DNS/规则分流（超出模拟器配置范围）。
4. 真机没有等价的全机代理手段（Wi-Fi 代理设置同为方案 C 局限，Dart 不读），
   国内真机验证语料下载需依赖应用内镜像源或本地网络环境本身可达 GitHub。
