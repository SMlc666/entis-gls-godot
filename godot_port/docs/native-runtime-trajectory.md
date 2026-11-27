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
- Several host APIs have fixed-success fallback handlers, but a same-named CSX function takes precedence in `csx_vm.gd`. A static scan found original CSX implementations for `InitRandom`, `WaitUntilSpriteActive`, `Confirm`, `HitWait`, `IsLoad`, and `LeaveLoad`; those Host fallbacks are shadowed. The single `UpdateWindow` call reaches the Host, and the Godot player synchronizes the compositor after each VM batch. `ProcessUserInput` has no original global call sites, so its success no-op mapping was removed; `host_unsupported_api_smoke.gd` checks this unsupported case and preserves `UpdateWindow` as a handled redraw request.
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
- `godot --headless --verbose --path godot_port --script res://tests/native_story_compositor_smoke.gd` with `YOSUGA_GAME_DIR` set to the local game directory: visual-tree/content assertions **PASS**; no ObjectDB, resource-in-use, or texture-RID leak report. Seven orphan `StringName`s remain. The earlier 151 ObjectDB / three resource / 43 texture-RID report was superseded after the unused controls were removed.

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
| Fixed-success Host API fallbacks | Classified and reduced | Original CSX implementations shadow `InitRandom`, `WaitUntilSpriteActive`, `Confirm`, `HitWait`, `IsLoad`, and `LeaveLoad`. The one `UpdateWindow` Host fallback is covered by per-batch redraw synchronization. The unused `ProcessUserInput` success fallback is removed so an unexpected call is reported as unimplemented; `host_unsupported_api_smoke.gd` passes. |
| Output log and test/runtime object cleanup | Tested Story teardown no longer reports ObjectDB/RID leaks; residual StringName diagnostics remain | Output logging appends. Two unattached dummy Buttons were removed; earlier verbose save, bustup, and MEI runs no longer reported ObjectDB/RID/resource leaks. A 2026-11-27 verbose selection run identified the intermittent four ObjectDB instances as two `AudioStreamWAV` and two `AudioStreamPlaybackWAV`. `native_story_selection_smoke.gd` now explicitly shuts down the runtime, frees AdvPlayer, waits one process frame, and drains audio for 250 ms; 3 ordinary + 1 verbose selection reruns and `story_lifecycle_smoke.gd` (3 real-CSX sessions in one process) have no ObjectDB/RID leak warning. This correlation is consistent with asynchronous AudioServer release at test exit, not an independently proven root cause. Seven orphan StringNames remain and are tracked separately as P2. See `runtime-compatibility-baseline-2026-11-27.md`. |
| Project-owned settings persistence, native config compatibility, audio overlap, dirty rendering, hardware audio sync | Partially implemented / not proven | Project-owned JSON settings are persisted by `AdvPlayer`, but this does not prove original `config.dat` semantics or restart compatibility. The original config UI path is exercised, while Story settings still include a Godot-owned modal; overlapping same-category sound behavior needs targeted checks; renderer Dirty Flags are not implemented; audio-clock behavior is tested with dummy output rather than hardware or SDK differential. |
| Android delivery | Deferred / not proven | Export include filters and documentation were improved, but there is no Android SDK/NDK/template/device verification in this environment. Linux remains the active target. |

The 2026-11-25 independent MEI review was addressed by checking the pinned `arc_unpacker` read path: `MemoryByteStream(const bstr&)` deep-copies, `read_chunks` retains compressed chunks and copies each by-value `MioChunk` during processing, `bstr::operator+=` grows the decoded aggregate, and `MioAudioDecoder` copies that aggregate into `Audio::samples`. The encoded MIO copy is now released immediately after `MemoryByteStream` construction. The estimate compares the short 3-input-copy phase with a decode phase that includes two live full-input buffers and bounded chunk/vector/DCT/frame allocations. It is deliberately labeled estimated live working set; allocator and RSS overhead are not included.

