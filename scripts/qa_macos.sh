#!/bin/zsh
# Rebuilds the single test copy "build/rotide.dm QA.app" (identifier app.rotide.dm.flutter.qa), separate from the installed app.
# Usage: scripts/qa_macos.sh [debug|release] [file.md ...]
set -euo pipefail
root="${0:A:h:h}"
mode="${1:-debug}"
[[ $# -gt 0 ]] && shift
product="$("$root/scripts/build_macos.sh" "$mode" | tail -n 1)"
[[ -d "$product" ]] || { echo "сборка не удалась" >&2; exit 1; }
qa="$root/build/rotide.dm QA.app"
osascript -e 'tell application id "app.rotide.dm.flutter.qa" to quit' >/dev/null 2>&1 || true
for _ in {1..100}; do pgrep -f "$qa/Contents/MacOS" >/dev/null || break; sleep 0.1; done
# The test copy holds no work worth keeping; stop it if it did not quit.
pkill -f "$qa/Contents/MacOS" 2>/dev/null || true
mkdir -p "$root/build"
rm -rf "$qa"
ditto "$product" "$qa"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier app.rotide.dm.flutter.qa" -c "Set :CFBundleDisplayName rotide.dm QA" "$qa/Contents/Info.plist"
codesign --force --deep --sign - "$qa" >/dev/null
if [[ $# -gt 0 ]]; then open -a "$qa" "$@"; else open "$qa"; fi
printf '%s\n' "$qa"
