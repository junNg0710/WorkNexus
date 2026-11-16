# Packaging

`build_dmg.sh` builds the universal Release app and writes the three release assets into `dist/`:

| File | What it is |
|---|---|
| `WorkNexusMac-macos-universal.zip` | `ditto` archive of `WorkNexusMac.app`. This is the asset the in-app updater (`FeatureAppUpdate`) downloads; the name comes from `AppUpdateConfig.macAssetName`. |
| `WorkNexusMac-macos-universal.dmg` | Drag-to-Applications disk image for first installs. |
| `SHA256SUMS.txt` | `<sha256>  <name>` lines. The updater refuses a zip whose hash is not listed. |

```bash
Packaging/build_dmg.sh                      # xcodegen (if needed) → xcodebuild Release → sign → zip + dmg + sums
Packaging/build_dmg.sh --app path/WorkNexusMac.app --out /tmp/release   # package an app that is already built
```

The build is ad-hoc signed (`CODE_SIGN_IDENTITY=-`), exactly like the Flutter build, so Gatekeeper treats a downloaded copy
as unidentified: the first launch is "right-click → Open" (or `xattr -dr com.apple.quarantine WorkNexusMac.app`). The app is not
sandboxed (it spawns the `opencode` CLI and reads browser cookie databases), so it is not a Mac App Store candidate either way.

When CI publishes a release, upload the three files with the other platforms' assets into one GitHub release and keep one
`SHA256SUMS.txt` for all of them (the Flutter workflow writes it for every asset; this script's file covers the macOS two).

## Optional: Developer ID signing and notarization

Not needed for the in-app updater (it swaps the bundle in place and `open`s it; a quarantine flag is only set by browsers). It
removes the Gatekeeper prompt for people who download the DMG. Needs a paid Apple Developer account.

1. Sign with a Developer ID Application certificate and the hardened runtime, then build the zip/dmg as usual:
   ```bash
   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" Packaging/build_dmg.sh
   ```
   The hardened runtime needs `--options runtime` on `codesign` (add it to the `codesign` line) and
   `ENABLE_HARDENED_RUNTIME: YES` in `project.yml`. Because the app loads no unsigned plug-ins, no extra entitlements beyond
   `App/WorkNexus.entitlements` are expected; if the camera/microphone prompts of mini apps stop working under the hardened
   runtime, add `com.apple.security.device.camera` and `com.apple.security.device.audio-input`.
2. Notarize the **zip** (or the dmg) and staple the ticket to the app/dmg:
   ```bash
   xcrun notarytool submit dist/WorkNexusMac-macos-universal.zip --keychain-profile "AC_NOTARY" --wait
   xcrun stapler staple build/release/Build/Products/Release/WorkNexusMac.app   # then re-zip so the staple travels with it
   xcrun notarytool submit dist/WorkNexusMac-macos-universal.dmg --keychain-profile "AC_NOTARY" --wait
   xcrun stapler staple dist/WorkNexusMac-macos-universal.dmg
   ```
   (`xcrun notarytool store-credentials AC_NOTARY …` saves the Apple ID / app-specific password once.)
3. Re-run the checksum step after stapling: the zip/dmg changed, so `SHA256SUMS.txt` must be rewritten
   (`cd dist && shasum -a 256 WorkNexusMac-macos-universal.zip WorkNexusMac-macos-universal.dmg > SHA256SUMS.txt`).

Switching from ad-hoc to Developer ID changes the app's code-signing identity: the Keychain item that holds the credential vault
(`worknexus.vault`) then asks the user once to allow the new build to read it.
