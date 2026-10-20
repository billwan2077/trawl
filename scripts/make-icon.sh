#!/bin/zsh
# Regenerates Assets/AppIcon.icns from scripts/draw-icon.swift.
set -euo pipefail
cd "${0:A:h}/.."

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
swift scripts/draw-icon.swift "$WORK/icon.png"

SET="$WORK/AppIcon.iconset"
mkdir -p "$SET"
for px in 16 32 128 256 512; do
    sips -z $px $px "$WORK/icon.png" --out "$SET/icon_${px}x${px}.png" >/dev/null
    sips -z $((px * 2)) $((px * 2)) "$WORK/icon.png" --out "$SET/icon_${px}x${px}@2x.png" >/dev/null
done

mkdir -p Assets
iconutil -c icns "$SET" -o Assets/AppIcon.icns
cp "$WORK/icon.png" Assets/AppIcon.png
echo "Wrote Assets/AppIcon.icns"
