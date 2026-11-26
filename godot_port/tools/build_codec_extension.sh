#!/usr/bin/env bash
set -euo pipefail

# Build only the Godot in-process codec extension. This avoids the Boost
# filesystem dependency required by the separate arc_unpacker CLI tool.
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_dir/tools/codec_build_sources.sh"
build_root="${YOSUGA_CODEC_BUILD_DIR:-$codec_reference_root/yzk2godot-codec-build}"
mkdir -p "$build_root"

cmake -S "$project_dir/tools/codec" -B "$build_root/build" \
	-DAU_SOURCE_DIR="$codec_arc_dir" \
	-DGODOTCPP_SOURCE_DIR="$codec_godot_cpp_dir" \
  -DCMAKE_BUILD_TYPE=Release \
  -DGODOTCPP_TARGET=template_release \
  -DGODOTCPP_API_VERSION=4.7 \
  -DCMAKE_SKIP_RPATH=ON
cmake --build "$build_root/build" --target yzk_codec --parallel "${YOSUGA_BUILD_JOBS:-4}"

runtime_dir="$project_dir/tools/bin/linux"
mkdir -p "$runtime_dir"
install -m 755 "$build_root/build/libyzk_codec.so" "$runtime_dir/libyzk_codec.so"
(
  cd "$runtime_dir"
  files=(libyzk_codec.so)
  for helper in arc_unpacker erisan_decode; do
    [[ ! -f "$helper" ]] || files+=("$helper")
  done
  sha256sum -- "${files[@]}" > SHA256SUMS
  sha256sum --check SHA256SUMS
)
printf 'Installed Godot codec extension: %s\n' "$runtime_dir/libyzk_codec.so"
printf 'Wrote runtime artifact checksums: %s\n' "$runtime_dir/SHA256SUMS"
printf 'Persistent source and build tree: %s\n' "$build_root"
