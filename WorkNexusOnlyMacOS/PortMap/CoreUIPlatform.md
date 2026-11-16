# CoreUI/Platform (lib/core/platform → Sources/CoreUI/Platform)

macOS-only ports. No composition-root wiring is done here: each service is created and held by `App/`.

| Area | Dart | Swift |
|---|---|---|
| App identity + Application Support folder | lib/core/config/app_config.dart, path_provider | PlatformPaths.swift (`AppIdentity`, `PlatformPaths`) |
| OS notifications, tap stream, permission / settings link | lib/core/platform/desktop_notifier.dart | DesktopNotifier.swift (`DesktopNotifying`, `DesktopNotifier`) |
| Dock badge | lib/core/platform/app_icon_badge.dart (macOS) | DockBadge.swift (`DockBadging`, `DockBadge`) |
| Tray / status item (localized menu) | lib/core/platform/desktop_tray_service.dart | StatusItemService.swift |
| Close-to-tray lifecycle | lib/core/platform/desktop_app_lifecycle.dart | CloseToTrayLifecycle.swift |
| Open in browser / Finder, link routing | lib/core/platform/open_external.dart, link_router.dart | OpenExternal.swift, LinkRouter.swift |
| Clipboard image / copied files (files win over image data) | lib/core/platform/image_clipboard.dart, features/chat/.../chat_attachments.dart | Pasteboard.swift (`PasteboardKit`) |
| Video thumbnails (AVAssetImageGenerator, QuickLook fallback, `.thumb.png` cache) | lib/core/platform/video_thumbnailer.dart | VideoThumbnailer.swift |
| Window placement (maximized + frame) | lib/core/platform/window_placement_store.dart, window_placement_recorder.dart | WindowPlacementStore.swift |
| Custom app icon | lib/core/platform/app_icon_service.dart, app_icon_image.dart | AppIconService.swift |
| Custom app name | lib/core/platform/app_name_service.dart | AppNameService.swift |
| Focus-regained counter (10 s gap) | lib/core/platform/app_resume.dart | AppResumeCounter.swift |
| Tests | test/core/platform/video_thumbnailer_test.dart | Tests/CoreUITests/PlatformTests.swift |

Integration pass: `PlatformPaths.applicationSupport()` honours `WN_SUPPORT_DIR`; `AppDatabase.open(path:registrars:)` added (CorePersistence); `FeatureChat.ChatPersonAvatar` / `ChatPersonChip` (public) back the shared `\.personAvatar` / `\.personChip` hooks.

Shell pass 2: `AppL10n.swift` now holds `AppLanguage` (the language picker: `appString` reads the picked `.lproj`, `Bundle.main` answers `localizedString` from it so `String(localized:)` follows, `AppleLanguages` is written for the next launch); `Widgets/Dialogs/CustomColorDialog.swift` (lib/core/widgets/custom_color_dialog.dart); `Widgets/Celebration/*`; `DialogCenter.isPresenting`. The tray menu follows the language (`PlatformServices.trayStrings` -> `updateStrings`) and a Dock click on the hidden window brings it back (`AppDelegate.applicationShouldHandleReopen`; the app is a single `Window` scene). Geist Mono is listed in the font picker; the font is not bundled (Flutter downloads it), so the monospaced system face stands in unless it is installed.