## Continued handoff and runtime audit: 2026-11-26

This checkpoint continues from checkout `702f219 Correct Story compositor audit evidence`; the following changes are in the working tree and are not committed yet. The uploaded `godot_port(3).zip` was not present under `/workspace`, so this pass uses the current Git checkout. The original game directory is ignored by Git and was treated as read-only.

### Changes and evidence

- **Save restoration (A04):** schema is now version 7. `HostResource` snapshots include `play_type` and an optional four-point volume envelope with duration and elapsed time. Validation rejects incomplete/non-finite envelope state, invalid play categories, and impossible elapsed-time state before staging resources. The restore commit copies these fields and registers pending envelopes only after the target graph commits. Older schema 6 data without the new fields loads with the previous defaults, including clearing stale envelope state on a reused root resource. This restores the saved automation timeline; it does not restart audio playback by itself.
- **Sleep host contract:** the raw CSX has eight `Sleep` host call sites, including 33 ms activation polling and 100 ms movie polling. `Sleep(ms)` now advances the CSX IP past the call, returns success, and asks the VM scheduler to pause subsequent instructions until a monotonic deadline. The Godot frame loop continues rendering and advancing animations during the wait. A synchronous callback fast-forwards `Sleep` without waiting; reentrant sync calls preserve the outer asynchronous deadline. `tests/vm_cooperative_sleep_smoke.gd` covers elapsed timing, blocked VM steps, a nested sync call, and the sync fast-forward rule. This is self-runtime semantics and has not yet been compared with the official Cotopha runtime.
- **Story compositor (A07/A11):** viewport coverage now accounts for transformed bounds, inherited visibility and opacity, alpha-bearing textures, and button-state textures in the order the compositor actually draws them. The button-state check prevents an opaque fallback texture from hiding the background under a transparent button. The message compositor clears stale font overrides when a sprite resets to default style. The weak texture-opacity cache now prunes released texture entries periodically.
- **Test fixture ownership (A02):** the save contract smoke now breaks cycles in both successfully restored fallback targets that it owns; the rerun completed without the prior ObjectDB leak warning.
- The original animation-skip, title-skin command-injection, and recollection flow smokes now await VM cooperative yields and advance synthetic sprite animation while waiting. This prevents test-only tight loops from counting suspended steps as executed instructions.

Commands run in this pass:

```sh
godot --headless --editor --path godot_port --quit
godot --headless --audio-driver Dummy --path godot_port --script res://tests/save_storage_contract_smoke.gd
godot --headless --audio-driver Dummy --path godot_port --script res://tests/vm_cooperative_sleep_smoke.gd
godot --headless --audio-driver Dummy --path godot_port --script res://tests/vm_sync_call_smoke.gd
godot --headless --audio-driver Dummy --path godot_port --script res://tests/host_command_queue_smoke.gd
godot --headless --audio-driver Dummy --path godot_port --script res://tests/host_unsupported_api_smoke.gd
godot --headless --audio-driver Dummy --path godot_port --script res://tests/native_activation_input_smoke.gd -- '<game-dir>'
godot --headless --audio-driver Dummy --path godot_port --script res://tests/native_form_page_smoke.gd -- '<game-dir>'
godot --headless --audio-driver Dummy --path godot_port --script res://tests/scene_recollection_smoke.gd -- '<game-dir>'
godot --headless --audio-driver Dummy --path godot_port --script res://tests/native_story_compositor_smoke.gd -- '<game-dir>'
godot --headless --audio-driver Dummy --path godot_port --script res://tests/native_story_selection_smoke.gd -- '<game-dir>'
bash godot_port/tools/verify_linux_runtime.sh
```

All commands above exited 0. Save failure-injection cases intentionally print `ERROR`/`WARNING` lines before the smoke reports PASS. The real-resource Story tests report unchanged source hashes: `system/yosuga.csx` SHA-256 `157be9eb39cdc2d3cb654096340ca686f4ef48ac7fd7a6255673ba5f0c79afb6`; `data1.noa` SHA-256 `d324c49ed4a80108f68aabaf7a202ec31d1b8f64075918f136944e72ec919831`. The save test's generated WAV verifies automation state and progress without reading original audio. No official-runtime output comparison was made.

