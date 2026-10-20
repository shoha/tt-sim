#!/usr/bin/env bash
# Parity of the native scatter library with GDScript on this platform: runs
# tests/unit/test_scatter_native.gd (about 80 s) under the given Godot command, with the
# template_debug library the editor loads and with the template_release library exports ship,
# the latter by pointing the extension's debug entries at the release files for that run.
# PARITY_TARGETS picks the libraries (default both). Fails if a run fails or the test is pending
# (the library did not load). The project must already be imported with native/ in place. Run
# from the repository root; the arguments are the Godot command:
#   bash .github/native/parity.sh <godot>
#   PARITY_TARGETS=template_release bash .github/native/parity.sh arch -x86_64 <godot>
set -euo pipefail

godot=("$@")
targets=${PARITY_TARGETS:-template_debug template_release}
extension=native/tt_scatter.gdextension
saved=$(mktemp)
cp "$extension" "$saved"
trap 'cp "$saved" "$extension"' EXIT

run() {
  local log
  log=$(mktemp)
  "${godot[@]}" --headless --path . --script res://addons/gut/gut_cmdln.gd -- \
    -gconfig=tests/.gutconfig.json -gselect=test_scatter_native 2>&1 | tee "$log"
  if grep -q 'the native library is not built' "$log" \
    || ! grep -qE 'noise: [1-9][0-9]* values over settings' "$log"; then
    echo "::error::$1: the native library did not load, so test_scatter_native was pending"
    exit 1
  fi
  echo "parity with the $1 library: passed"
}

for target in $targets; do
  sed "s/template_debug/$target/g" "$saved" > "$extension"
  run "$target"
done
