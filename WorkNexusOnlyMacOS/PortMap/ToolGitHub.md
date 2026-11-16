# ToolGitHub — Dart → Swift (Data + Domain layers; Presentation comes in a later pass)

Paths: Dart under `lib/`, Swift under `Packages/WorkNexusKit/Sources/ToolGitHub/`.

| Area | Dart | Swift |
|---|---|---|
| HTTP client (api.github.com / GHES `/api/v3`, Bearer + API-version headers, Link paging, Search) | lib/tools/github/data/datasources/github_client.dart | Data/Datasources/GitHubClient.swift |
| Transport (dio options, badCertificateCallback — Enterprise only, interceptors) | lib/tools/github/data/datasources/github_client.dart | Data/Datasources/GitHubHTTPTransport.swift |
| DTOs (User, Repo, Label, PullMarker, Issue, Ref, Pull, Comment, Event) | lib/tools/github/data/models/github_models.dart | Data/Models/GitHubModels.swift |
| Normalizers + status/priority mapping + `repoFromUrl` + `contentHash` | lib/tools/github/data/mappers/github_normalize.dart, lib/core/util/content_hash.dart | Data/Mappers/GitHubNormalize.swift |
| ProviderAdapter | lib/tools/github/data/repositories/github_adapter.dart | Data/Repositories/GitHubProviderAdapter.swift |
| GitHub PR adapter operations | lib/tools/github/data/repositories/github_adapter.dart | Data/Repositories/GitHubProviderAdapter+PullRequests.swift |
| Optimistic PR/issue service | lib/tools/github/data/services/github_pr_service_impl.dart | Data/Services/GitHubPrServiceImpl.swift |
| Adapter factory (account + secret → adapter) | lib/app/di/provider_adapter_registry_impl.dart | Data/GitHubAdapterFactory.swift |
| GitHubPrAdapter interface | lib/core/domain/adapters/github_pr_adapter.dart | Domain/Repositories/GitHubPrAdapter.swift |
| GitHubPrService interface | lib/core/domain/adapters/github_pr_service.dart | Domain/Services/GitHubPrService.swift |
| RepoCommit / RepoFileChange / countDiffLines | lib/core/domain/value_objects/repo_change.dart | Domain/Entities/RepoChange.swift |
| Item kind | lib/tools/github/domain/value_objects/github_item_kind.dart | Domain/ValueObjects/GitHubItemKind.swift |
| Board columns | lib/tools/github/domain/value_objects/github_{issue,pr}_column.dart | Domain/ValueObjects/GitHubColumns.swift |
| Priority label detector, synthetic board labels | lib/core/util/priority_labels.dart, lib/core/util/synthetic_labels.dart | Domain/ValueObjects/GitHubLabels.swift |
| PR / issue board builders | lib/tools/github/domain/usecases/build_github_{pr,issue}_board.dart | Domain/UseCases/GitHubBoards.swift |
| PR action use cases | lib/tools/github/domain/usecases/{close,reopen,merge,update_branch}_github_*.dart, post_github_comment.dart | Domain/UseCases/GitHubPrUseCases.swift |
| Metrics | lib/tools/github/domain/usecases/compute_github_metrics.dart | Domain/UseCases/ComputeGitHubMetrics.swift |
| Tests: client / paging / auth | test/data/github_client_test.dart | Tests/ToolGitHubTests/GitHubClientTests.swift |
| Tests: adapter | test/data/github_adapter_test.dart | Tests/ToolGitHubTests/GitHubAdapterTests.swift |
| Tests: normalize | test/data/github_normalize_test.dart | Tests/ToolGitHubTests/GitHubNormalizeTests.swift |
| Tests: boards / use cases / metrics | test/domain/github_board_test.dart, github_pr_usecases_test.dart, test/unit/github_usecases_test.dart | Tests/ToolGitHubTests/GitHubDomainTests.swift |
| Tests: service (optimistic + rollback) | (contract of `_githubAction`) | Tests/ToolGitHubTests/GitHubPrServiceTests.swift |

## Not ported here (Presentation pass)
`lib/tools/github/github_module.dart` and everything under `lib/tools/github/presentation/` (nav pane, sections, board view, PR detail, ticket actions, providers). Widget tests (`test/widget/github_*`) belong with that pass.

## Deviations
- Board builders and metrics take pre-filtered tickets / return plain counts (no `BoardQuery`/`FilterTickets`/`ToolMetrics` dependency from the domain layer).
- Typed DTOs (`GitHubCommitRow`, `GitHubFileRow`) replace the Dart client's raw `Map` rows.
- GHES base URL keeps a custom port (`http://ghe:8443` → `…:8443/api/v3`); the Dart client dropped it.
- `GitHubPrServiceImpl` talks to `TicketRepository` / `TicketDetailService` / `SyncStatusRepository` (CoreDomain) instead of `SyncCoordinator`; no image/project caches (those stay with the sync layer).
- `RepoCommit`/`RepoFileChange` live in this target (and, identically, in ToolGitLab) until hoisted into `CoreDomain`.
