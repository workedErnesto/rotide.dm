#!/bin/zsh
# Builds "app/build/macos/Build/Products/<Mode>/rotide.dm.app". Usage: scripts/build_macos.sh [release|debug]
set -euo pipefail
cd "${0:A:h:h}/app"
mode="${1:-release}"
export LANG="${LANG:-en_US.UTF-8}"
flutter build macos "--${mode}"
product="build/macos/Build/Products/${(C)mode}/rotide.dm.app"
codesign --verify --deep --strict "$product"
printf '%s\n' "$PWD/$product"
