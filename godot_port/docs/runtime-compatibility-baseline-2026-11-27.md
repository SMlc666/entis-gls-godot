# yzk2godot 原版运行时兼容基线（2026-11-27）

本文件是本轮接续工作的**当前差距基线**，优先于下方所链接的历史检查点；历史记录仍用于解释结论如何形成。这里的优先级是 A01–A20 的当前残余风险，原始交接优先级另列，不把一次内部烟测通过等同于原版运行时兼容。

## 快照、证据标准与只读边界

- 仓库：PR 分支 `compat/native-runtime-audit`，本轮补充的基线提交为 `59a83684b90dbe0b898e1cdd7dc864b58ed59610`。本文记录该提交后的 Host command dispatch、VFS 存在性查询与回归结果；`.pi/` 是本地 Goal/session state，不是游戏资源或产品代码，也不纳入提交。
- 目标游戏副本：`缘之空（全cg步兵版）/`。原始 `system/yosuga.csx`、`data1.noa`、`opening.mei` 在本轮测试前后 SHA-256 完全一致：
  - `system/yosuga.csx`: `157be9eb39cdc2d3cb654096340ca686f4ef48ac7fd7a6255673ba5f0c79afb6`
  - `data1.noa`: `d324c49ed4a80108f68aabaf7a202ec31d1b8f64075918f136944e72ec919831`
  - `opening.mei`: `9509dc23f0060f0ac98b67a3d7c3331bc0a0efc95450c8e0f311c51c592bf137`
- **全部原始 NOA/CSX/MEI/ERI/MIO 文件严格只读。** Story/title/save 测试配置到 `user://test_saves/` 的隔离目录；媒体 smoke 只读游戏归档和影片。上述哈希比较证明本轮选定烟测没有改动这三份代表性原始资源，不代替对每次未来运行的哈希检查。
- 本轮环境为 Godot `4.7.stable.official.5b4e0cb0f`，Linux codec `godot_port/tools/bin/linux/libyzk_codec.so` 存在。
- **兼容性证据分级：** 0=无行为/桩/绕过原始脚本；1=项目 VM/宿主路径运行或通过内部烟测；2=真实原始脚本/资源触发行为，并与原版 SDK/runtime 的单项输出对照；3=端到端原始脚本流程与原版参考一致且有回归。内部自测、原始 CSX 被自研 VM 执行、或与非官方解码器做 codec differential 均不能单独支持 2/3。
- 本轮并行的三份 Luna 只读审计分别覆盖 VM/存档/队列、UI/compositor、媒体/资源/API；发现均按当前代码和测试状态核对。现有 `native-runtime-trajectory.md` 是多日期历史记录，不能孤立引用其中旧快照。

## 主要路径现状

| 路径 | 当前证据 | 当前结论 / 未覆盖项 |
|---|---|---|
| CSX 载入与 VM | `vm_safety_smoke.gd` 用真实 `yosuga.csx` 验证解析/指令边界；`vm_sync_call_smoke.gd` 验证合成 VM 行为。 | 实际游戏仍由自研 GDScript `CsxVM` 执行；不是官方 Cotopha `ECSContext`。官方 VM 接入和差分仍未证明。 |
| Title / Config / Appreciation | `native_title_player_smoke.gd` 通过，执行真实 CSX `Title()` / Appreciation 与原版 `ConfigWindow::run` 路径；`title_saveload_smoke.gd` 还通过原版 Continue → `LoadSaveWindow::run` → `Confirm` 加载 Save003 并恢复 `ScenarioLoop`。 | 这些仍是原版脚本在自研 VM 上运行；不能证明官方 runtime 语义。Story Escape 的设置入口仍打开项目自有 fallback modal；`native_menu_config_smoke.gd` 覆盖的是该 fallback，而非原版 CSX ConfigWindow。 |
| Story 消息与选择 | `native_story_compositor_smoke.gd` 到达真实 `00_Z000` MessageSprite/HostWindow，检查文本、渐显状态和 10 个按钮；`native_story_selection_smoke.gd` 到达 `00_Z005` 的原版 `AdvScreen::startSelect`，选择后 `selectResult=1`。 | 成功证明了自研 VM 上原始 CSX 的部分窗口树与选项闭环。输入由测试合成按钮触发并提供逻辑光标位置；物理鼠标/键盘、官方 Cotopha 差分尚无证据。QSave 测试只证实命令入队/唤醒，不证实实际写入存档。 |
| 立绘/动画/compositor | Story 测试证明 HostWindow 消息树渲染及显式 `SetBustup`/`AdvScreen::update` 探针被单一路径显示。 | 探针不是自然剧情事件；自然场景的 bustup 附着、跨模式/转场、裁剪/混合/逐像素原版对照仍未证明。Godot CG/temp/unattached-bustup 回退节点仍存在。 |
| 音视频 | `mei_playback_smoke.gd` 通过；`mei_fullstream_smoke.gd` 已修正为接收游戏目录与隔离存档，本轮完整解码 2520 个视频记录通过（28.49 秒）。 | 这是项目内 MEI 解码/播放验证。官方 SDK 的像素、PCM、时序差分仍缺；Audio Dummy 不能证明硬件音频时钟同步。其他 MEI 变体覆盖不完整。 |
| 存档/读档 | `save_storage_contract_smoke.gd` 覆盖项目 JSON 原子提交/备份恢复；`bustup_smoke.gd` 用真实 CSX QuickSave/QuickLoad 检查 continuation、BGM07、环境声和 `isLoad`；`title_saveload_smoke.gd` 用原版 Title Continue、LoadSaveWindow 卡片与 Confirm 载入 Save003，并以场景字段变异验证还原。 | Save003 由项目 `AdvPlayer.save_to_slot()` 写入，随后由真实 CSX Title/Load 流程读取；尚未验证原版 Story 保存 UI 写入后跨进程重启恢复，也不是 Cotopha 原生存档格式/官方 runtime 兼容证明。 |
| 官方运行时 | 当前 `adv_player.gd` 将脚本装入项目 `CsxVM`；官方 Cotopha 执行/SDK differential 尚未完成。EntisGLS 4.07.03 ZIP 与选定源码在仓库外 `/root/reference-sources/entisgls-sdk-selected` 可用，但这不等于官方 runtime harness 或执行证据。 | **原版运行时执行仍是此目标的首要架构缺口。** 已获取的 SDK source subset 可供只读检查；官方 runtime 未执行，Story 仍由项目 `CsxVM` 运行。未证明的官方语义不得由静态源码声明、项目实现或自研 VM smoke 推断；不得声称官方 parity。 |

## A01–A20 差距表

