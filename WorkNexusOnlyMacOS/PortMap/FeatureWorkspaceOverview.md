# FeatureWorkspaceOverview (lib/features/workspace_overview → Sources/FeatureWorkspaceOverview)

Public entry: `WorkspaceOverviewFeature.make(services:nav:registry:activeWorkspaceId:)` → `OverviewModel` (call `start()` / `stop()`), and `WorkspaceOverviewHost(model:onConnect:accounts:)`, which renders the active `AppNavState.workspaceSection` (`overview` / `integrations` / `members`). The Integrations account list belongs to FeatureConnections, so the shell passes it as the `accounts` slot.
Not ported / changed: the Riverpod providers (replaced by the one `@Observable OverviewModel`), `lucide` icons (SF Symbols), `intl` date formats (`DateFormatter` templates). "Manage integrations" / "Connect a tool" go to `nav.setWorkspaceSection("integrations")` (the Swift shell has no settings integrations section). Plural strings are resolved in `OL` and fall back to English when the xcstrings value is raw ICU. `DashboardWorkPage` measures its width once and hands `both` to the header and the view (Dart measured each with its own `LayoutBuilder`).
The ZenTao dashboard entities / mapper / GRDB repository are hoisted outside this target: `CoreDomain/Entities/ZenTaoDashboard.swift` (`ZenTaoDashboardItemKind` is what `DashboardItemKind` aliases), `CoreDomain/Repositories/ZenTaoFeatureRepositories.swift`, `ToolZenTao/Data/Local/GRDBZenTaoDashboardRepository.swift`; this feature reaches them through `AppServices.zentaoDashboard` / `zentaoTickets`.

| Area | Dart | Swift |
|---|---|---|
| DashboardItemKind (+ `isTicket`, `fromObjectType`) | domain/value_objects/dashboard_item_kind.dart | Domain/ValueObjects/DashboardItemKind.swift |
| AssignedWorkItem, AssignedReason | domain/entities/assigned_work_item.dart | Domain/Entities/AssignedWorkItem.swift |
| ListAssignedWork | domain/usecases/list_assigned_work.dart | Domain/UseCases/ListAssignedWork.swift |
| BuildWorkQueue, FilterMyWork, GroupMyWork | domain/usecases/{build_work_queue,filter_my_work,group_my_work}.dart | Domain/UseCases/{BuildWorkQueue,FilterMyWork,GroupMyWork}.swift |
| RankDashboardExecutions, RefreshDashboard | domain/usecases/{rank_dashboard_executions,refresh_dashboard}.dart | Domain/UseCases/{RankDashboardExecutions,RefreshDashboard}.swift |
| Session-wide assigned-work sync (`myWorkSyncProvider`) | presentation/providers/dashboard_providers.dart | Domain/UseCases/SyncAssignedWork.swift (actor) |
| Open an item in the detail panel | presentation/util/open_dashboard_item.dart | Domain/UseCases/OpenDashboardItem.swift |
| DashboardRepository + ticket resolver | domain/repositories/dashboard_repository.dart | Domain/Repositories/OverviewRepository.swift, Data/Repositories/ServicesOverviewRepository.swift |
| Providers (`assignedWork`, `workspaceAccounts`, `myWorkTarget`, `dashboardWorkOpenOnly`, refresh/sync state) | presentation/providers/{overview,dashboard}_providers.dart | Presentation/Providers/OverviewModel.swift (`FetchState`, `MyWorkTarget`) |
| `shortWhen`, status labels / colours, layout constants | presentation/util/{short_when,my_work_status,dashboard_status_color}.dart | Presentation/Support/OverviewFormat.swift |
| l10n keys | lib/l10n/app_en.arb | Presentation/Support/OverviewStrings.swift (`OL`) |
| Overview / Integrations / Members / full-lists pages | presentation/pages/*.dart | Presentation/Pages/{OverviewPage,IntegrationsPage,MembersPage,DashboardWorkPage,WorkspaceOverviewHost}.swift |
| AppPage frame | lib/core/widgets/app_page.dart | Presentation/Widgets/PageFrame.swift |
| Tool card, grid, parts, metrics | widgets/{tool_card,tool_card_parts,tool_card_metrics}.dart | Presentation/Widgets/{ToolCard,ToolCardParts,ToolCardMetrics}.swift |
| Dashboard card / grid / row / queue | widgets/{dashboard_card,dashboard_grid,dashboard_row,dashboard_queue}.dart | Presentation/Widgets/{DashboardCard,DashboardRow,DashboardQueue,CardSurface}.swift |
| Executions / activity / todos cards and lists | widgets/{dashboard_snapshot_cards,dashboard_execution_list,dashboard_activity_list,dashboard_work_list}.dart | Presentation/Widgets/{DashboardSnapshotCards,DashboardExecutionList,DashboardActivityList,DashboardWorkList}.swift |
| Sync status + refresh, ZenTao section, dashboard body | widgets/{dashboard_sync_status,zentao_overview_section,dashboard_body}.dart | Presentation/Widgets/{DashboardSyncStatus,ZenTaoOverviewSection,DashboardBody}.swift |
| Assigned work list / row | widgets/{assigned_work_list,assigned_work_row}.dart | Presentation/Widgets/{AssignedWorkList,AssignedWorkRow}.swift |
| My-work row + meta facts | widgets/{my_work_row,my_work_meta}.dart | Presentation/Widgets/{MyWorkRow,MyWorkMeta}.swift |
| Full lists: view / column / header | widgets/{dashboard_work_view,dashboard_work_column,dashboard_work_header}.dart | Presentation/Widgets/{DashboardWorkView,DashboardWorkColumn,DashboardWorkHeader}.swift |
| Tests | test/domain/{list_assigned_work,refresh_dashboard,build_work_queue,filter_my_work,group_my_work,rank_dashboard_executions}_test.dart, test/widget/workspace_overview_test.dart | Tests/FeatureWorkspaceOverviewTests/{OverviewDomainTests,OverviewModelTests,OverviewPresentationTests,RenderSmokeTests}.swift (PNGs: /tmp/wn-feat-render/overview-*.png) |
