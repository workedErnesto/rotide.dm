#!/bin/zsh
# Test, build release and replace the installed application, keeping its bundle identifier and settings (shared with
# the Swift version). Quits a running copy first and reopens it afterwards.
set -euo pipefail
root="${0:A:h:h}"
(cd "$root/packages/rotide_core" && dart test)
(cd "$root/app" && flutter test)
product="$("$root/scripts/build_macos.sh" release | tail -n 1)"
[[ -d "$product" ]] || { echo "сборка не удалась" >&2; exit 1; }
target="/Applications/rotide.dm.app"
bundle_id="app.rotide.dm"
was_running=false
if pgrep -f "$target/Contents/MacOS" >/dev/null; then
  was_running=true
  osascript -e "tell application id \"$bundle_id\" to quit" >/dev/null 2>&1 || true
  for _ in {1..50}; do pgrep -f "$target/Contents/MacOS" >/dev/null || break; sleep 0.1; done
  if pgrep -f "$target/Contents/MacOS" >/dev/null; then
    echo "rotide.dm не завершилась: сохраните документы и закройте её, затем повторите установку" >&2
    exit 1
  fi
fi
stage=$(mktemp -d /Applications/.rotide-install.XXXXXXXX)
trap 'rm -rf "$stage"' EXIT
ditto "$product" "$stage/new.app"
codesign --verify --deep --strict "$stage/new.app"
if [[ -e "$target" ]]; then mv "$target" "$stage/previous.app"; fi
if ! mv "$stage/new.app" "$target"; then
  if [[ -e "$stage/previous.app" ]]; then mv "$stage/previous.app" "$target"; fi
  exit 1
fi
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$target"
touch "$target"
if [[ "$was_running" == true ]]; then open "$target"; fi
printf 'установлено: %s\n' "$target"