“交接优先级”来自上一轮问题表；“当前优先级”按本轮残余风险保守分级。标为“已解决”的只表示所列自研实现契约有回归覆盖，不表示已达到官方 Cotopha parity。

| ID / 原交接优先级 | 当前优先级 / 状态 | 当前证据（代码 / 测试，证据强度） | 剩余缺口与关闭验证 |
|---|---|---|---|
| **A01 输入等待阻塞原始菜单命令** / P0 | **P1 候选风险（非已证实的官方契约违例）；项目调度及分派链已覆盖，flush/物理输入语义未确认** | `adv_player.gd:925–930,959–962` 在等待输入时允许活动窗口有命令就继续 VM；`host_command_queue.gd:35–46,123–164` 有 scope/FIFO/容量/关闭；`native_story_compositor_smoke.gd` 与 `native_story_selection_smoke.gd` 用真实 CSX 验证命令唤醒/消费（输入为合成触发）；`host_command_queue_smoke.gd` 覆盖队列本身；`host_flush_integration_smoke.gd` 通过 CsxVM 的 HostWindow dispatcher 测 push→FlushCommandQueue→GetCommand；dispatch 按窗口 ID 精确隔离，只有 `-1` 是全局哨兵（Godot instance ID 可为负，不能用 `<0` 判断）；CSX mode-2 `GetJoyButtonPushed` 成员调用中，`argc=2` 包含 `HostInputFilter` receiver（`args[0]`）和一个显式方法参数（`args[1]`）；窗口归属从 `OpenFilter.window_ref` 解析。测试覆盖 HostWindow 与 CSX mode-2 `HostInputFilter` 成员调用/活动过滤器的同窗/跨窗路径（含 `during_activation`）、窗口销毁清理和新 scope reset。该测试锁定本项目调度/no-op flush 策略，不证明原版语义；官方 Native Cotopha 声明仅确认接口/签名，未定义 flush 效果或物理输入/事件时序；静态调用点不证明运行时可达，真实 CSX smoke 的输入为合成触发，不构成官方 parity。 | `HostWindow.flush_command_queue` 当前返回 0 并保留已入队命令（`csx_host.gd:2695`，仅为项目行为），原始 CSX 有 40 处调用；物理输入时序及 SDK flush 语义未确认。需官方参考输出后才能变更 flush 行为；物理鼠标/键盘时序另行验证。 |
| **A02 Story 对象/纹理泄漏** / P0 | **P2：正常 teardown 测试无 ObjectDB/RID；强制进程退出诊断尚未归因** | 移除未挂接 Button 后早期 ObjectDB/RID 报告曾停止。进一步复跑发现：没有 audio-drain 的 selection 测试在部分退出时报告 4 个对象；verbose 给出 2 个 `AudioStreamWAV` 与 2 个 `AudioStreamPlaybackWAV`。`native_story_selection_smoke.gd` 现在显式调用幂等的 runtime shutdown、释放 AdvPlayer、等待一帧和 250 ms；之后 3 次普通 + 1 次 verbose selection smoke 均无 ObjectDB/RID warning。新增 `story_lifecycle_smoke.gd` 在同一进程启动/推进/释放 3 个真实 `00_Z000` CSX 会话，正常退出。首轮回归中 `native_story_compositor_smoke.gd`、`native_title_player_smoke.gd` 与 `native_resource_error_contract_smoke.gd` 立即退出时也出现 2 个 ObjectDB 实例；verbose 将 compositor/title 两项定位为一对 `AudioStreamWAV` / `AudioStreamPlaybackWAV`。三项测试现均显式 runtime shutdown 并等待 process frame + 250 ms AudioServer drain，`--verbose` 复跑不再出现 ObjectDB/RID 实例警告。`title_saveload_smoke.gd` 改为所有 67 个失败出口和成功出口共用 `_finish()`：shutdown runtime、queue_free、等一帧与 250 ms 音频 drain 后才清理隔离 save dir/退出；独立 Luna 复核未发现问题。修复前 4 次诊断有 2 次报告 4 个对象（2 `AudioStreamWAV` + 2 `AudioStreamPlaybackWAV`）；修复后 3 次 verbose 复跑均无 ObjectDB/RID。另有 `main-scene-boot --quit-after 240` 到达真实首行/SE270 的 3 次 verbose 运行，2 次报告 1 个 `AudioStreamWAV` 与 1 个 `AudioStreamPlaybackWAV`，1 次未报告；强制退出时音频仍活动、没有显式 drain，不能由此判定生产期泄漏或断言警告无害。Orphan StringName（7–8 个）及强制退出诊断均保留为 P2。 | 重复 Story/Title/save-load teardown 覆盖未观察到同进程会话累积；title-save/load 的 3 次修复后 verbose 运行无 ObjectDB/RID。`--quit-after` 强制退出中的音频对象警告单独保留为 P2 测试/退出诊断，不作为生产期泄漏的证明。以上不等于全局 RSS/资源零泄漏；orphan StringName 与 ObjectDB 泄漏是不同诊断。后续仍需正常 app-close、媒体解码失败清理路径及非 Dummy audio driver 复核。 |
| **A03 CSX 构造函数错误传播** / P0 | **已解决（自研 VM 契约）** | `csx_vm.gd:644–712,876–880,919–925` 在构造失败时返回显式创建错误，不继续伪造对象；`vm_sync_call_smoke.gd:111–148` 覆盖失败/超时构造。合成 VM 测试，非官方 runtime 对照。 | 仅当官方 Cotopha 接入/差分时再关闭原版构造语义差异；保留可能已有副作用的错误诊断。 |
| **A04 存档恢复遗漏精灵/音频状态** / P0 | **P1，项目自研保存/恢复路径有实际资源回归；官方语义未确认** | 除 schema v7 与 envelope 恢复外，`bustup_smoke.gd` 通过真实 CSX QuickSave/QuickLoad 验证 `scObj.scenarioCall`、`isLoad=-1`、BGM07 和 SE270 在 `ScenarioLoop` 后恢复；`title_saveload_smoke.gd` 通过原版 Title LoadSaveWindow/Confirm 载入 Save003，并在确认前篡改内存中的 `scenarioCall`，断言读档恢复保存值并将该 continuation 作为 `ScenarioLoop` 参数。 | 以上仍是项目 JSON/Host 与自研 VM 的结果。缺官方 Cotopha 对照；未覆盖原版 Story 保存 UI 写档、进程重启、完整精灵树和所有活动音频通道。保持 P1 parity 风险，不把自研烟测解释为原版兼容已关闭。 |
| **A05 备份恢复只覆盖部分失败** / P1 | **已解决（项目自有存档格式的已测场景）** | `csx_host.gd:4386–4445,4455–4489,4773–4780` 原子保存、主备候选、阶段化恢复；`save_storage_contract_smoke.gd:420–450,508–535` 覆盖主文件损坏/语义无效时回退。合成 fixture。 | 不等同原生存档格式兼容；继续用真实 UI 路径测试用户操作和崩溃恢复。 |
| **A06 新旧渲染路径重复/分叉** / P1 | **P1 候选未关闭；双路径架构仍存，但未证明同一表面重复绘制，也未发现可安全删除/合并的路径** | Luna 只读审计 `task-67`：`adv_player.gd:417–470,475–554` 构建旧背景、CG/temp、5 个 bustup rect 与 DialogueBox/按钮；`:1092–1248,1943–1971` 更新旧 bustup/CG/temp 并同步 MessageSprite 到隐藏 fallback；`:2763–2827` 把 HostWindow roots 投影至 wrapper，非空 Story tree 时隐藏 DialogueBox、结束后恢复；无覆盖 viewport 的 surface 时背景 fallback 仍可见，`:2616–2624` 仍有 Title fallback。`native_story_compositor_smoke.gd:72–84` 证明真实 Story message tree 当前不双绘；`:212–219` 与 `bustup_smoke.gd:89–97` 只用显式 bustup 探针，未证明自然场景/转场挂接；`native_adv_screen_sprite_smoke.gd:45–59` 的 CG 走 AdvPlayer 层，未证明同一 CG 同时在 HostWindow 中。故分类为分拆的 renderer ownership，不是已证实重复绘制。生命周期方面，HostWindow roots、wrapper 节点/纹理及绑定 `HostSprite` 的回调持有引用；stale wrapper 通过 deferred `queue_free` 清理，shutdown (`adv_player.gd:3962–4019`) 断开回调、排队释放子节点并清空 map/cache/temp 与纹理引用；这些代码及既有 `story_lifecycle_smoke.gd` / audio-drain 结果不证明整个场景立即释放或全局零泄漏。 | 当前证据下不做渲染器删除/合并。仍需覆盖自然 bustup、CG/temp、fallback 与 Title/Story/Config/SaveLoad/Appreciation/recollection/error 等模式和转场，逐面断言 exactly-one-visible-owner，并核对输入/可见性；补原版参考帧对照。重复会话检查 wrapper、信号闭包、纹理/材质引用与 audio drain；不要把 deferred cleanup 写成即时释放保证。官方参考渲染仍缺失。 |
| **A07 背景覆盖检测错误** / P1 | **P2，逻辑已改、视觉差分未证** | `adv_player.gd:2765–2800` 递归考虑变换、继承可见/不透明度和表面；`native_story_compositor_smoke.gd:242–299` 测变换覆盖及按钮多状态纹理不透明度。真实 CSX compositor 路径通过。 | 组合裁剪、Z 顺序、blend、透明像素和实际输出还未与官方渲染对照。增加像素级 fixture 与原版参考捕获。 |
| **A08 精灵命中与显示变换不一致** / P1 | **P2，几何变换已覆盖；命中掩码未证** | `csx_host.gd:1938–1974` 逆变换到精灵局部坐标并检查父链可见/透明；`native_sprite_methods_smoke.gd` 覆盖旋转命中/假阳性。Story 选项实际 CSX 流程使用逻辑坐标，不是物理指针。 | `hit_transparency=true` 目前没有消费者；父子组合、零缩放、alpha hit mask、实际鼠标/触屏需要测试；透明像素语义应先核对 SDK。 |
| **A09 焦点覆盖按钮选中状态** / P1 | **P2，自研状态修复已测** | `csx_host.gd:2544–2563` 将 `has_window_focus` 与 checked/pushed 状态分开；`native_sprite_methods_smoke.gd` 覆盖选中态跨焦点变化。 | 原版键盘导航、hover/pressed/focus/checked 纹理优先级和多窗口切换需真实交互/SDK 参照。 |
| **A10 命令队列缺生命周期约束** / P1 | **P2，队列自身已解决；集成边界未全证** | `csx_host.gd:2876–2925` 管理 scope 和入队，`host_command_queue.gd` 丢弃 stale token、窗口/精灵事件清理并在 shutdown 后拒绝；`host_command_queue_smoke.gd` 全部通过（内部 fixture）。 | 原始窗口切换/销毁和 Godot 物理输入的队列时序未全覆盖；继续从真实菜单到切换/关闭的集成测试。 |
| **A11 文本转义、渐显、字体状态** / P1 | **P2，基础行为部分验证** | `adv_player.gd:3217–3242,3340–3352` 处理转义、渐显、fade 和字体 override reset；`native_story_compositor_smoke.gd` 用真实 MessageSprite 检查解析文本/reveal count 和字体重置。 | 复杂 BBCode/literal brackets、字体 fallback、换行/对齐、跨语言字形、fade 时序无原版差分。构建覆盖矩阵和参考截图/行为测试。 |
| **A12 控件类型变化未同步** / P1 | **P2，动态变化尚未证明** | `adv_player.gd:2899–2930` 在新建 wrapper 时按类型创建 Button/slider/texture control；之后主要更新现有节点状态（`:2990–3024`）。`native_form_page_smoke.gd` 读取真实 title/frame NOA 皮肤数据，但直接构造 synthetic HostSprite/form-page fixtures；只测创建后的控件，不证明原始 CSX 表单流程或后续类型切换。 | 先审计原版 API/CSX 是否在 wrapper 已创建后改变 control type；若可达则实现类型切换并添加回归，否则记录“不可达”的静态/实际脚本证据。 |
| **A13 原生设置与项目 fallback 设置一致性** / P1 | **P2，双路由已明确；跨路由语义未证** | 原始 `ID_CONFIG` 在 Title/Story 都进入 CSX `ConfigWindow`；`native_story_config_smoke.gd` 执行 Story `ID_VOL_BGM` 通知并验证 `cnfObj.volBgm` 按滚动位置/256 更新。Escape 路径（`adv_player.gd:1038–1043`）仍打开明确标识的项目-owned fallback，使用 `settings_state` / `player-settings.json`（`:3875–3954`）。它们是两个可见路由，但现有证据未证明具体状态冲突；fallback 的自运行时结果也不能证明原版 `config.dat` 语义。 | 保留为 P2 互操作问题；后续明确 Escape fallback 与原生 Config 是独立 convenience state 还是需要共享值，再针对跨路由/重启设计测试。无官方参考时不宣称 `config.dat` parity。 |
| **A14 HostFile 原生流接口缺口** / P1 | **P1 候选：静态 Story 调用点有项目实现缺口；Native File 契约与 parity 未证** | 原始 `system/yosuga.csx` SHA-256 `157be9eb39cdc2d3cb654096340ca686f4ef48ac7fd7a6255673ba5f0c79afb6`：`MessageFrame::output` 函数 @`0x2DD83` 在调用点 @`0x2E29F` 调用 `OutputLogText`；`OutputLogText` 函数 @`0xAC83` 执行 `File.Open(path,4)`、失败重试 mode 5、`Seek(0,2)`、`WriteText(text)`、`Close`。静态调用者包括 `AdvScreen::hitret` @`0x144FD`、`AdvScreen::changeStyle` @`0x19837`、`LeaveLoad` @`0x307AF`；这证明静态字节码调用点，不证明任一 runtime 执行。项目 `csx_host.gd:2738–2769` 接受 mode 0/1/2/5、拒绝 4，Open 仅记逻辑状态而不打开字节流；`csx_vm.gd:2438–2469` 无 Seek/WriteText dispatch，unsupported 通过 `:1370–1375,2063–2068` 失败。便捷 `OutputLogText`（`csx_host.gd:2801–2830`）是不同的 append/line 语义。`save_storage_contract_smoke.gd:468–490` 只覆盖 HostFile helper，`host_unsupported_api_smoke.gd:18–63` 仅测通用 unsupported，不覆盖该序列。 | 官方 EntisGLS 4.07.03 ZIP 与选定源码已在仓库外 `/root/reference-sources/entisgls-sdk-selected` 获取。Archive-relative `Cotopha\Include\cotopha\stdtype.ch:9–17,26–90` 声明 Seek origins、mode 常量/签名及 File/WriteText prototypes，但未定义 Native `File::Open` 具体 mode/error 语义或 `WriteText` 编码/默认值/返回语义；`Cotopha\Source\common\sakura\ssys_file.cpp:621–631` 显示 `__COTOPHA__` 委派给 `File::NewOpen`，其实现未定位。该文件中的非-Cotopha `SFile` 是另一 backend，不能作为 Native 契约。未运行官方 runtime 或 differential。项目 runtime 的一份有界真实 Story trace 记录于 [`a14-runtime-reachability-2026-11-28.md`](a14-runtime-reachability-2026-11-28.md)：在开场 16 行 flow 中未观察到该 File 流序列（这不证明不可达）；官方语义和 parity 仍未证实。保留 P1 候选，不据此改变语义或声称 parity。 |
| **A15 同步 VM 调用共享状态契约未确认** / P1 | **P1 风险候选；非已确认的官方契约 P1 缺陷** | `csx_vm.gd:736–818,821–871,890–893`：`call_address_sync` 保存/恢复选定控制子集：`ip`、halt、return IP、浅复制的参数/栈数组根、返回值、同步标志及 cooperative-sleep 字段。`last_error`、`executed_instructions`、confirmation 字段、global/data tables 与 host 不在快照中；其遗漏本身不证明设计缺陷或意图。浅复制可保留嵌套引用。`vm_sync_call_smoke.gd:10–185` 和 `vm_cooperative_sleep_smoke.gd:10–77` 仅覆盖合成的选定情形，不穷尽字段、生产调用者状态或官方 parity。 | task-54 仅搜索 8 个选定 SDK 文件，未找到权威同步调用契约；无官方 runtime differential。未测得泄漏，浅引用路径也不证明存在泄漏。A15 保留为项目跟踪的 P1 风险候选，而非已证实官方契约缺陷；语义变更须先取得权威契约或官方参考运行确认。 |
| **A16 视频追帧无每帧预算** / P2 | **P2，开放** | `adv_player.gd:1585–1660` 按过期帧同步解码；限制最多到影片帧数而非每帧小预算。fullstream 证明功能，不证明帧延迟。 | 大 delta/audio lag 下测单帧工作量和最长帧耗时；若限预算需证明最终追帧行为与原版一致。 |
| **A17 全量逐帧渲染同步成本** / P2 | **P2，开放** | `adv_player.gd:871–940,2698–2738,2882–2892` 每帧并在 VM batch 后递归同步 HostWindow 并清理 stale wrapper；没有 dirty/revision early-out 证据。 | 对大型树采样 visit 数和帧时间，增加“不变树不重复同步、变更仍重绘”测试；优化不能丢 UpdateWindow/redraw 请求。 |
| **A18 内存预算未覆盖全生命周期** / P2 | **P2，部分** | `csx_host.gd:32–50,3477–3513` 有图像/声音 cache 限额，但注释明确不包含 sprite/player/GPU/active decoder 保留；native MEI 256 MiB 是 estimated working-set 而非 RSS。`resource_read_limits_smoke.gd`、MEI codec smoke 覆盖组件边界。 | 定义全局预算与所有者；多资源生命周期压力测试并测 peak RSS/native buffers/GPU（可行时），或清晰限定当前预算范围。 |
| **A19 未实现 Host API 假成功** / P1 | **代表性 dispatch 已解决；API 清单覆盖未完成** | `csx_vm.gd:1445–1451,1993,2014–2018` 令未实现全局/成员调用报错且不压入伪造返回值；`host_unsupported_api_smoke.gd` 通过。`UpdateWindow` 保留为 redraw 请求。真实 Story `ID_CONFIG` 流程还覆盖 `File::IsExisting(".mio")` 的可选资源缺失路径：`native_resource_error_contract_smoke.gd` 检查 Host predicate、HostFile 和 CSX handler 均返回 false 且保留前一诊断，`native_story_config_smoke.gd` 检查原始 CSX 在自研 VM 上执行后没有残留该 miss 诊断；这仍是自运行时证据，未与官方 Host 比对。已知一些窗口/输入 API 仍是 partial/no-op。 | 建立原始 CSX 实际调用点与 Host handlers 的完整差异表；每个 no-op 必须有证据支持或改为显式 unsupported；最终用官方 runtime 比较返回值。 |
| **A20 存档缩略图边界** / P1 | **P2，主要边界已覆盖** | `csx_host.gd:4296–4341` 限制 16 MiB 文件、PNG IHDR 最大尺寸/像素数并在解码后复核；`thumbnail_bounds_smoke.gd:13–63` 测有效图、超尺寸 IHDR、hash。 | 对截断/畸形/边缘 PNG 扩展 fixture 或 fuzz；确认 Godot 解码器瞬时内存边界。 |

