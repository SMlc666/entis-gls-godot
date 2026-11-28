# Third-party source and build artifact record

This file records source references and build steps visible in this workspace.
It is an engineering inventory, not a legal conclusion or a complete release
clearance review.

## arc_unpacker / Entis decoder

- Upstream repository: <https://github.com/vn-tools/arc_unpacker>
- Pinned source revision in `tools/build_arc_unpacker.sh`:
  `456834ecf2e5686813802c37efd829310485c57d`.
- The accompanying notice is `tools/arc_unpacker-LICENSE.md` (GNU GPL
  version 3 text). The local decoder wrappers declare `GPL-3.0-or-later` in
  their SPDX headers.
- The build script fetches that exact revision to a temporary checkout and
  applies CMake/header adjustments there; it does not edit a vendored source
  tree in place.

## Generated Linux artifacts

`tools/build_arc_unpacker.sh` currently installs these files in
`tools/bin/linux/`:

| Artifact | Build inputs |
|---|---|
| `arc_unpacker` | The pinned `arc_unpacker` checkout, with the temporary CMake decoder selection described above. |
| `erisan_decode` | Local wrapper `tools/erisan_decode.cc` plus decoder objects from the pinned `arc_unpacker` checkout. |
| `libyzk_codec.so` | Local `tools/yzk_codec.cc` and `tools/codec/CMakeLists.txt`, Entis decoder sources from the pinned checkout, and `godot-cpp` revision `507ed9d840c01a3c5b2a39af8bb4000bfac30bf5`. The build requests GDExtension API version `4.7`. |

These generated files are ignored by `.gitignore` and are not source inputs.
The build also uses the host compiler and system libraries; their exact versions
are not locked here, so the script records source revisions but does not claim
bit-for-bit reproducible binaries.

`erisan_decode` is an optional Linux fallback when the in-process ERISAN
extension is unavailable. `arc_unpacker` is only used by the optional
`native_codec_differential_smoke.gd` reference comparison; normal ERI/MIO
runtime decoding uses the in-process extension. When a sidecar is needed, it
must be an ordinary executable file because a PCK does not turn resources into
filesystem executables. A Linux distribution must place it under
`tools/bin/linux/` beside the standalone app or configure the corresponding
absolute-path environment variable. This workspace has no Linux export
sidecar deployment step and has not verified PCK execution.

After a successful Linux build, the script writes `tools/bin/linux/SHA256SUMS`.
Verify the installed outputs from the project root with:

```sh
(cd tools/bin/linux && sha256sum --check SHA256SUMS)
```

Keep this manifest with the build output and record the SHA-256 of the final
release archive separately, for example:

```sh
sha256sum -- dist/yosuga-port-linux.tar.zst
```

The checksums identify the files that were produced; they do not by themselves
prove that a binary was built from the listed sources.

## Android codec build

`tools/build_android_codec.sh` builds the ERISAN/ERI/MIO GDExtension for
`arm64-v8a`, `armeabi-v7a`, and `x86_64`. It accepts only Android NDK r28b
revision `28.1.13356709`, checked against the NDK's `source.properties`, and
requires CMake 3.18 or newer. It uses the pinned `arc_unpacker` and `godot-cpp`
revisions listed above and compiles with `ANDROID_PLATFORM=android-24` and
GDExtension API `4.7`. It writes `android/libs/<ABI>/libyzk_codec.so` and a
per-ABI `SHA256SUMS` manifest. The Android export preset selects only
`arm64-v8a`. The script does not export an APK or verify a device runtime; the
full Android playback chain remains incomplete. The checked-in workspace has
not produced Android `.so` files because NDK r28b is not available in this
environment. The only Android SDK component found is
`/usr/lib/android-sdk/platform-tools/adb`; cmdline-tools, platforms,
build-tools, Java SDK, and Godot export templates are absent, so APK export is
unavailable here.

## Godot and godot-cpp

- `tools/build_arc_unpacker.sh` fetches `godot-cpp` revision
  `507ed9d840c01a3c5b2a39af8bb4000bfac30bf5` for the Linux GDExtension build.
- `godot-cpp` is fetched into the temporary build directory and is not vendored
  in this project. No Godot editor, export template, or Android SDK/NDK is
  bundled here.

## User-provided game files

The `.noa` archives and `yosuga.csx` are expected to be supplied by the user.
`tools/stage_game_assets.sh` copies the required files without decoding or
rewriting them, verifies source and destination SHA-256 values, checks source
hashes again after copying, and writes `assets/STAGED_GAME_ASSETS.sha256`. The
user is responsible for deciding whether their copies may be packaged or
redistributed.
