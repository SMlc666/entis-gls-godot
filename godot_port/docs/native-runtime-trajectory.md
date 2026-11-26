# Native Runtime Compatibility Trajectory

This is the project-level record for judging progress toward the target:

> Keep the original NOA/CSX content unchanged, use the original runtime semantics and assets, and let Godot provide the platform host.

Engineering hardening matters, but it does not count as original-runtime parity by itself. Record semantic coverage and reliability separately.

## Milestone review rubric

For each milestone, record:

- the current Git commit and SHA-256 of the original CSX/NOA inputs used;
- the original CSX entry point and the SDK/source contract being checked;
- the Godot call path and whether a custom Godot UI or script bypasses the original flow;
- the original-runtime reference output, the test command, and its actual result;
- any failure, unsupported path, or remaining scope.

Rate each behavior independently:

| Score | Evidence |
| --- | --- |
| 0 | No behavior, a stub, or a Godot-only path bypasses the original script. |
| 1 | The code path runs in the port or passes an internal smoke test. |
| 2 | A real original asset and script exercise the behavior, with a single behavior compared against an original SDK/runtime reference. |
| 3 | An end-to-end original-script flow matches the reference, has regression coverage, and preserves the original inputs. |

Record reliability work separately: transaction safety, bounds, diagnostics, memory budgets, and cache behavior. Do not use these as semantic-parity points.

## Baseline: 2026-11-25

Two independent GPT-6 Luna reviews of the current worktree agree on the following assessment. Their reports are in this conversation; the code links below are the evidence to recheck at the next milestone.

### Semantic progress

- The port indexes and executes the original `yosuga.csx` through its own `CsxVM`; this preserves original script content but is not the official Cotopha runtime. See `scripts/csx_vm.gd` and the original `Title()` startup path in `scripts/adv_player.gd`.
- Original title/configuration/appreciation entry points and portions of the original UI skin are active. This is real source-flow progress, but covered paths are not yet the complete original game loop.
- The `MovieSprite` call contract is being aligned with the SDK: successful `OpenMovie` precedes `PlayMovie`; `Release` is distinct from `CloseMovie`. MEI playback uses the actual `opening.mei` asset and handles I/P/B frame ordering, seek, looping, and audio. Official SDK pixel/audio differential results are still missing.
- Sprite animation, placement, alpha, scale, rotation, crop, and timing work reduces visual-behavior gaps, but combined effects still need original-runtime comparison.
- NOA CP932 name decoding improves access to original assets.

### Reliability work, not semantic-parity evidence

The current audit branch contains object-graph save restoration, atomic save/thumbnail handling, bounded reads, VFS collision fixes, MEI index reuse and memory estimates, append-safe logs, and Linux binary hash checks. These improve the self-built runtime's safety and reliability. The JSON save schema remains project-owned and is not evidence of original save-format compatibility.

### Known bypasses and unresolved risks

- Parts of the ADV shortcut menu, configuration window, and save/load UI are built and handled by Godot controls in `scripts/adv_player.gd`; original-looking skins and `ID_*` names do not make those interactions original CSX UI flows.
- Several host APIs have fixed-success fallback handlers, but a same-named CSX function takes precedence in `csx_vm.gd`. A static scan of the original CSX found 36 `WaitUntilSpriteActive` and 12 `Confirm` call sites; existing native-flow tests exercise those CSX functions, so the fallback is not itself evidence of a current defect. `ProcessUserInput` has no original global call sites. `HitWait` has two calls whose owners/arguments still need identification, and `UpdateWindow` has one call.
- `IsLoad` (38 calls) and `LeaveLoad` (2 calls) occur in `ScenarioEnter`, `AdvScreen::hitret`, and `AdvScreen::startSelect`. The VM function table has CSX implementations, so the fixed-success Host fallbacks are shadowed on these paths. Quick-load sets `scObj.isLoad == -1` synchronously; the resumed `ScenarioLoop` consumes it on the next frame. The smoke now asserts before that frame.
- Movie playback currently has one active decoder/player state. A new read-only bytecode audit found one `MovieSprite` creation in the original CSX; its helper opens, plays, waits, stops, and closes the same local receiver synchronously. This supports one active decoder for the original single-VM CSX call chain, while multi-VM/native-thread concurrency remains outside the evidence.
- The original runtime has not yet been demonstrated executing a game scene inside the Godot process. The existing VM and Host remain substantial self-implemented runtime layers.
- A complete original-script vertical slice covering dialogue, animation, audio, choice, save, and load has not yet been compared end to end with the original runtime.
- Android export/device validation remains later work; Linux is the current target.
- The MEI decoder now applies a 256 MiB *estimated live working-set* guard to open and public I/P/B frame calls. It caps section tables before vector growth and checks a COW-backed index snapshot to avoid rescanning the movie on each seek. An independent review found the revised phase estimates cover the pinned decoder's input/chunk/audio/video buffers and found no reachable arithmetic overflow; preflight allocations are bounded by the 128 MiB input and 32,768-entry limits. This is not an RSS or multi-object/process memory cap: actual RSS was not measured, and each codec instance retains its indexed input snapshot.

