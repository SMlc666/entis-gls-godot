# Story HostWindow compositor and selection audit (2026-11-26)

This audit runs the real `AdvPlayer` with the original CSX and NOA files. It
checks Story rendering against the original `HostWindow` / `HostSprite` object
tree and records whether a sprite is naturally attached or only appears after
an explicit diagnostic call. Test saves go to isolated `user://` directories.

## Reproduction

From the workspace root:

```sh
godot --headless --audio-driver Dummy --path godot_port \
  --script res://tools/audit_story_window_tree.gd -- \
  '/mnt/sdb1/devs/yzk2godot/缘之空（全cg步兵版）' --probe-bustup

godot --headless --audio-driver Dummy --path godot_port \
  --script res://tests/native_story_compositor_smoke.gd -- \
  '/mnt/sdb1/devs/yzk2godot/缘之空（全cg步兵版）'

godot --headless --audio-driver Dummy --path godot_port \
  --script res://tests/native_story_selection_smoke.gd -- \
  '/mnt/sdb1/devs/yzk2godot/缘之空（全cg步兵版）'
```

## Current observations

- `ScenarioLoop("00_Z000")` reaches a body-message wait with a `HostWindow`
  containing two roots. The first is the 800x600 scene/background tree; the
  second is the 750x152 message frame. `ID_FONT_MESSAGE` at `root[1]/child[7]`
  is the same object reported by `message_output`, not a reconstructed copy.
- That same tree contains eight original quick-menu button sprites
  (`ID_QSAVE` through `ID_HISTORY`), plus `ID_CLOSE` and `ID_VOICE`. The
  compositor smoke checks their Godot wrappers, the MessageSprite text,
  reveal count and geometry, and that the legacy DialogueBox/background are
  hidden while the HostWindow tree is active.
- In the unmodified `00_Z000` snapshot, all five `adv.bustupMan.spr` slots are
  invisible, textureless, and unattached. This does not establish natural
  bustup attachment later in a scenario.
- The optional `--probe-bustup` calls the original `SetBustup("CA02_01M", 0, 0)`
  and `AdvScreen::update(adv, 0, 0)` in memory. The resulting 588x528 sprite is
  found at `root[0]/child[0]/child[0]` and rendered by the compositor without a
  second Bustup TextureRect. This is explicit diagnostic evidence, not a
  natural ScenarioLoop event. Its `root_window` weak field remains unset.
- `ScenarioLoop("00_Z005")` reaches a real `AdvScreen::startSelect` CSX stack
  frame. The HostWindow has four roots; `root[2]` and `root[3]` are the original
  750x48 option rows. Each contains an `ID_SELECT` HostSprite and an
  `ID_FONT_SELECT` MessageSprite containing `敲门` or `今天这先这样吧`.
- The VM no longer intercepts `AdvScreen::startSelect`, and the separate
  `ChoiceContainer`, `current_choices`, and `is_waiting_choice` implementation
  has been removed. `native_story_selection_smoke.gd` queues `ID_SELECT` for
  the original first option with a logical cursor override. The CSX function
  consumes the command, runs its cursor hit-test, returns `selectResult == 1`,
  and leaves no stale command. This smoke uses a synthetic TextureButton
  activation; it does not yet exercise a physical mouse or keyboard event.
- During the same original `00_Z000` body-message wait, the compositor smoke
  activates the original `ID_QSAVE` HostSprite and verifies the producer
  contract: exactly one bounded event is queued with its window and source
  sprite IDs, and `CsxHost.push_command()` wakes the paused VM without adding
  an advance tick. It then opens a fresh command scope to discard this
  synthetic event. This smoke does not claim that the QSave action itself was
  consumed or that a save was written. The selection smoke separately proves
  full CSX command consumption for `ID_SELECT` and `selectResult == 1`.
- Both Story smokes verify that `system/yosuga.csx` and `data1.noa` retain their
  input hashes:
  - `yosuga.csx`: `157be9eb39cdc2d3cb654096340ca686f4ef48ac7fd7a6255673ba5f0c79afb6`
  - `data1.noa`: `d324c49ed4a80108f68aabaf7a202ec31d1b8f64075918f136944e72ec919831`

The audit command exits with `PASS Story HostWindow tree audit`; the selection
smoke exits with the `selectResult=1` pass above. The compositor smoke passes
its assertions. A verbose rerun on commit `1b49dcd` exited 0 without ObjectDB,
resource-in-use, or texture-RID leak reports; it still reports seven orphan
`StringName`s (`ScriptBacktrace`, `YzkCodec`, `OS`, `RefCounted`, `Object`,
`ClassDB`, and `Logger`) at shutdown. An earlier worktree run reported 151
ObjectDB instances, three resources, and 43 dummy texture RIDs; that result is
superseded by the later clean resource teardown, but the remaining
`StringName` reports are still open.

## Remaining split paths and limits

The Story HostWindow tree now carries the ordinary message frame, quick menu,
and original selection rows. The migration is not complete: `adv_player.gd`
still constructs a hidden fallback DialogueBox and quick-menu controls, copies
MessageSprite text into fallback labels, separately draws CG/temporary sprites,
and can draw unattached bustups through TextureRects. Backlog and some modal
flows remain Godot-owned. Story advance input still writes `advance_ticks`
and clears `is_waiting_input` directly, while native buttons use the HostWindow
command queue; queued window commands now wake a paused VM without synthesizing
an advance tick. The title compositor also retains title-specific generated UI
and callback branches.

The compositor's viewport-background test, source Z ordering, local clipping,
all text formatting/fade cases, physical input mapping, natural bustup
attachment, and title-to-Story/modal transitions still need dedicated
regression and original-runtime comparison. No official Cotopha runtime output
or pixel differential was captured here.
