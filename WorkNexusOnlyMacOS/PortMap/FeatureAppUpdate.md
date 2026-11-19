# FeatureAppUpdate (lib/features/app_update → Sources/FeatureAppUpdate)

Public entry: `AppUpdateFeature.makeModel(config:currentVersion:preference:session:quit:)` → `UpdateModel` (`start()`, `check()`, `installAndRestart()`, `state`), `UpdateBannerView(model:)`, `AppUpdateFeature.makeWhatsNew(config:currentVersion:seen:session:)` → `WhatsNewModel` (`checkAtLaunch()`, `news`, `dismiss()`), `ReleaseNotesDialog`, `UpdateProgressRing`, `AppUpdateFeature.autoUpdatePreference()`.
macOS only: the Windows/Linux/AppImage/deb installers are not ported. Not ported as such: the update dialog (the banner covers download progress, restart and the release-page fallback, and its "What's new" button opens the collected notes in `ReleaseNotesDialog`) and the settings card (the app's Settings page has its own).

Native releases are tagged `vX.Y.Z+mac` (`AppUpdateConfig.releaseTagSuffix = "+mac"`, set in the app's `CompositionRoot.updateConfig`): only those releases' notes are collected, and `AppVersion` treats `+mac` as build metadata, so `v1.9.5+mac` orders as, and equals, the running `1.9.5`. Headings show the `vX.Y.Z` part only.

| Area | Dart | Swift |
|---|---|---|
| Release identity (owner/repo/asset names, own-release tag suffix) | lib/core/config/app_config.dart (update constants) | Domain/Entities/AppUpdateConfig.swift |
| AvailableUpdate | domain/entities/available_update.dart | Domain/Entities/AvailableUpdate.swift |
| UpdateRepository (+ `ReleaseNote`, `fetchStableReleaseNotes`) / AutoUpdatePreference | domain/repositories/*.dart | Domain/Repositories/UpdateRepository.swift |
| SeenVersionStore (last version run) | domain/repositories/seen_version_store.dart | Domain/Repositories/SeenVersionStore.swift |
| AppVersion (semver order, `+build` ignored) | domain/value_objects/app_version.dart | Domain/ValueObjects/AppVersion.swift |
| CheckForUpdate (notes of every release since the running one, else the latest's) | domain/usecases/check_for_update.dart | Domain/UseCases/CheckForUpdate.swift |
| CollectReleaseNotes (newest first, `## vX.Y.Z` per version) | domain/usecases/collect_release_notes.dart | Domain/UseCases/CollectReleaseNotes.swift |
| FindWhatsNew (first launch after an update; first install shows nothing; failed fetch retried next launch) | domain/usecases/find_whats_new.dart | Domain/UseCases/FindWhatsNew.swift |
| Download / Install | domain/usecases/{download,install}_update.dart | Domain/UseCases/DownloadAndInstallUpdate.swift |
| Issue report URL | domain/usecases/build_issue_report_url.dart | Domain/UseCases/BuildIssueReportURL.swift |
| GitHub Releases latest + `/releases?per_page=100` + download with progress + SHA-256 | data/datasources/github_release_datasource.dart | Data/DataSources/GitHubReleaseDataSource.swift |
| Installer contract | data/datasources/update_installer.dart | Data/DataSources/UpdateInstaller.swift |
| macOS installer (`ditto -x -k`, detached `/bin/sh` swap script, writable check) | data/datasources/macos_update_installer.dart | Data/DataSources/MacOSUpdateInstaller.swift |
| Repository (asset lookup case-insensitive, SHA256SUMS, verify, unpack, swap + quit, own releases' notes) | data/repositories/github_update_repository.dart | Data/Repositories/GitHubUpdateRepository.swift |
| Last version run (`app_settings_kv` → UserDefaults `app_update.last_seen_version`) | data/repositories/local_seen_version_store.dart | Data/Repositories/UserDefaultsSeenVersionStore.swift |
| Auto-update marker file | data/repositories/local_auto_update_preference.dart, data/datasources/auto_update_marker_file.dart | Data/Repositories/MarkerFileAutoUpdatePreference.swift |
| State + controller (hourly check, stage → ready → installing) | presentation/providers/{update_state,update_controller}.dart | Presentation/{UpdateState,UpdateModel}.swift |
| Banner (+ "What's new" → notes since the running version) | presentation/widgets/update_rail_button.dart, update_dialog.dart | Presentation/UpdateBannerView.swift |
| What's new at launch | presentation/widgets/whats_new_at_launch.dart | Presentation/WhatsNewModel.swift; shown by the app's `UpdateBannerHost` (App/Sources/UpdateViews.swift) |
| What's new / notes dialog + version pills | presentation/widgets/{whats_new_dialog,update_version_change}.dart | Presentation/ReleaseNotesDialog.swift |
| Rail button: progress ring while downloading (tooltip %), spinning while installing, restart when verified | presentation/widgets/update_rail_button.dart (`_ProgressIcon`) | Presentation/UpdateProgressRing.swift; button in App/Sources/UpdateViews.swift (`UpdateRailButton`) |
| Tests | test/features/app_update/* | Tests/FeatureAppUpdateTests/{FeatureAppUpdateTests,ReleaseNotesTests}.swift |
