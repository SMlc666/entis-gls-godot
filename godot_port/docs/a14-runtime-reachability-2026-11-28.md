# A14 bounded runtime trace — 2026-11-28

## Result and scope

A temporary trace of the project-owned CSX VM observed File dispatches while the original Story opening ran through 16 dialogue lines in `adv_player_smoke.gd`. It observed **22** dispatches total: **18 `IsExisting`**, **2 `Open` with mode 5**, and **2 `SaveObject`**. The A14 `OutputLogText` → `Open(4)` / fallback `Open(5)` → `Seek(0, 2)` → `WriteText` → `Close` sequence was **not observed in this bounded flow**. This says nothing about whether that sequence is reachable in other story paths or sessions.

This is evidence of execution by this project's runtime, not the official Cotopha runtime. The official Native `File` semantics, encoding, error behavior, and parity remain unresolved. No semantic change is authorized by this trace.

## Run procedure and outcome

The Luna (`openai/gpt-6-luna`) scout copied the project with `cp -a godot_port /tmp/yzk-a14-trace-project`, instrumented only the copied `scripts/csx_vm.gd`, and ran the copied real-resource smoke against the original game directory. The executable reported `Godot Engine v4.7.stable.official.5b4e0cb0f`.

Invocation and relevant environment:

```sh
HOME=/tmp/yzk-a14-home \
XDG_CONFIG_HOME=/tmp/yzk-a14-home/.config \
XDG_CACHE_HOME=/tmp/yzk-a14-home/.cache \
XDG_DATA_HOME=/tmp/yzk-a14-home/.local/share \
godot --headless --audio-driver Dummy \
  --path /tmp/yzk-a14-trace-project \
  --script res://tests/adv_player_smoke.gd -- \
  '/root/entis-gls-godot/缘之空（全cg步兵版）'
```

The process exited **0** and printed `PASS AdvPlayer Interactive VN Integration Smoke Test`. The smoke instantiated the copied `AdvPlayer` scene, initialized the original `ScenarioLoop('00_Z000')`, simulated Enter input to reveal/advance dialogue, and observed 16 opening-story dialogue lines across 105 frames. It reported `is_running=true`, `is_halted=false`, an empty VM `last_error`, and reached its visual/audio/UI assertions. The test was the existing `res://tests/adv_player_smoke.gd`; this task adds no persistent regression test.

The original game directory was passed only as the resource source. Save output was isolated with the temporary HOME/XDG directories (the run log shows saves below `user://test_saves/...`, hence in that isolated user-data area). The game directory was not modified.

## Instrumentation and evidence files

The only instrumentation was in the temporary copy at `/tmp/yzk-a14-trace-project/scripts/csx_vm.gd`, inside `_dispatch_file_method`: it collected `call_stack` frame names and printed each File method, arguments, current `ip`, and frames. Its default unsupported-method branch also printed the unsupported method and `last_error`. Comparison against the worktree VM showed only these additions in the copied function; no repository source was instrumented or changed. No unsupported-dispatch trace was emitted.

Temporary evidence (not committed):

- Full stdout/stderr and trace: `/tmp/yzk-a14-evidence/godot-full.log` (also recorded as `/tmp/yzk-a14-evidence/godot-stdout-stderr.log`).
- Godot log file: `/tmp/yzk-a14-evidence/godot-run.log`.
- Original-asset manifests: `/tmp/yzk-a14-evidence/assets-before.sha256` and `/tmp/yzk-a14-evidence/assets-after.sha256`.
- Instrumented project copy: `/tmp/yzk-a14-trace-project`.

The three run logs contain the same 80-line run output. The trace rows, grouped by identical IP and caller frames, account for all 22 `[A14_TRACE]` entries:

