#!/bin/zsh
# Launches the dev app for this worktree.
#
# scripts/launch-dev-app.sh regenerates the brand icons with whatever python3
# is on PATH, and Homebrew's lacks PIL. The system one has it, so a shim
# directory goes first on PATH. The shim lives in /tmp and /tmp gets cleared:
# rebuild it every time rather than assuming it survived. Without this the
# brand step fails, `set -e` aborts the script BEFORE it copies the new binary
# into the bundle, and you spend an hour screenshotting yesterday's build.
set -e

shim=/tmp/pyshim
mkdir -p "$shim"
ln -sf /usr/bin/python3 "$shim/python3"

export PATH="$shim:$PATH"
exec zsh scripts/launch-dev-app.sh "$@"