## Audit follow-up: save/video lifecycle, 2026-11-25

The raw VM function table contains CSX implementations for `IsLoad`, `LeaveLoad`, `QuickLoad`, and `EnterLoad`. Original `EnterLoad` sets `scObj.isLoad` to `-1`; the resumed `ScenarioLoop` consumes that flag on its next frame. The previous `bustup_smoke.gd` assertion yielded a frame before checking, so it observed the consumed state. The check now runs immediately after synchronous QuickLoad returns, before the next VM frame. This is a test-timing correction, not a Host implementation change.

Main-agent re-runs and the implementation-agent report show these commands passing with exit code 0 against the local game copy:

```sh
godot --headless --audio-driver Dummy --path . --script res://tests/bustup_smoke.gd -- '/mnt/sdb1/devs/yzk2godot/缘之空（全cg步兵版）'
godot --headless --audio-driver Dummy --path . --script res://tests/mei_playback_smoke.gd
godot --headless --audio-driver Dummy --path . --script res://tests/save_storage_contract_smoke.gd
godot --headless --audio-driver Dummy --path . --script res://tests/mei_codec_smoke.gd -- '/mnt/sdb1/devs/yzk2godot/缘之空（全cg步兵版）'
godot --headless --audio-driver Dummy --path . --script res://tests/mei_index_reuse_smoke.gd -- '/mnt/sdb1/devs/yzk2godot/缘之空（全cg步兵版）'
godot --headless --audio-driver Dummy --path . --script res://tests/native_title_player_smoke.gd -- '/mnt/sdb1/devs/yzk2godot/缘之空（全cg步兵版）'
godot --headless --audio-driver Dummy --path . --script res://tests/scene_recollection_smoke.gd -- '/mnt/sdb1/devs/yzk2godot/缘之空（全cg步兵版）'
godot --headless --audio-driver Dummy --path . --script res://tests/vm_sync_call_smoke.gd
godot --headless --audio-driver Dummy --path . --script res://tests/sprite_tree_contract_smoke.gd
godot --headless --audio-driver Dummy --path . --script res://tests/resource_read_limits_smoke.gd
godot --headless --audio-driver Dummy --path . --script res://tests/vfs_collision_smoke.gd
```

The main-agent MEI index re-run opened the 68,446,404-byte `opening.mei`, decoded 128 seeks in 1.66 seconds, and reported one index build with 133 reuses. `tools/verify_linux_runtime.sh` also exited 0 and verified the Linux x86_64 codec/helper hashes, extension symbol, and 22,560-byte CP932 table. These are Linux/self-runtime checks, not official-runtime differential validation.

The first run once reported `double free or corruption (out)` after a failed timing assertion; the corrected full run and repeated MEI lifecycle runs exited successfully, so the corruption is currently not reproducible rather than conclusively explained. A second lifecycle issue was traced to two unattached dummy `Button` nodes whose pressed callables retained `AdvPlayer` and its UI/resource graph. Removing those unused controls eliminated ObjectDB, CanvasItem, texture, TextServer, font, and resource-in-use leak reports in the verbose save, bustup, and MEI smoke reruns. The current runs only report seven orphan `StringName`s (`ScriptBacktrace`, `YzkCodec`, `OS`, `RefCounted`, `Object`, `ClassDB`, `Logger`) at process shutdown.

