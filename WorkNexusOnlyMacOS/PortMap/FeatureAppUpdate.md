# FeatureAppUpdate (lib/features/app_update → Sources/FeatureAppUpdate)

Public entry: `AppUpdateFeature.makeModel(config:currentVersion:preference:session:quit:)` → `UpdateModel` (`start()`, `check()`, `installAndRestart()`, `state`), `UpdateBannerView(model:)`, `AppUpdateFeature.autoUpdatePreference()`.
macOS only: the Windows/Linux/AppImage/deb installers are not ported. Not ported: the update dialog with release notes, the settings card and the rail button (the banner covers download progress, restart and the release-page fallback).

| Area | Dart | Swift |
|---|---|---|
| Release identity (owner/repo/asset names) | lib/core/config/app_config.dart (update constants) | Domain/Entities/AppUpdateConfig.swift |
| AvailableUpdate | domain/entities/available_update.dart | Domain/Entities/AvailableUpdate.swift |
| UpdateRepository / AutoUpdatePreference | domain/repositories/*.dart | Domain/Repositories/UpdateRepository.swift |
| Version ordering | domain/usecases/check_for_update.dart (`_Version`) | Domain/ValueObjects/SemanticVersion.swift |
| CheckForUpdate | domain/usecases/check_for_update.dart | Domain/UseCases/CheckForUpdate.swift |
| Download / Install | domain/usecases/{download,install}_update.dart | Domain/UseCases/DownloadAndInstallUpdate.swift |
| Issue report URL | domain/usecases/build_issue_report_url.dart | Domain/UseCases/BuildIssueReportURL.swift |
| GitHub Releases latest + download with progress + SHA-256 | data/datasources/github_release_datasource.dart | Data/DataSources/GitHubReleaseDataSource.swift |
| Installer contract | data/datasources/update_installer.dart | Data/DataSources/UpdateInstaller.swift |
| macOS installer (`ditto -x -k`, detached `/bin/sh` swap script, writable check) | data/datasources/macos_update_installer.dart | Data/DataSources/MacOSUpdateInstaller.swift |
| Repository (asset lookup case-insensitive, SHA256SUMS, verify, unpack, swap + quit) | data/repositories/github_update_repository.dart | Data/Repositories/GitHubUpdateRepository.swift |
| Auto-update marker file | data/repositories/local_auto_update_preference.dart, data/datasources/auto_update_marker_file.dart | Data/Repositories/MarkerFileAutoUpdatePreference.swift |
| State + controller (hourly check, stage → ready → installing) | presentation/providers/{update_state,update_controller}.dart | Presentation/{UpdateState,UpdateModel}.swift |
| Banner | presentation/widgets/update_rail_button.dart | Presentation/UpdateBannerView.swift |
| Tests | test/features/app_update/* | Tests/FeatureAppUpdateTests/FeatureAppUpdateTests.swift |
