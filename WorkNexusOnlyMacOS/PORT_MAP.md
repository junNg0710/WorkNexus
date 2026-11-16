# Port map (Dart → Swift). Cột 2 là file Dart, cột 3 là file Swift; `upstream-diff.sh` grep file này.

| Area | Dart | Swift |
|---|---|---|
| Failure/Result | lib/core/error/failure.dart | CoreDomain/Error/Failure.swift |
| Result | lib/core/error/result.dart | CoreDomain/Error/Outcome.swift |
| Ticket | lib/core/domain/entities/ticket.dart | CoreDomain/Entities/Ticket.swift |
| Account | lib/core/domain/entities/account.dart | CoreDomain/Entities/Account.swift |
| Workspace/Project | lib/core/domain/entities/workspace.dart | CoreDomain/Entities/Workspace.swift |
| Comment/Activity | lib/core/domain/entities/comment.dart | CoreDomain/Entities/Comment.swift |
| ProviderEntity | lib/core/domain/entities/provider_entity.dart | CoreDomain/Entities/TicketProviderEntity.swift |
| ProviderAdapter | lib/core/domain/adapters/provider_adapter.dart | CoreDomain/Adapters/ProviderAdapter.swift |
| Repositories | lib/core/domain/repositories/ticket_repository.dart | CoreDomain/Repositories/Repositories.swift |
| Settings | lib/core/settings/app_settings.dart | CoreDomain/Entities/AppSettings.swift |
| Database | lib/core/database/database.dart | CorePersistence/Database/{AppDatabase,CoreMigrations,Records}.swift |
| Credential store | lib/core/platform/credential_store.dart | CorePersistence/Keychain/KeychainCredentialStore.swift |
| Palette | lib/core/theme/app_palette.dart | CoreUI/Theme/AppPalette.swift |
| Tokens | lib/core/theme/app_theme.dart | CoreUI/Theme/AppTheme.swift |
| ToolModule | lib/core/tools/tool_module.dart | CoreTools/Registry/ToolModule.swift |
| Nav state | lib/core/navigation/app_nav_state.dart | CoreTools/Navigation/AppNavState.swift |
| Nav controller | lib/core/navigation/app_nav_controller.dart | CoreTools/Navigation/AppNavController.swift |
| App shell | lib/app/shell/app_shell.dart | SharedKit/Presentation/Shell/AppShell.swift |
| DI root | lib/app/di/service_locator.dart | App/Sources/CompositionRoot.swift |
