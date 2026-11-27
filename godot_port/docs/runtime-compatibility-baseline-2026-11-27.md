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
| 官方运行时 | 当前 `adv_player.gd` 将脚本装入项目 `CsxVM`；历史轨迹承认官方 Cotopha 执行 0/3。Luna 只读检查确认 `/workspace` 不存在；`/workspace/reference-sources/official-runtime-harness`、官方 ZIP/source 子集及 `/mnt/sdb1/devs/reference-sources/...` 不存在；`/root/reference-sources` 仅剩 codec 相关产物、`entisgls-sdk-legal/` 中带反斜杠文件名的 `license.txt`/`readme.txt`，以及 `/root/reference-sources/tools/entisgls_remote_zip.py` 获取辅助脚本，不含 SDK 源码或 harness。未下载、构建或修改任何 SDK 文件。 | **原版运行时执行仍是此目标的首要架构缺口。** 旧文档中的“已获取 SDK 源码”是历史记录，不代表当前文件可访问或可复核。当前暂停依赖 SDK 的改动；请用户提供可访问的官方源码/harness 路径，或明确批准在仓库外重新获取官方源子集。获得许可与文件前，不得用推测性替代实现冒充官方 runtime parity。 |

## A01–A20 差距表

“交接优先级”来自上一轮问题表；“当前优先级”按本轮残余风险保守分级。标为“已解决”的只表示所列自研实现契约有回归覆盖，不表示已达到官方 Cotopha parity。