| Count | File dispatch and arguments | IP | `call_stack` frames |
|---:|---|---:|---|
| 15 | `IsExisting(".mio")` | `0x14140` | `ScenarioLoop` → `sc00_Z000` → `Hitret` → `AdvScreen::hitret` |
| 1 | `IsExisting("SR000001.mio")` | `0x14140` | `ScenarioLoop` → `sc00_Z000` → `Hitret` → `AdvScreen::hitret` |
| 1 | `IsExisting("system.dat")` | `0x7C7F` | `Initialize` → `LoadSystemData` |
| 1 | `IsExisting("config.dat")` | `0x8095` | `Initialize` → `LoadConfigData` |
| 1 | `Open("system.dat", 5)` | `0xAAD2` | `Initialize` → `LoadSystemData` → `SaveSystemData` → `SaveObject` |
| 1 | `Open("config.dat", 5)` | `0xAAD2` | `Initialize` → `LoadConfigData` → `SaveConfigData` → `SaveObject` |
| 1 | `SaveObject(...)` | `0xAB0D` | `Initialize` → `LoadSystemData` → `SaveSystemData` → `SaveObject` |
| 1 | `SaveObject(...)` | `0xAB0D` | `Initialize` → `LoadConfigData` → `SaveConfigData` → `SaveObject` |

There were no `OutputLogText`, `Open` mode 4 (or 4→5 fallback), `Seek`, `WriteText`, `Close`, or unsupported File dispatches. The VM reached the smoke's PASS result; no runtime abort from unsupported File dispatch occurred.

## Hypothetical unsupported-call path (source only)

The following is a code-path explanation, **not an event observed in this run**. In `godot_port/scripts/csx_vm.gd:2438–2469`, `_dispatch_file_method` has no `Seek` or `WriteText` case, so either would reach the unsupported-method default. `_report_unsupported_host_method` copies the host capability error to `last_error` (`csx_vm.gd:2063–2068`). At the HostFile member-call site, a nonempty `last_error` makes `step()` return false before appending a result to `eval_stack` (`csx_vm.gd:1370–1375`). `AdvPlayer` checks that false return and stops the current VM loop, reporting `last_error` (`godot_port/scripts/adv_player.gd:932–937`). No such failure occurred in the traced run: no unsupported call was dispatched and the smoke completed normally.

## Original asset integrity

The before and after SHA-256 manifests each contain **11 asset entries** and compare byte-for-byte equal (`cmp` exit status **0**). Thus all listed original game files retained identical hashes across the run.

| Asset | SHA-256 |
|---|---|
| `data1.noa` | `d324c49ed4a80108f68aabaf7a202ec31d1b8f64075918f136944e72ec919831` |
| `data2.noa` | `bdcc7836aac58fee447786de84e0ee15ac889822ee268743df06b32ac91e5fab` |
| `opening.mei` | `9509dc23f0060f0ac98b67a3d7c3331bc0a0efc95450c8e0f311c51c592bf137` |
| `sound.noa` | `166b22277d5398b452241a7502f5e6262de8d28a52d113f3c29673cc7d2a4005` |
| `system/frame.noa` | `b6f5ad7bd4067ad65ab764faaf76fb9442e0d01ab5c88807ecb7c6cddf5cf875` |
| `system/option.noa` | `054d2f6b7583f09f9b728d38a89da7fa0ef5a16cc334dd8fb576dbdffd768310` |
| `system/title.noa` | `b74f4c62f2dd208393552f3cb9b4287af32121c665c1a27ae57d59b1f713fbbc` |
| `system/yosuga.csx` | `157be9eb39cdc2d3cb654096340ca686f4ef48ac7fd7a6255673ba5f0c79afb6` |
| `voice.noa` | `b3b39bb227ea60ecffbfcd8812e232a9b72f930ee2103465572955ff899e54e9` |
| `原版有码文件备份/data1.noa` | `8956763db9c6e1559d5c19d376c6b6960bf3a629dace4ace90a39e474d88975b` |
| `无码补丁备份/data1.noa` | `d324c49ed4a80108f68aabaf7a202ec31d1b8f64075918f136944e72ec919831` |

The complete logs and manifests remain temporary evidence under `/tmp`; this report preserves the findings, limitations, and asset hashes durably.
