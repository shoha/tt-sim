#!/usr/bin/env bash
# CI build of the native scatter library (native/, docs/systems/scatter.md "Native path").
# Runs SCons with full command lines and fails unless every compile command carries
# -ffp-contract=off (native/SConstruct): the rows are bit-equal to GDScript's only when no
# compiler fuses a multiply and an add, which arm64 and any FMA target would otherwise do.
# Arguments go to scons. Run from the repository root: bash .github/native/build.sh target=...
set -euo pipefail

log=$(mktemp)
scons -C native -j"$(getconf _NPROCESSORS_ONLN)" verbose=yes "$@" 2>&1 | tee "$log"

total=$(grep -c -- ' -c ' "$log" || true)
contracted=$(grep -- ' -c ' "$log" | grep -c -- '-ffp-contract=off' || true)
echo "compile commands: $total, with -ffp-contract=off: $contracted"
if [ "$total" -eq 0 ] || [ "$total" -ne "$contracted" ]; then
  echo "::error::-ffp-contract=off is missing from $((total - contracted)) compile commands"
  grep -- ' -c ' "$log" | grep -v -- '-ffp-contract=off' | head -n 5
  exit 1
fi
