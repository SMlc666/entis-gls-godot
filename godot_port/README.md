# EntisGLS Godot Runtime

Godot 上的 Cotopha/EntisGLS 兼容性移植原型。当前开发重点是 Linux；原始 `.noa` 和 `yosuga.csx` 以只读方式加载，资源暂存只写入副本。

## 当前状态

- **Linux**：已实现 NOA/VFS 读取、进程内 ERISAN/ERI/MIO 解码、CSX VM 与 ADV 播放器。原生扩展缺失或不支持输入时，Linux helper 提供有限回退。标题、设置、存档和鉴赏仍以 smoke test 覆盖的行为为准，不代表所有游戏流程已经完整复现。
- **Android**：工程包含 Android 导出预设、资源打包脚本和 ERISAN/ERI/MIO GDExtension 构建脚本。当前没有经过 Android 原生库构建、APK 导出、设备安装或完整剧情验证；Android 播放链仍未闭合。
- **资源格式**：游戏资源不会被改写。给 APK 暂存资源会复制原文件并验证复制前后的 SHA-256。

## Linux 启动

从工作区根目录使用启动脚本：

```sh
./play.sh --title
./play.sh --game
./play.sh --inspector
```

也可以直接指定自己的游戏目录。播放器会读取显式路径、`YOSUGA_GAME_DIR`、`res://assets` 或 `user://game`：

```sh
godot --path godot_port res://scenes/adv_player.tscn -- \
  --title --game-dir "/path/to/YosugaGame"
```

也可不传目录参数，改用环境变量：

```sh
YOSUGA_GAME_DIR="/path/to/YosugaGame" godot --path godot_port
```

`--scenario 00_A020` 可从指定剧本启动。脚本入口和参数详见 [工作区启动脚本](../play.sh)；桌面快捷方式位于 [yosuga.desktop](../yosuga.desktop)。这些文件位于工作区根目录，不属于 `godot_port/`。

资源检测器：

```sh
./play.sh --inspector
```

## 将原始资源放进 Android 项目

将游戏文件无损复制到 `assets/`：

```sh
cd godot_port
./tools/stage_game_assets.sh "/path/to/YosugaGame"
```

脚本只复制需要的 `.noa` 和 `.csx` 文件；如果目标已有不同内容，会停止并要求显式传入 `--force`。脚本会检查每个目标文件的哈希，并再次检查源文件没有变化。它不解包、不转换源文件。

暂存后可从 `godot_port/` 根目录复核副本：

```sh
sha256sum --check assets/STAGED_GAME_ASSETS.sha256
```

资源暂存会复制约 2 GiB 文件（实际大小取决于游戏发行版）。请先确认 APK 体积和设备存储预算；原版归档不会自动进入仓库，暂存后的 `assets/` 由使用者自行管理。

## Android 导出脚手架

工程带有 [Android ARM64 导出预设](export_presets.cfg)。需要在 Godot Editor Settings 配置 Java SDK 与 Android SDK，并安装匹配的 Godot 导出模板。当前预设只启用 ARM64，并将 `.noa`、`.csx` 和 CP932 `.tbl` 文件加入导出。

**该预设不等于 Android 已支持。** 当前工作区没有 Android 原生 codec 库；本机只有 Android `platform-tools/adb`，没有用于扩展构建和 APK 导出的完整 SDK/NDK 工具链、Java SDK 或 Godot 导出模板。因此这里尚不能导出可运行 APK。codec 和真机状态以 [Android 状态文档](docs/android-porting.md) 为准。

## 原生 Codec 构建

`tools/build_codec_extension.sh` 会将固定版本的 `arc_unpacker`、`godot-cpp` 源码和 CMake 构建树保存在项目外的 `../reference-sources/`，Linux 运行库安装到 `tools/bin/linux/`。Linux 原生构建支持 x86_64 与 ARM64；源码和构建树可用 `YOSUGA_REFERENCE_ROOT`、`YOSUGA_CODEC_SOURCE_DIR`、`YOSUGA_CODEC_BUILD_DIR` 改变位置；Android 构建使用同一组持久化源码，构建树可用 `YOSUGA_ANDROID_CODEC_BUILD_DIR` 指定。构建脚本不会把参考 SDK 源码复制进 Godot 项目，也不会把编译过程丢在 `/tmp`。

构建后用 `./tools/verify_linux_runtime.sh` 校验架构、入口符号和哈希，再运行 `godot --headless --audio-driver Dummy --path . --script res://tests/native_codec_smoke.gd` 验证扩展加载与 GDScript 接口。

MEI open 与 I/P/B 单帧解码都按输入、音频 chunk/PCM、图像和索引元数据估算 live working set，并在估算超过 256 MiB 时拒绝解码。MIO 输入副本按其实际生命周期分阶段估算；section table 最多接受 32,768 条。该值是 **estimated live working set**，不是 RSS 硬限制；allocator/RSS overhead、碎片和进程内其他资源不包含在估算中。

## 命令行回归

依赖游戏文件的 smoke test 使用本地资源目录，例如：

```sh
godot --headless --audio-driver Dummy --path godot_port \
  --script res://tests/native_title_player_smoke.gd -- \
  "/path/to/YosugaGame"
```

不需要商业资源的 VM/解析器 fixture 可以独立运行：

```sh
godot --headless --audio-driver Dummy --path godot_port \
  --script res://tests/vm_safety_smoke.gd
```

存档 smoke 使用独立的 `user://test_saves/` 目录，不应写入正式 `user://saves`。原始游戏归档应在涉及资源验证的操作前后保持相同 SHA-256。

## 构建 Linux 辅助程序

```sh
YOSUGA_DEPS_PREFIX=/path/to/dependencies/usr \
  ./tools/build_arc_unpacker.sh
```

Linux helper 的构建输出放在非隐藏目录 `tools/bin/linux/`。Godot 能将这些文件纳入资源导出，但 PCK 中的副本不是操作系统可执行文件；外部 sidecar 限制见下文。依赖来源和许可证记录见 [LICENSES.md](LICENSES.md)。

### Linux 导出包与外部辅助程序

`erisan_decode` 是仅在原生 ERISAN 解码不可用时使用的 Linux 回退 ELF；正常播放优先使用进程内 GDExtension。`arc_unpacker` 不再是 ERI/MIO 播放回退，只供可选的 `native_codec_differential_smoke.gd` 做参考对照。需要 sidecar 时，运行时从开发目录的 `tools/bin/linux/`、独立导出程序旁的 `tools/bin/linux/`，或 `YOSUGA_ERISAN_DECODER` 指定的绝对路径解析 `erisan_decode`；找不到时相应回退会明确失败。

PCK 中的 `res://` 资源不会自动解包成可执行文件。工程目前没有 Linux 导出 preset 或 sidecar 自动部署流程，也没有验证“导出为 PCK 后运行外部 ELF”的闭环。若由系统 Godot 加载独立 PCK，请把 helper 放在普通文件系统路径，并显式设置对应环境变量；不能依赖 `globalize_path("res://...")` 将 PCK 内容转换为可执行路径。
