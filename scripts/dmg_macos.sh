#!/bin/zsh
# Builds the release app and packs it into build/rotide.dm-<version>.dmg with a drag-to-Applications window,
# plus a .sha256 next to it. Usage: scripts/dmg_macos.sh [--no-build]
set -euo pipefail
root="${0:A:h:h}"
cd "$root"
if [[ "${1:-}" != "--no-build" ]]; then
  (cd packages/rotide_core && dart test)
  (cd app && flutter test)
  scripts/build_macos.sh release >/dev/null
fi
app="$root/app/build/macos/Build/Products/Release/rotide.dm.app"
[[ -d "$app" ]] || { echo 'rotide.dm.app is missing; run scripts/build_macos.sh release first' >&2; exit 1; }
codesign --verify --deep --strict "$app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
[[ "$version" == [0-9]* && "$version" != *[^0-9.]* ]] || { echo "invalid version: $version" >&2; exit 1; }
mkdir -p build
output="$root/build/rotide.dm-$version.dmg"
work=$(mktemp -d "${TMPDIR:-/tmp}/rotide-dmg.XXXXXXXX")
mount="$work/mount"
mkdir -p "$work/source/.background" "$mount"
mounted=0
cleanup() {
  if [[ "$mounted" == 1 ]]; then hdiutil detach "$mount" -quiet || true; fi
  rm -rf "$work"
}
trap cleanup EXIT
swift tool/dmg/background.swift "$work/source/.background/background.png"
ditto "$app" "$work/source/rotide.dm.app"
ln -s /Applications "$work/source/Applications"
hdiutil create -quiet -volname "rotide.dm $version" -srcfolder "$work/source" -format UDRW -fs HFS+ "$work/staging.dmg"
hdiutil attach -quiet -nobrowse -noautoopen -mountpoint "$mount" "$work/staging.dmg"
mounted=1
osascript - "$mount" <<'APPLESCRIPT'
on run argv
    set volumePath to POSIX file (item 1 of argv) as alias
    tell application "Finder"
        open volumePath
        set w to container window of volumePath
        set current view of w to icon view
        set toolbar visible of w to false
        set statusbar visible of w to false
        set bounds of w to {200, 160, 920, 600}
        set viewOptions to icon view options of w
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 112
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:background.png" of volumePath
        set position of item "rotide.dm.app" of volumePath to {170, 162}
        set position of item "Applications" of volumePath to {550, 162}
        update volumePath without registering applications
        delay 2
        close w
    end tell
end run
APPLESCRIPT
sync
hdiutil detach -quiet "$mount"
mounted=0
hdiutil convert -quiet "$work/staging.dmg" -format UDZO -imagekey zlib-level=9 -o "$work/final.dmg"
mv -f "$work/final.dmg" "$output"
(cd "${output:h}" && shasum -a 256 "${output:t}" > "${output:t}.sha256")
printf '%s\n' "$output" "$output.sha256"
