# Linux / Ubuntu 构建 FAQ（Flutter Linux 桌面版）

> 记录日期：2026-10-04　|　实测环境：WSL Ubuntu 26.04 (resolute) + Flutter 3.44.2 stable
> （`/home/ssy/development/flutter`）+ CMake 4.4.3（apt 与 pip 同版本）+ Clang 21
> （apt.llvm.org `llvm-toolchain-resolute-23`）。文中标注 ✅ 的命令均在本机实测通过。
> 相关文档：`docs/vm_ubuntu_macos_test_env.md`（环境总览）。
> 本文档汇总 `flutter run / build -d linux` 在本机遇到的 3 个环境问题及解决方案。

## 0. 环境速览

| 组件 | 版本 | 说明 |
|------|------|------|
| Flutter | 3.44.2 stable | `/home/ssy/development/flutter` |
| CMake | 4.4.3 | Ubuntu 26.04 自带即为 4.4.x，`/usr/bin/cmake` 与 pip 版同为 4.4.3 |
| Clang | 21 | 新版 Clang 对 C++ 弃用写法更严格 |
| 构建目标 | Linux desktop (x64) | `flutter run -d linux` |

## 1. 缺少 libsecret-1 开发包 → CMake 配置阶段报错

**现象**

```text
CMake Error at .../Modules/FindPkgConfig.cmake:1093 (message):
  The following required packages were not found:
   - libsecret-1>=0.18.4
```

**原因**

`flutter_secure_storage_linux` 插件的 CMake 用 `pkg_check_modules(LIBSECRET REQUIRED ... libsecret-1>=0.18.4)` 检测系统密钥环（libsecret）开发包；未安装时 pkg-config 找不到对应的 `.pc` 文件，整个 CMake 配置阶段直接失败。

**解决（✅）**

```bash
sudo apt update
sudo apt install libsecret-1-dev libjsoncpp-dev
```

`libjsoncpp-dev` 是同一插件 CMake 中 `find_package(jsoncpp)` 所需。Flutter Linux 其余工具链依赖为 `clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev`（本机已装，无需重复安装）。

## 2. Clang 21 弃用告警被 -Werror 升级为编译错误（json.hpp）

**现象**

```text
.../flutter_secure_storage_linux/linux/include/json.hpp:24392:35: error:
identifier '_json' preceded by whitespace in a literal operator declaration
is deprecated [-Werror,-Wdeprecated-literal-operator]
（24400 / 24464 / 24465 行同类，针对 _json_pointer）
```

**原因**

`flutter_secure_storage_linux` 1.2.3 内置 nlohmann/json **3.11.2** 单头文件，字面量运算符写成旧式 `operator "" _json`（声明中标识符前有空格）。Clang 16+ 默认开启 `-Wdeprecated-literal-operator` 告警；而 Flutter Linux 模板通过 `APPLY_STANDARD_SETTINGS` 给每个插件目标追加 `-Wall -Werror`，告警即被升级为硬错误。

**解决（✅，两层任一层即可）**

1. 项目级兜底：`linux/CMakeLists.txt` 的 `APPLY_STANDARD_SETTINGS` 中追加 `-Wno-deprecated-literal-operator`（只关闭该条告警，不弱化其他告警；项目内持久生效）。
2. 根因修复：按上游 nlohmann 3.11.3 的官方改法，去掉字面量运算符声明中的空格（共 4 处）：

```bash
sed -i 's/operator "" _json/operator""_json/g' \
  ~/.pub-cache/hosted/pub.flutter-io.cn/flutter_secure_storage_linux-1.2.3/linux/include/json.hpp
```

- 本机 PUB_HOSTED_URL 走 `pub.flutter-io.cn` 镜像；官方源路径则为 `~/.pub-cache/hosted/pub.dev/...`。
- ⚠️ 该文件位于 pub 缓存内：插件升级或 `flutter pub cache` 清理后会还原，届时 CMake 标志是持久兜底。
- 治本方案：升级 `flutter_secure_storage` 到内置新版 json.hpp 的版本（当前 11.x 与项目依赖约束不兼容，未升级）。

## 3. CMake 4.x 安装前缀守卫失效 → install 阶段 Permission denied

**现象**

```text
CMake Error at cmake_install.cmake:66 (file):
  file INSTALL cannot copy file ".../intermediates_do_not_run/chinese_chess_ultra"
  to "/usr/local/chinese_chess_ultra": Permission denied.
```

**原因**

Flutter Linux 模板依靠 `CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT` 变量判断"安装前缀仍是默认值"，命中时把前缀重定向到 `build/linux/x64/debug/bundle`。**CMake 4.x 不再设置该内部变量**（4.4.3 实测 CMakeCache.txt 中无此项），守卫条件恒为假，前缀保持 `/usr/local`，普通用户无写权限，install 阶段失败。

**解决（✅）**

修改 `linux/CMakeLists.txt` 的守卫条件，兼容新旧 CMake：

```cmake
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT OR CMAKE_INSTALL_PREFIX STREQUAL "/usr/local")
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()
```

## 4. 验证

```bash
flutter build linux --debug   # ✅ ✓ Built build/linux/x64/debug/bundle/chinese_chess_ultra
flutter run -d linux          # ✅ 正常启动
```

bundle 产物结构：`build/linux/x64/debug/bundle/{chinese_chess_ultra, data/, lib/}`。

## 5. 遗留说明

- `pubspec.lock` 在构建时被 pub 重新解析改写（非手动改动），未随本次提交。
- 本次涉及的仓库改动：`docs/linux_ubuntu_build_faq.md`（本文）、`linux/CMakeLists.txt`（§2、§3 两处）。
