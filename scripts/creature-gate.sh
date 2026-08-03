#!/bin/zsh
# Phase 0 creature legibility gate.
#
# Compiles scripts/creature-gate.swift against the real OpenIslandCore sources
# and renders the gate PNGs. Linking the shipped sources rather than copying
# constants is the point: if CreaturePalette or CreatureForm moves, the gate
# renders the moved values instead of a stale duplicate.
#
# The whole target is compiled rather than a curated file list. CreaturePose
# needs GeodeShard, which needs AgentSession and AgentEvent, and those reach
# most of Core — a hand-picked list breaks on unrelated Core edits, which for a
# gate that must be re-runnable months from now is the worse trade. Core has no
# external package dependencies, so the glob is self-contained.
#
#   zsh scripts/creature-gate.sh [output-directory]
set -euo pipefail

cd "$(dirname "$0")/.."

OUT="${1:-$(mktemp -d)/creature-gate}"
mkdir -p "$OUT"

# The binary is built outside $OUT so the output directory holds nothing but the
# renders — someone is going to open it in Finder and page through them.
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

swiftc -swift-version 6 -package-name OpenIsland \
  Sources/OpenIslandCore/*.swift \
  scripts/creature-gate.swift \
  -o "$BUILD/creature-gate"

"$BUILD/creature-gate" "$OUT" "${@:2}"
