#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
runtime_dir="$project_dir/tools/bin/linux"
manifest="$runtime_dir/SHA256SUMS"

[[ -f "$runtime_dir/libyzk_codec.so" ]] || {
  echo "Missing Linux runtime artifact: $runtime_dir/libyzk_codec.so" >&2
  exit 1
}
[[ -f "$manifest" ]] || { echo "Missing checksum manifest: $manifest" >&2; exit 1; }

(
  cd "$runtime_dir"
  sha256sum --check SHA256SUMS
  expected="$(for name in arc_unpacker erisan_decode libyzk_codec.so; do [[ ! -f "$name" ]] || printf '%s\n' "$name"; done | sort)"
  actual="$(awk '{ print $2 }' SHA256SUMS | sort)"
  [[ "$actual" == "$expected" ]] || {
    echo "SHA256SUMS does not match the Linux runtime artifacts present." >&2
    exit 1
  }
)

case "$(uname -m)" in
  x86_64)
    expected_machine="Advanced Micro Devices X86-64"
    architecture="x86_64"
    ;;
  aarch64|arm64)
    expected_machine="AArch64"
    architecture="arm64"
    ;;
  *)
    echo "Unsupported Linux architecture: $(uname -m)" >&2
    exit 1
    ;;
esac
actual_machine="$(readelf -h "$runtime_dir/libyzk_codec.so" | awk -F: '/Machine:/ { gsub(/^[[:space:]]+/, "", $2); print $2 }')"
[[ "$actual_machine" == "$expected_machine" ]] || {
  echo "Expected $architecture codec artifact ($expected_machine), got: $actual_machine" >&2
  exit 1
}
nm -D --defined-only "$runtime_dir/libyzk_codec.so" | grep -Eq '[[:space:]]yzk_codec_init$'
"$project_dir/tools/generate_cp932_table.py" --check
echo "Verified Linux $architecture codec artifact, checksum manifest, entry symbol, and CP932 table."