### Newly traced gaps and remaining blockers

- **HitWait / UpdateWindow classification:** raw `HitWait(time)` calls resolve to the original CSX function at both Logo call sites, so the fixed-success Host fallback is shadowed there. The single `UpdateWindow()` call after `WaitUntilSpriteActive` reaches the Host fallback; the current scheduler synchronizes the compositor after each VM batch. Keep a dirty-redraw contract explicit if batching later becomes event-driven.
- A second read-only audit found an original `SendCommand` setting `hit_transparency=true`, but that state has no consumer: `HostSprite.is_hit_at()` still uses a rectangular hit area. The expected transparent-pixel behavior should be checked against an official reference before changing hit semantics.
- Raw CSX uses `FlushCommandQueue` 40 times. The host intentionally leaves it as a no-op so a flush cannot discard a click already delivered to a native window. Add tests for event enqueue/flush/poll timing before changing that behavior.
- The earlier checkpoint found only `arc_unpacker` and `godot-cpp` in the project tree and no SDK in this environment. That blocker is superseded by the official SDK acquisition recorded below. At that earlier checkpoint, the full archive had not yet been downloaded; the complete package has since been acquired and verified outside the repository. There is still no project-owned official-runtime harness or SDL3 package. Do not claim official runtime integration from source availability alone. The next gate is a console-only `InitializeContext` harness built from the external official source subset.

Current parity remains unchanged by these reliability and self-runtime fixes: Story still runs on `CsxVM`; official Cotopha execution remains 0/3. First build and run the official-source console harness described below. Once it reaches a real script phase, map each unresolved file/window/input/media request into the Godot adapter. Then continue raw-CSX Host API coverage (`hit_transparency`, `FlushCommandQueue`, and remaining successful stubs), real pointer/keyboard checks, and a full save/load action through the original Story UI. Android remains later work.

## Official EntisGLS SDK source acquired, 2026-11-26

The official EntisGLS 4.07.03 package was inspected at <https://www.entis.jp/gls/download.html>. Its published ZIP is 3,093,469,524 bytes; most of that archive is prebuilt Windows/Android libraries and tools, not Linux inputs. The source-relevant entries were fetched by HTTP byte ranges into `/workspace/reference-sources/EntisGLS4.07.03-source`, outside this repository. At the user's request, the complete official ZIP is also available at `/workspace/reference-sources/EntisGLS4.07.03.zip`.

The external source subset contains 1,425 files (38,573,375 extracted bytes): Cotopha C++ source and headers, Cotopha documentation/scripts/resources, GLS3/ESL source and headers, official project files, `license.txt`, and `readme.txt`. Each subset ZIP entry was checked for its declared uncompressed size and CRC-32; all 1,425 extracted file hashes pass `SHA256SUMS`. The complete archive was downloaded as 47 verified HTTP ranges, matches the published size, passes `unzip -tqq`, and has SHA-256 `08e6059bd1ca526497fba1f855faa61bf042030ecf3018a41e9abf2cf4d15993`. The full ZIP and source subset are both outside this repository; the subset excludes prebuilt binaries and tools from the build inputs.

The official license allows local use and source modification, but prohibits redistributing the SDK source, libraries, or tools without permission. Individuals and nonprofit groups may distribute applications with the required VM under the license terms; sales above ¥1,000,000 incur a 1% royalty. For-profit organizations need prior permission before application distribution. Distributed applications must show the specified EntisGLS copyright notice with the required visibility and duration. Keep the SDK outside this repository and out of distributable project sources; review those terms again before packaging any runtime.

