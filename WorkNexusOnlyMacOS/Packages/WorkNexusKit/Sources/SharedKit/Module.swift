/// Feature-agnostic slices: shell + shell_pane kit, board (kanban / table / filters), detail (slide-over), sync.
///
/// Entry points for tools / features / the composition root:
/// - Board: `BoardController` (+ `BoardView`, `TicketTable`, `BoardToolbar`, `PagedViewsController`, `BuildBoard`…)
/// - Detail: `DetailController` + `.detailOverlay(_:)` / `DetailOverlayHost`, `DetailExtensions` hooks
/// - Sync: `SyncCoordinator` (an `AccountSyncService` and `TicketDetailService`), `TicketStore`, `SourceListCache`
public enum SharedKitModule { public static let name = "SharedKit" }
