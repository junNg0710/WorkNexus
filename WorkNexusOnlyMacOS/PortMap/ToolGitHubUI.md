# ToolGitHub — Presentation layer (Dart → Swift)

Dart under `lib/tools/github/`, Swift under `Packages/WorkNexusKit/Sources/ToolGitHub/Presentation/`.
Entry point: `GithubModule(services:nav:registry:prService:)` (`: ToolModule`). The composition root builds the shared `ToolRegistry`, `ShellModel(services:registry:)`, then `GithubModule(services:, nav: shell.nav, registry:, prService: GitHubPrServiceImpl(...))` and `registry.register(module)`.

| Area | Dart | Swift |
|---|---|---|
| Module (sections, nav pane, section, metrics, webUrl, detail hooks, scopeTickets) | github_module.dart | GithubModule.swift (+ `GithubSections`, `githubWebURL`) |
| Scope helpers (`scopeGitHubTickets`, review-requested, PR state tabs) | presentation/providers/github_scope.dart, sections/github_pulls_section.dart | Providers/GithubScope.swift |
| UI state (selected repo, slice sync, pins, view modes) | providers/github_board_providers.dart (`selectedGitHubRepoProvider`, `githubItemsSliceProvider`, `githubKindProvider`), util/watch_github_items.dart | Providers/GithubContext.swift |
| Repo list (cached then fresh), grouping, open counts | github_board_providers.dart (`githubReposProvider`), nav/github_repos_scope_list.dart | Providers/GithubReposModel.swift |
| Board data (PR / issue boards) | github_board_providers.dart (`githubPrBoardProvider`, `githubIssueBoardProvider`) | Providers/GithubSectionModel.swift |
| Use-case providers, action snackbars | providers/github_detail_providers.dart, detail/*_detail.dart `_run` | Providers/GithubActionRunner.swift |
| Metrics | providers/github_metrics_providers.dart | `GithubModule.metrics` |
| Nav pane + repo scope list + repo row | nav/github_nav_pane.dart, nav/github_repos_scope_list.dart, widgets/github_repo_row.dart | Nav/GithubNavPane.swift, Nav/GithubReposScopeList.swift |
| PR / Issues sections | sections/github_{pulls,issues}_section.dart | Sections/GithubItemsSection.swift |
| List rows → shared table | widgets/github_pr_row.dart, `_IssueRow` | Sections/GithubItemTable.swift |
| Board | widgets/github_board_view.dart | Sections/GithubBoardView.swift |
| Actions placeholder | core/widgets/coming_soon_view.dart | CoreUI `ComingSoonView` |
| PR detail wiring (+ confirmations) | detail/github_pr_detail.dart | Detail/GithubPrDetail.swift, Providers/GithubPrDetailModel.swift |
| PR overview / header / merge panel / sidebar | detail/github_pr_{overview,header,merge_panel,sidebar}.dart | Detail/GithubPr{Overview,Header,MergePanel,Sidebar}.swift |
| Issue / PR metadata card | detail/github_detail_sections.dart | Detail/GithubDetailSections.swift |
| Header actions + Assign / Reviewers dialogs | detail/github_ticket_actions.dart, shared assign_dialog / reviewers_dialog | Detail/GithubTicketActions.swift, Detail/GithubAssignDialog.swift |
| Shared Dart widgets not in SharedKit | detail_sidebar_section, metadata_editor_parts, user_picker_editor, detail_panel_header_actions, detail_back_button, item_description, provider_detail_sections (`DetailMetaCard`, `humanizeMergeState`), merge_request_state_pill | Parts/*.swift, Providers/GithubPrState.swift |
| Tests | test/unit/repo_board_scope_test.dart (GitHub), test/widget/github_shell_test.dart, test/widget/github_pr_detail_test.dart | Tests/ToolGitHubTests/Presentation{Logic,Context,Render}Tests.swift (+ PresentationFakes.swift) |

## Not ported
- `widgets/github_tabs.dart` (kind tab strip of the old `BoardPage`; the sections carry the kind), `widgets/github_board_refresh_button.dart` (SharedKit `BoardRefreshButton` is used), `nav/github_pinned_branch.dart`, `nav/github_repos_branch.dart` (workspace sources-tree branches; the shell's tree is not part of this target).

## Deviations
- Section labels / view-mode labels are resolved with `appString(arbKey, English)` at call time (not raw keys).
- `Review requested` lives in `GithubContext` (Swift `QuickScope` has no such case); it filters board and list (Dart: list only).
- List views use SharedKit `TicketTable` (sortable, resizable) instead of hand-rolled rows; issues list too.
- Merge / Close / Update branch ask for confirmation (`AppConfirmDialog`); the Dart app ran them at once. Header-action dialogs use `.sheet`; the PR detail uses the in-panel `appDialog`.
- Copy-link button toasts "Copied!" instead of flashing a check mark. Merged-state colour is `violet` (the palette has no `info`).
- `ctx.kind` global is replaced by the section on screen passing its kind to `syncSlice(kind:)`.
- `RepoCommit` / `RepoFileChange` are converted to SharedKit's types for `CommitsSection` / `ChangedFilesSection`.

## New l10n keys (add to Localizable.xcstrings / .arb)
`githubNoPullRequests`, `githubNoIssues`, `githubColPr`, `githubColIssue`, `githubConfirmMergeTitle`, `githubConfirmMergeBody`, `githubConfirmCloseTitle`, `githubConfirmCloseBody`, `githubConfirmUpdateTitle`, `githubConfirmUpdateBody`, `title` (table column header, "Title").
