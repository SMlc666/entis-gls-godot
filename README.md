# EntisGLS Godot Runtime

An experimental Godot compatibility runtime for Cotopha / EntisGLS game content. The project keeps the original CSX scripts and archives as the source of game behavior, while Godot provides the host runtime and rendering/audio/video services.

## Status

- Linux is the current development target. The project includes NOA/VFS loading, a CSX virtual machine, native `HostWindow`/`HostSprite` composition, and ERISAN/ERI/MIO/MEI support under active development.
- Android export is scaffolding only. Native codec builds, APK export, device installation, and a complete playthrough have not been verified.
- This is a prototype, not a stable release. A passing smoke test covers only the specific path named by that test.

## Run

Install Godot 4.7 or newer, then launch from the repository root:

```sh
YOSUGA_GAME_DIR="/path/to/your/game" ./play.sh --title
```

The local game directory is read-only to the runtime and is excluded from Git. See [the Godot project guide](godot_port/README.md) for launch modes, test commands, Android status, and codec build details.

## Repository layout

- [`godot_port/`](godot_port/) — Godot application, CSX VM, host APIs, codecs, tests, and technical notes.
- [`play.sh`](play.sh) — Linux launcher.
- [`godot_port/docs/`](godot_port/docs/) — runtime trajectory and platform notes.

Original game archives and local installs are not included. The root `.gitignore` excludes the complete `缘之空（全cg步兵版）` directory and raw NOA/CSX/Entis media files wherever they appear.
