#!/usr/bin/env bash
set -euo pipefail

force=0
if [[ "${1:-}" == "--force" ]]; then
  force=1
  shift
fi
if [[ $# -ne 1 || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'USAGE'
Usage: tools/stage_game_assets.sh [--force] GAME_DIRECTORY

Copies the original game files required by the Godot project into assets/.
It never edits the source game files and refuses to replace different staged
files unless --force is supplied. The script verifies SHA-256 hashes before
and after copying and writes assets/STAGED_GAME_ASSETS.sha256.
USAGE
  [[ $# -eq 1 ]] && exit 0
  exit 2
fi

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source_dir="$(realpath -e -- "$1")"
asset_dir="$project_dir/assets"
if [[ -L "$asset_dir" ]]; then
  echo "Refusing to stage through a symlinked assets directory: $asset_dir" >&2
  exit 1
fi
mkdir -p -- "$asset_dir"
asset_dir="$(realpath -e -- "$asset_dir")"

is_same_or_child() {
  local candidate="$1"
  local parent="$2"
  if [[ "$candidate" == "$parent" ]]; then
    return 0
  fi
  if [[ "$parent" == "/" ]]; then
    [[ "$candidate" == /* ]]
  else
    [[ "$candidate" == "$parent/"* ]]
  fi
}

if is_same_or_child "$asset_dir" "$source_dir" || is_same_or_child "$source_dir" "$asset_dir"; then
  echo "Refusing to stage when the source game and assets directory overlap." >&2
  exit 1
fi

required_files=(
  "data1.noa"
  "data2.noa"
  "sound.noa"
  "voice.noa"
  "system/frame.noa"
  "system/option.noa"
  "system/title.noa"
  "system/yosuga.csx"
)

write_hash_manifest() {
  local root="$1"
  local path_prefix="$2"
  local relative_path
  local output
  for relative_path in "${required_files[@]}"; do
    output="$(sha256sum -- "$root/$relative_path")"
    printf '%s  %s%s\n' "${output%%  *}" "$path_prefix" "$relative_path"
  done
}

for relative_path in "${required_files[@]}"; do
  if [[ ! -f "$source_dir/$relative_path" ]]; then
    echo "Missing required game file: $source_dir/$relative_path" >&2
    exit 1
  fi
done

prepare_destination() {
  local relative_path="$1"
  local current="$asset_dir"
  local component_index
  local -a components
  IFS='/' read -r -a components <<< "$relative_path"
  for ((component_index = 0; component_index < ${#components[@]}; component_index++)); do
    current="$current/${components[component_index]}"
    if [[ -L "$current" ]]; then
      echo "Refusing to write through a symlink in the assets directory: $current" >&2
      exit 1
    fi
    if (( component_index + 1 < ${#components[@]} )); then
      if [[ -e "$current" && ! -d "$current" ]]; then
        echo "Destination parent is not a directory: $current" >&2
        exit 1
      fi
      mkdir -p -- "$current"
    elif [[ -e "$current" && ! -f "$current" ]]; then
      echo "Destination is not a regular file: $current" >&2
      exit 1
    fi
  done
}

for relative_path in "${required_files[@]}"; do
  prepare_destination "$relative_path"
done
prepare_destination "STAGED_GAME_ASSETS.sha256"

before_manifest="$(mktemp)"
after_manifest="$(mktemp)"
source_after_manifest="$(mktemp)"
trap 'rm -f -- "$before_manifest" "$after_manifest" "$source_after_manifest"' EXIT

write_hash_manifest "$source_dir" "assets/" > "$before_manifest"

for relative_path in "${required_files[@]}"; do
  destination="$asset_dir/$relative_path"
  if [[ -f "$destination" ]]; then
    if cmp -s -- "$source_dir/$relative_path" "$destination"; then
      if [[ ! "$source_dir/$relative_path" -ef "$destination" ]]; then
        continue
      fi
    fi
    if [[ $force -ne 1 ]] && ! cmp -s -- "$source_dir/$relative_path" "$destination"; then
      echo "Staged file differs; use --force to replace it: $destination" >&2
      exit 1
    fi
  fi
  cp --reflink=auto --remove-destination --preserve=mode,timestamps -- "$source_dir/$relative_path" "$destination"
done

write_hash_manifest "$asset_dir" "assets/" > "$after_manifest"
if ! diff -u "$before_manifest" "$after_manifest"; then
  echo "Staged SHA-256 verification failed; source files were not changed." >&2
  exit 1
fi

write_hash_manifest "$source_dir" "assets/" > "$source_after_manifest"
if ! diff -u "$before_manifest" "$source_after_manifest"; then
  echo "Source game files changed while staging; investigate before continuing." >&2
  exit 1
fi

rm -f -- "$asset_dir/STAGED_GAME_ASSETS.sha256"
install -m 644 "$after_manifest" "$asset_dir/STAGED_GAME_ASSETS.sha256"
echo "Staged ${#required_files[@]} original files into $asset_dir (source hashes unchanged)."
