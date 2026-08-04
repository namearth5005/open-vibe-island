#!/bin/zsh
# Renders the companion rig to PNG so it can be looked at.
#
# Compiles scripts/companion-rig-preview.swift against the real OpenIslandCore
# sources — the same trick creature-gate.sh uses, and for the same reason: if
# the preview drew its own copy of the rig it would be judging something that
# does not ship.
#
#   zsh scripts/companion-rig-preview.sh [output-directory]
set -euo pipefail

cd "$(dirname "$0")/.."

OUT="${1:-$(mktemp -d)/companion-rig}"
mkdir -p "$OUT"

BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

swiftc -swift-version 6 -package-name OpenIsland \
  Sources/OpenIslandCore/*.swift \
  scripts/companion-rig-preview.swift \
  -o "$BUILD/companion-rig-preview"

"$BUILD/companion-rig-preview" "$OUT" "${@:2}"