`mei_playback_smoke.gd` now uses an isolated `user://test_saves/mei_playback_*` directory and removes it on both pass and failure; it no longer reads the user's normal save directory.

The original script's movie paths include `Starting @ 0x250CA`, `OpeningMovie @ 0x29A5C`, and `ScPlayMovie @ 0x2A288`. `tools/audit_movie_lifecycle.gd` now provides the missing local instruction and branch context: it finds one `new MovieSprite` at `0x5BC1` in `PlayMovie @ 0x5B7A`, then the same local receiver executes Open → Play → IsMoviePlaying/Sleep/input wait → Stop → Close before the helper returns. This is strong evidence for one active decoder on the original single-VM CSX path; it does not establish behavior for external native threads or multiple independent VM sessions.

## Review cadence

At each major milestone, ask an independent GPT-6 Luna reviewer who did not implement the change to classify it as semantic parity, reliability hardening, or a bypass; require code/source evidence and exact verification output. Ask a second reviewer when the milestone changes VM/host architecture, original UI ownership, save semantics, or media timing. Update this file with the verdict, score, evidence, and residual risks before starting another large implementation tranche.

## Requested architecture consolidation: Story and native-window compositor

The next architectural target is one presentation path: original CSX creates the `HostWindow` / `HostSprite` tree, and one reusable Godot compositor renders that tree for Story, Title, Config, Save/Load, and other original windows. Story must not keep a parallel dialogue/menu/bustup renderer implemented directly in `adv_player.gd`.

At the start of this review, `_build_ui()` created a `DialogueBox`, `SpeakerLabel`, `RichTextLabel`, quick-menu buttons, choices, backlog, and a separate `TextureRect` per bustup; message callbacks copied HostSprite text/state into those controls; `_update_bustups()` rendered another CSX-driven sprite subset; and `_sync_native_title_canvas()` projected native windows through a title-specific layer. The compositor has since been generalized for Story and Title, and custom choice controls removed. Hidden dialogue/menu fallbacks, CG/temp sprite layers, unattached-bustup rendering, and modal panels remain to be consolidated.

### Architectural acceptance criteria

1. `ScenarioLoop("00_Z000")` remains the source of Story progression; the implementation does not replace or translate its original CSX content.
2. Original `MessageFrame` / `MessageSprite`, choice, quick-menu, title, configuration, and save/load construction produces `HostWindow` and `HostSprite` objects through host APIs.
3. A single compositor recursively renders every supported `HostWindow.root_sprites` / `HostSprite.children` tree, including text, image frames, transforms, alpha, Z order, clipping, skin slices, and input hit regions. Title-only filtering is a policy on the same compositor, not a second rendering engine.
4. Godot input is translated back to the original HostWindow command/input contract. It does not invoke alternate per-widget Story callbacks that bypass CSX.
5. ADV dialogue, bustups, choices, and in-game quick menu no longer have independent Godot visual nodes. Godot keeps the application shell, compositor surface, audio/video/rendering services, platform dialogs where the original runtime has no equivalent, and the runtime scheduler.
6. The first vertical slice starts from the original `ScenarioLoop`, shows a real message and bustup, advances through input, executes a branch/choice, and returns through the original menu/window path. Record the CSX entrypoints, sprite tree, host calls, and original-runtime comparison evidence.
7. `AdvPlayer` becoming smaller is an outcome of clear ownership, not a line-count target. Session lifecycle, VM scheduling, resource/audio/video services, and UI composition must have explicit owners; mechanical file splitting alone does not pass this milestone.

Two independent read-only agents traced the Story bytecode/call graph and reviewed the compositor boundary. Their findings shape the first implementation slice; do not generalize the existing `native_title_canvas` path by renaming it or remove Story controls before the runtime tree and input bridge are proven.

## Independent architecture trend audit: 2026-11-26

**Historical snapshot:** the code findings in this section describe the
pre-follow-up worktree. The VM interception and custom choice UI described
below were removed and verified in the current revision recorded under
“Story compositor follow-up” below.

