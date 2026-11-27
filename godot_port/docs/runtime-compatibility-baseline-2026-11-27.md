# yzk2godot 原版运行时兼容基线（2026-11-27）

本文件是本轮接续工作的**当前差距基线**，优先于下方所链接的历史检查点；历史记录仍用于解释结论如何形成。这里的优先级是 A01–A20 的当前残余风险，原始交接优先级另列，不把一次内部烟测通过等同于原版运行时兼容。

## 快照、证据标准与只读边界

- 仓库：分支 `main`，`HEAD=8de808d0b71a013766318ea7286c8330463e07b2`。本基线是在已有未提交工作树上审计的；不能把工作树现状归因于该提交。开始审计前已有解码器、VM、宿主、测试与文档改动，另有当前 Goal 的 `.pi/` 状态文件。本轮额外新增/调整：MEI 全流测试路径修正、Story selection teardown 诊断、`story_lifecycle_smoke.gd` 和本基线/轨迹文档校准。
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
| Title / Config / Appreciation | `native_title_player_smoke.gd` 通过，执行真实 CSX `Title()` / Appreciation 路径；原版标题/部分配置窗口由 HostWindow 展示。 | 这是原版脚本在自研 VM 上运行；不能证明官方 runtime 语义。Story 配置仍有 Godot 自建 modal/settings 路径。 |
| Story 消息与选择 | `native_story_compositor_smoke.gd` 到达真实 `00_Z000` MessageSprite/HostWindow，检查文本、渐显状态和 10 个按钮；`native_story_selection_smoke.gd` 到达 `00_Z005` 的原版 `AdvScreen::startSelect`，选择后 `selectResult=1`。 | 成功证明了自研 VM 上原始 CSX 的部分窗口树与选项闭环。输入由测试合成按钮触发并提供逻辑光标位置；物理鼠标/键盘、官方 Cotopha 差分尚无证据。QSave 测试只证实命令入队/唤醒，不证实实际写入存档。 |
| 立绘/动画/compositor | Story 测试证明 HostWindow 消息树渲染及显式 `SetBustup`/`AdvScreen::update` 探针被单一路径显示。 | 探针不是自然剧情事件；自然场景的 bustup 附着、跨模式/转场、裁剪/混合/逐像素原版对照仍未证明。Godot CG/temp/unattached-bustup 回退节点仍存在。 |
| 音视频 | `mei_playback_smoke.gd` 通过；`mei_fullstream_smoke.gd` 已修正为接收游戏目录与隔离存档，本轮完整解码 2520 个视频记录通过（28.49 秒）。 | 这是项目内 MEI 解码/播放验证。官方 SDK 的像素、PCM、时序差分仍缺；Audio Dummy 不能证明硬件音频时钟同步。其他 MEI 变体覆盖不完整。 |
| 存档/读档 | `save_storage_contract_smoke.gd` 通过，覆盖项目自有 JSON 格式、原子提交、备份恢复、对象图和模式权限；Title/Story 的部分入口由真实 CSX 驱动。 | 完整“原版 Story UI 操作 → 真实存档写入 → 重启/读档 → 原剧情恢复”的端到端路径未完成；JSON 格式是项目自有格式，不是 Cotopha 原生存档兼容证明。 |
| 官方运行时 | 当前 `adv_player.gd` 将脚本装入项目 `CsxVM`；历史轨迹承认官方 Cotopha 执行 0/3。Luna 只读检查确认 `/workspace` 不存在；`/workspace/reference-sources/official-runtime-harness`、官方 ZIP/source 子集及 `/mnt/sdb1/devs/reference-sources/...` 不存在；`/root/reference-sources` 仅剩 codec 相关产物、`entisgls-sdk-legal/` 中带反斜杠文件名的 `license.txt`/`readme.txt`，以及 `/root/reference-sources/tools/entisgls_remote_zip.py` 获取辅助脚本，不含 SDK 源码或 harness。未下载、构建或修改任何 SDK 文件。 | **原版运行时执行仍是此目标的首要架构缺口。** 旧文档中的“已获取 SDK 源码”是历史记录，不代表当前文件可访问或可复核。当前暂停依赖 SDK 的改动；请用户提供可访问的官方源码/harness 路径，或明确批准在仓库外重新获取官方源子集。获得许可与文件前，不得用推测性替代实现冒充官方 runtime parity。 |

## A01–A20 差距表

“交接优先级”来自上一轮问题表；“当前优先级”按本轮残余风险保守分级。标为“已解决”的只表示所列自研实现契约有回归覆盖，不表示已达到官方 Cotopha parity。

