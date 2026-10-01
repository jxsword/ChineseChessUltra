# Android 模拟器命令行管理与 Root 指南

> 记录日期：2026-10-01　|　实测环境：Windows 11 + Android SDK `E:\dev\android-sdk`
> （无 Android Studio）+ AVD `Pixel_7_API34`（system-images;android-34;
> **google_apis**;x86_64）。文中标注 ✅ 的命令均在本机实测通过。
> 相关文档：`docs/android_env_handover.md`（环境总览）、
> `docs/android_emulator_proxy.md`（代理配置）。

## 1. 从命令行启动模拟器

```bash
# 基本启动（黑屏窗口 + GPU 自动）
E:\dev\android-sdk\emulator\emulator.exe -avd Pixel_7_API34 -gpu auto &

# 本项目常用完整参数（✅）
E:\dev\android-sdk\emulator\emulator.exe -avd Pixel_7_API34 \
  -no-snapshot -no-boot-anim -gpu auto
```

常用启动参数：

| 参数 | 作用 |
|------|------|
| `-avd <名称>` | 指定要启动的 AVD |
| `-no-snapshot` | 本次冷启动，不加载也不保存快照（调试时状态可预期，本项目默认用） |
| `-no-snapshot-save` | 加载快照但退出时不保存 |
| `-wipe-data` | 启动前清空 userdata（恢复出厂，慎用；需重新配置系统代理等） |
| `-no-boot-anim` | 跳过开机动画，加快启动 |
| `-gpu auto` | GPU 渲染模式（宿主有显卡即可；`-gpu swiftshader_indirect` 为纯软件兜底） |
| `-port 5556` | 指定控制台/adb 端口（默认从 5554 起，奇偶成对：5554=console，5555=adb） |
| `-writable-system` | 使 `/system` 可写（配合 `adb root && adb remount`，见 §4.2） |
| `-http-proxy <url>` | 全机 TCP 走代理，如 `socks5://10.0.2.2:10808`（详见 emulator_proxy 文档） |
| `-no-window` | 无窗口（CI/后台运行），配合 `-no-audio` |
| `-no-audio` | 禁用音频（无声卡/远程环境避免报错） |
| `-accel-check` | 不启动，仅检查硬件加速（本机 WHPX ✅ 可用） |
| `-list-avds` | 不启动，列出所有 AVD 名称 |

启动后等待系统就绪（✅，可放入脚本）：

```bash
E:\dev\android-sdk\platform-tools\adb.exe wait-for-device shell \
  'while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done; echo BOOTED'
```

## 2. 命令行日常管理（adb）

以下假设 `adb` 在 PATH 中（`E:\dev\android-sdk\platform-tools`）。

### 2.1 设备与应用

```bash
adb devices                        # 列出设备（emulator-5554 等，✅）
adb -s emulator-5554 <cmd>         # 多设备时指定目标
adb install -r app-release.apk     # 安装/覆盖安装（✅ -r 保留数据）
adb uninstall com.ssy.chinesechess.chinese_chess_ultra
adb shell pm list packages | grep chinesechess   # 查包名（✅）
adb shell am force-stop <包名>      # 杀进程（✅）
adb shell am start -n <包名>/.MainActivity       # 启动 Activity（✅）
adb shell monkey -p <包名> -c android.intent.category.LAUNCHER 1  # 启动主入口（✅）
```

### 2.2 文件读写

```bash
adb push 本地文件 /sdcard/xxx              # 宿主 → 设备
adb pull /sdcard/xxx 本地目录              # 设备 → 宿主
adb shell ls /storage/emulated/0/Android/data/<包名>/files/corpus   # ✅
# 注意 Git Bash 下设备绝对路径会被 MSYS 转换成本地盘符路径：
export MSYS_NO_PATHCONV=1   # 或整条 shell 命令加引号
```

### 2.3 输入注入与截屏（UI 冒烟常用，✅）

```bash
adb shell input tap <x> <y>            # 点击（物理像素坐标；1080x2400 屏）
adb shell input swipe x1 y1 x2 y2 <ms> # 滑动/拖拽
adb shell input text "abc123"          # 输入文本（仅 ASCII，不支持中文）
adb shell input keyevent 4             # 返回键；111=ESC、82=菜单
adb exec-out screencap -p > screen.png # 截屏到宿主（✅）
adb shell screenrecord /sdcard/x.mp4   # 录屏（Ctrl-C 结束后 adb pull）
```

### 2.4 日志与状态

```bash
adb logcat                     # 全量日志；-s flutter 只看 Flutter（✅）
adb logcat -d -t 200           # 先 dump 最近 200 行后退出
adb shell getprop sys.boot_completed    # 启动状态（✅）
adb shell dumpsys battery | head       # 电量/充电状态
adb shell wm size                       # 屏幕物理分辨率（✅ 1080x2400）
adb shell settings get global http_proxy        # 查系统代理（✅）
```

## 3. 模拟器控制台（emulator console）

每个模拟器实例开一个控制台 TCP 端口（默认 5554，奇数；下一个实例 5556，依此
类推）。经 adb 可直接发控制台命令，无需 telnet 登录：

```bash
adb emu kill            # 优雅关闭模拟器（✅ 比杀进程安全）
adb emu avd name        # 查询当前 AVD 名
```

更完整的控制台经 telnet 使用（首次需认证，token 在
`C:\Users\ysm\.emulator_console_auth_token`）：

