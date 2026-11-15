#!/bin/zsh
# Xcode build phase: compiles the Dock tile plug-in into the app bundle before the app is signed.
set -euo pipefail
source_dir="${SRCROOT}/DockTile"
plugin="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/PlugIns/RotideDockTile.docktileplugin"
mkdir -p "${plugin}/Contents/MacOS"
cp "${source_dir}/Info.plist" "${plugin}/Contents/Info.plist"
archs=(${=ARCHS})
binaries=()
for arch in $archs; do
  out="${DERIVED_FILE_DIR}/RotideDockTile-${arch}"
  xcrun swiftc -O -module-name RotideDockTile -target "${arch}-apple-macos${MACOSX_DEPLOYMENT_TARGET}" \
    -emit-library -Xlinker -bundle -o "$out" "${source_dir}/RotideDockTile.swift"
  binaries+=("$out")
done
xcrun lipo -create "${binaries[@]}" -output "${plugin}/Contents/MacOS/RotideDockTile"
codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "${plugin}"