The source tree has no drop-in Linux runtime library. Its modern Cotopha tree has common, Android, Win32, and OpenGL sources plus Unix include headers, but those Unix headers target Sakura2 and do not supply a Linux backend for the legacy GLS3 CSX runtime used by Yosuga. The Android makefile builds GLS4; the legacy path also depends on GLS3/ESL sources and host services. A Godot port therefore still needs a project-owned Linux/Godot adapter and a source build. No official Cotopha execution or SDK differential test has been run yet; Story still executes through `CsxVM`, so official-runtime parity remains 0/3.

### Next gate

Build a small console-only harness from the official source subset, with original NOA/CSX opened read-only. First prove source initialization and `ECSExecutionImage` loading, then call the unmodified Yosuga CSX through `ECSContext::InitializeContext`, its static initializer, and its entry point while logging unresolved host/file/window requests. Do not add SDL, OpenGL, or Godot rendering until that reaches a reproducible script phase. Record each missing host contract as an explicit adapter task. After that, expose the same native context through a Godot GDExtension and migrate one vertical slice at a time; retire the corresponding `CsxVM` path only after real-resource regression and output comparison pass.

## Official Host API delta, 2026-11-26

The official source review maps the next compatibility work to actual SDK interfaces. `CsxVM` and the GDScript host are useful temporary fallbacks, but they do not implement the Cotopha VM or SDK object contracts.

| Boundary | Official interface | Current port gap |
| --- | --- | --- |
| File/VFS | `ECSEnvironment` (`LoadEnvironment`, `AddFileDirectory`, `AddFileArchive`, `OpenFileObject`, `NewOpenFile`); `ECSContext::OpenFileOnScript` | `HostFile` covers object save/load, thumbnails, existence, logs, and basic read/write-mode enforcement, but lacks general read/write/seek/length/position and the full native stream contract. Build the native file bridge before running script code. |
| VM | `ECSContext` (`InitializeContext`, `CallFunction`, `ResumeExecution`, `ExecuteInstruction`, `WaitUntilEvent`, `ReleaseContext`) | Execution semantics currently live in `CsxVM`. The target is the official context, driven from the Godot frame loop with an explicit scheduler/host event bridge. |
| Window/render | `SGLAbstractWindow`, `SGLPaintInterface`, `SGLTimerInterface` | `HostWindow` and the Story compositor are custom Godot paths; there is no SDK `RenderDevice` or paint callback integration. Several window methods remain no-op or partial (`show_cursor`, lock/unlock, update rect, display change, command flush). |
| Input | `SGLVirtualInput` and window event/listener interfaces | Current `HostWindow` exposes a small command/joy subset, without native event maps, filters, event queues, listener lifecycle, or proven `FlushCommandQueue` timing. |
| Sprite/UI | `SGLSprite`, `ButtonSprite`, `MessageSprite`, action/timer and listener APIs | `HostSprite` reproduces many visible properties but remains a custom object. Hit masks, native listeners, action/timer callbacks, and the SDK render tree are not connected. |
| Audio/video | `SoundPlayer`, `MovieSprite` | MEI decode/playback is substantial and uses real assets, but the wrapper's SDK object lifecycle, callback and volume automation contracts still need direct comparison. |

Recommended order is: (1) console-only official VM startup with read-only game files; (2) a native file bridge and explicit missing-host diagnostics; (3) Title/Config input and queue semantics; (4) Story sprite/message rendering; (5) audio/video lifecycle and a save/load vertical slice. This order proves the runtime executes the original script before investing in renderer parity. Keep one original CSX/NOA hash record per comparison and add compatibility behavior only when observed in the SDK or a reference run.

### Current compatibility baseline refresh: 2026-11-27

See [`runtime-compatibility-baseline-2026-11-27.md`](runtime-compatibility-baseline-2026-11-27.md) for the current A01–A20 matrix, current-worktree evidence, test commands, original asset hashes, and residual P0/P1/P2 gaps. It supersedes older point-in-time status statements above where they conflict; earlier sections remain historical evidence.

## Traditional CSX build gate