## HostSprite.Release 动画生命周期修复（2026-11-28）

独立只读审计确认一个自研 HostSprite 生命周期缺陷（P2）：`Release()` 清理显示图像但未停止活动动画或释放其帧/序列；Host animation advance 因而可重新创建 image/texture。`HostSprite.release()` 现调用 `end_animation()`、清空帧/尺寸/序列并重置动画计时与索引，同时保留原 Release 返回值。资产无关的 `host_sprite_release_lifecycle_smoke.gd` 以合成 Images、WeakRefs 和 release 后 host advance 覆盖释放、注册移除、无资源复活及幂等性；配合 `resource_lifecycle_smoke.gd` 检查 HostResource 路径。

从仓库根目录复现（headless Godot，无游戏资源）：

```sh
godot --headless --audio-driver Dummy --path godot_port --script res://tests/host_sprite_release_lifecycle_smoke.gd
godot --headless --audio-driver Dummy --path godot_port --script res://tests/resource_lifecycle_smoke.gd
```

这是项目自运行时生命周期修复证据，不证明 Native Cotopha 语义或 parity。

## 本轮可复现验证

以下全部在 Godot 4.7、headless、Dummy audio 下运行；括号说明资源证据类别。命令模板均从仓库根目录执行：

```sh
godot --headless --audio-driver Dummy --path godot_port --script res://tests/vm_safety_smoke.gd -- '<game-dir>/system/yosuga.csx'
godot --headless --audio-driver Dummy --path godot_port --script res://tests/vm_sync_call_smoke.gd
godot --headless --audio-driver Dummy --path godot_port --script res://tests/host_command_queue_smoke.gd
godot --headless --audio-driver Dummy --path godot_port --script res://tests/host_flush_integration_smoke.gd
godot --headless --audio-driver Dummy --path godot_port --script res://tests/host_unsupported_api_smoke.gd
godot --headless --audio-driver Dummy --path godot_port --script res://tests/native_sprite_methods_smoke.gd
godot --headless --audio-driver Dummy --path godot_port --script res://tests/thumbnail_bounds_smoke.gd
godot --headless --audio-driver Dummy --path godot_port --script res://tests/save_storage_contract_smoke.gd
godot --headless --audio-driver Dummy --path godot_port --script res://tests/native_story_compositor_smoke.gd -- '<game-dir>'
godot --headless --audio-driver Dummy --path godot_port --script res://tests/native_story_selection_smoke.gd -- '<game-dir>'
godot --headless --audio-driver Dummy --path godot_port --script res://tests/story_lifecycle_smoke.gd -- '<game-dir>'
godot --headless --audio-driver Dummy --path godot_port --script res://tests/native_title_player_smoke.gd -- '<game-dir>'
godot --headless --audio-driver Dummy --path godot_port --script res://tests/native_form_page_smoke.gd -- '<game-dir>'
godot --headless --audio-driver Dummy --path godot_port --script res://tests/mei_playback_smoke.gd -- '<game-dir>'
godot --headless --audio-driver Dummy --path godot_port --script res://tests/mei_fullstream_smoke.gd -- '<game-dir>'
```

