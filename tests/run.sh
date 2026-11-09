#!/bin/sh
# Runs the plugin's real code against KOReader stand-ins, starting from a copy
# with no audiobookshelf_config.lua. Needs luajit.  Usage: sh tests/run.sh
set -e
repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/plugin" "$work/settings"
cp -r "$repo/main.lua" "$repo/_meta.lua" "$repo/audiobookshelf_version.lua" "$repo/audiobookshelf" "$work/plugin/"
luajit "$repo/tests/tests.lua" "$work/plugin" "$work/settings"
