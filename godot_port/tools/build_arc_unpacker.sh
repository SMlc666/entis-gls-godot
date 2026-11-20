#!/usr/bin/env bash
set -euo pipefail

# Build an optional Linux development codec from its pinned GPL source.
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_url="${YOSUGA_ARC_SOURCE:-https://github.com/vn-tools/arc_unpacker.git}"
revision="456834ecf2e5686813802c37efd829310485c57d"
godot_cpp_url="https://github.com/godotengine/godot-cpp.git"
godot_cpp_revision="507ed9d840c01a3c5b2a39af8bb4000bfac30bf5"
build_root="$(mktemp -d "${TMPDIR:-/tmp}/yzk-arc.XXXXXXXX")"
trap 'rm -rf -- "$build_root"' EXIT
source_dir="$build_root/source"
godot_cpp_dir="$build_root/godot-cpp"

git init -q "$source_dir"
git -C "$source_dir" remote add origin "$source_url"
git -C "$source_dir" fetch -q --depth 1 origin "$revision"
git -C "$source_dir" checkout -q --detach FETCH_HEAD
cp "$project_dir/tools/erisan_decode.cc" "$source_dir/yzk_erisan_decode.cc"
git init -q "$godot_cpp_dir"
git -C "$godot_cpp_dir" remote add origin "$godot_cpp_url"
git -C "$godot_cpp_dir" fetch -q --depth 1 origin "$godot_cpp_revision"
git -C "$godot_cpp_dir" checkout -q --detach FETCH_HEAD

# Keep only the Entis and common image decoders for the preview tool. The
# includes fix missing transitive headers with current compilers.
python3 - "$source_dir" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
cmake = root / 'CMakeLists.txt'
text = cmake.read_text()
text = text.replace('find_package(Boost COMPONENTS filesystem system REQUIRED)',
                    'find_package(Boost COMPONENTS filesystem REQUIRED)')
needle = 'list(REMOVE_ITEM au_sources "${CMAKE_SOURCE_DIR}/src/main.cc")'
assert needle in text
text = text.replace(needle, needle + '''
foreach(item ${au_sources})
    if(item MATCHES "/src/dec/[^/]+/" AND NOT item MATCHES "/src/dec/(entis|png|jpeg)/")
        list(REMOVE_ITEM au_sources "${item}")
    endif()
endforeach()''')
cmake.write_text(text)
with cmake.open('a') as output:
    output.write('''
add_executable(yzk_erisan_decode "${CMAKE_SOURCE_DIR}/yzk_erisan_decode.cc" $<TARGET_OBJECTS:libau>)
target_include_directories(yzk_erisan_decode BEFORE PUBLIC "${CMAKE_SOURCE_DIR}/src" "${CMAKE_BINARY_DIR}/generated")
target_link_libraries(yzk_erisan_decode ${iconv} ${Boost_LIBRARIES} ${ZLIB_LIBRARIES} ${PNG_LIBRARIES} ${JPEG_LIBRARIES} ${OPENSSL_LIBRARIES})
if(WEBP_FOUND)
    target_link_libraries(yzk_erisan_decode ${WEBP_LIBRARIES})
endif()

''')
types = root / 'src/types.h'
text = types.read_text().replace('#include <string>', '#include <cstdint>\n#include <string>')
types.write_text(text)
facade = root / 'src/flow/cli_facade.h'
text = facade.read_text().replace('#include "logger.h"', '#include <vector>\n#include <string>\n#include "logger.h"')
facade.write_text(text)
PY

cmake_args=(
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_SKIP_RPATH=ON
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5
  -DBoost_NO_BOOST_CMAKE=ON
  -DBoost_USE_STATIC_LIBS=OFF
)
if [[ -n "${YOSUGA_DEPS_PREFIX:-}" ]]; then
  cmake_args+=("-DBOOST_ROOT=$YOSUGA_DEPS_PREFIX" "-DCMAKE_PREFIX_PATH=$YOSUGA_DEPS_PREFIX")
  multiarch_include="$YOSUGA_DEPS_PREFIX/include/$(gcc -dumpmachine)"
  if [[ -d "$multiarch_include" ]]; then
    cmake_args+=("-DCMAKE_CXX_FLAGS=-I$multiarch_include")
  fi
fi

cmake -S "$source_dir" -B "$source_dir/build" "${cmake_args[@]}"
cmake --build "$source_dir/build" --target arc_unpacker yzk_erisan_decode --parallel "${YOSUGA_BUILD_JOBS:-4}"
codec_build="$build_root/codec-build"
cmake -S "$project_dir/tools/codec" -B "$codec_build" \
  -DAU_SOURCE_DIR="$source_dir" \
  -DGODOTCPP_SOURCE_DIR="$godot_cpp_dir" \
  -DCMAKE_BUILD_TYPE=Release \
  -DGODOTCPP_TARGET=template_release \
  -DGODOTCPP_API_VERSION=4.7 \
  -DCMAKE_SKIP_RPATH=ON
cmake --build "$codec_build" --target yzk_codec --parallel "${YOSUGA_BUILD_JOBS:-4}"
runtime_dir="$project_dir/tools/bin/linux"
mkdir -p "$runtime_dir"
install -m 755 "$source_dir/build/arc_unpacker" "$runtime_dir/arc_unpacker"
install -m 755 "$source_dir/build/yzk_erisan_decode" "$runtime_dir/erisan_decode"
install -m 755 "$codec_build/libyzk_codec.so" "$runtime_dir/libyzk_codec.so"
(
  cd "$runtime_dir"
  sha256sum -- arc_unpacker erisan_decode libyzk_codec.so > SHA256SUMS
)
printf 'Installed in-process Godot codec extension: %s\n' "$runtime_dir/libyzk_codec.so"
printf 'Installed Linux preview decoder: %s\n' "$runtime_dir/arc_unpacker"
printf 'Wrote runtime artifact checksums: %s\n' "$runtime_dir/SHA256SUMS"