A format check against the official source shows that `system/yosuga.csx` uses the traditional `image/function/global/data/conststr/linkinf` sections. The modern Sakura2 `ExecutableModule::ReadModule` expects a different section table, so `EnvironmentVM::Run` is not the correct replacement. Use the official GLS3 `ECSExecutionImage` + `ECSContext` path.

A first GNU C++ 14.2 syntax check of official `EntisGLS3/GLS3/Source/glscs_context.cpp` with the SDK include paths stopped at `EntisGLS3/EGL/Include/egl.h:17` because it includes Win32 `windows.h`. The package has no Linux/CMake target. A local CMake 4.4.5 tool was installed under `/workspace/work/cmake-python` for an external build probe; SDL3 development files remain absent. The next engineering task was a build-only legacy platform shim around selected GLS3 core sources; its current progress and remaining ABI blocker are recorded below. Keep generated compatibility files outside the game project.

### Headless compile probe status, 2026-11-26

The external source-build probe is at `/workspace/reference-sources/official-runtime-harness`. Its CMake configure succeeds, but the current executable is only a print-only scaffold; the official runtime has not linked or run. Generated overlays patch copies of selected legacy template headers. They remain outside this repository and the official SDK tree.

The include-order ABI collision between Unix Sakura2 ESL and traditional GLS3 ESL (`ESLError`, `memset`, and `memmove`) is resolved by loading the legacy ESL before Sakura2 and keeping `_DISABLE_ESL_NEW` undefined. The first full-EGL build then reached Win32 graphics types (`LONG`, `BITMAPINFO`, `LOGFONT`). A narrower probe now includes the official `egl2d.h` declarations directly and avoids the full EGL/EGL3D renderer headers. This passes the POD geometry declarations, but the compile still fails before linking: `ctscriptplugin.h` and `glscs_environment.h` require image-sprite, display-size, Win32 handle, game-window, and internet-session declarations; `glscs_context.cpp` also requires complete thread/file/resource classes and contains Win32 x86 assembly/SEH. Its Sakura context source has CP932 wide literals; passing `-finput-charset=CP932` globally also breaks UTF-8 SDK headers and generated overlays. Adding the official sprite/render/setup headers leads into a Win32-only SakuraGL window header. The exact latest log and compile notes are in the external harness `build.log` and `README.md`.

The official source map shows that no EGL renderer implementation is required for `ECSExecutionImage::ReadExecution` or the interpreter. A narrower build should start from `eslfile`, `eslheap`, array/string support, `glscs_execution_image`, `glscs_context`, `glscs_context_naked`, core object/class-info sources, and the Sakura processor/VM sources, then use linker evidence to add dependencies. The official extension hook is `ECSContext::GetImportNativeFunction`: it returns `API_ECS_FUNC`, a direct C++ callback of `(ECSContext&, ECSObjArray<ECSObject>&)`, and both global and native instruction paths call it directly. A Linux `ECSContext` subclass can override this hook for host API adapters; resolved functions are cached per native-function index. The old `CallFunctionWin32x86API` stack/assembly route is only the fallback for unresolved or Windows DLL exports and should return an explicit unsupported error on Linux. Do not keep growing opaque window/media typedefs: first separate parser/context headers from the full `glsscript.h` plug-in ABI and prove a bounded source list. Then load the original module, initialize a subclassed context, and call its static initializer and entry point while logging unresolved APIs. Only after a real script phase is observed should a `CotophaRuntime` GDExtension be started. Story remains on `CsxVM`; official runtime parity remains 0/3.

The original `system/yosuga.csx` and `data1.noa` hashes still match the baseline (`157be9eb39cdc2d3cb654096340ca686f4ef48ac7fd7a6255673ba5f0c79afb6` and `d324c49ed4a80108f68aabaf7a202ec31d1b8f64075918f136944e72ec919831`). The extracted SDK source subset SHA-256 manifest verifies all 1,425 files. No official VM execution, visual comparison, or host API differential has passed yet.
