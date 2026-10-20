#!/usr/bin/env bash
# Fails if a Linux library needs a newer glibc than a reference binary, Godot's own Linux
# export template: a GDExtension that asks for a newer glibc than the game itself does not load
# on the older machines the game still runs on, and the game falls back to GDScript there. Also
# fails on a dynamic libstdc++ or libgcc_s, which godot-cpp links statically
# (use_static_cpp). Prints what both binaries need.
#   bash .github/native/check_glibc.sh <library.so> <template binary>
set -euo pipefail

lib=$1
ref=$2

glibc_versions() {
  objdump -T "$1" | grep -o 'GLIBC_[0-9][0-9.]*' | sort -uV
}

echo "$lib NEEDED: $(objdump -p "$lib" | awk '/NEEDED/ {print $2}' | tr '\n' ' ')"
echo "$lib glibc versions: $(glibc_versions "$lib" | tr '\n' ' ')"
need=$(glibc_versions "$lib" | tail -n 1)
have=$(glibc_versions "$ref" | tail -n 1)
echo "$ref needs up to $have; the library needs up to $need"

newest=$(printf '%s\n%s\n' "$need" "$have" | sort -V | tail -n 1)
if [ "$newest" != "$have" ]; then
  echo "::error::$lib needs $need, newer than the export template's $have"
  objdump -T "$lib" | grep -F "$need"
  exit 1
fi
if objdump -p "$lib" | grep -qE 'NEEDED +(libstdc\+\+|libgcc_s)'; then
  echo "::error::$lib links libstdc++ or libgcc_s dynamically"
  exit 1
fi