```bash
telnet localhost 5554
auth <token 内容>
help                    # 全部命令
kill                    # 关闭
rotate                  # 旋转屏幕
snapshot list / save <名> / load <名> / del <名>   # 快照管理
gsm call 13800138000    # 模拟来电
sms send 13800138000 hello
sensor set acceleration 0,9.81,0   # 传感器注入
geo fix 116.39 39.90    # 注入 GPS 坐标
```

多实例管理：`emulator -list-avds` 列出全部 AVD；同时启动多个实例时用 `-port`
错开端口，adb 用 `-s emulator-<端口-1>`（console 端口 5556 的实例 adb 端口是
5557，`adb devices` 里显示为 `emulator-5554`/`emulator-5556`…）。

AVD 生命周期（avdmanager，✅）：

```bash
AVDM="E:\dev\android-sdk\cmdline-tools\latest\bin\avdmanager.bat"
"$AVDM" list avd                          # 列出（✅）
"$AVDM" create avd -n Pixel_7_API34 \
  -k "system-images;android-34;google_apis;x86_64" -d pixel_7   # 创建（✅）
"$AVDM" delete avd -n <名称>               # 删除
# AVD 数据目录：C:\Users\ysm\.android\avd\<名称>.avd\
#   config.ini（硬件配置）、userdata*.img（数据，wipe-data 即删这些）
```

## 4. Root 相关

### 4.1 模拟器支持 root 吗？——支持（分镜像类型）

| 镜像类型 | `adb root` | 说明 |
|----------|-----------|------|
| AOSP（`default`） | ✅ 可 root | 无 Google 服务 |
| **google_apis**（本项目使用） | ✅ **可 root** | 有 Google 服务、无 Play 商店；`adb root` 直接把 adbd 以 root 重启，**无需 Magisk/刷机** |
| google_apis_playstore | ❌ 不可 root | 有 Play 商店，`adb root` 报 "adbd cannot run as root in production builds"；此镜像刻意锁死 |

即：**模拟器 root 是官方特性**（google_apis/AOSP 镜像出厂即带 su 上下文），
不存在"如何给模拟器刷 root"的问题，只有"如何用"。

### 4.2 root 基本操作（✅ 本机实测）

```bash
adb root        # "restarting adbd as root" → 之后 adb shell 即 root（✅）
adb shell whoami   # root（✅ uid=0）
adb unroot      # 恢复非 root adbd（✅）
```

root 后能做什么：读 `/data/data/<包名>/`（release 应用私有目录）、
`settings put`、调试助手进程、访问全部 `logcat` 缓冲等。例：

```bash
adb root && adb shell "ls /data/data/com.ssy.chinesechess.chinese_chess_ultra/cache"
```

### 4.3 修改 /system 分区（-writable-system + remount，✅ 实测完整流程）

`/system` 默认只读 + dm-verity 保护。**修改它必须在启动模拟器时加
`-writable-system`**，且首次需要 disable-verity + 重启一次：

```bash
# 1) 带 -writable-system 启动（注意：-writable-system 与 -no-snapshot 同用，
#    改过 /system 的状态不要保存快照，避免镜像不一致）
emulator -avd Pixel_7_API34 -no-snapshot -writable-system ...

# 2) root 并关闭 verity，然后重启模拟器（仅首次需要）
adb root && adb disable-verity && adb reboot
#    （✅ 输出 "Successfully disabled verity"；直接 remount 会报
#     "could not map scratch image"，必须先重启一次才生效）

# 3) 重启完成后：root + remount
adb root && adb remount
#    （✅ 输出 "Remounted /system as RW"）

# 4) 验证写入（✅ WRITE_OK）
adb shell "touch /system/test_write && rm /system/test_write && echo WRITE_OK"
```

注意事项：

- 不加 `-writable-system` 时 `adb remount` 报
  **"Device must be bootloader unlocked"**（✅ 实测），且即使 remount 成功
  `/system` 仍是只读。
- `disable-verity` 的状态持久保存在 userdata 中；恢复出厂（`-wipe-data`）
  即回到默认。
- 修改 `/system` 后**不要保存快照**（`-no-snapshot` 启动可规避），否则快照与
  system 镜像可能不一致导致启动异常。
- 玩完记得 `adb unroot`；普通验证用不到改 /system，root 即可满足绝大多数需求。

### 4.4 什么情况才需要 root？

本项目至今的验证（冒烟 a-h）全部用**非 root**完成；root 的典型用途：

- 查看应用的 `/data/data` 私有目录（数据库/SharedPreferences 实况）；
- 卸载系统级残留、注入测试证书（抓 HTTPS 包时放根证书）；
- 修改系统配置文件（hosts 等）。

## 5. 快速排障

| 症状 | 处理 |
|------|------|
| `adb devices` 里是 `offline` | `adb kill-server && adb devices` 重连；仍不行则重启模拟器 |
| 启动卡在黑屏 | 确认 `-accel-check` 通过（WHPX）；去掉 `-no-snapshot` 改冷启动 |
| `adb emu kill` 无响应 | 检查 `C:\Users\ysm\.emulator_console_auth_token` 存在；或任务管理器结束 qemu 进程 |
| 端口被占（5554/5555） | 残留 qemu 进程未退出；`-port 5556` 换端口 |
| remount 报 scratch 映射失败 | 未按 §4.3 顺序：`disable-verity` 后必须重启再 remount |
| 模拟器联网失败 | 看代理文档；直连失败是网络环境问题，不是模拟器故障 |
