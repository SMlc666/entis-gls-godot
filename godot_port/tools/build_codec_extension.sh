#!/usr/bin/env bash
set -euo pipefail

# Build only the Godot in-process codec extension. This avoids the Boost
# filesystem dependency required by the separate arc_unpacker CLI tool.
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_url="${YOSUGA_ARC_SOURCE:-https://github.com/vn-tools/arc_unpacker.git}"
arc_revision="456834ecf2e5686813802c37efd829310485c57d"
godot_cpp_url="https://github.com/godotengine/godot-cpp.git"
godot_cpp_revision="507ed9d840c01a3c5b2a39af8bb4000bfac30bf5"
build_root="$(mktemp -d "${TMPDIR:-/tmp}/yzk-codec.XXXXXXXX")"
trap 'rm -rf -- "$build_root"' EXIT
arc_dir="$build_root/arc_unpacker"
godot_cpp_dir="$build_root/godot-cpp"

git init -q "$arc_dir"
git -C "$arc_dir" remote add origin "$source_url"
git -C "$arc_dir" fetch -q --depth 1 origin "$arc_revision"
git -C "$arc_dir" checkout -q --detach FETCH_HEAD
git init -q "$godot_cpp_dir"
git -C "$godot_cpp_dir" remote add origin "$godot_cpp_url"
git -C "$godot_cpp_dir" fetch -q --depth 1 origin "$godot_cpp_revision"
git -C "$godot_cpp_dir" checkout -q --detach FETCH_HEAD

cmake -S "$project_dir/tools/codec" -B "$build_root/build" \
  -DAU_SOURCE_DIR="$arc_dir" \
  -DGODOTCPP_SOURCE_DIR="$godot_cpp_dir" \
  -DCMAKE_BUILD_TYPE=Release \
  -DGODOTCPP_TARGET=template_release \
  -DGODOTCPP_API_VERSION=4.7 \
  -DCMAKE_SKIP_RPATH=ON
cmake --build "$build_root/build" --target yzk_codec --parallel "${YOSUGA_BUILD_JOBS:-4}"

runtime_dir="$project_dir/tools/bin/linux"
mkdir -p "$runtime_dir"
install -m 755 "$build_root/build/libyzk_codec.so" "$runtime_dir/libyzk_codec.so"
printf 'Installed Godot codec extension: %s\n' "$runtime_dir/libyzk_codec.so"