Two independent GPT-6 Luna reviewers confirmed that the dual presentation path is still present. One additionally decoded the current, unmodified `system/yosuga.csx` through the project VM and located `ScenarioLoop @ 0x8F83`, `MessageFrame::create @ 0x2A7A8`, `MessageFrame::output @ 0x2DD83`, `AdvScreen::setupSelectItem @ 0x18AD9`, and `AdvScreen::startSelect @ 0x16A5C` in a 1,414,381-instruction / 780-function image.

At the time of this first review, `_build_ui()` still created the dialogue labels, quick-menu and choice controls, and five bustup TextureRects; the VM also intercepted `AdvScreen::startSelect`. This was a pre-fix snapshot and is superseded below. The other parallel Story paths listed here remain under review.

The first review found the recursive HostWindow projection title-layer-specific and identified a generated `NativeTitleGalleryEntry` Godot button and title callback special cases. The projection has since been generalized to `HostWindowLayer` / `HostWindowCanvas` and extended to Story, but title-specific behavior and the fallback Story nodes still remain. The old choice smoke now aliases the native selection smoke; the hidden DialogueBox and other split paths have not yet been removed.

The raw CSX static decode originally proved only that MessageFrame and selection construction calls exist. Runtime object identity and original selection behavior have now been checked as recorded below. Natural-story bustup attachment remains unproven.

Trend score on the project rubric: Story progression = 1/3 (original CSX runs in the self-written VM); Title/Config/SaveLoad projection = 1–2/3 (real CSX-generated HostSprite trees and internal flow tests, no official-runtime output comparison); Story message/bustup/choice = 1/3 (CSX data is consumed but rendering and selection still bypass the original window interaction loop); host-only / official Cotopha execution = 0/3 (not demonstrated in-process). Save transactions, read bounds, VFS, and MEI memory/index work are reliability improvements and do not raise these parity scores.

The Story slice preserves the original CSX `ScenarioLoop`; the current tests exercise the MessageFrame, eight quick-menu buttons, original selection rows, and a returned 1-based selection result through one recursive HostWindow compositor. Physical pointer/keyboard behavior, native message advance, title/modal ownership, natural bustup attachment, and removal of the remaining fallback nodes are still acceptance work.

## Story compositor follow-up: 2026-11-26

After removing the `AdvScreen::startSelect` VM interception and the Godot
`ChoiceContainer`, the following actual-resource checks passed:

- `godot --headless --audio-driver Dummy --path godot_port --script res://tests/native_story_selection_smoke.gd -- '<game-dir>'`: original `ScenarioLoop(00_Z005)` reached the original `AdvScreen::startSelect` stack frame. The tree exposed two original `ID_SELECT` option sprites; activating the row containing `敲门` sent the original command and cursor position, and CSX returned `selectResult=1`. The command queue was empty afterward and source hashes were unchanged.
- `godot --headless --audio-driver Dummy --path godot_port --script res://tools/audit_story_window_tree.gd -- '<game-dir>' --probe-bustup`: **PASS**. `00_Z000` MessageSprite identity matched the HostWindow child; `00_Z005` exposed both option rows under roots 2 and 3; original CSX and `data1.noa` hashes remained unchanged. The bustup was an explicit in-memory probe, not a natural story event.
- `godot --headless --audio-driver Dummy --path godot_port --script res://tests/native_story_compositor_smoke.gd -- '<game-dir>'`: visual-tree/content assertions **PASS**, but shutdown reported 151 ObjectDB instances, three resources and 43 dummy texture RIDs still in use. This teardown issue remains open.

Two independent GPT-6 Luna reviews agree that the selection migration is
substantive, but the project still has two presentation/input paths. Fallback
dialogue and quick-menu nodes and text callbacks remain; CG and temporary
sprite layers and unattached-bustup fallback remain; ordinary Story advance
uses `advance_ticks` while native buttons use `command_queue`. Native Host
commands now wake the paused VM without faking an advance tick, verified with
original `ID_QSAVE` during a real message wait. Backlog and some modals remain
Godot-owned; title-specific synthetic UI callbacks remain.
The compositor still needs checks for effective viewport coverage, Z ordering,
local clipping, physical pointer/keyboard input, and mode transitions. Neither
review found evidence of natural bustup attachment in the captured scenes.
These findings are architectural follow-up, not proof of original Cotopha
runtime parity.