| ID / 原交接优先级 | 当前优先级 / 状态 | 当前证据（代码 / 测试，证据强度） | 剩余缺口与关闭验证 |
|---|---|---|---|
| **A01 输入等待阻塞原始菜单命令** / P0 | **P1，项目调度及分派链已覆盖；原版 flush 语义未确认** | `adv_player.gd:925–930,959–962` 在等待输入时允许活动窗口有命令就继续 VM；`host_command_queue.gd:35–46,123–164` 有 scope/FIFO/容量/关闭；`native_story_compositor_smoke.gd` 与 `native_story_selection_smoke.gd` 用真实 CSX 验证命令唤醒/消费（输入为合成触发）；`host_command_queue_smoke.gd` 覆盖队列本身；`host_flush_integration_smoke.gd` 通过 CsxVM 的 HostWindow dispatcher 测 push→FlushCommandQueue→GetCommand；dispatch 按窗口 ID 精确隔离，只有 `-1` 是全局哨兵（Godot instance ID 可为负，不能用 `<0` 判断）；直接 VM 的 `HostInputFilter` 路径从 `OpenFilter.window_ref` 解析所属窗口。测试覆盖 HostWindow 与直接/活动 HostInputFilter 的同窗/跨窗路径（含 `during_activation`）、窗口销毁清理和新 scope reset。该测试锁定本项目调度/no-op flush 策略，不证明原版语义。 | `FlushCommandQueue` 仍是 no-op（`csx_host.gd:2656–2662`），原始 CSX 有 40 处调用；物理输入时序及 SDK flush 语义未确认。需官方参考输出后才能变更 flush 行为；物理鼠标/键盘时序另行验证。 |
| **A02 Story 对象/纹理泄漏** / P0 | **P2，所测路径的 ObjectDB/RID 警告已通过 teardown 排除；StringName 残项未归因** | 移除未挂接 Button 后早期 ObjectDB/RID 报告曾停止。进一步复跑发现：没有 audio-drain 的 selection 测试在部分退出中泄漏 4 个对象；verbose 给出 2 个 `AudioStreamWAV` 与 2 个 `AudioStreamPlaybackWAV`。`native_story_selection_smoke.gd` 现在显式调用幂等的 runtime shutdown、释放 AdvPlayer、等待一帧和 250 ms；之后 3 次普通 + 1 次 verbose selection smoke 均无 ObjectDB/RID warning。新增 `story_lifecycle_smoke.gd` 在同一进程启动/推进/释放 3 个真实 `00_Z000` CSX 会话，正常退出。首轮回归中 `native_story_compositor_smoke.gd`、`native_title_player_smoke.gd` 与 `native_resource_error_contract_smoke.gd` 立即退出时也出现 2 个 ObjectDB 实例；verbose 将 compositor/title 两项定位为一对 `AudioStreamWAV` / `AudioStreamPlaybackWAV`。三项测试现均显式 runtime shutdown 并等待 process frame + 250 ms AudioServer drain，`--verbose` 复跑不再报告 ObjectDB/RID 实例泄漏。StringName orphan 仍作为 P2；音频关联支持测试 teardown 时序解释，不能证明生产运行时全局零泄漏。 | 该测试覆盖证明没有观察到同进程会话累积或退出 ObjectDB/RID 警告，不等同于全局 RSS/资源零泄漏。把 ObjectDB/RID 作为所测路径已关闭的 P0；残余 7 个 orphan StringName 单独追查并作为 P2 诊断项，不将其等同于泄漏对象。后续仍需在媒体解码失败清理路径和非 Dummy audio driver 下复核。 |
| **A03 CSX 构造函数错误传播** / P0 | **已解决（自研 VM 契约）** | `csx_vm.gd:644–712,876–880,919–925` 在构造失败时返回显式创建错误，不继续伪造对象；`vm_sync_call_smoke.gd:111–148` 覆盖失败/超时构造。合成 VM 测试，非官方 runtime 对照。 | 仅当官方 Cotopha 接入/差分时再关闭原版构造语义差异；保留可能已有副作用的错误诊断。 |
| **A04 存档恢复遗漏精灵/音频状态** / P0 | **P1，项目自研保存/恢复路径有实际资源回归；官方语义未确认** | 除 schema v7 与 envelope 恢复外，`bustup_smoke.gd` 通过真实 CSX QuickSave/QuickLoad 验证 `scObj.scenarioCall`、`isLoad=-1`、BGM07 和 SE270 在 `ScenarioLoop` 后恢复；`title_saveload_smoke.gd` 通过原版 Title LoadSaveWindow/Confirm 载入 Save003，并在确认前篡改内存中的 `scenarioCall`，断言读档恢复保存值并将该 continuation 作为 `ScenarioLoop` 参数。 | 以上仍是项目 JSON/Host 与自研 VM 的结果。缺官方 Cotopha 对照；未覆盖原版 Story 保存 UI 写档、进程重启、完整精灵树和所有活动音频通道。保持 P1 parity 风险，不把自研烟测解释为原版兼容已关闭。 |
| **A05 备份恢复只覆盖部分失败** / P1 | **已解决（项目自有存档格式的已测场景）** | `csx_host.gd:4386–4445,4455–4489,4773–4780` 原子保存、主备候选、阶段化恢复；`save_storage_contract_smoke.gd:420–450,508–535` 覆盖主文件损坏/语义无效时回退。合成 fixture。 | 不等同原生存档格式兼容；继续用真实 UI 路径测试用户操作和崩溃恢复。 |
| **A06 新旧渲染路径重复/分叉** / P1 | **P1，部分解决** | `adv_player.gd:474,1089–1226,2743–2762,3446+` 仍构建隐藏 DialogueBox 并保留 bustup/CG/temp/回退渲染；Story HostWindow 激活时隐藏 dialogue/background。真实 Story compositor smoke 证明当前消息流未双绘，附着 bustup 仅用显式探针验证。 | 仍是双路径架构，模态/转场/自然立绘路径可不一致。对 Story、Title、Config、SaveLoad 模式迁移逐项证明唯一渲染所有权，再做原版参考帧对照。 |
| **A07 背景覆盖检测错误** / P1 | **P2，逻辑已改、视觉差分未证** | `adv_player.gd:2765–2800` 递归考虑变换、继承可见/不透明度和表面；`native_story_compositor_smoke.gd:242–299` 测变换覆盖及按钮多状态纹理不透明度。真实 CSX compositor 路径通过。 | 组合裁剪、Z 顺序、blend、透明像素和实际输出还未与官方渲染对照。增加像素级 fixture 与原版参考捕获。 |
| **A08 精灵命中与显示变换不一致** / P1 | **P2，几何变换已覆盖；命中掩码未证** | `csx_host.gd:1938–1974` 逆变换到精灵局部坐标并检查父链可见/透明；`native_sprite_methods_smoke.gd` 覆盖旋转命中/假阳性。Story 选项实际 CSX 流程使用逻辑坐标，不是物理指针。 | `hit_transparency=true` 目前没有消费者；父子组合、零缩放、alpha hit mask、实际鼠标/触屏需要测试；透明像素语义应先核对 SDK。 |
| **A09 焦点覆盖按钮选中状态** / P1 | **P2，自研状态修复已测** | `csx_host.gd:2544–2563` 将 `has_window_focus` 与 checked/pushed 状态分开；`native_sprite_methods_smoke.gd` 覆盖选中态跨焦点变化。 | 原版键盘导航、hover/pressed/focus/checked 纹理优先级和多窗口切换需真实交互/SDK 参照。 |
| **A10 命令队列缺生命周期约束** / P1 | **P2，队列自身已解决；集成边界未全证** | `csx_host.gd:2876–2925` 管理 scope 和入队，`host_command_queue.gd` 丢弃 stale token、窗口/精灵事件清理并在 shutdown 后拒绝；`host_command_queue_smoke.gd` 全部通过（内部 fixture）。 | 原始窗口切换/销毁和 Godot 物理输入的队列时序未全覆盖；继续从真实菜单到切换/关闭的集成测试。 |
| **A11 文本转义、渐显、字体状态** / P1 | **P2，基础行为部分验证** | `adv_player.gd:3217–3242,3340–3352` 处理转义、渐显、fade 和字体 override reset；`native_story_compositor_smoke.gd` 用真实 MessageSprite 检查解析文本/reveal count 和字体重置。 | 复杂 BBCode/literal brackets、字体 fallback、换行/对齐、跨语言字形、fade 时序无原版差分。构建覆盖矩阵和参考截图/行为测试。 |
| **A12 控件类型变化未同步** / P1 | **P2，动态变化尚未证明** | `adv_player.gd:2899–2930` 在新建 wrapper 时按类型创建 Button/slider/texture control；之后主要更新现有节点状态（`:2990–3024`）。`native_form_page_smoke.gd` 读取真实 title/frame NOA 皮肤数据，但直接构造 synthetic HostSprite/form-page fixtures；只测创建后的控件，不证明原始 CSX 表单流程或后续类型切换。 | 先审计原版 API/CSX 是否在 wrapper 已创建后改变 control type；若可达则实现类型切换并添加回归，否则记录“不可达”的静态/实际脚本证据。 |
| **A13 原生设置与模拟设置双状态** / P1 | **P1，未关闭** | Title 里的 CSX ConfigWindow 有真实原始脚本路径；Story 输入可进入 Godot-owned settings modal（`adv_player.gd:1038–1040,3866–3889,3966–3980`），JSON 状态属于项目自有。相关 smoke 对原版 Title Config 与 Godot modal 分开验证。 | 收拢状态源；隔离保存目录验证重启持久化，并说明 Story overlay 是兼容 fallback 还是迁移到 CSX；不得用模拟 UI 测试宣称原版 config.dat 兼容。 |
| **A14 HostFile 未检查读写模式** / P1 | **P1，模式权限已修，文件桥未完成** | `csx_host.gd:2697–2728,2732–2746` 检查 open mode、阻止只读写/只写读；`save_storage_contract_smoke.gd:469–485` 验证。旧轨迹关于“缺少 open-mode semantics”与当前代码冲突，应以本表为准。 | HostFile 仍缺通用读取、写入、seek、length、position 及原版流对象行为；实现/核对官方接口并测各 mode。 |
| **A15 同步 VM 调用上下文隔离不完整** / P1 | **P1，执行控制状态部分隔离** | `csx_vm.gd:736–807` 保存/恢复 IP、栈、返回值、同步标志、cooperative sleep；`vm_sync_call_smoke.gd` 覆盖嵌套调用/失败/超时。 | 同步调用中发生的全局/Host 副作用不会回滚，是显式行为；剩余 scheduler/input/error 字段和重入场景仍需测试，并定义共享状态契约。 |
| **A16 视频追帧无每帧预算** / P2 | **P2，开放** | `adv_player.gd:1585–1660` 按过期帧同步解码；限制最多到影片帧数而非每帧小预算。fullstream 证明功能，不证明帧延迟。 | 大 delta/audio lag 下测单帧工作量和最长帧耗时；若限预算需证明最终追帧行为与原版一致。 |
| **A17 全量逐帧渲染同步成本** / P2 | **P2，开放** | `adv_player.gd:871–940,2698–2738,2882–2892` 每帧并在 VM batch 后递归同步 HostWindow 并清理 stale wrapper；没有 dirty/revision early-out 证据。 | 对大型树采样 visit 数和帧时间，增加“不变树不重复同步、变更仍重绘”测试；优化不能丢 UpdateWindow/redraw 请求。 |
| **A18 内存预算未覆盖全生命周期** / P2 | **P2，部分** | `csx_host.gd:32–50,3477–3513` 有图像/声音 cache 限额，但注释明确不包含 sprite/player/GPU/active decoder 保留；native MEI 256 MiB 是 estimated working-set 而非 RSS。`resource_read_limits_smoke.gd`、MEI codec smoke 覆盖组件边界。 | 定义全局预算与所有者；多资源生命周期压力测试并测 peak RSS/native buffers/GPU（可行时），或清晰限定当前预算范围。 |
| **A19 未实现 Host API 假成功** / P1 | **代表性 dispatch 已解决；API 清单覆盖未完成** | `csx_vm.gd:1445–1451,1993,2014–2018` 令未实现全局/成员调用报错且不压入伪造返回值；`host_unsupported_api_smoke.gd` 通过。`UpdateWindow` 保留为 redraw 请求。真实 Story `ID_CONFIG` 流程还覆盖 `File::IsExisting(".mio")` 的可选资源缺失路径：`native_resource_error_contract_smoke.gd` 检查 Host predicate、HostFile 和 CSX handler 均返回 false 且保留前一诊断，`native_story_config_smoke.gd` 检查原始 CSX 在自研 VM 上执行后没有残留该 miss 诊断；这仍是自运行时证据，未与官方 Host 比对。已知一些窗口/输入 API 仍是 partial/no-op。 | 建立原始 CSX 实际调用点与 Host handlers 的完整差异表；每个 no-op 必须有证据支持或改为显式 unsupported；最终用官方 runtime 比较返回值。 |
| **A20 存档缩略图边界** / P1 | **P2，主要边界已覆盖** | `csx_host.gd:4296–4341` 限制 16 MiB 文件、PNG IHDR 最大尺寸/像素数并在解码后复核；`thumbnail_bounds_smoke.gd:13–63` 测有效图、超尺寸 IHDR、hash。 | 对截断/畸形/边缘 PNG 扩展 fixture 或 fuzz；确认 Godot 解码器瞬时内存边界。 |

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
- 三份独立 Luna 只读复核分别检查 Title 读档交接、A01–A20 当前差距和正则捕获类型。未发现新交接代码或捕获变更中的明确 P0/P1 缺陷；审计仍将 A01、A04、A06、A13、A14、A15、A19 列为未关闭或待官方语义确认的 P1 风险。A02 无所测路径的 ObjectDB/RID 泄漏证据，StringName 残项继续作为 P2 诊断；A03 的结论仅限自研 VM。
- 本次补充的真实资源/自研运行时回归均 exit 0：`native_title_player_smoke.gd`、`title_saveload_smoke.gd`、`bustup_smoke.gd`、`save_storage_contract_smoke.gd`、`native_form_page_smoke.gd`、`native_story_selection_smoke.gd`、`choice_interaction_smoke.gd`、`story_lifecycle_smoke.gd`、`native_activation_input_smoke.gd`、`native_adv_screen_sprite_smoke.gd`、`native_menu_config_smoke.gd`、`native_saveload_voice_smoke.gd`、`native_reference_smoke.gd`、`native_sprite_methods_smoke.gd`、`sprite_activation_smoke.gd`、`sprite_effect_smoke.gd`、`native_bezier_math_smoke.gd`、`native_alpha_mask_contract_smoke.gd`、`native_shading_filter_smoke.gd`、`sprite_tree_contract_smoke.gd`、`vm_safety_smoke.gd`、`vm_sync_call_smoke.gd`、`vm_cooperative_sleep_smoke.gd`、`host_command_queue_smoke.gd`、`host_flush_integration_smoke.gd`、`host_unsupported_api_smoke.gd`、`audio_host_contract_smoke.gd`、`mei_codec_smoke.gd`、`mei_playback_smoke.gd` 和 `mei_fullstream_smoke.gd`（全流 2520 帧，31.39 秒）。其中 `choice_interaction` 与 `native_bezier_math` 在首次启动时漏传资源路径，修正参数后通过；这两次启动错误不计作游戏行为失败。
- 上述真实资源烟测未修改原始文件。最终读取的 SHA-256 与基线相同：`system/yosuga.csx` `157be9eb39cdc2d3cb654096340ca686f4ef48ac7fd7a6255673ba5f0c79afb6`、`data1.noa` `d324c49ed4a80108f68aabaf7a202ec31d1b8f64075918f136944e72ec919831`、`voice.noa` `b3b39bb227ea60ecffbfcd8812e232a9b72f930ee2103465572955ff899e54e9`、`opening.mei` `9509dc23f0060f0ac98b67a3d7c3331bc0a0efc95450c8e0f311c51c592bf137`。此前 `native_form_page_smoke.gd` 还核对 `system/title.noa`、`system/frame.noa`、`system/option.noa` 与 `sound.noa` 的固定哈希。 `
## 本轮补充：Host command dispatch 与可选资源探测（2026-11-27）

- `HostWindow.GetCommand` 消费非空事件后将 pending-dispatch 绑定到该窗口；按 Godot instance ID 精确查询（ID 可为负，只有 `-1` 表示全局查询）。其后 `GetJoyButtonPushed`（HostWindow、活动过滤器以及 CSX 直接调用 `HostInputFilter`）只在所属窗口 dispatch 尚未被空 `GetCommand` 收尾时抑制 scheduler input wait；直接过滤器调用从 `OpenFilter.window_ref` 得到窗口归属。其它窗口的空轮询或 advance-button poll 不会误清除/抑制本窗口状态。弱引用窗口销毁、命令 scope 切换和 runtime shutdown 都清理状态；`during_activation` 仍设置 cooperative sprite yield。`host_flush_integration_smoke.gd` 验证这些项目内契约；不是官方 runtime parity。
- `CsxHost.is_file_existing()` 将正常 VFS miss 作为 false predicate；仅当 lookup 写入对应的标准 `VFS entry not found` 诊断时才恢复既有 `last_error`。当前实现与调用链由 smoke 覆盖，官方 `File::IsExisting` 对错误状态副作用的语义仍待参考。
- 可复现命令（仓库根目录，`<game-dir>` 指原始游戏目录）：

  ```sh
  godot --headless --path godot_port --script res://tests/host_flush_integration_smoke.gd -- '<game-dir>'
  godot --headless --path godot_port --script res://tests/native_resource_error_contract_smoke.gd -- '<game-dir>'
  godot --headless --path godot_port --script res://tests/native_story_config_smoke.gd -- '<game-dir>'
  ```

  三项均 exit 0。Story Config smoke 执行真实 `00_Z000` 的 CSX `ID_CONFIG` → `ConfigWindow::run` → 可见 `ID_PAGE_CONFIG` 路径（由项目 GDScript VM 执行），并对 `system/yosuga.csx`、`data1.noa`、`sound.noa`、`system/title.noa`、`system/frame.noa`、`system/option.noa` 做前后 SHA-256 比较；未发现变化。`native_resource_error_contract_smoke.gd` 实际从原始 `sound.noa` 解码 `BGM07.mio` 并验证播放 API Error codes，清理 runtime 与播放器后通过。
- 独立 Luna 只读复核确认 dispatch 生命周期清理和 VFS miss 恢复未见具体实现缺陷；审查也强调上述 self-runtime 结果不能代替官方 `FlushCommandQueue`、物理输入或 `IsExisting` 行为差分。初轮审查指出 active HostInputFilter 路径缺少覆盖，补测后第二轮审查进一步发现直接 VM dispatch 未继承过滤器窗口归属；修复从 `OpenFilter.window_ref` 解析 owner，并将 `-1` 作为唯一全局哨兵（Godot `instance_id` 可为负），加入同窗/跨窗断言。最终 Luna 复审未发现该改动中的具体 P0/P1；官方语义差距仍未关闭。
- 该修复后重跑 33 项核心回归，均 exit 0：上述历史 30 项列表，加 `native_story_config_smoke.gd`、`native_story_compositor_smoke.gd`、`native_resource_error_contract_smoke.gd`。其中包含真实 Title/Story 输入、Config/存读档、精灵与动画、VM/Host、音视频路径；8 份原始资源（`system/yosuga.csx`、`data1.noa`、`voice.noa`、`opening.mei`、`system/title.noa`、`system/frame.noa`、`system/option.noa`、`sound.noa`）前后 SHA-256 一致。`cg_catalog_source_smoke.gd` 也通过；其断言已改为保留 Linux 物理归档路径大小写，与 VFS 的大小写敏感 identity 一致。
- 两个额外目录扫描用例未计入通过集：`csx_vm_smoke.gd` 通过 `call_function_sync` 尝试同步跑完整 `sc00_Z000`，300,000 步预算在 `0x14CAE` 超时；相关真实 Story 输入/选择/配置已由异步调度 smoke 独立覆盖。`native_codec_differential_smoke.gd` 依赖可选的 `arc_unpacker` sidecar（`YOSUGA_ARC_UNPACKER` 未设置且 PATH 无 helper），因此本环境无法做外部 ERI/MIO 字节差分；本轮仍通过 in-process codec 与媒体烟测。两项均不宣称通过，也不改变无 CLI runtime fallback 的设计。

## 接续顺序 / 关闭门槛

1. **当前官方 SDK/runtime 轨道暂停，等待用户提供源码/harness 路径或批准仓库外重新获取。** `/workspace` 与历史 SDK/harness 路径均缺失；在取得许可和文件前，不下载/改写替代代码、不声称 parity。恢复后再于项目外构建最小控制台 harness，原始资源只读，证明官方 context 成功载入 CSX 并达到可记录脚本阶段；许可、ABI、平台、API blocker 均须记录，不拿自研 VM 代替官方执行结论。
2. 与此同时保持 A01–A20 差距表更新；A02 的对象泄漏报告在所测 Story 生命周期经 audio-drain teardown 后不再复现，剩余 orphan StringName 作为 P2 诊断项跟踪。当前尚未关闭的核心 P1 风险为 A01（flush/物理输入语义）、A04（官方存档恢复语义）、A06（Story/HostWindow 双渲染所有权）、A13（原生与 fallback 设置状态）、A14（通用 HostFile 流接口）、A15（同步调用共享状态契约）和 A19（全量宿主 API 差异清单）。在取得官方参考前，不把项目内实现推测成兼容行为。
3. 用实际脚本入口逐项覆盖窗口/输入/精灵/文本/资源/音视频/存档桥。先定义官方参考输出，再决定哪些自实现保留为 host adapter、哪些 VM/UI 近似实现应被原生路径替代。
4. 做一条端到端纵切：官方/兼容 CSX 入口 → message/bustup/动画 → 物理输入与 choice → 音频/视频 → 真实保存/读档 → 返回；记录状态、渲染、音频时序差分和原始资源哈希。
5. 完成门槛必须有**官方 Cotopha runtime 实际执行未修改 CSX 到可记录脚本阶段**的证据，并且对每条被宣称兼容的核心路径记录与官方 runtime/SDK 输出的行为对照；自研 VM 的真实资源烟测不能替代此门槛。若官方执行/对照因 ABI、平台、许可或 API blocker 无法达到，目标保持未完成、如实报告 blocker，不得宣称主要原生路径完整可用。除此之外还须由独立 Luna 复核当前 matrix、未关闭 P0/P1 及自实现依赖；P0 清零、核心 P1 有证据关闭或经用户确认排除、P2 已处理或有理由、核心真实资源回归通过。
