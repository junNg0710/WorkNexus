#!/bin/sh
# Copy fonts, brand logos, stickers, tray icons from the Flutter repo's assets/ into the app bundle resources.
set -e
ROOT="$(git rev-parse --show-toplevel)"
DST="$ROOT/WorkNexusOnlyMacOS/App/Resources"
mkdir -p "$DST"
rsync -a --delete "$ROOT/assets/fonts/" "$DST/Fonts/"
rsync -a --delete "$ROOT/assets/brands/" "$DST/Brands/"
# HyperRabbit is a macOS-only pack: not in the Flutter assets, so it is kept (an excluded folder is not deleted).
rsync -a --delete --exclude 'HyperRabbit' "$ROOT/assets/stickers/" "$DST/Stickers/"
rsync -a --delete --exclude '*.ico' "$ROOT/assets/tray/" "$DST/Tray/"
echo "assets synced -> $DST"