## Next review gates

1. Recheck save/load and MovieSprite P0 contracts after the current integration batch; QuickLoad timing is now covered, and the one heap-corruption report has not reproduced.
2. Re-review the MEI estimated live-working-set guard against the pinned decoder and real `opening.mei`; keep it explicitly separate from an RSS limit and from total process memory.
3. Trace original `ScenarioLoop` host API calls and distinguish real Host fallbacks from same-named CSX functions; resolve the remaining `HitWait`/`UpdateWindow` callsites before claiming support.
4. Make a time-boxed, evidence-backed attempt to execute a minimal original CSX scene through the official runtime as an in-process backend. Record the concrete API, graphics, and platform blockers if it cannot be integrated.
5. Complete one original-script vertical slice with a reference capture and differential checks for state, sprite properties, audio/video timing, branching, and save/load.
6. Reassess the architecture after those gates; then continue broader script/API compatibility and only later close Android delivery.

## SDK integration feasibility: source review, 2026-11-25

The persistent reference tree at `/mnt/sdb1/devs/reference-sources/entisgls-8235a2af` contains a traditional Cotopha execution route in `native/launcher/runtime_session.cpp`: initialize `ECotophaScript`, load an environment, read the CSX image, call `ECSContext::InitializeContext`, then invoke the script's static initializer and entry point. This proves that the reference code has an original-runtime execution path; it does not prove that the Yosuga script runs successfully through it.

The route belongs to an SDL application shell. `apps/launcher/main.cpp` services SDL events and draws windows on the main thread while `RunLegacyGame` runs on a worker. `native/platform/sdl/window_implementation.inc` creates an SDL window and a separate desktop OpenGL 2.1 compatibility context (or GLES context on mobile) for Cotopha windows. `cmake/sdl3_runtime.cmake` links SDK, platform, and GL code into static targets, while `cmake/legacy_runtime.cmake` explicitly describes its object target as not yet a complete linked runtime. No stable host-facing runtime ABI or shared Godot GL context has been demonstrated.

The next official-runtime experiment should therefore begin with a small, persistent harness at `/mnt/sdb1/devs/reference-sources/yzk2godot-official-runtime-harness` that calls the execution path and records VM state and host/window requests without creating an SDL or Godot window. Keep both source and build tree there, not in `/tmp` or inside the game project. It succeeds only when the unmodified Yosuga CSX passes context initialization and reaches a documented script phase; it does not count as a Godot integration until window/input/render ownership is proven. Stop and record a concrete blocker if the script immediately requires unavailable native bindings or its own SDL/GL main loop.

The reference tree's `EntisGLS/license.txt` also restricts redistributing the library itself and sets terms for distributing an application that includes its VM. Keep SDK sources outside this project and verify the applicable distribution terms before packaging a runtime. EntisGLS's official overview describes its VM/library model, and the official download page lists the library, source/include files, documentation, and tools: <https://www.entis.jp/gls/about.html> and <https://www.entis.jp/gls/download.html>.

## Full audit remediation checkpoint: 2026-11-25

