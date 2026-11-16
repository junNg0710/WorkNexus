# ToolGitLab — Presentation layer (Dart → Swift)

Dart under `lib/tools/gitlab/`, Swift under `Packages/WorkNexusKit/Sources/ToolGitLab/Presentation/`.
Entry point: `GitlabModule(services:nav:registry:mrService:)` (`: ToolModule`). The composition root builds the shared `ToolRegistry`, `ShellModel(services:registry:)`, then `GitlabModule(services:, nav: shell.nav, registry:, mrService: GitLabMrServiceImpl(...))` and `registry.register(module)`.

| Area | Dart | Swift |
|---|---|---|
| Module (sections, nav pane, section, webUrl, scopeTickets, scopeTitle) | gitlab_module.dart | GitlabModule.swift (+ `GitlabSections`) |
| Detail hooks + metrics | gitlab_module.dart (`buildDetail/Actions/DetailSidebar`, `metrics`), providers/gitlab_metrics_providers.dart | GitlabModule+Hooks.swift |
| Scope helpers, MR chips, state tabs, web URL | providers/gitlab_scope.dart, sections/gitlab_mrs_section.dart | Providers/GitlabScope.swift |
| UI state (selected project, slice sync, groups collapsed, chip, pins, view modes) | providers/gitlab_board_providers.dart, util/watch_gitlab_items.dart | Providers/GitlabContext.swift |
| Project list (cached then fresh), grouping, open counts | gitlab_board_providers.dart (`gitlabProjectsProvider`), nav/gitlab_projects_scope_list.dart | Providers/GitlabProjectsModel.swift |
| Board data (MR / issue boards), sort | gitlab_board_providers.dart, sections | Providers/GitlabSectionModel.swift |
| Use-case providers, toasts, confirmations | providers/gitlab_detail_providers.dart, detail/gitlab_mr_detail.dart `_run` | Providers/GitlabActionRunner.swift |
| MR phase / need-rebase / state pill / `humanizeMergeState` | util/gitlab_mr_phase.dart, core/widgets/merge_request_state_pill.dart | Providers/GitlabMrState.swift |
| `templateRuns` | util/template_runs.dart | Providers/TemplateRuns.swift |
| Nav pane, scope list, group tree, project row | nav/*.dart, widgets/gitlab_project_row.dart | Nav/GitlabNavPane, GitlabProjectsScopeList, GitlabGroupNodeView |
| MR / Issues sections | sections/gitlab_{mrs,issues}_section.dart | Sections/GitlabItemsSection.swift |
| MR table / issue rows → shared table | widgets/gitlab_mr_table*.dart, `_IssueRow` | Sections/GitlabItemTable.swift |
| Board + card (card = shared `TicketCard`) | widgets/gitlab_board_view.dart, gitlab_ticket_card.dart | Sections/GitlabBoardView.swift |
| Pipelines placeholder | core/widgets/coming_soon_view.dart | CoreUI `ComingSoonView` |
| MR detail wiring (+ confirmations for merge / rebase / close) | detail/gitlab_mr_detail.dart, gitlab_mr_commands.dart | Detail/GitlabMrDetail.swift, Providers/GitlabMrDetailModel.swift |
| Overview / header / breadcrumb / "⋮" menu | detail/gitlab_mr_{overview,header,breadcrumb,more_button}.dart | Detail/GitlabMr{Overview,Header,Breadcrumb,MoreButton}.swift |
| Merge / approval / outcome panels, widget card, async button | detail/gitlab_mr_{merge,approval,outcome}_panel.dart, mr_widget_card.dart, mr_async_button.dart | Detail/GitlabMr{MergePanel,ApprovalPanel,OutcomePanel,WidgetCard}.swift |
| Sidebar + labels / milestone / time-tracking editors | detail/gitlab_mr_sidebar.dart, milestone_editor.dart, time_tracking_editor.dart, shared labels_editor.dart | Detail/GitlabMrSidebar, GitlabLabelsEditor, GitlabMilestoneEditor, GitlabTimeTrackingEditor |
| Issue / MR metadata card, header actions, Assign / Reviewers dialogs | detail/gitlab_detail_sections.dart, gitlab_ticket_actions.dart, shared assign / reviewers dialogs | Detail/GitlabDetailSections, GitlabTicketActions, GitlabAssignDialog |
| Shared Dart widgets not in SharedKit | detail_sidebar_section, metadata_editor_parts, user_picker_editor, detail_panel_header_actions, detail_back_button, item_description, `DetailMetaCard` | Parts/*.swift |
| Tests | test/features/task_detail/gitlab_mr_phase_test.dart, test/widget/gitlab_default_kind_test.dart, gitlab_shell_test.dart (filters), gitlab_mr_detail_test.dart (actions) | Tests/ToolGitLabTests/Presentation{Logic,Context,Render}Tests.swift (+ PresentationFakes.swift) |

## Not ported
`widgets/gitlab_tabs.dart` (kind tab strip of the old `BoardPage`; sections carry the kind), `gitlab_board_refresh_button.dart` (SharedKit `BoardRefreshButton`), `widgets/gitlab_pinned_branch.dart`, `gitlab_projects_branch.dart`, `gitlab_project_row.dart` (workspace sources-tree branches, not part of this target). Widget tests that drive Flutter gestures (merge options checkbox, Rebase spinner, tab keep-alive) are covered at the logic level plus renders.

## Deviations
- The shell passes no nav / services to `ToolModule` methods, so the module owns a `GitlabContext` (nav, services, MR service, UI state); views read `nav.location(for:)` themselves.
- Lists use the shared `TicketTable` (sortable, resizable) instead of hand-rolled rows; boards use shared `TicketCard`.
- The "Assigned to me" quick scope and the MR chips also narrow the board, not only the list. MR boards use the `.gitlabMergeRequest` facet filters; issues none.
- Merge, rebase and close ask for confirmation (`AppConfirmDialog`); the merge dialog repeats the chosen squash / delete-branch options.
- Merge / approve buttons show a spinner keyed on `GitlabMrAction.Kind` (the Dart commands returned futures); the pending confirmation does not spin.
- Merged pill / band colour is `violet` (palette has no `info`).
- `cachedProjects` is reached through `services.sync as? SyncCoordinator` (the `GitLabMrService` protocol has none).
- Time-tracking section uses a "+" icon trigger like Dart; the popover editors use SwiftUI popovers.
- New l10n keys (English fallbacks in code): gitlabColMr, gitlabNoMergeRequests, gitlabNoIssues, gitlabConfirm{Merge,Rebase,Close}{Title,Body}, gitlabConfirmSquash, gitlabConfirmRemoveBranch, commitsBehindTarget{One,Other}, approvalsLeft{One,Other}, reviewerSingular (the .arb ones are ICU plurals).
