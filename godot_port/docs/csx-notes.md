# CSX 调研记录

这份游戏目录中的 `system/yosuga.csx` 使用 `Cotopha Image file` 头。只读索引读到 `image`、`function`、`global`、`data`、`conststr`、`linkinf` 六个区段，其中有 780 个命名函数、321 个初始化地址。文件声明的内容之后还有 521,638 字节的零填充；解析器以头部声明的长度为边界。这些数字对应当前本地副本，其他版本可能不同。

公开的 [yosugano](https://github.com/Senko-heart/yosugano) 反编译器以《缘之空》原版 CSX 为主要目标。对本地脚本的隔离副本试运行后，它生成了 323 个源码文件；这证明工具能够处理该文件，尚未证明生成代码的行为完整。生成内容没有放入本项目。

另对 [Aether 1.1.0 的 EntisGLS 运行时](https://github.com/AetherKiri/EntisGLS-SDL3/blob/aether/aether_runtime/README.md)做了 Linux 无界面试验：使用游戏副本和手写启动配置后，运行时打开了归档并读取 CSX，但日志报告 `Legacy InitializeContext failed: aborted (ip=0x00000049)`。其 smoke 脚本仍以成功状态退出，因此不能把该退出码当成游戏启动成功。此结果只说明本次配置未能运行，不代表所有启动配置或后续版本都不兼容。

`csx_index.gd` 读取区段和函数表，`csx_bytecode.gd` 解码 image 区段的指令及操作数。指令布局参考了 [yosugano 的解析器](https://github.com/Senko-heart/yosugano/blob/fede9021bcb03adf10e0a2e492f40326828f77f7/src/parse.rs)。当前本地脚本完整扫描得到 1,414,381 条指令；命名函数和初始化地址均落在指令边界。

## 虚拟机与执行语义调研

1. **执行生命周期**：
   - 启动首先串行执行 321 个 `@Initialize` prologue 块，初始化全局对象与基础映射。其中在 0x0211DD 处设置 `global[9]`（`BUSTUP_XPOS`）为 `[0, 0, 80, 160, 240, 320, 400, 480, 560, 640, 720, 800]`。
   - `Initialize()`（@ 0x007288）加载或初始化系统存档 `system.dat` 和配置文件 `config.dat`，挂载 UI 皮肤 `frameSkin`。
   - `SetupAdvScreen()`（@ 0x009373）初始化 ADV 画布与文本层。
   - `ScenarioLoop(func)`（@ 0x008F83）作为场景驱动主循环，依据 `global[4]`（`scObj`）的 `scenarioCall` 动态调用对应场景函数（如 `sc00_Z000`、`sc00_Z005` 等）。

2. **立绘管线（BustupManager）**：
   - 全库 2,420 个 ERI 资源经扫描全部为独立完备的 32 位 RGBA8 图像，无需底图参考合成。
   - 立绘插槽定位由 `BustupManager::adjustPosition` 动态分配屏幕中心坐标（如单人居中为 X 320 / Center 400）。
   - 角色立绘参考原点由 `ptRevCenter`（通常为 `(width/2, height - 50)`）确定，Godot 中以 `Vector2(spr.position.x - ox, spr.position.y - oy)` 计算左上角渲染坐标。
   - EntisGLS 透明度规则：`nTransparency = 0` 表示完全不透明（alpha = 1.0），`256` 表示完全透明（alpha = 0.0）。

3. **选项分支（Choices）**：
   - `AddSelect` 往 `global[10].selectItem` 注册分支选项文本。
   - `StartSelect` 触发分支展示，通过返回值赋值给 `global[10].selectResult`，驱动场景进入对应分支剧情。

4. **存档与读档（Save / Load）**：
   - 原生 CSX 提供 `File` 类，`SaveObject(path, object)` 打开文件并序列化传入的 `CsxInstance`（`global[4]` 为场景数据，`global[6]` 为系统数据）。
   - `File::Open` 成功返回 0（符合 C 规范 0=OK），失败返回非 0 错误码；条件跳转（`op7`）依据条件 0 进行错误分支短路。
   - 存档文件存放于 `user://saves/` 下，支持生成 120x90 预览缩略图，在重新启动游戏时自动恢复系统设置（`gameClear`、已读文本标记等）及场景状态。
   - 常规存档 `NormalSave(id, hideSpr, showSpr)`（1 <= id <= 60）序列化生成 `Save%03d.dat` 与 `Save%03d.png`，并同步更新全局 `sysObj.bookmark[id]`（包含 `fSave = -1`、`comment` 对话截取与 `Time` 结构体：年/月/日/时/分/秒），最后保存 `system.dat`。
   - `NormalLoad(id)` 读取对应的 `Save%03d.dat` 并反序列化 `scObj`，重置 `isLoad = -1`，重启 `ScenarioLoop` 即可直接从存档点无缝续播。

5. **标题画面系统（Title Screen）**：
   - 原版标题画面入口 `Title()`（@ 0x025EEB），使用 `titleSkin` 挂载 `system/title.noa`。
   - 画面资源包含 800x600 背景 `FRM_0611.eri`、Logo `FRM_0612.eri`（坐标 223, 95）、副标题 `FRM_0613.eri`（坐标 511, 171）及原版标题曲 `BGM07.mio`。
   - 播放器在 `--title` 冷启动或游戏中返回标题时，逐帧运行原版 `Title()`；Godot 将 `HostWindow.root_sprites` 递归映射到 800x600 参考画布，保留原始位置、尺寸、纹理、透明度和层级，按钮按原 `ID_*` 命令回送给 `GetCommand`。
   - headless smoke 已验证新档 `Title()` 的四个原版命令（`ID_START`、`ID_CONTINUE`、`ID_CONFIG`、`ID_EXITGAME`）、`ID_START` 进入 `ScenarioLoop("00_Z000")`，以及 `ID_CONFIG` 打开原版 `ConfigWindow`、显示 532x552 原生页、回送 BGM 滚动条的 `ncTracking` 值，并通过原版确认窗返回标题。皮肤还定义五项的 `ID_PAGE_MENU_FULL`，但当前新档实际使用 `ID_PAGE_MENU`；完整菜单/鉴赏解锁条件尚未验证。原版 `Appreciation()` 作为独立 CSX 界面可启动，回想标签、CG 项与 BGM 曲目按钮会回送到 CSX 循环；点选 `ID_BGM21` 已验证原版逻辑切换至 `BGM02_S.mio`。静音切换、配置值持久化、角色语音细节、CG 打开/差分、跨页及回想播放仍需逐项回归。

6. **色调滤镜着色器（ToneFilter Shaders）**：
   - 游戏脚本调用 `AdvScreen::setToneFilter` 或 `HostToneFilter` 设置画面色调。
   - Godot 端通过 CanvasItem 实时 Shader 实现四种滤镜模式：`NORMAL`（0：原始色彩）、`SEPIA`（1：复古棕褐回忆）、`MONO`（2：黑白单色灰度）、`NEGATIVE`（3：颜色反相负片）。
   - 色调滤镜统一作用于当前背景图及立绘图层，支持动态插值平滑切换。

7. **原生 MEI 视频播放（Movie Playback）**：
   - `tools/yzk_codec.cc` 在进程内解码 Entis MEI 音频及 ERI 图像帧，处理 I/P/B 帧、半像素运动矢量和重排；原始 `.mei` 文件只读。`opening.mei` 实测为 800x600、声明 2521 帧/126 秒，包含 2520 条帧记录（582 I、259 P、1679 B），音轨为 44.1 kHz 立体声 16 位 PCM。
   - `MovieSprite` 已实现打开并查询帧数/时长、播放、随机 seek、停止后保留解码资源、关闭释放资源；播放模式支持 SDK 的 loop、no-skip-frame 与 no-loop-filter 标志。视频和音频按媒体时钟播放，慢帧时普通模式追时钟，no-skip-frame 模式逐帧清空积压。
   - 对照 Entis SDK 的 `eriImageFilterLoop421` 移植了 operation-table `0x08` 的局部滤波、`0x04` 的全帧滤波，以及 `UseLoopFilter` 强制全帧滤波和 `NoLoopFilter` 优先关闭的播放标志。滤波后显示像素存于独立结果，P/B 预测继续使用未滤波参考帧。原版 `opening.mei` 的 operation table 为 0、1、3，游戏调用带 `NoLoopFilter`，因此原片保持未滤波结果。测试以原片隔离副本核对 I/P/B、标志优先级与参考帧保持；其他 MEI 内容仍未逐像素覆盖。
   - 若找不到原生 `.mei`，仍尝试 `VideoStreamPlayer` 播放 `.ogv`；没有可用视频时安全跳过。`mei_codec_smoke.gd`、`mei_playback_smoke.gd` 和 `bustup_smoke.gd` 使用真实游戏资源验证解码、帧序、模式和生命周期；集成测试会核对 CSX/NOA 原始文件未改变。

8. **CG 鉴赏与全屏差分查看器（Appreciation / Gallery）**：
   - 逆向分析与梳理 `data1.noa` 与 `data2.noa` 中的全量事件 CG：共 273 个 ERI 图像，归纳为六大角色场景系列：`EA`（春日野 穹，16 场景 / 53 差分）、`EB`（依媛 奈绪，15 场景 / 41 差分）、`EC`（天女目 瑛，14 场景 / 48 差分）、`ED`（渚 一叶，15 场景 / 43 差分）、`EE`（初佳 / 梢，15 场景 / 46 差分）、`EZ`（剧情共通，4 场景 / 42 差分），共 79 个独立 CG 场景。
   - 界面实现 4 列卡片网格分页浏览，支持动态解码卡片缩略图；点击进入全屏查看器，支持鼠标点击、左右方向键或空格顺逆循环浏览差分变体。
   - 内置“全解锁”模式自由切换开关，兼顾完整浏览与剧情探索体验。

9. **音乐回想点唱机（BGM Jukebox）**：
   - 从 `sound.noa` 中提取并索引全部 22 首原版 BGM（`BGM01.mio`～`BGM21.mio` 与 `BGM02_S.mio`）。
   - 界面配备日文原名与中文译名展示、曲目列表即点即播、切歌、暂停/继续/停止控制及音量实时滑块。

10. **Android 平台支持与移动端包内资源架构**：
    - 针对移动沙盒不支持外部独立进程启动的限制，设计了 C ABI 原生共享库 `libyzk_codec.so`（`tools/yzk_codec.cc`）与 `tools/yzk_codec.gdextension`。
    - 结合 Godot 的虚拟文件系统（VFS），支持将未解包、未修改的 `.noa` 原版资源直接置于应用包内（`res://assets/`）或沙盒目录（`user://game/`）进行零拷贝流式读取，彻底杜绝外置解包或格式破坏。

11. **方案 B：EntisGLS 原生 UI 皮肤与表单页面引擎（system.inf & CreateFormPage）**：
    - **UI 定义体系**：原版游戏界面并非硬编码，而是通过各资源包根目录下的 `system.inf`（XML 格式）定义。其中 `title.noa` 定义标题菜单页面，`frame.noa` 定义 ADV 对话框、快捷操作条及选择支，`option.noa` 定义存读档与配置窗口。
    - **XML 皮肤解析器**：`HostResourceManager` 挂载归档后自动扫描并解析 `<resource>`（图像资源映射）、`<declare_style>`（按钮不同状态坐标及字体样式）与 `<page>` / `<window>`（控件排布）。
    - **表单页面构建（CreateFormPage）**：解析 `image="ID_RES:RECT(x,y,w,h)"` 坐标表达式，从图集中提取裁切区域生成独立子纹理，并自动生成具备 `normal`（常规）、`focus`（悬停）与 `pushed`（按下）原版质感状态的 `HostSprite` 控件树。
    - **事件循环闭环（GetCommand & FlushCommandQueue）**：CSX 主循环（如 `Title()` @ 0x025EEB、`Starting()` @ 0x0250CA）通过 `GetCommand` 轮询 UI 事件；宿主将交互事件推入队列，触发对应按钮 ID（如 `ID_START` 赋值 1 返回并驱动 `ScenarioLoop("00_Z000")`）。
    - **对话框与底部快捷菜单（MessageFrame::create）**：逆向 CSX 字节码（0x2A7A8 与 0x2E510），对齐原版 750x152 对话框底图（`FRM_0101.eri`）、说话人（27, 8）、正文（39, 38）、右侧语音重听（689, 6，`FRM_0105.eri`）、关闭/隐藏（727, 7，`FRM_0119.eri`）及底部（9, 124）8 个 84x25 原生按钮（`ID_PAGE_ADV_MENU`：快存、快读、存档、读档、设置、自动、快进、历史）。
    - **原生设置面板（ConfigWindow::create）**：解析 `ID_PAGE_CONFIG`（`FRM_0201.eri`，532x552），对齐窗口模式/全屏按钮、BGM/SE/系统/语音原生音量滑块（`FRM_0221.eri` 轨道、`FRM_0222.eri` 滑块）、静音勾选框（`FRM_0217.eri`）、返回标题（`ID_TITLE`）及语音细节设置入口（`ID_VOICE_DETAILS`，`FRM_0204.eri`）。
    - **原生角色独立语音音量控制（ConfigWindow::voiceDetails）**：逆向 CSX 0x38AE6，解析 `ID_PAGE_VOICE_DETAILS`（`FRM_0231.eri`，335x179），精准对齐穹（`ID_SORA`）、瑛（`ID_AKIRA`）、奈绪（`ID_NAO`）、一叶（`ID_KAZUHA`）、初佳（`ID_MOTOKA`）、梢（`ID_KOZUE`）、八寻（`ID_YAHIRO`）、亮平（`ID_RYOUHEI`）及其他（`ID_OTHER`）9 个勾选按钮；宿主智能识别 `voice.noa` 中 18,032 个音频文件前缀（`SR`、`AK`、`NO`、`KA`、`MT`、`KO`、`YH`、`RH`），实现实时角色语音静音过滤联动。
    - **原生 60 槽位存读档界面（LoadSaveWindow::create / setPage）**：逆向 CSX 0x3160F 与 0x328E4，解析 `ID_PAGE_SAVE`（690x547，`FRM_0506.eri` 标题）、`ID_PAGE_LOAD`（690x574，`FRM_0505.eri` 标题、`ID_QSAVE` 快读按钮）；3x3 网格排布 9 个 `ID_PAGE_SAVE_INDEX` 卡片，精准对齐 220x170 `FRM_0501.eri` 卡片底图与 Focus 高亮、`FRM_0502.eri` 最新存档标记（8, 3）、120x90 游戏截图（95, 2）、编号（15, 38）、日期时间（7, 100）、对话摘要（14, 121）及 `FRM_0302.eri` / `FRM_0303.eri` 原生滚动条。
    - **原版确认弹窗与历史记录**：确认弹窗采用 800x120 `FRM_0401.eri` 横幅底图、`ID_YES`（`FRM_0402.eri`）与 `ID_NO`（`FRM_0403.eri`）；历史记录采用 701x504 `FRM_0301.eri` 配合原生滚动条。

12. **原生场景回想系统（Scene Recollection & checkPaletteRecollect）**：
    - **原生反汇编调用点**：逆向 CSX 字节码中 `AppreciationView::recollectProc`（@ 0x058901）与 `AppreciationView::setCgPalette`（@ 0x04221A），揭示了原版游戏回想画廊的完整实现：
    - **解锁位标志与判定**：原生使用 `sysObj.recollectFlag` 进行 1 对应 1 的位掩码判定（`1 << (flag - 1)`）。共 18 个独立场景回想，分布在 5 位主角下：
      - **春日野 穹（Sora, tag 0）**：5 幕回想
        - 槽位 1: Flag 1 -> `REC_SR1.eri` -> 场景 `00_A020`
        - 槽位 2: Flag 2 -> `REC_SR2.eri` -> 场景 `00_A022`
        - 槽位 3: Flag 3 -> `REC_SR3.eri` -> 场景 `00_A025B`
        - 槽位 4: Flag 4 -> `REC_SR4.eri` -> 场景 `00_A026`
        - 槽位 5: Flag 5 -> `REC_SR5.eri` -> 场景 `00_A032`
      - **依媛 奈绪（Nao, tag 1）**：4 幕回想
        - 槽位 1: Flag 6 -> `REC_NO1.eri` -> 场景 `00_B005`
        - 槽位 2: Flag 7 -> `REC_NO2.eri` -> 场景 `00_B021`
        - 槽位 3: Flag 8 -> `REC_NO3.eri` -> 场景 `00_B025`
        - 槽位 4: Flag 9 -> `REC_NO4.eri` -> 场景 `00_B032`
      - **天女目 瑛（Akira, tag 2）**：3 幕回想
        - 槽位 1: Flag 10 -> `REC_AK1.eri` -> 场景 `00_C019B`
        - 槽位 2: Flag 11 -> `REC_AK2.eri` -> 场景 `00_C023`
        - 槽位 3: Flag 12 -> `REC_AK3.eri` -> 场景 `00_C034`
      - **渚 一叶（Kazuha, tag 3）**：3 幕回想
        - 槽位 1: Flag 13 -> `REC_KA1.eri` -> 场景 `00_D025B`
        - 槽位 2: Flag 14 -> `REC_KA2.eri` -> 场景 `00_D028B`
        - 槽位 3: Flag 15 -> `REC_KA3.eri` -> 场景 `00_D042B`
      - **渚 初佳（Motoka, tag 4）**：3 幕回想
        - 槽位 1: Flag 16 -> `REC_MT1.eri` -> 场景 `00_E013C`
        - 槽位 2: Flag 17 -> `REC_MT2.eri` -> 场景 `00_E024B`
        - 槽位 3: Flag 18 -> `REC_MT3.eri` -> 场景 `00_E036`
    - **原生 UI 纹理规范**：对应 `option_system.xml`，回想面板使用 2x3 网格排布，卡片尺寸 242x90。未解锁时展示 `FRM_0735.eri` 锁定横幅；已解锁时展示对应主角专属 `REC_*.eri` 宽幅横幅，并叠加上下状态边框 `FRM_0734.eri`（484x90，左右切片为 Normal 与 Focus）。模式切换使用 `FRM_0724.eri`（123x28，三切片：Normal、Focus、Pushed）。
    - **场景流转与无缝返回**：点击回想卡片后，触发宿主 `EnterRecollectMode`，清理当前 ADV 画布与文本，将执行权移交给 `ScenarioLoop(scenario_name)`。当场景执行完成或用户在菜单中选择“返回标题”时，触发 `LeaveRecollectMode`，自动无缝返回鉴赏窗口并恢复至所选主角标签页。

另外检查过 [CUFFS](https://github.com/Senko-heart/CUFFS)：它是 Godot 小说引擎，但使用 `.gss` 剧本，无法直接执行此处的 CSX；截至检查时仓库未声明源码许可证，因此没有复制其代码。
