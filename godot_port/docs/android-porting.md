# Android 移植状态与操作说明

本文说明当前 Android 交付脚手架和未完成项。项目仍以 Linux 开发为主；添加 export preset 不表示 Android APK 已经可用。

## 当前状态

| 部分 | 当前状态 |
|---|---|
| 资源打包 | 支持将原始 .noa 与 yosuga.csx 无损复制到 assets/；导出 preset 显式包含这两类文件和 CP932 `.tbl` 表。 |
| 横屏 | project.godot 设置 display/window/handheld/orientation=0（横屏）。 |
| Godot 主场景 | 指向 ADV 播放器；资源来源可为显式游戏目录、环境变量或工程内资源。 |
| Android 导出 preset | 有 ARM64 脚手架；尚未在此环境完成导出。 |
| 原生 codec | GDExtension 源码包含 ERISAN、ERI、MIO 进程内入口，Android 构建脚本固定使用 NDK r28b；本地 Android `.so` 尚未生成/验证。 |
| 触屏交互 | 当前 ADV 推进与全屏 CG 交互监听鼠标按钮；没有显式触屏/手势输入处理，也未完成 Android 设备验证。 |
| APK/AAB 安装和完整剧情 | 尚未验证。 |

## 暂存原版资源

在 godot_port/ 下运行：

    ./tools/stage_game_assets.sh "/path/to/YosugaGame"

脚本要求源目录中存在以下文件：

    data1.noa
    data2.noa
    sound.noa
    voice.noa
    system/frame.noa
    system/option.noa
    system/title.noa
    system/yosuga.csx

它只复制、不解包、不转码源文件；对已有不同内容默认中止，只有显式传入 --force 才会覆盖工程内暂存副本。复制前后逐文件核对 SHA-256，并确认源文件哈希没变化。清单写在 assets/STAGED_GAME_ASSETS.sha256。

从 `godot_port/` 根目录复核暂存副本：

    sha256sum --check assets/STAGED_GAME_ASSETS.sha256

大部分游戏发行版包含约 2 GiB 的归档，尤其 voice.noa。把这些归档放进 PCK 会明显增大 APK/AAB；目前工程没有分包或按需下载流程。原始资源应由用户自行提供，本仓库不自动复制商业数据。

## Godot Android 设置

工程包含 export_presets.cfg 中名为 Android ARM64 (scaffold) 的预设。Godot Editor Settings 需要配置 Java SDK 和 Android SDK，并安装与本地 Godot 版本匹配的导出模板。官方 Android 导出要求和 SDK 配置见 [Godot Android 导出文档](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html)。

导出前还必须同时满足：

1. 对应架构的 android/libs/<ABI>/libyzk_codec.so 已构建并包含在工程里。
2. .gdextension 指定的入口符号在该库中存在，且库已通过 Godot 进程内加载和 GDScript 调用验证。
3. Entis .noa 压缩条目、ERI 图像、MIO 音频都能在 Android 不依赖 Linux 外部子进程的情况下解码。
4. 从 PCK 资源启动标题，完成剧情/分支/音频/存档读回的真机流程。

## 构建 Entis Android GDExtension

`tools/build_android_codec.sh` 从固定的 `arc_unpacker` 与 `godot-cpp` 提交构建包含 ERISAN、ERI 图像及 MIO 音频入口的原生扩展，目标 ABI 为 `arm64-v8a`、`armeabi-v7a`、`x86_64`。脚本读取 NDK 安装目录的 `source.properties`，只接受 NDK r28b `28.1.13356709`；并要求 PATH 上的 CMake 版本不低于 3.18。Godot 4.7 导出文档列出的 SDK CMake 包为 3.10.2.4988404，单独安装该版本不能满足此扩展构建脚本的最低版本要求。固定源码、ABI 构建目录和编译产物默认保存在项目外的 `../reference-sources/`；可通过 `YOSUGA_REFERENCE_ROOT`、`YOSUGA_CODEC_SOURCE_DIR` 和 `YOSUGA_ANDROID_CODEC_BUILD_DIR` 指定持久目录。脚本会在每个 ABI 目录生成 `libyzk_codec.so` 和 `SHA256SUMS`。

示例（将路径改为本机 NDK r28b 的安装目录）：

    cd godot_port
    ANDROID_NDK_HOME="/path/to/android-ndk/28.1.13356709" ./tools/build_android_codec.sh

构建后源码和 CMake 中间产物保留在项目外的持久目录，Android `.so` 会安装到项目的 `android/libs/<ABI>/` 供 PCK 导出。可复核每个 ABI 的扩展：

    for abi in arm64-v8a armeabi-v7a x86_64; do
      (cd "android/libs/$abi" && sha256sum --check SHA256SUMS)
    done

脚本依赖可用的 CMake、Git 和网络访问，会编译 ERISAN、ERI 和 MIO 三个进程内方法。Android export preset 目前只选择 ARM64，所以另外两个 ABI 不会被这个 preset 使用。该构建脚本不是 APK 导出脚本；本工作区尚无 Android 库产物，也没有 Android 环境下的 GDExtension 加载或实际解码验证。

Godot 4.7 的完整 Android 导出还需要 Android SDK、Java SDK 和匹配的导出模板。当前机器只有 `/usr/lib/android-sdk/platform-tools/adb`，缺少 cmdline-tools、platforms、build-tools、NDK r28b、Java SDK 和 Godot 导出模板；因此没有 APK 导出、设备安装或剧情验证结果。Android SDK 包版本要求见 [Godot 4.7 Android 导出文档](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_android.html)；其 NDK r28b 版本与本项目扩展构建检查一致。Linux 的 `tools/build_arc_unpacker.sh` 只构建 Linux helper 和 GDExtension。

## 编解码器接口要求

Linux 开发机可运行 `tools/verify_linux_runtime.sh` 复核扩展 ELF 架构、入口符号、哈希清单与 CP932 表内容。`tools/build_codec_extension.sh` 和 `tools/build_arc_unpacker.sh` 均会在安装产物后重写 Linux 清单，避免仅更新扩展后遗留旧哈希。

tools/yzk_codec.gdextension 声明的入口符号、原生库实际导出的符号和库路径必须一致，并在 Godot 中完成加载与 GDScript 调用验证。GDExtension 初始化成功本身不足以证明解码方法可用；还需确认 ERISAN、ERI 图像和 MIO 音频路径都使用可用的运行时实现。

Android 运行时不得依赖 OS.execute() 调起 Linux ELF。Android preset 排除 `tools/bin/linux/*`，并包含 CP932 `.tbl`；GDScript 解码器在加载到原生扩展时优先走 ERISAN、ERI 与 MIO 进程内路径，但 Android `.so` 尚未构建和验证，因此不能据此宣称 Android 解码已可用。资源暂存脚本不复制 `.mei` 视频；当前播放代码从 `game_dir` 的文件系统路径读取 MEI。Android 上游戏目录的提供方式、文件访问权限以及 MEI 可访问性尚未实现或验证，不能假设视频会随 PCK 自动打包。

## Android 验收清单

在干净环境构建并在真实设备上验证：

- 从资源包安装后启动标题，不依赖开发机绝对路径。
- 读取 .noa 中压缩内容，确认解码结果与 Linux 相同。
- 展示一张 ERI 图片，并播放 BGM、SE 和角色语音。
- 完成标题、剧情、选项分支、存档、杀进程后读档。
- 确认横屏、单指推进、弹窗返回、长时间翻阅 CG 的内存占用。

在以上项目通过前，README 和发行说明都应将 Android 标为“脚手架/待验证”，而不是“已支持”。