主会话本轮运行的上述 15 项最终均 exit 0（`mei_fullstream_smoke` 曾先因硬编码旧机器路径 `/mnt/sdb1/devs/yzk2godot/...` 失败；现已改为读取参数/`YOSUGA_GAME_DIR`，使用隔离 save dir、等候播放器初始化并核对 CSX/NOA/MEI 哈希，随后全 2520 帧通过）。其中队列/VM/缩略图/存档及新增 HostWindow flush 集成测试是合成 fixture；Story/title smoke 通过自研 VM 执行真实 CSX，form-page smoke 读取真实 NOA 皮肤数据但使用 synthetic HostSprite/form fixtures，MEI smoke 读取真实影片；均不是官方 Cotopha 差分。初始 selection 退出 warning 的 verbose 日志定位为两条 `AudioStreamWAV`/两条 `AudioStreamPlaybackWAV`。改用显式 shutdown、释放节点、等候一帧及 250 ms 音频 drain 后，selection 的 3 次普通+1 次 verbose 复跑无 ObjectDB/RID warning；`story_lifecycle_smoke.gd` 又在同一 Godot 进程通过 3 次真实-CSX Story 启动/输入等待/销毁循环。verbose 仍报告 7 个 orphan StringName；其与 ObjectDB 泄漏是不同诊断，当前不视为 P0 泄漏证据。