| ID / 原交接优先级 | 当前优先级 / 状态 | 当前证据（代码 / 测试，证据强度） | 剩余缺口与关闭验证 |
|---|---|---|---|
| **A01 输入等待阻塞原始菜单命令** / P0 | **P1，项目调度及分派链已覆盖；原版 flush 语义未确认** | `adv_player.gd:925–930,959–962` 在等待输入时允许活动窗口有命令就继续 VM；`host_command_queue.gd:35–46,123–164` 有 scope/FIFO/容量/关闭；`native_story_compositor_smoke.gd` 与 `native_story_selection_smoke.gd` 用真实 CSX 验证命令唤醒/消费（输入为合成触发）；`host_command_queue_smoke.gd` 覆盖队列本身；新增 `host_flush_integration_smoke.gd` 通过 CsxVM 的 HostWindow dispatcher 测 push→FlushCommandQueue→GetCommand。该新测试只锁定本项目的 no-op flush 策略，不证明原版语义。 | `FlushCommandQueue` 仍是 no-op（`csx_host.gd:2656–2662`），原始 CSX 有 40 处调用；物理输入时序及 SDK flush 语义未确认。需官方参考输出后才能变更 flush 行为；物理鼠标/键盘时序另行验证。 |
| **A02 Story 对象/纹理泄漏** / P0 | **P2，所测路径的 ObjectDB/RID 警告已通过 teardown 排除；StringName 残项未归因** | 移除未挂接 Button 后早期 ObjectDB/RID 报告曾停止。进一步复跑发现：没有 audio-drain 的 selection 测试在部分退出中泄漏 4 个对象；verbose 给出 2 个 `AudioStreamWAV` 与 2 个 `AudioStreamPlaybackWAV`。`native_story_selection_smoke.gd` 现在显式调用幂等的 runtime shutdown、释放 AdvPlayer、等待一帧和 250 ms；之后 3 次普通 + 1 次 verbose selection smoke 均无 ObjectDB/RID warning。新增 `story_lifecycle_smoke.gd` 在同一进程启动/推进/释放 3 个真实 `00_Z000` CSX 会话，正常退出；verbose 仅余 7 个 orphan StringName。音频对象类型与 teardown drain 的相关性支持“退出时 AudioServer 异步释放尚未完成”的解释，但尚非独立根因证明。 | 该测试覆盖证明没有观察到同进程会话累积或退出 ObjectDB/RID 警告，不等同于全局 RSS/资源零泄漏。把 ObjectDB/RID 作为所测路径已关闭的 P0；残余 7 个 orphan StringName 单独追查并作为 P2 诊断项，不将其等同于泄漏对象。后续在 Title/recollection/媒体失败清理路径重复 teardown smoke，并在不同音频驱动环境复核。 |
| **A03 CSX 构造函数错误传播** / P0 | **已解决（自研 VM 契约）** | `csx_vm.gd:644–712,876–880,919–925` 在构造失败时返回显式创建错误，不继续伪造对象；`vm_sync_call_smoke.gd:111–148` 覆盖失败/超时构造。合成 VM 测试，非官方 runtime 对照。 | 仅当官方 Cotopha 接入/差分时再关闭原版构造语义差异；保留可能已有副作用的错误诊断。 |
| **A04 存档恢复遗漏精灵/音频状态** / P0 | **P1，部分解决** | `native-runtime-trajectory.md` 的 A04 记录 schema v7、HostResource play type 和音量 envelope 进度恢复；`csx_host.gd:5774–5788` 恢复 envelope/audio 状态；`save_storage_contract_smoke.gd` 覆盖合成存档图。 | 恢复 envelope 不等于重新启动正在播放的声音；覆盖活动音频、剩余 envelope、实际 Story UI 保存/读档和重新启动行为，明确与原版的期望。 |
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
| **A19 未实现 Host API 假成功** / P1 | **代表性 dispatch 已解决；API 清单覆盖未完成** | `csx_vm.gd:1445–1451,1993,2014–2018` 令未实现全局/成员调用报错且不压入伪造返回值；`host_unsupported_api_smoke.gd` 通过。`UpdateWindow` 保留为 redraw 请求，已知一些窗口/输入 API 仍是 partial/no-op。 | 建立原始 CSX 实际调用点与 Host handlers 的完整差异表；每个 no-op 必须有证据支持或改为显式 unsupported；最终用官方 runtime 比较返回值。 |
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

## 接续顺序 / 关闭门槛

1. **当前官方 SDK/runtime 轨道暂停，等待用户提供源码/harness 路径或批准仓库外重新获取。** `/workspace` 与历史 SDK/harness 路径均缺失；在取得许可和文件前，不下载/改写替代代码、不声称 parity。恢复后再于项目外构建最小控制台 harness，原始资源只读，证明官方 context 成功载入 CSX 并达到可记录脚本阶段；许可、ABI、平台、API blocker 均须记录，不拿自研 VM 代替官方执行结论。
2. 与此同时保持 A01–A20 差距表更新；A02 的对象泄漏报告在所测 Story 生命周期经 audio-drain teardown 后不再复现，剩余 orphan StringName 作为 P2 诊断项跟踪。继续优先解决核心 P0，再处理 P1；A01/A10/A13/A14/A15 与 Story UI 属于当前主要行为/架构风险。
3. 用实际脚本入口逐项覆盖窗口/输入/精灵/文本/资源/音视频/存档桥。先定义官方参考输出，再决定哪些自实现保留为 host adapter、哪些 VM/UI 近似实现应被原生路径替代。
4. 做一条端到端纵切：官方/兼容 CSX 入口 → message/bustup/动画 → 物理输入与 choice → 音频/视频 → 真实保存/读档 → 返回；记录状态、渲染、音频时序差分和原始资源哈希。
5. 完成门槛必须有**官方 Cotopha runtime 实际执行未修改 CSX 到可记录脚本阶段**的证据，并且对每条被宣称兼容的核心路径记录与官方 runtime/SDK 输出的行为对照；自研 VM 的真实资源烟测不能替代此门槛。若官方执行/对照因 ABI、平台、许可或 API blocker 无法达到，目标保持未完成、如实报告 blocker，不得宣称主要原生路径完整可用。除此之外还须由独立 Luna 复核当前 matrix、未关闭 P0/P1 及自实现依赖；P0 清零、核心 P1 有证据关闭或经用户确认排除、P2 已处理或有理由、核心真实资源回归通过。
