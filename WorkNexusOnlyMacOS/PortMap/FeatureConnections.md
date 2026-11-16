# Port map - FeatureConnections (Domain + Data + Presentation)

Paths: Dart under `lib/`, Swift under `Packages/WorkNexusKit/Sources/FeatureConnections/`. Public entry point:
`ConnectionsFeature.swift` (views, model, migration registrars - none: this feature owns no tables).

| Area | Dart | Swift |
|---|---|---|
| Entry point (model + views for the composition root) | app/di/service_locator.dart (wiring) | ConnectionsFeature.swift |
| Cache section enum | features/connections/domain/entities/cache_section.dart | Domain/Entities/CacheSection.swift |
| Connect request / result (typed issues instead of English strings) | presentation/connection_controllers.dart (args, `AddConnectionState`) | Domain/Entities/ConnectRequest.swift |
| Connection repository protocol | domain/repositories/connection_repository.dart | Domain/Repositories/ConnectionRepository.swift |
| Local cache repository protocol | domain/repositories/local_cache_repository.dart | Domain/Repositories/LocalCacheRepository.swift |
| Connect flow ZenTao / GitLab / GitHub (probe via `ProviderAdapterRegistry`, `secret:{accountId}`, persist, first sync, Jira disabled) | presentation/connection_controllers.dart (`connectZenTao/GitLab/GitHub`, `_resolveWorkspaceId`) | Domain/UseCases/ConnectAccount.swift |
| Account / workspace id scheme `zt-{slug}-{hash(url)}`, `intHash`, `_slug`, `_initials`, `_pickColor`, initial workspace | connection_controllers.dart, core/util/content_hash.dart, widgets/workspace_picker.dart (`initialWorkspaceId`) | Domain/UseCases/ConnectionIdentity.swift |
| Token help links (GitHub new-token page, GitLab PAT page by version) | github_connection_dialog.dart, gitlab_connection_dialog.dart (`_openTokenPage`, `_tokenSettingsBase`) | Domain/UseCases/TokenSettingsURL.swift |
| Rename workspace (name / badge letters validation) | features/workspace/domain/usecases/rename_workspace.dart | Domain/UseCases/RenameWorkspace.swift |
| Clear local cache use case | domain/usecases/clear_local_cache.dart | Domain/UseCases/ClearLocalCache.swift |
| Accounts / workspaces persistence + cascade delete | data/local_connection_repository.dart | Data/Repositories/GRDBConnectionRepository.swift |
| Local cache clear (one transaction, tables per section) | data/repositories/drift_local_cache_repository.dart | Data/Repositories/GRDBLocalCacheRepository.swift |
| Workspaces / accounts lookups + account actions (sync, remove, version) + workspace edit / delete + cache clear | core/di/providers.dart (`lookupsProvider`), widgets/account_list.dart, account_row.dart, providers/local_cache_providers.dart | Presentation/Providers/ConnectionsModel.swift |
| Add-connection state (busy / error / done) | connection_controllers.dart (`AddConnectionController`) | Presentation/Providers/AddConnectionModel.swift |
| l10n keys (ARB -> `appString`) | l10n/app_en.arb | Presentation/Providers/ConnectionsL10n.swift |
| Integrations page body + info box | workspace_overview/presentation/pages/integrations_page.dart, widgets/active_workspace_accounts.dart | Presentation/Widgets/IntegrationsContentView.swift |
| Workspace heading + accounts card | widgets/account_list.dart | Presentation/Widgets/WorkspaceAccountsView.swift |
| Account row | widgets/account_row.dart | Presentation/Widgets/AccountRowView.swift |
| Connect dialog (provider picker + 3 forms) | connect_account_dialog.dart, add_connection_dialog.dart, github_/gitlab_connection_dialog.dart | Presentation/Widgets/ConnectAccountDialog.swift |
| Dialog chrome + error note | widgets/connection_dialog_frame.dart | Presentation/Widgets/ConnectionDialogFrame.swift |
| Provider picker (Jira dimmed, "coming soon") | widgets/connection_provider_picker.dart | Presentation/Widgets/ConnectionProviderPicker.swift |
| Labeled text field, "Generate token" link | core/widgets/connection_text_field.dart, widgets/generate_token_link.dart | Presentation/Widgets/ConnectionTextField.swift |
| Workspace picker | widgets/workspace_picker.dart (+ popover) | Presentation/Widgets/WorkspacePicker.swift (AppDropdown) |
| Workspace editor (name, letters, colour, icon file) | widgets/workspace_editor_dialog.dart, workspace_editor_parts.dart | Presentation/Widgets/{WorkspaceEditorDialog,WorkspaceEditorParts}.swift |
| Local cache panel + section rows | widgets/local_cache_panel.dart, local_cache_section_row.dart | Presentation/Widgets/LocalCachePanelView.swift |

## Tests (Tests/FeatureConnectionsTests)

| Dart behaviour | Swift test |
|---|---|
| intHash / slug / ids / initials / colour (vectors computed independently) | ConnectionIdentityTests.swift |
| token help URLs | ConnectionIdentityTests.swift (`TokenSettingsURLTests`) |
| rename_workspace | ConnectionIdentityTests.swift (`RenameWorkspaceTests`) |
| connection_controllers flows (mock registry / credentials / repo / sync) | ConnectAccountTests.swift |
| local_connection_repository, drift_local_cache_repository (in-memory GRDB) | ConnectionDataTests.swift |
| account actions, add-connection states, editor refusals | ConnectionsModelTests.swift (doubles in ModelDoubles.swift) |
| Render smoke (PNG in /tmp/wn-feat-render/connections-*.png) | RenderSmokeTests.swift |

## Not ported / deviations

- ZenTao profile dialogs and the profile refresh after connecting (`zentao_profile_*`, `RefreshZenTaoProfile`): `ZenTaoProfileRepository` is not hoisted into CoreDomain. The root passes `afterAccountAdded` to `ConnectionsFeature` to refresh the profile.
- Create-workspace dialog (`create_workspace_dialog.dart`) and workspace chips / switcher popover: they drive the shell's navigation (`appNavProvider.onWorkspaceSwitched`) and live with the workspace switcher in SharedKit.
- `LocalCacheCard` / `LocalCacheQuickSettings` (settings entry buttons): the settings page hosts `localCachePanel(onCleared:)` itself.
- Sync toast shows the ticket count by reading the store after the sync (the Swift `AccountSyncService.sync` returns `Void`, Dart returned a count).
- GitLab version on the row: `ProviderAdapter.testConnection().serverVersion` through `AccountSyncService.adapter(for:)` (no `GitLabMrService` in CoreDomain).
- `removeAccount` also drops the account's tickets' comments / activity / translations by ticket id (Dart matched comments by project-id prefix).
- Chat tables are cleared by name (`chatMessages`, ...) and skipped when the module's tables are not in the database.