| Audit area | Status | Evidence and remaining scope |
| --- | --- | --- |
| Save context, object identity, forward references, transaction failure | Implemented and smoke-checked | VM context is passed through `HostFile`; graph preallocation supports forward/cyclic references; staged restores preserve the caller's root and fail before commit on malformed fields or missing media. `save_storage_contract_smoke.gd` and `save_result_contract_smoke.gd` pass. The JSON format remains private to this port. |
| QuickLoad / stale `isLoad` expectation | Resolved as test timing | Original CSX `EnterLoad` sets `scObj.isLoad = -1`; `ScenarioLoop` consumes it on the next frame. The smoke asserts immediately after synchronous load. Host fallbacks are shadowed by real CSX functions on these paths. |
| Sprite tree ownership and restore bindings | Implemented and smoke-checked | Self/cyclic/multiple-parent attachment is rejected; child array identity, parent links, pending-message registration, and root references are restored. `sprite_tree_contract_smoke.gd` and save contract pass. |
| Movie API result and lifecycle semantics | Implemented and smoke-checked | Open/Play/Seek/Close results propagate; Play requires a successful open; `Release` does not substitute for `CloseMovie`. Real MEI lifecycle smoke passes. `tools/audit_movie_lifecycle.gd` decodes the original 1,414,381 instructions and finds one MovieSprite allocation in the synchronous helper; one decoder is supported for the original single-VM call chain. |
| MEI decode failure, initial frame, time and frame-index reuse | Implemented and smoke-checked | EOF differs from decode failure; initial RGBA dimensions are validated; audio clock and GOP commits are covered; 128 seeks reuse one index. Official SDK pixel/audio differential is still missing. |
| MEI working-set and hostile section limits | Estimated live working-set guard implemented; not an RSS limit | Section tables cap at 32,768 records; audio chunk/PCM growth, staged input copies, index metadata, initial frame output, and I/P/B frame decode estimates are checked before decode. `mei_codec_smoke.gd` and `mei_index_reuse_smoke.gd` cover real playback, overlong section tables, large-frame rejection, and COW snapshot changes. Allocator/RSS overhead and unrelated process memory are excluded; the 256 MiB value remains an estimate. |
| VFS collision behavior and CP932 NOA names | Implemented and smoke-checked | Candidate search continues after archive-hint mismatch; explicit disk paths preserve filesystem case; NOA names use the existing CP932 decoder. `vfs_collision_smoke.gd` passes; CP932 behavior is in the current committed baseline. |
| Codec binary consistency | Verified | `tools/verify_linux_runtime.sh` verifies the Linux x86_64 library/helper manifest, extension entry symbol, and CP932 data file. Android ARM64 binary is not available. |
| Save integer precision, dictionary keys, log append, thumbnail generation | Implemented and smoke-checked | Schema v4 stores wide integers and typed key/value entries; logs append and report failure; thumbnail generations are content-hashed and transactionally referenced by primary/backup saves. |
| Resource size checks and media cache | Partially implemented | `BoundedFileReader`, CSX/image limits, and aggregate cached-media budget smoke pass. A cache budget is not actual process RSS; audit every remaining direct file/resource entry point before calling bounds complete. |
| Recollection entry/exit state | Implemented and smoke-checked | Synchronous CSX return values are checked; stale waits/choices/skip modes are cleared. `scene_recollection_smoke.gd` passes; long repeated transition stress is still outstanding. |
| Fixed-success Host API fallbacks | Partially classified | `WaitUntilSpriteActive`, `Confirm`, `IsLoad`, and `LeaveLoad` are implemented in raw CSX and take VM precedence. `ProcessUserInput` has no original global call sites. `HitWait` (two calls) and `UpdateWindow` (one) still need owner/argument evidence. |
| Output log and test/runtime object cleanup | Implemented and smoke-checked | Output logging appends. Two unattached dummy Buttons were removed; verbose save, bustup, and MEI runs no longer report ObjectDB/RID/resource leaks. Seven orphan StringNames remain at Godot process shutdown. |
| Settings persistence, audio overlap, dirty rendering, hardware audio sync | Deferred / not proven | The original config UI path is exercised, but restart persistence and overlapping same-category sound behavior need targeted checks; renderer Dirty Flags are not implemented; audio-clock behavior is tested with dummy output rather than hardware or SDK differential. |
| Android delivery | Deferred / not proven | Export include filters and documentation were improved, but there is no Android SDK/NDK/template/device verification in this environment. Linux remains the active target. |

The 2026-11-25 independent MEI review was addressed by checking the pinned `arc_unpacker` read path: `MemoryByteStream(const bstr&)` deep-copies, `read_chunks` retains compressed chunks and copies each by-value `MioChunk` during processing, `bstr::operator+=` grows the decoded aggregate, and `MioAudioDecoder` copies that aggregate into `Audio::samples`. The encoded MIO copy is now released immediately after `MemoryByteStream` construction. The estimate compares the short 3-input-copy phase with a decode phase that includes two live full-input buffers and bounded chunk/vector/DCT/frame allocations. It is deliberately labeled estimated live working set; allocator and RSS overhead are not included.
