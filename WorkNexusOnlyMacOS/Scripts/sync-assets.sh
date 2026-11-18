#!/bin/sh
# Copy fonts, brand logos, stickers, tray icons from the Flutter repo's assets/ into the app bundle resources.
set -e
ROOT="$(git rev-parse --show-toplevel)"
DST="$ROOT/WorkNexusOnlyMacOS/App/Resources"
mkdir -p "$DST"
rsync -a --delete "$ROOT/assets/fonts/" "$DST/Fonts/"
rsync -a --delete "$ROOT/assets/brands/" "$DST/Brands/"
# HyperRabbit and Cute are macOS-only packs, and ko_can_biet.png / gui_ten_ai_lam.png / ko_quan_tam.png / thay_vo.png macOS-only WorkNexus stickers
# (Scripts/make-sticker.py): not in the Flutter assets, so they are kept (an excluded path is not deleted).
rsync -a --delete --exclude 'HyperRabbit' --exclude 'Cute' --exclude '/WorkNexus/ko_can_biet.png' --exclude '/WorkNexus/gui_ten_ai_lam.png' --exclude '/WorkNexus/ko_quan_tam.png' --exclude '/WorkNexus/thay_vo.png' "$ROOT/assets/stickers/" "$DST/Stickers/"
rsync -a --delete --exclude '*.ico' "$ROOT/assets/tray/" "$DST/Tray/"
# The bundled MCP server (built from mcp/ by `npm run build`); Settings › Chat › AI tools copies it to Application Support.
rsync -a --delete "$ROOT/assets/mcp/" "$DST/Mcp/"
echo "assets synced -> $DST"
