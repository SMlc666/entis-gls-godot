#!/usr/bin/env bash

# Shared, pinned source checkouts for the Linux and Android codec builds.
# The default location is alongside the project in the durable reference tree,
# never under /tmp and never inside the distributable Godot project.
if [[ -z "${project_dir:-}" ]]; then
  echo "codec_build_sources.sh must be sourced after project_dir is set." >&2
  return 2 2>/dev/null || exit 2
fi

default_reference_root="$project_dir/../../reference-sources"
mkdir -p "$default_reference_root"
codec_reference_root="${YOSUGA_REFERENCE_ROOT:-$(cd "$default_reference_root" && pwd -P)}"
codec_source_root="${YOSUGA_CODEC_SOURCE_DIR:-$codec_reference_root/yzk2godot-codec-sources}"
codec_arc_url="${YOSUGA_ARC_SOURCE:-https://github.com/vn-tools/arc_unpacker.git}"
codec_arc_revision="456834ecf2e5686813802c37efd829310485c57d"
codec_godot_cpp_url="https://github.com/godotengine/godot-cpp.git"
codec_godot_cpp_revision="507ed9d840c01a3c5b2a39af8bb4000bfac30bf5"
codec_arc_dir="$codec_source_root/arc_unpacker"
codec_godot_cpp_dir="$codec_source_root/godot-cpp"
mkdir -p "$codec_source_root"

codec_prepare_pinned_source() {
  local source_dir="$1"
  local source_url="$2"
  local revision="$3"
  if [[ -e "$source_dir" && ! -d "$source_dir/.git" ]]; then
    echo "Persistent source path is not a Git checkout: $source_dir" >&2
    return 1
  fi
  if [[ ! -d "$source_dir/.git" ]]; then
    mkdir -p "$source_dir"
    git init -q "$source_dir"
  fi
  local configured_url=""
  configured_url="$(git -C "$source_dir" remote get-url origin 2>/dev/null || true)"
  if [[ -z "$configured_url" ]]; then
    git -C "$source_dir" remote add origin "$source_url"
  elif [[ "$configured_url" != "$source_url" ]]; then
    echo "Persistent source remote mismatch in $source_dir: $configured_url" >&2
    return 1
  fi
  local current_revision=""
  current_revision="$(git -C "$source_dir" rev-parse HEAD 2>/dev/null || true)"
  if [[ "$current_revision" != "$revision" ]]; then
    if [[ -n "$(git -C "$source_dir" status --porcelain)" ]]; then
      echo "Refusing to replace modified persistent source checkout: $source_dir" >&2
      return 1
    fi
    git -C "$source_dir" fetch -q --depth 1 origin "$revision"
    git -C "$source_dir" checkout -q --detach FETCH_HEAD
  fi
  if [[ -n "$(git -C "$source_dir" status --porcelain)" ]]; then
    echo "Persistent pinned source checkout is modified: $source_dir" >&2
    return 1
  fi
  if [[ "$(git -C "$source_dir" rev-parse HEAD)" != "$revision" ]]; then
    echo "Pinned source revision mismatch in $source_dir" >&2
    return 1
  fi
}

codec_prepare_pinned_source "$codec_arc_dir" "$codec_arc_url" "$codec_arc_revision"
codec_prepare_pinned_source "$codec_godot_cpp_dir" "$codec_godot_cpp_url" "$codec_godot_cpp_revision"

printf 'Persistent codec source checkouts: %s\n' "$codec_source_root"
printf 'arc_unpacker revision: %s\n' "$codec_arc_revision"
printf 'godot-cpp revision: %s\n' "$codec_godot_cpp_revision"
