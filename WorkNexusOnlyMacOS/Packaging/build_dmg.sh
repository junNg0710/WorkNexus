#!/usr/bin/env bash
# Builds the native macOS app as a universal (arm64 + x86_64) Release, ad-hoc signed like the Flutter build, and packages it
# the way CI publishes the Flutter one (see ../packaging/macos/build_dmg.sh and .github/workflows/build.yml):
#
#   dist/WorkNexusMac-macos-universal.zip   `ditto` archive of WorkNexusMac.app — what the in-app updater downloads
#   dist/WorkNexusMac-macos-universal.dmg   drag-to-Applications disk image
#   dist/SHA256SUMS.txt                  `<sha256>  <name>` lines — the updater refuses a zip not listed here
#
# Usage:
#   Packaging/build_dmg.sh                       # build, then package into ./dist
#   Packaging/build_dmg.sh --out /tmp/release    # another output folder
#   Packaging/build_dmg.sh --app path/to/WorkNexusMac.app   # package an existing .app, no build
#
# Environment:
#   SIGN_IDENTITY   codesign identity (default "-" = ad-hoc). See Packaging/README.md for notarization.
#   DERIVED_DATA    xcodebuild derived-data folder (default build/release under this project)
#   SYNC_ASSETS=1   run Scripts/sync-assets.sh and gen-l10n.py before building
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$root/dist"
app=""
sign_identity="${SIGN_IDENTITY:--}"
derived="${DERIVED_DATA:-$root/build/release}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) out="$2"; shift 2 ;;
    --app) app="$2"; shift 2 ;;
    -h|--help) sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 64 ;;
  esac
done

name="WorkNexusMac"
asset="$name-macos-universal"      # the names AppUpdateConfig / AppConfig.updateAssetMacos expect

if [[ -z "$app" ]]; then
  # The Xcode project is generated from project.yml (xcodegen) and not kept in git.
  if [[ ! -d "$root/WorkNexusOnlyMacOS.xcodeproj" ]]; then
    command -v xcodegen >/dev/null || { echo "xcodegen is needed to generate the project: brew install xcodegen" >&2; exit 69; }
    (cd "$root" && xcodegen generate)
  fi
  # Strings and assets come from the Flutter sources. SYNC_ASSETS=1 refreshes them first, so the build matches the
  # checked-out upstream (off by default: it rewrites Localizable.xcstrings and the bundled fonts/logos).
  if [[ "${SYNC_ASSETS:-0}" == 1 && -x "$root/Scripts/sync-assets.sh" && -f "$root/Scripts/gen-l10n.py" ]]; then
    (cd "$root" && Scripts/sync-assets.sh && python3 Scripts/gen-l10n.py)
  fi

  rm -rf "$derived"
  # Both architectures in one binary (ONLY_ACTIVE_ARCH=NO); signed ad-hoc by the project's own settings, re-signed below.
  xcodebuild \
    -project "$root/WorkNexusOnlyMacOS.xcodeproj" \
    -scheme "$name" \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$derived" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE=Manual \
    build
  app="$derived/Build/Products/Release/$name.app"
fi

[[ -d "$app" ]] || { echo "not an app bundle: $app" >&2; exit 66; }

# Both slices must be there, or the updater would ship Apple-silicon-only to Intel users.
archs="$(lipo -archs "$app/Contents/MacOS/$name")"
for arch in arm64 x86_64; do
  [[ " $archs " == *" $arch "* ]] || { echo "the binary lacks $arch (has: $archs)" >&2; exit 65; }
done

# Ad-hoc signing (no Developer ID), as the Flutter build. --deep covers the frameworks and helpers in the bundle.
codesign --force --deep --sign "$sign_identity" --entitlements "$root/App/WorkNexus.entitlements" "$app"
codesign --verify --deep --strict "$app"

mkdir -p "$out"
rm -f "$out/$asset.zip" "$out/$asset.dmg" "$out/SHA256SUMS.txt"

# ditto (not zip) preserves the .app bundle's symlinks, permissions and signature; the updater unpacks it with `ditto -x -k`.
ditto -c -k --sequesterRsrc --keepParent "$app" "$out/$asset.zip"

# The disk image: the app next to a link to /Applications.
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/$name.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "$name" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$out/$asset.dmg"

# `<sha256>  <name>` (two spaces), the format `sha256sum` writes and the updater reads.
(cd "$out" && shasum -a 256 "$asset.zip" "$asset.dmg" > SHA256SUMS.txt)

echo
echo "Built $name ($archs):"
ls -lh "$out/$asset.zip" "$out/$asset.dmg" "$out/SHA256SUMS.txt"
cat "$out/SHA256SUMS.txt"
