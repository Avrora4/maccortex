#!/usr/bin/env zsh
# Prints the context part of benchmark schema v1 as one JSON line:
#   {"machine":..., "env":{"macos","xcode","metal_toolchain"}, "git":...}
# Compiler and flags are NOT collected here: the benchmark binary reports what
# it was actually built with, because the shell cannot know that.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# Refuse contexts that would make a measurement unreproducible. This script
# runs as a child process, so it sees only exported variables: exactly the
# ones that can reach a build.
if [[ -n "${CONDA_PREFIX:-}" ]]; then
  print -u2 "✗ conda environment active (${CONDA_PREFIX}); it replaces ld/ar for Homebrew LLVM"
  print -u2 "  fix: conda deactivate"
  exit 1
fi
if [[ -n "${CC:-}${CXX:-}" ]]; then
  print -u2 "✗ CC/CXX exported (CC='${CC:-}' CXX='${CXX:-}'); they override the preset's compiler"
  print -u2 "  fix: unset CC CXX"
  exit 1
fi

machine=$(git config --get maccortex.machine) \
  || { print -u2 "✗ machine id not set; run tools/setup_clone.zsh <machine-id> first"; exit 1 }

xcode=$(xcodebuild -version | awk '/^Xcode/{v=$2} /Build version/{b=$3} END{print v "/" b}')
metal=$(xcodebuild -showComponent MetalToolchain 2>/dev/null \
        | awk -F': ' '/^Build Version/{print $2}')
rev=$(git rev-parse --short HEAD)
# Only tracked files count: untracked result files from an earlier run must not
# mark the next run dirty. Sources are listed explicitly in CMake, so an
# untracked file can only reach a build through a tracked change.
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || rev="${rev}-dirty"

jq -nc \
  --arg machine "$machine" \
  --arg macos   "$(sw_vers -productVersion)/$(sw_vers -buildVersion)" \
  --arg xcode   "$xcode" \
  --arg metal   "${metal:-unknown}" \
  --arg git     "$rev" \
  '{machine: $machine,
    env: {macos: $macos, xcode: $xcode, metal_toolchain: $metal},
    git: $git}'
