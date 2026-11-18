#!/bin/sh
# Copy fonts, brand logos, stickers, tray icons from the Flutter repo's assets/ into the app bundle resources.
set -e
ROOT="$(git rev-parse --show-toplevel)"
DST="$ROOT/WorkNexusOnlyMacOS/App/Resources"
mkdir -p "$DST"
rsync -a --delete "$ROOT/assets/fonts/" "$DST/Fonts/"
rsync -a --delete "$ROOT/assets/brands/" "$DST/Brands/"
# HyperRabbit and Cute are macOS-only packs: not in the Flutter assets, so they are kept (an excluded path is not deleted).
# Each Flutter pack brings its stickers.json (the emoji / words each sticker stands for, read for sticker suggestions);
# the WorkNexus stickers first drawn for macOS (Scripts/make-sticker.py) are upstream now, tagged there too.
rsync -a --delete --exclude 'HyperRabbit' --exclude 'Cute' "$ROOT/assets/stickers/" "$DST/Stickers/"
rsync -a --delete --exclude '*.ico' "$ROOT/assets/tray/" "$DST/Tray/"
# The bundled MCP server (built from mcp/ by `npm run build`); Settings › Chat › AI tools copies it to Application Support.
rsync -a --delete "$ROOT/assets/mcp/" "$DST/Mcp/"
echo "assets synced -> $DST"