## 接续验证补充：Title 读档交接与独立复核

本节回顾的 Title 读档交接最初基于 `compat/native-runtime-audit`、HEAD `4fb1982` 的工作树快照；其后续进展已提交到 `59a8368`。以下证据保留该历史基线背景，当前 Host dispatch 与 VFS 增量见本页后续小节。

- `adv_player.gd::_try_resume_native_title_load()` 只在 Title 执行原版 `EnterLoad` 且 `scObj.isLoad == -1` 后进入待交接状态，并等待 `EnterLoad`、`Load`、`NormalLoad`、`QuickLoad`、`LoadSaveWindow::loadsave`、`LoadSaveWindow::run` 与 `Confirm` 均离开调用栈；成功交接要求 `scObj.scenarioCall` 非空，随后清理旧 VM 栈并从 `ScenarioLoop` 以保存的场景名恢复。`load_from_slot()` 对无场景 continuation 的保存同样显式失败，不再悄悄回退到 `start_scenario`。
- `title_saveload_smoke.gd` 保存 Save003 的原始 `scObj.scenarioCall`，在原版 Confirm 的 Yes 前把内存值改成测试标记，断言 native Title Load 恢复了保存值、`ScenarioLoop` IP 和待传参数；之后继续通过剧情输入等待。`bustup_smoke.gd` 的 QuickLoad 用例还验证 BGM07 与 SE270 在 ScenarioLoop 继续后启动。以上是 self-runtime 集成证据，不是官方 Cotopha 差分。
- `_is_match_usage()` 保留原始捕获文本而非转整数：`native_title_player_smoke.gd` 验证 Appreciation 页码捕获 `"1"`，`title_saveload_smoke.gd` 验证 Save003 按钮路径保留零填充捕获 `"04"`。独立 Luna 源码审阅没有发现生产 GDScript 调用点依赖整数 Variant；CSX 二进制消费者全集和官方运行时语义仍未证明。
- `tools/audit_native_api.gd` 对只读 `system/yosuga.csx` 完成扫描（1,414,381 条指令、780 个函数），语法调用点中有 `FlushCommandQueue` method mode 36 处和 global mode 4 处。该结果确认调用范围，不证明宿主处理语义；A19 的 handler/返回值差异表仍未完成。
- 三份早期 Luna 只读复核分别检查 Title 读档交接、A01–A20 当前差距和正则捕获类型。后续独立复审将 A13 从“已确认 P1”收窄为 P2：Story 原生菜单已进入 CSX ConfigWindow，Escape 另开 project-owned fallback，但具体跨路由状态冲突尚未证明；A14 保持 P1 候选：项目实现缺口有静态调用证据，但 Native File 契约和 parity 未证。A01、A04、A06、A14、A15、A19 仍列为未关闭/待确认的 P1 风险；其中 A15 只是项目跟踪的风险候选，task-55 未建立官方契约缺陷，语义改动须先经权威契约或官方参考运行确认。A02 无所测路径的 ObjectDB/RID 泄漏证据，StringName 残项继续作为 P2 诊断；A03 的结论仅限自研 VM。
- 本次补充的真实资源/自研运行时回归均 exit 0：`native_title_player_smoke.gd`、`title_saveload_smoke.gd`、`bustup_smoke.gd`、`save_storage_contract_smoke.gd`、`native_form_page_smoke.gd`、`native_story_selection_smoke.gd`、`choice_interaction_smoke.gd`、`story_lifecycle_smoke.gd`、`native_activation_input_smoke.gd`、`native_adv_screen_sprite_smoke.gd`、`native_menu_config_smoke.gd`、`native_saveload_voice_smoke.gd`、`native_reference_smoke.gd`、`native_sprite_methods_smoke.gd`、`sprite_activation_smoke.gd`、`sprite_effect_smoke.gd`、`native_bezier_math_smoke.gd`、`native_alpha_mask_contract_smoke.gd`、`native_shading_filter_smoke.gd`、`sprite_tree_contract_smoke.gd`、`vm_safety_smoke.gd`、`vm_sync_call_smoke.gd`、`vm_cooperative_sleep_smoke.gd`、`host_command_queue_smoke.gd`、`host_flush_integration_smoke.gd`、`host_unsupported_api_smoke.gd`、`audio_host_contract_smoke.gd`、`mei_codec_smoke.gd`、`mei_playback_smoke.gd` 和 `mei_fullstream_smoke.gd`（全流 2520 帧，31.39 秒）。其中 `choice_interaction` 与 `native_bezier_math` 在首次启动时漏传资源路径，修正参数后通过；这两次启动错误不计作游戏行为失败。
- 上述真实资源烟测未修改原始文件。最终读取的 SHA-256 与基线相同：`system/yosuga.csx` `157be9eb39cdc2d3cb654096340ca686f4ef48ac7fd7a6255673ba5f0c79afb6`、`data1.noa` `d324c49ed4a80108f68aabaf7a202ec31d1b8f64075918f136944e72ec919831`、`voice.noa` `b3b39bb227ea60ecffbfcd8812e232a9b72f930ee2103465572955ff899e54e9`、`opening.mei` `9509dc23f0060f0ac98b67a3d7c3331bc0a0efc95450c8e0f311c51c592bf137`。此前 `native_form_page_smoke.gd` 还核对 `system/title.noa`、`system/frame.noa`、`system/option.noa` 与 `sound.noa` 的固定哈希。 `
## 本轮补充：Host command dispatch 与可选资源探测（2026-11-27）

- `HostWindow.GetCommand` 消费非空事件后将 pending-dispatch 绑定到该窗口；按 Godot instance ID 精确查询（ID 可为负，只有 `-1` 表示全局查询）。其后 `GetJoyButtonPushed` 的 HostWindow、活动过滤器及 CSX mode-2 `HostInputFilter` 成员调用路径，只在所属窗口 dispatch 尚未被空 `GetCommand` 收尾时抑制 scheduler input wait；该 CSX 调用的 `argc=2` 包含 `args[0]` receiver 与唯一显式方法参数 `args[1]`，窗口归属从 `OpenFilter.window_ref` 得到。其它窗口的空轮询或 advance-button poll 不会误清除/抑制本窗口状态。弱引用窗口销毁、命令 scope 切换和 runtime shutdown 都清理状态；`during_activation` 仍设置 cooperative sprite yield。`host_flush_integration_smoke.gd` 验证这些项目内契约；不是官方 runtime parity。
- `CsxHost.is_file_existing()` 将正常 VFS miss 作为 false predicate；仅当 lookup 写入对应的标准 `VFS entry not found` 诊断时才恢复既有 `last_error`。当前实现与调用链由 smoke 覆盖，官方 `File::IsExisting` 对错误状态副作用的语义仍待参考。
- 可复现命令（仓库根目录，`<game-dir>` 指原始游戏目录）：

  ```sh
  godot --headless --path godot_port --script res://tests/host_flush_integration_smoke.gd -- '<game-dir>'
  godot --headless --path godot_port --script res://tests/native_resource_error_contract_smoke.gd -- '<game-dir>'
  godot --headless --path godot_port --script res://tests/native_story_config_smoke.gd -- '<game-dir>'
  ```

  三项均 exit 0。Story Config smoke 执行真实 `00_Z000` 的 CSX `ID_CONFIG` → `ConfigWindow::run` → 可见 `ID_PAGE_CONFIG` 路径（由项目 GDScript VM 执行），并实际改变原生 `ID_VOL_BGM`，断言 CSX `cnfObj.volBgm` 更新为滚动位置/256；同时对 `system/yosuga.csx`、`data1.noa`、`sound.noa`、`system/title.noa`、`system/frame.noa`、`system/option.noa` 做前后 SHA-256 比较，未发现变化。该结果不证明官方 Config/`config.dat` parity。`native_resource_error_contract_smoke.gd` 实际从原始 `sound.noa` 解码 `BGM07.mio` 并验证播放 API Error codes，清理 runtime 与播放器后通过。
- 独立 Luna 只读复核确认 dispatch 生命周期清理和 VFS miss 恢复未见具体实现缺陷；审查也强调上述 self-runtime 结果不能代替官方 `FlushCommandQueue`、物理输入或 `IsExisting` 行为差分。初轮审查指出 active HostInputFilter 路径缺少覆盖，补测后第二轮审查进一步发现 CsxVM 的 HostInputFilter mode-2 成员分支未继承过滤器窗口归属；修复从 `OpenFilter.window_ref` 解析 owner，并将 `-1` 作为唯一全局哨兵（Godot `instance_id` 可为负），加入同窗/跨窗断言。最终 Luna 复审未发现该改动中的具体 P0/P1；官方语义差距仍未关闭。
- A13 后续 Luna 复核确认 Title 与 Story 原生 `ID_CONFIG` 路径；新增的 Story 测试进一步驱动原生 `ID_VOL_BGM` 并检查 `cnfObj.volBgm`。Escape 仍是单独的项目-owned `settings_state` / JSON fallback。当前证据证明两条路线存在，不证明它们必须共享值或已经产生冲突，因此 P1 证据不足，按 P2 互操作风险追踪。
- A14 接受的只读合成确认原始 CSX 静态序列 `MessageFrame::output` function @`0x2DD83` → `OutputLogText` callsite @`0x2E29F` → `File.Open(4→5)` → `Seek(0,2)` → `WriteText`；没有 runtime 执行证据。官方 EntisGLS 4.07.03 ZIP/selected source subset 已在 `/root/reference-sources/entisgls-sdk-selected` 获取，但 `stdtype.ch:9–17,26–90` 仅声明 API，`ssys_file.cpp:621–631` 仅显示 `__COTOPHA__` 委派给未定位的 `File::NewOpen`；Native Open 的 mode/error 与 WriteText 编码/返回语义仍未建立。A14 保持 P1 候选，语义实现及 parity 声明未获授权。
- 该修复后重跑 33 项核心回归，均 exit 0：上述历史 30 项列表，加 `native_story_config_smoke.gd`、`native_story_compositor_smoke.gd`、`native_resource_error_contract_smoke.gd`。其中包含真实 Title/Story 输入、Config/存读档、精灵与动画、VM/Host、音视频路径；8 份原始资源（`system/yosuga.csx`、`data1.noa`、`voice.noa`、`opening.mei`、`system/title.noa`、`system/frame.noa`、`system/option.noa`、`sound.noa`）前后 SHA-256 一致。`cg_catalog_source_smoke.gd` 也通过；其断言已改为保留 Linux 物理归档路径大小写，与 VFS 的大小写敏感 identity 一致。
- 两个额外目录扫描用例未计入通过集：`csx_vm_smoke.gd` 通过 `call_function_sync` 尝试同步跑完整 `sc00_Z000`，300,000 步预算在 `0x14CAE` 超时；相关真实 Story 输入/选择/配置已由异步调度 smoke 独立覆盖。`native_codec_differential_smoke.gd` 依赖可选的 `arc_unpacker` sidecar（`YOSUGA_ARC_UNPACKER` 未设置且 PATH 无 helper），因此本环境无法做外部 ERI/MIO 字节差分；本轮仍通过 in-process codec 与媒体烟测。两项均不宣称通过，也不改变无 CLI runtime fallback 的设计。

## 后续只读审计与回归观察（2026-11-28）

- Bezier/动画调度的独立审计未发现已确认 P0/P1：`Bezier2D::SetLinear` / `SetAcceleration` 走索引 CSX VM 函数；原始 CSX 中的 `WaitUntilSpriteActive` 有索引函数实现，method-mode-5 会先解析该脚本全局函数，因此不能把 Host fallback 的固定返回值当作这些路径的实际行为。CSX 静态字节码调用点仍不等于动态可达。真实资源 `system/yosuga.csx` 的 VM/vector/动画 smoke、合成 sprite activation/release smoke 在审计批次通过；这些仅证明项目自运行时。
- `HostSprite.SetBezierCurve` 将曲线控制点拷贝为 `Vector2`/标量数组，`HostResource.SetVolumeEnvelope` 将点拷贝为 `Vector2` 并以弱引用登记；源 `CsxInstance` 不由这两条路径持有。取消、完成和 shutdown 会清理 envelope 数据与登记。相反，直接 `HostSprite.release()` 虽清除 Image/Texture/动画帧并注销 sprite，但留下 `activation_curves` / `activation_durations` 的 primitive arrays，直到覆盖、flush 或析构；目前没有证据表明这是 RefCounted 泄漏或无界增长，也没有权威 release/reuse 语义证明它是行为缺陷。作为 P2 stale-state/保留数据风险记录；先补有界 release→reuse 测试并确认语义，不做推测性改动。
- A14 官方声明 follow-up 进一步确认 `stdtype.ch` 中 `Write=0x4`、`CreateFlag=0x1`、`Create=0x5`，Seek origin 为 0/1/2，`WriteText` 暴露 Integer 返回类型；Cotopha syscall 将 flags 转发给 `pVM->NewOpenFile`，但该 VM backend 与 Native `WriteText` / `Close` 实现未在当前选定 SDK 源中找到。当前 HostFile 的 `Open` 仅维护逻辑状态、mode 4 被拒绝、mode 5 不创建流，且没有 `Seek` / `WriteText` dispatch；不相关的 `OutputLogText` append helper 不能替代该原生序列。非-Cotopha `SFile` OS 分支不构成 Native 契约。既有 real-Story trace 仅覆盖开场 16 行/105 帧，未执行目标序列；本次后续 trace 未形成新的可审计运行记录。A14 因此仍是 P1 候选，阻塞于 Cotopha backend 或受控官方 runtime differential 与进一步路径可达性证据；不改语义、不宣称 parity。原始资源与外部 SDK 文件均未修改/纳入仓库。
- `audio_host_contract_smoke.gd` 的历史同环境复跑曾 exit 1 / exit 0，失败在 350 ms 后 `AudioStreamPlayer.playing` 的 one-shot 完成时序断言；PCM range 截断断言已通过。2026-11-29 隔离矩阵又连续运行 3 次并均 exit 0，但测试仍使用固定 350 ms timer + `playing` 状态断言，未用有界 `finished` 事件/轮询取代；故前次 timing 风险仍为 P2，3 次通过不等于已消除 flake，也不证明生产音频错误。若该断言再失败，现有 `expect()` 会立即 `quit(1)`，失败 teardown 不如成功路径完整；单次 ObjectDB warning 不足以判定生产泄漏。

## 原生路径回归补充（2026-11-29）

- 在 Godot 4.7 / Linux / Dummy audio、隔离 HOME/XDG 环境中执行 41 条初始矩阵记录：39 项 PASS；主场景启动项 exit 0 且到达 `ScenarioLoop('00_Z000')`，但没有测试 PASS 标记；`native_sprite_error_contract_smoke.gd` 首次失败是 fixture 未表达 MovieSprite 当前打开/归属状态。补 fixture 后同一用例 PASS（真实代码未改）。相关核心实测覆盖 Title/Continue、Story 消息/选择/Config/输入、Host UI/表单、sprite/activation/Bezier、真实 MIO/MEI 与 2520 帧全流、存档恢复、音频合同及 VM/Host 合同；合成 fixture 与真实脚本路径按前文证据分类，不等同官方 Cotopha parity。
- `title_saveload_smoke.gd` 的成功和所有 67 个 `_run()` 失败出口均进入 `_finish()`；停止 AdvPlayer runtime、释放节点、等一帧及 250 ms 音频 drain，再清除本测试目录并退出。独立 Luna review 为 OK with notes。修复后 3 次 verbose 重跑 exit 0、无 ObjectDB/RID；每次仍有 7 个 orphan StringName。修复前 4 次运行有 2 次报告 WAV/PlaybackWAV 对象；这支持 test teardown 缺口解释，但不证明生产实现全局无泄漏。
- 真实主场景以 `--quit-after 240` 复跑，三次 verbose 均进入真实 `00_Z000` 首条对白并切换到 B27A 背景；其中 2/3 在强制进程退出时报告一对 `AudioStreamWAV` / `AudioStreamPlaybackWAV`，1/3 无该 ObjectDB warning。日志显示退出时刚播放 `SE270.mio`；命令没有显式 audio drain。结合代码中 `AdvPlayer._exit_tree()` 的 runtime shutdown 调用路径，这只把相关性指向 forced-exit teardown 时序，根因和对象持有者仍未证明。保留为 P2，不改生产音频语义、不宣称 warning harmless；真实正常 app-close smoke 尚待验证。
- 回归期间为 `native_sprite_error_contract_smoke.gd` 修正 MovieSprite fixture：测试 active 时把 host 的 `movie_opened`、owner 和 active instance ID 设为被测 sprite，避免只置全局 playing flag 就误断言其 `IsMoviePlaying`。三个重复 `audio_host_contract_smoke.gd` 当前均通过，但固定 350 ms one-shot timing 及断言失败时的直接 quit 仍为 P2 测试可靠性缺口（见上节）。
- 游戏目录中匹配 `.noa/.csx/.mei/.eri/.mio` 的 11 份文件，其路径、大小和 SHA-256 前后 manifest 完全一致；完整基准见 [`original-assets-readonly-manifest-2026-11-29.tsv`](original-assets-readonly-manifest-2026-11-29.tsv)。所有 XDG 数据写入 `$RUN_ROOT`，title 测试 `test_saves` 目录最终为空。主场景在 sandbox 用户数据目录创建的 `saves/config.dat` 与 `system.dat` 不在游戏安装目录。原始资源始终只读。
- 维护者可从仓库根复测：为游戏原始副本设置 `GAME_DIR`，创建独立 `RUN_ROOT`，隔离 HOME/XDG，再运行测试并用记录的 manifest 验证资源。Title teardown 和强制退出诊断命令为：

  ```sh
  REPO_ROOT="$PWD"
  GAME_DIR="$REPO_ROOT/缘之空（全cg步兵版）"
  RUN_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/yzk-native-paths.XXXXXX")"
  mkdir -p "$RUN_ROOT/home" "$RUN_ROOT/xdg-data" "$RUN_ROOT/xdg-config" "$RUN_ROOT/xdg-cache" "$RUN_ROOT/xdg-runtime" "$RUN_ROOT/xdg-state"
  chmod 700 "$RUN_ROOT/xdg-runtime"
  export HOME="$RUN_ROOT/home" XDG_DATA_HOME="$RUN_ROOT/xdg-data" XDG_CONFIG_HOME="$RUN_ROOT/xdg-config" XDG_CACHE_HOME="$RUN_ROOT/xdg-cache" XDG_RUNTIME_DIR="$RUN_ROOT/xdg-runtime" XDG_STATE_HOME="$RUN_ROOT/xdg-state" YOSUGA_GAME_DIR="$GAME_DIR" GODOT_SILENCE_ROOT_WARNING=1
  godot --headless --verbose --audio-driver Dummy --path godot_port --script res://tests/title_saveload_smoke.gd -- "$GAME_DIR"
  godot --headless --verbose --audio-driver Dummy --path godot_port --quit-after 240
  (cd "$GAME_DIR" && sha256sum -c <(awk -F '\t' 'NR > 1 { print $3 "  " $1 }' "$REPO_ROOT/godot_port/docs/original-assets-readonly-manifest-2026-11-29.tsv"))
  ```

  本轮 `summary.tsv` 和命令/退出日志保存在本地 `$RUN_ROOT`（当次路径 `/root/.cache/yzk-native-paths.HKl2FT`），不作为仓库测试产物提交；后续复测应生成新 run root 并重新校验 manifest。

## 接续顺序 / 关闭门槛

1. **官方 SDK/runtime 执行仍待完成。** 官方 SDK source subset 在仓库外 `/root/reference-sources/entisgls-sdk-selected` 可供只读检查，但没有成功运行的官方 runtime harness，也没有官方执行/差分证据。下一阶段如开展 harness，原始资源只读，须证明官方 context 成功载入 CSX 并达到可记录脚本阶段；许可、ABI、平台、API blocker 均须记录，不拿自研 VM 代替官方执行结论。
2. 与此同时保持 A01–A20 差距表更新；A02 在正常 Story/Title/save-load teardown smoke 中未观察到持续对象累积；`--quit-after` 主场景强制退出仍偶见一对 WAV/PlaybackWAV ObjectDB 警告，正常 app-close 与其归因待验证；7–8 个 orphan StringName 和该退出诊断作为 P2 跟踪。当前尚未关闭的核心 P1 风险为 A01（候选：官方 flush/物理输入语义未定）、A04（官方存档恢复语义）、A06（Story/HostWindow 双渲染所有权）、A14（通用 HostFile 流接口）、A15（项目跟踪的同步调用共享状态风险候选，非已确认官方契约缺陷）和 A19（全量宿主 API 差异清单）。A15 的 task-54 搜索限于 8 个选定 SDK 文件，未找到权威契约，且无官方 runtime differential；任何语义变更须先经权威契约或官方参考运行确认。A13 已按当前证据降为 P2 跨路由互操作风险；其是否需要共享设置值仍待针对性验证。在取得官方参考前，不把项目内实现推测成兼容行为。
3. 用实际脚本入口逐项覆盖窗口/输入/精灵/文本/资源/音视频/存档桥。先定义官方参考输出，再决定哪些自实现保留为 host adapter、哪些 VM/UI 近似实现应被原生路径替代。
4. 做一条端到端纵切：官方/兼容 CSX 入口 → message/bustup/动画 → 物理输入与 choice → 音频/视频 → 真实保存/读档 → 返回；记录状态、渲染、音频时序差分和原始资源哈希。
5. 完成门槛必须有**官方 Cotopha runtime 实际执行未修改 CSX 到可记录脚本阶段**的证据，并且对每条被宣称兼容的核心路径记录与官方 runtime/SDK 输出的行为对照；自研 VM 的真实资源烟测不能替代此门槛。若官方执行/对照因 ABI、平台、许可或 API blocker 无法达到，目标保持未完成、如实报告 blocker，不得宣称主要原生路径完整可用。除此之外还须由独立 Luna 复核当前 matrix、未关闭 P0/P1 及自实现依赖；P0 清零、核心 P1 有证据关闭或经用户确认排除、P2 已处理或有理由、核心真实资源回归通过。
