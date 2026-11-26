#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ndk_path="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
required_ndk_revision="28.1.13356709"
if [[ -z "$ndk_path" || ! -f "$ndk_path/build/cmake/android.toolchain.cmake" ]]; then
  echo "Set ANDROID_NDK_HOME (or ANDROID_NDK_ROOT) to Android NDK r28b ($required_ndk_revision)." >&2
  exit 2
fi
ndk_path="$(cd -- "$ndk_path" && pwd -P)"
ndk_properties="$ndk_path/source.properties"
if [[ ! -f "$ndk_properties" ]]; then
  echo "NDK source.properties is missing: $ndk_properties" >&2
  exit 2
fi
ndk_revision="$(awk -F= '$1 ~ /^[[:space:]]*Pkg.Revision[[:space:]]*$/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' "$ndk_properties")"
if [[ "$ndk_revision" != "$required_ndk_revision" ]]; then
  echo "Android codec build requires NDK r28b ($required_ndk_revision); found '${ndk_revision:-unknown}' at '$ndk_path'." >&2
  exit 2
fi
if ! command -v cmake >/dev/null 2>&1; then
  echo "CMake 3.18 or newer is required to build the Android codec." >&2
  exit 2
fi
cmake_version="$(cmake --version | awk 'NR == 1 { print $3; exit }')"
if ! awk -v version="$cmake_version" 'BEGIN { split(version, parts, "."); exit !((parts[1] > 3) || (parts[1] == 3 && parts[2] >= 18)) }'; then
  echo "Android codec build requires CMake 3.18 or newer; found '${cmake_version:-unknown}'." >&2
  exit 2
fi

source "$project_dir/tools/codec_build_sources.sh"
build_root="${YOSUGA_ANDROID_CODEC_BUILD_DIR:-$codec_reference_root/yzk2godot-android-codec-build}"
mkdir -p "$build_root"

abis=(arm64-v8a armeabi-v7a x86_64)
for abi in "${abis[@]}"; do
  build_dir="$build_root/$abi"
  echo "===> Building ERISAN/ERI/MIO GDExtension for $abi"
  cmake -S "$project_dir/tools/codec" -B "$build_dir" \
    -DCMAKE_TOOLCHAIN_FILE="$ndk_path/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$abi" \
    -DANDROID_PLATFORM=android-24 \
    -DCMAKE_BUILD_TYPE=Release \
    -DGODOTCPP_TARGET=template_release \
    -DGODOTCPP_API_VERSION=4.7 \
	    -DAU_SOURCE_DIR="$codec_arc_dir" \
	    -DGODOTCPP_SOURCE_DIR="$codec_godot_cpp_dir" \
    -DCMAKE_SKIP_RPATH=ON
  cmake --build "$build_dir" --target yzk_codec --parallel "${YOSUGA_BUILD_JOBS:-4}"
  output_dir="$project_dir/android/libs/$abi"
  mkdir -p "$output_dir"
  install -m 755 "$build_dir/libyzk_codec.so" "$output_dir/libyzk_codec.so"
  (
    cd "$output_dir"
    sha256sum -- libyzk_codec.so > SHA256SUMS
    sha256sum --check SHA256SUMS
  )
done
printf 'Persistent Android source and build tree: %s\n' "$build_root"
