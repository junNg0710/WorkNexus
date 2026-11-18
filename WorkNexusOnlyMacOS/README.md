# WorkNexusOnlyMacOS

The native Swift/SwiftUI macOS build of WorkNexus (ported from the Flutter app in the parent folder). This folder stands alone: upstream never touches it, so syncing the fork does not conflict.

```bash
brew install xcodegen            # once
Scripts/sync-assets.sh && python3 Scripts/gen-l10n.py   # fonts/logos/stickers + l10n strings from lib/
xcodegen generate && open WorkNexusOnlyMacOS.xcodeproj
(cd Packages/WorkNexusKit && swift test)
```

**Following upstream:** `Scripts/upstream-diff.sh` lists the Dart files changed since `UPSTREAM_PORTED`, each with its Swift counterpart (`PORT_MAP.md`). Once they are ported, run `Scripts/upstream-diff.sh --mark`.

Architecture rules and how to port: [PORTING.md](PORTING.md).

## Status (integration pass)

`App/Sources` is the composition root: `CompositionRoot` builds the database (every module's migration), repositories, `SyncCoordinator` (adapter registry dispatching to the ZenTao / GitLab / GitHub factories), the ZenTao wiring and the optional `AppServices.zentao*` hooks, the `ToolRegistry` (ZenTao, GitLab, GitHub), and all features. `HostWiring` fills `ShellModel.host` (slots of `SharedKit/Presentation/Shell/ShellHost.swift`) so the shell itself imports no tool or feature.

| Area | State |
|---|---|
| Rail (workspace, chat + unread, accounts + chat badge, Connect, mini apps + Mac apps + Add, bell, update, settings) | wired, seen in screenshots |
| Workspace pages: overview / integrations / members / workspace settings | wired (overview, connect dialog seen) |
| ZenTao / GitLab / GitHub tool modules, detail slide-over (`.detailOverlay`), ticket editor route | wired (ZenTao + GitLab sections, detail, editor error state seen); needs real servers for data |
| Chat (repository, services, unread counter, notification bridge -> `DesktopNotifier` / Dock badge, avatars via `\.personAvatar` / `\.personChip`) | wired; offline state seen, never connected to a server |
| Translation (service, chat adapter, ticket Translation tab, card dot, settings) | wired; no real backend run |
| Mini apps (rail, host stack, Add dialog) | wired; add dialog / pages not exercised |
| Mac app shortcuts (new, no Dart counterpart: rail buttons that open / focus an installed Mac app, running dot, Add menu + picker dialog, settings list) | wired; unit + render tested, never launched an app from the real rail |
| Notifications (bell, panel, poller, Dock badge), app update (banner, rail button, settings) | wired; need ZenTao / GitHub to produce data |
| Settings: general, appearance, chat, translation, local data; quick settings popover | wired; appearance + quick settings seen |
| Platform: tray + close-to-tray, window placement, app icon / name, resume counter | wired (off in demo mode) |
| Not ported / simplified | mini-app edit / icon picker / cookie-import dialogs, update release-notes dialog, workspace colour/icon editor on the workspace settings page, global search (⌘K field is inert), workspace switcher |

Deviations from the Dart rail: ZenTao has one rail button per account (its Tasks / Bugs / Docs sections are tabs in the nav pane) instead of section buttons; the chat view carries its own conversation list so the Chat place has no separate pane (an account list appears with several ZenTao accounts).

### Demo mode (DEBUG builds)
`WN_DEMO=1` runs on fake accounts / tickets, an in-memory credential store and no network jobs. `WN_DB_PATH` (database file), `WN_SUPPORT_DIR` (every per-user file), `WN_DEMO_NAV` (`workspace[:section]`, `account:<id>[:section]`, `settings[:section]`, `chat`, `editor:bug|task`, `ticket:<id>`, `connect`), `WN_DEMO_THEME`, `WN_DEMO_SIZE` (`1000x700`).

### Build
`xcodegen generate && xcodebuild -project WorkNexusOnlyMacOS.xcodeproj -scheme WorkNexus -configuration Debug build`. Extra l10n keys that are not in `lib/l10n/*.arb` live in `App/Resources/Localizable.extra.json`; `Scripts/gen-l10n.py` merges them.

### Diagnostics
Errors are written to `~/Library/Application Support/<bundle id>/Logs/worknexus.log` (rotated at 1 MB, 5 files, 7 days) and mirrored to the system log (Console.app, subsystem `com.worknexus`). Report through `Diagnostics.error/warning/info(area, message)` (CoreDomain) from any layer; messages are redacted (URL queries, passwords, tokens, cookies) and an error carries the user's last steps (`Diagnostics.step`, fed from the navigation state). Failed HTTP requests of the ZenTao, GitLab and GitHub clients, sync failures, chat failures and error toasts are recorded automatically; crash and hang reports arrive through MetricKit on a later launch. Settings → Local data → Diagnostics opens the folder or exports a zip for a bug report. Nothing is sent anywhere.

**Performance log** (off by default; Settings → Local data → Diagnostics): while on, `FrameStutterMonitor` (CoreUI) watches the screen's frames and writes a line per 5 s window of late frames ("Stutter: 6 late frames in 5 s, worst 140 ms, 420 ms lost"), or a "Not responding" line for a stall over 1 s; `PerformanceLog.measure` (CoreDomain) writes work slower than its limit (opening a chat, loading older / newer messages, building the chat rows, decoding a picture). Each line says where it happened: the place on screen and what is on it (`PerformanceLog.setContext`, e.g. "24 chat rows on screen (5 pictures, 2 stickers)"). Area `perf` in the log. Off, nothing is measured.
