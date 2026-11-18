# ToolGitLab — Dart → Swift (Data + Domain layers; Presentation comes in a later pass)

Paths: Dart under `lib/`, Swift under `Packages/WorkNexusKit/Sources/ToolGitLab/`.

| Area | Dart | Swift |
|---|---|---|
| HTTP client (REST v4, PRIVATE-TOKEN same-host only, self-signed except gitlab.com, `X-Next-Page` paging) | lib/tools/gitlab/data/datasources/gitlab_client.dart | Data/Datasources/GitLabClient.swift |
| Client mutations (issue/MR update, time estimate/spent, merge, approve, rebase, compare) | lib/tools/gitlab/data/datasources/gitlab_client.dart | Data/Datasources/GitLabClient+Mutations.swift |
| Client assets (`/uploads` → Markdown uploads API) | lib/tools/gitlab/data/datasources/gitlab_client.dart | Data/Datasources/GitLabClient+Assets.swift |
| Transport (dio options, badCertificateCallback, interceptors) | lib/tools/gitlab/data/datasources/gitlab_client.dart | Data/Datasources/GitLabHTTPTransport.swift |
| DTOs (User, Label, Project, Issue, MR, Approvals, Milestone, TimeStats, References, Note) | lib/tools/gitlab/data/models/gitlab_models.dart | Data/Models/GitLabModels.swift |
| Normalizers + status/priority mapping + `contentHash` | lib/tools/gitlab/data/mappers/gitlab_normalize.dart, lib/core/util/content_hash.dart | Data/Mappers/GitLabNormalize.swift |
| Draft-title helpers | lib/tools/gitlab/data/mappers/gitlab_draft_title.dart | Data/Mappers/GitLabDraftTitle.swift |
| ProviderAdapter | lib/tools/gitlab/data/repositories/gitlab_adapter.dart | Data/Repositories/GitLabProviderAdapter.swift |
| GitLab MR adapter operations | lib/tools/gitlab/data/repositories/gitlab_adapter.dart | Data/Repositories/GitLabProviderAdapter+MergeRequests.swift |
| Optimistic MR/issue service | lib/tools/gitlab/data/services/gitlab_mr_service_impl.dart | Data/Services/GitLabMrServiceImpl.swift |
| Adapter factory (account + secret → adapter) | lib/app/di/provider_adapter_registry_impl.dart | Data/GitLabAdapterFactory.swift |
| GitLabMrAdapter interface | lib/core/domain/adapters/gitlab_mr_adapter.dart | Domain/Repositories/GitLabMrAdapter.swift |
| GitLabMrService interface | lib/core/domain/adapters/gitlab_mr_service.dart | Domain/Services/GitLabMrService.swift |
| RepoCommit / RepoFileChange / countDiffLines | lib/core/domain/value_objects/repo_change.dart | Domain/Entities/RepoChange.swift |
| Project tree | lib/tools/gitlab/domain/entities/gitlab_project_tree.dart | Domain/Entities/GitLabProjectTree.swift |
| Item kind | lib/tools/gitlab/domain/value_objects/gitlab_item_kind.dart | Domain/ValueObjects/GitLabItemKind.swift |
| Board columns | lib/tools/gitlab/domain/value_objects/gitlab_{issue,mr}_column.dart | Domain/ValueObjects/GitLabColumns.swift |
| Priority label detector, synthetic board labels | lib/core/util/priority_labels.dart, lib/core/util/synthetic_labels.dart | Domain/ValueObjects/GitLabLabels.swift |
| MR / issue board builders | lib/tools/gitlab/domain/usecases/build_gitlab_{mr,issue}_board.dart | Domain/UseCases/GitLabBoards.swift |
| MR action use cases | lib/tools/gitlab/domain/usecases/{approve,unapprove,close,reopen,merge,rebase,set_draft}_gitlab_mr.dart, post_gitlab_mr_comment.dart | Domain/UseCases/GitLabMrUseCases.swift |
| Metrics | lib/tools/gitlab/domain/usecases/compute_gitlab_metrics.dart | Domain/UseCases/ComputeGitLabMetrics.swift |
| Tests: client / paging / current user | test/data/gitlab_client_test.dart, gitlab_client_current_user_test.dart | Tests/ToolGitLabTests/GitLabClientTests.swift |
| Tests: adapter | test/data/gitlab_adapter_test.dart | Tests/ToolGitLabTests/GitLabAdapterTests.swift |
| Tests: notes sharing | test/data/gitlab_adapter_notes_test.dart | Tests/ToolGitLabTests/GitLabAdapterNotesTests.swift |
| Tests: normalize / label colours / draft title | test/data/gitlab_normalize_test.dart, gitlab_label_color_test.dart, gitlab_draft_title_test.dart | Tests/ToolGitLabTests/GitLabNormalizeTests.swift |
| Tests: boards / use cases / project tree / metrics | test/domain/gitlab_board_test.dart, gitlab_mr_usecases_test.dart, test/unit/gitlab_*_test.dart | Tests/ToolGitLabTests/GitLabDomainTests.swift |
| Tests: service (optimistic + rollback) | (contract of `_gitlabAction`) | Tests/ToolGitLabTests/GitLabMrServiceTests.swift |

## Not ported here (Presentation pass)
`lib/tools/gitlab/gitlab_module.dart` and everything under `lib/tools/gitlab/presentation/` (nav pane, sections, board view, MR detail, ticket actions, providers). Widget tests (`test/widget/gitlab_*`, `test/features/task_detail/gitlab_mr_phase_test.dart`) belong with that pass.

## Deviations
- Board builders and metrics take pre-filtered tickets / return plain counts (no `BoardQuery`/`FilterTickets`/`ToolMetrics` dependency from the domain layer). The card order (Dart `q.sort`) is the builder's `sort:` (the section model passes `AppNavController.boardSort`), compared by CoreDomain's `CompareTickets.board`.
- Typed DTOs (`GitLabCommitRow`, `GitLabDiffRow`) replace the Dart client's raw `Map` rows.
- `GitLabMrServiceImpl` talks to `TicketRepository` / `TicketDetailService` / `SyncStatusRepository` (CoreDomain) instead of `SyncCoordinator`; it has no image/project caches (those stay with the sync layer).
- `RepoCommit`/`RepoFileChange` live in this target (and, identically, in ToolGitHub) until hoisted into `CoreDomain`.
