# Port map - ToolZenTao Presentation (`Sources/ToolZenTao/Presentation/`)

Public entry: `ZentaoModule(ZentaoDependencies)` (see the doc comment in `Presentation/ZentaoModule.swift`); `ZentaoDependencies(wiring:workflow:services:nav:registry:)`
builds the dependencies from `ZentaoModuleData.wire(...)`. Session state: `State/ZentaoUIState` (selection, boards, paged streams, loaders).

## Core, state and boards (`Presentation/{ZentaoModule,State,Support,Boards,Widgets}`)

| Dart (`lib/tools/zentao/`) | Swift |
|---|---|
| zentao_module.dart | ZentaoModule.swift |
| presentation/providers/zentao_board_providers.dart (selection, tabs, source lists), bug/task_module_names_provider, zentao_facet_catalog_provider (members) | State/{ZentaoSelection,ZentaoUIState,ZentaoUIState+Loaders}.swift |
| presentation/providers/zentao_{bug,task}_streams.dart | State/ZentaoUIState+Streams.swift (over SharedKit `PagedViewsController`) |
| presentation/providers/zentao_scope_providers.dart, zentao_scope_title_provider.dart, util/{keep_bug_board_product,keep_task_board_scope,open_execution_board,select_bug_board_product}.dart | State/ZentaoUIState+Scope.swift, ZentaoUIState.swift (`openProduct`, `openExecution`) |
| domain/usecases/{build_zentao_bug_board,build_zentao_task_board,build_zentao_facet_catalog,compute_zentao_metrics}.dart | Support/ZentaoBoardBuilders.swift (pure; kept in Presentation because Domain was out of scope) |
| presentation/providers/{zentao_table_providers,zentao_table_sort,zentao_module_tree_provider (shown count)}.dart | Boards/ZentaoBoards.swift, State (`bugSort`, `taskSort`, `refreshFetchSorts`) |
| presentation/sections/zentao_{bugs,tasks}_section.dart | Boards/{ZentaoBugsSection,ZentaoTasksSection,ZentaoSectionMode}.swift |
| widgets/zentao_{bug,task}_section_header.dart | Boards/ZentaoSectionHeader.swift |
| widgets/zentao_board_toolbar.dart, zentao_board_refresh_button.dart, zentao_active_filter_bar.dart | Boards/ZentaoBoardToolbar.swift |
| widgets/zentao_bug_board_view.dart, zentao_bug_column_card.dart (drop rules / handlers) | Boards/{ZentaoBugBoardView,ZentaoBugDrops}.swift |
| widgets/zentao_task_board_view.dart | Boards/ZentaoTaskBoardView.swift |
| widgets/zentao_board_card.dart | Boards/ZentaoBoardCard.swift |
| widgets/zentao_{bug,task}_column_parts.dart, zentao_status_filter_option.dart | Boards/ZentaoColumnVisuals.swift |
| widgets/zentao_bug_column_footer.dart, zentao_task_column_parts.dart (footer) | Boards/ZentaoColumnFooters.swift |
| widgets/zentao_{bug,task}_table_view.dart, zentao_bug_row.dart, zentao_task_row*.dart, zentao_task_table_*.dart, zentao_sortable_header_cell.dart, zentao_*_sort_menu_button.dart | Boards/{ZentaoTableViews,ZentaoTableColumns}.swift (SharedKit `TicketTable`: sortable / resizable headers replace the Dart row widgets and sort menus) |
| widgets/zentao_formatters.dart, zentao_status_pill.dart, zentao_priority_badge.dart | Widgets/Shared/{ZentaoFormatters,ZentaoBadges}.swift |

Celebration after resolving a bug as Fixed (by drop or from the Resolve dialog): `Support/ZentaoCelebrate.swift` (`\.zentaoCelebrate`, see the second pass below). Not ported: `zentao_task_manager_*` (unused in Dart), `zentao_card_parent` in the cards is the detail fork's `ZentaoCardParentLine`.

## Nav (`Presentation/Nav/`)

| Dart (`lib/tools/zentao/presentation/`) | Swift (`Packages/WorkNexusKit/Sources/ToolZenTao/Presentation/Nav/`) |
|---|---|
| nav/zentao_nav_pane.dart | ZentaoNavPane.swift (`ZentaoNavPane`, `ZentaoNavBody`) |
| nav/zentao_account_switcher.dart | ZentaoAccountSwitcher.swift |
| nav/zentao_bug_module_pane.dart | ZentaoBugModulePane.swift |
| nav/zentao_task_module_pane.dart | ZentaoTaskModulePane.swift |
| nav/zentao_module_tree_section.dart (+ `ZenTaoHideEmptyModulesToggle`) | ZentaoModuleTreeSection.swift |
| nav/zentao_scope_picker_row.dart | ZentaoScopePickerRow.swift |
| widgets/zentao_product_popover.dart, zentao_product_popover_list.dart, zentao_popover_product_node.dart | ZentaoProductPopover.swift (`ZentaoProductPopover`, `ZentaoProductPopoverList`, `ZentaoProductNode`) |
| widgets/zentao_execution_popover.dart, zentao_execution_list.dart | ZentaoExecutionPopover.swift (`ZentaoExecutionPopover`, `ZentaoExecutionList`) |
| widgets/zentao_popover_tree_node.dart | ZentaoProjectNode.swift (project folder, its executions, execution row) |
| widgets/zentao_popover_tab_button.dart + the popovers' shared search / Mine-Others card | ZentaoPickerShell.swift (`ZentaoPickerShell`, `ZentaoPopoverTabButton`, `ZentaoKindTag`, `ZentaoPickerEmpty`) |
| widgets/zentao_execution_switcher.dart (unused in Flutter outside its own file) | ZentaoExecutionSwitcher.swift (public) + ZentaoSwitcherButton.swift (the shared breadcrumb button) |
| the Bugs header's product picker (no switcher widget in Flutter; same breadcrumb as the execution one) | ZentaoProductSwitcher.swift (public) |
| providers/zentao_module_tree_provider.dart, the pane / list decisions, `zentaoTaskInProject` | ZentaoNavLogic.swift (pure functions, tested without a view) |
| `AppSettings.togglePinnedProject` / `togglePinnedExecution` | ZentaoNavActions.swift (`ZentaoUIState.togglePinnedProduct` / `togglePinnedExecution`) |
| nav/zentao_pinned_branch.dart, zentao_projects_branch.dart, zentao_executions_branch.dart, widgets/zentao_module_filter_sidebar.dart, zentao_execution_row.dart, zentao_project_row.dart | not ported: nothing in the nav pane references them (the pane is the rail's Tasks / Bugs place panes); only each other and `zentao_task_manager_table_view.dart` (Boards) use some of the rows. |
| nav/zentao_doc_*.dart | not part of Nav here: the Docs pane is `ZentaoDocLibsPane` (Docs port). |

Public entry points: `ZentaoNavPane` (built by `ZentaoModule.buildNavPane`), `ZentaoExecutionSwitcher(state:account:)` (account optional: the rail's is
used) and `ZentaoProductSwitcher(state:account:)` for the section headers.

### Differences from Flutter
- **Pins.** `AppSettings.pinnedExecutions` holds `accountId:executionId` keys only (Flutter's `PinnedExecution` also carried name + project). The Tasks pane
  therefore resolves pinned rows against the executions loaded so far: with at least one pin it loads the account's projects and every project's
  executions (same as `keepTaskBoardScope`). A pin whose execution no longer exists is not listed, and cannot be unpinned from the pane.
- **Picker `Mine` with no account.** Flutter's execution list treated every project as "Others" when the switcher had no `account`; here the rail's account
  (from the board's account stream) is used, so Mine works there too.
- **Module names** are loaded by the module tree section (`.task(id: moduleScopeKey)`): the Swift loader is explicit where Flutter's provider loaded on watch.
- **Popovers** are native `.popover` (arrow below the row / button) instead of `MenuAnchor`; the card chrome comes from the popover, so no `AppPopupCard`.

### New l10n keys (English fallback in code; add to `Localizable.xcstrings` / arb)
`zentaoPickerMine` "Mine", `zentaoPickerOthers` "Others", `zentaoNoProductsFound` "No products found", `zentaoNoProjectsFound` "No projects found",
`zentaoSearchProject` "Search project…", `zentaoSelectProject` "Select Project", `zentaoSelectProduct` "Select Product".
(Reused existing keys: `zentaoProductsGroup`, `zentaoOtherProducts`, `executions`, `zentaoOtherExecutions`, `zentaoModulesGroup`, `zentaoAllModules`,
`zentaoNoModules`, `zentaoModulesUnavailable`, `zentaoShowEmptyModules`, `zentaoHideEmptyModules`, `filterProducts`, `project`, `fieldProduct`,
`noExecutions`, `executionsUnavailable`.)

### Tests
`Tests/ToolZenTaoTests/PresentationNavTests.swift`: 19 tests (pin toggling and keys, pane row order, module tree counts / hide-empty, picker
Mine / Others / search / sort, account filter) plus off-screen renders of the picker, project nodes and switcher button (`/tmp/wn-zt-nav-render/*.png`).
Not covered: the full `ZentaoNavPane` (needs a `ZentaoUIState`, i.e. fakes for all `ZentaoDependencies` services).

## Detail (Presentation/Detail)

| Area | Dart (lib/tools/zentao/presentation) | Swift (ToolZenTao/Presentation/Detail) |
|---|---|---|
| Detail hooks of the module (status strip, effort, subtasks, attachments, sidebar, header extras, actions) | zentao_module.dart (build* overrides) | ZentaoDetailHooks.swift |
| Action bar (Assign, primary, "⋯", Clone task) + dialog host | detail/zentao_ticket_actions.dart, shared/detail/.../detail_action_button.dart | Actions/ZentaoTicketActions.swift (`ZentaoTicketActions`, `ZentaoActionsModel`) |
| Action looks, editor routes | detail/zentao_action_looks.dart, zentao_ticket_actions.dart (`_editorRoute`) | Support/ZentaoActionLooks.swift (`ZentaoActionLooks`, `zentaoEditorRoute`) |
| Dialog chrome, note field, assignee picker | shared/detail/.../{action_dialog_scaffold,ticket_note_field}.dart | Actions/ZentaoActionFrame.swift |
| Bug confirm / close / activate | detail/zentao_bug_action_dialog.dart | Actions/ZentaoBugActionDialog.swift |
| Bug resolve + non-fix resolution | detail/{resolve_dialog,non_fix_resolution_dialog}.dart | Actions/ZentaoResolveDialog.swift (`ZentaoResolveDialog`, public `ZentaoNonFixResolutionDialog`) |
| Task actions (form state, dialog, hours / date fields, problem text, files) | detail/{zentao_task_action_dialog,task_hours_field,task_action_date_field,task_input_problem_text}.dart | Actions/{ZentaoTaskActionForm,ZentaoTaskActionDialog,ZentaoTaskInputFields}.swift |
| Assign (bug / task) | shared/detail/.../assign_dialog.dart, detail/zentao_task_assign_dialog.dart | Actions/ZentaoAssignDialogs.swift |
| Run action (pending card, toast) | submit handlers of the dialogs | Actions/ZentaoActionRunner.swift |
| Bug / task sidebar cards | detail/{bug_detail_sections,task_detail_sections,bug_module_name}.dart | Sections/{ZentaoBugSectionRows,ZentaoBugSections,ZentaoTaskSections}.swift |
| Linked ticket / execution / parent links | detail/{zentao_linked_ticket,zentao_execution_link,parent_task_link}.dart, util/open_zentao_task.dart | Sections/ZentaoLinks.swift (`ZentaoDependencies.openLinked` is in State/) |
| Subtasks, related bugs, status strip, effort bar | detail/{subtask_list,task_bugs_card,bug_status_strip,task_effort_bar}.dart, providers/task_bugs_providers.dart | Sections/{ZentaoSubtaskList,ZentaoTaskBugsCard,ZentaoStatusAndEffort}.swift |
| Attachments list + viewer (image / video with session headers / text / Markdown), Downloads save | detail/bug_attachments.dart, util/zentao_file_preview.dart, shared attachment viewer | Attachments/{ZentaoBugAttachments,ZentaoAttachmentViewer,ZentaoAttachmentKinds}.swift |
| Person avatar / chip hooks | core/navigation/person_chip.dart (consumers) | People/ZentaoPerson.swift |
| Row copy actions, card parent line | widgets/{zentao_row_copy_actions,zentao_card_parent}.dart | People/ZentaoRowCopyActions.swift |

Tests: Tests/ToolZenTaoTests/PresentationDetail{Logic,Render}Tests.swift (+ PresentationDetailFakes.swift) port widget/{zentao_ticket_actions,parent_task_link,bug_status_strip,task_bugs_card}_test.dart and unit/zentao_file_preview_test.dart as pure-logic tests; render smoke PNGs in /tmp/wn-zentao-render/detail-*.png.

## Docs (Presentation/Docs)

Swift under `Packages/WorkNexusKit/Sources/ToolZenTao/Presentation/Docs/`; Dart under `lib/tools/zentao/presentation/`.
Public entry points: `ZentaoDocsState(deps:)`, `ZentaoDocsSection(deps:docs:account:location:)`, `ZentaoDocLibsPane(deps:docs:account:location:)`.

| Area | Dart | Swift |
|---|---|---|
| Session state (open doc per account, tree filter, expanded libs, pane collapse, reader brightness) | providers/zentao_doc_providers.dart (`zentaoOpenDocProvider`, `zentaoDocFilterProvider`, `zentaoDocExpandedLibsProvider`, `zentaoDocReaderBrightnessProvider`) | State/ZentaoDocsState.swift |
| Cache streams + fetch (`ZenTaoDocSync`, 10 min idle life, history sync) | same file (`zentaoDocLibsProvider`, `zentaoDocsProvider`, `zentaoDocProvider`, `zentaoDocPinsProvider`, `zentaoDocHistoryProvider`, `zentaoDocSyncProvider`) | State/ZentaoDocsState+Data.swift (`watchAccount/watchLib`, `observeDoc/observeHistory`, `ensure(_:account:force:)`) |
| Section (open doc or "pick a document") | sections/zentao_docs_section.dart | ZentaoDocsSection.swift |
| Libraries tree pane, lib node + doc rows, tree row | nav/{zentao_doc_libs_scope_list,zentao_doc_lib_node,zentao_doc_tree_row}.dart, util/open_zentao_doc.dart | Nav/{ZentaoDocLibsPane,ZentaoDocLibNode,ZentaoDocTreeRow}.swift |
| Reader (find, outline beside / popover, tools, states) | widgets/zentao_doc_viewer.dart | Viewer/ZentaoDocViewer.swift |
| Scrolling page, heading tracking | widgets/zentao_doc_page.dart | Viewer/ZentaoDocPage.swift |
| Body (HTML -> blocks, text runs, code, tables, lists, images) | widgets/{zentao_doc_body,zentao_doc_inline,zentao_doc_code_block}.dart, flutter_widget_from_html | Support/ZentaoDocBlocks.swift, Viewer/{ZentaoDocBlockView,ZentaoDocText,ZentaoDocCodeBlock}.swift |
| Prepare (anchors + find marks) | util/zentao_doc_prepare.dart | Support/ZentaoDocPrepare.swift |
| Reader controller (current match, active heading, scroll requests) | widgets/zentao_doc_reader_controller.dart | Support/ZentaoDocReader.swift |
| Header, people card | widgets/{zentao_doc_header,zentao_doc_people}.dart | Viewer/{ZentaoDocHeader,ZentaoDocPeople}.swift |
| Tools (find, history, copy, export, link, web, brightness, refresh) | widgets/{zentao_doc_header (toolbar),zentao_doc_export_button,zentao_doc_history_button}.dart | Viewer/ZentaoDocToolbar.swift |
| Outline, find bar | widgets/{zentao_doc_outline,zentao_doc_find_bar}.dart | Viewer/{ZentaoDocOutline,ZentaoDocFindBar}.swift |
| Attached files + in-place preview | widgets/{zentao_doc_files,zentao_doc_file_preview}.dart, util/zentao_file_preview.dart | Viewer/{ZentaoDocFiles,ZentaoDocFilePreview}.swift, Support/ZentaoFilePreview.swift |
| Reader page theme (forced brightness), tool button, floating card | widgets/zentao_doc_reader_theme.dart | Viewer/ZentaoDocChrome.swift |
| History panel / entry / changes | widgets/zentao_doc_history_{panel,entry,changes}.dart | History/*.swift |

### Tests (Tests/ToolZenTaoTests)

| Dart test | Swift test |
|---|---|
| unit/zentao_doc_prepare_test, widget/zentao_doc_body_test, widget/zentao_doc_find_outline_test, widget/zentao_doc_code_block_test | ZentaoDocsSupportTests.swift (prepare, blocks, layout, reader state, file previews, theme, history sentences) |
| unit/zentao_doc_sync_lifetime_test, unit/zentao_doc_reader_brightness_test | ZentaoDocsStateTests.swift (fake `ZenTaoDocRepository` / `SettingsRepository`) |
| widget/zentao_doc_{toolbar,history_panel,find_bar,people}_test | ZentaoDocsRenderTests.swift (off-screen render smoke, PNGs in /tmp/wn-zt-docs-render) |

### Deviations / notes

- Selecting across the page is per `Text` (SwiftUI), not one selection across blocks.
- The nav pane's scroll offset is not kept across a rebuild (no `PageStorageKey` equivalent); the open document's reading offset is (`ZentaoDocsState.readingOffsets`).
- Pane collapse is kept in `ZentaoDocsState.collapsedPanes` (`isPaneCollapsed(accountId:section:)`); the shell has no collapsible-pane host yet, so nothing reads it.
- `SharedKit.PersonAvatarRequest` has no public init, so the header's faces / message button come from this tool's own env keys `\.zentaoDocPersonFace` / `\.zentaoDocPersonAction` (plain initial avatar without them).
- Copy-as-Markdown calls `ZenTaoDocMarkdown.render` (Data) through `ZentaoDocsState.markdown(_:)`; there is no domain use case for it in Swift.
- Fetch freshness is measured from the last fetch (10 min) rather than from the last time something watched it.

## Tests (`Tests/ToolZenTaoTests`)

| Dart test | Swift test |
|---|---|
| unit/zentao_scope_title_test, unit/zentao_parent_child_scoping_test, widget/{zentao_bug_streams,zentao_task_streams,keep_task_board_scope,zentao_board_refresh_button}_test | PresentationBoardsTests.swift (fakes: PresentationBoardsFakes.swift) |
| render checks of the boards / lists / nav panes / docs section through `ZentaoModule` | PresentationBoardsRenderTests.swift (PNGs in /tmp/wn-zentao-render/boards-*.png) |
| nav panes | PresentationNavTests.swift |
| detail / actions | PresentationDetailLogicTests.swift, PresentationDetailRenderTests.swift |
| docs | ZentaoDocsSupportTests.swift, ZentaoDocsStateTests.swift, ZentaoDocsRenderTests.swift |

## Second pass (audit fixes)

New files are CoreUI widgets (provider-agnostic, reusable by Chat / SharedKit) plus ZenTao-side wiring.

| Area | Dart | Swift |
|---|---|---|
| Dropping files on the editor, composer, action dialogs, attachments inputs | core/widgets/{file_drop_target,rich_text_editor}.dart, core/util/dropped_files.dart | CoreUI `Widgets/Drop/{DroppedFiles,FileDropTarget}.swift` (`FileDropTarget`, `FileDropZones`, `DroppedFile`); `RichTextEditor(onDropFiles:)` (images upload inline, the rest go to the closure); `ZentaoFilesInput`, `ZentaoNoteField(onDropFiles:)`, ticket editor `AttachmentsInput` / `BugMainFields` / `TaskFormCentered` |
| Editor colour grid + custom colour | core/util/editor_text_colors.dart, core/widgets/{editor_color_button,custom_color_dialog,hsv_color_fields,swatch_button}.dart | CoreUI `Editor/{EditorTextColors,EditorColorButton}.swift` (24 swatches x 6 columns, text and highlight, "custom colour" opens `CustomColorDialog`), `Fields/HsvColorFields.swift`, `Dialogs/CustomColorDialog.swift` (settings agent) |
| Docs HTML: colours, sub/sup, alignment, spans, blocks in cells | widgets/zentao_doc_body.dart + flutter_widget_from_html | `Docs/Support/{ZentaoDocStyle,ZentaoDocBlocks,ZentaoDocTableSizing}.swift`, `Docs/Viewer/{ZentaoDocTable,ZentaoDocBlockView,ZentaoDocText}.swift` (`ZentaoDocCell`, `.aligned`, `.table(rows:)`, own table `Layout`) |
| "+" / Cmd-N scope, header buttons | widgets/zentao_*_section_header.dart | `State/ZentaoUIState+NewTicket.swift` (`newBugRoute(accountId:)`, `newTaskRoute(accountId:)`), `Boards/ZentaoSectionHeader.swift` |
| Fireworks hook | `celebrationProvider.celebrate()` in zentao_bug_column_card.dart / resolve_dialog.dart | `Support/ZentaoCelebrate.swift` (`\.zentaoCelebrate`, default no-op), called by `ZentaoBugBoardView` (drop into Resolved) and `ZentaoResolveDialog` (resolution `fixed`) |
| Video player | shared/detail/.../attachment_video_{view,picture,frame}.dart, core/widgets/video/*, core/util/load_speed_meter.dart | CoreUI `Video/{AppVideoPlayerModel,AppVideoPlayerView,VideoSurface,VideoControlBar,VideoSeekBar,VideoSupport,VideoFrameCard,VideoStills,AdaptiveViewerFrame}.swift` |
| Attachment viewer | shared/detail/.../attachment_viewer_dialog.dart | `Detail/Attachments/ZentaoAttachmentViewer.swift` (window-level `.appDialog`, `AdaptiveViewerFrame`, `ZoomableImage` 5x) and SharedKit `AttachmentViewerDialog` |
| Timeline video frames | shared/detail/.../comment_tile.dart, `attachmentThumbnail` | SharedKit `ActivityRow(loadStill:)` + `DetailController.attachmentThumbnail` (stream still via `AppVideoStills`, else `VideoThumbnailer` on the cached file <= 20 MB) |
| Attachment storage panel | shared/detail/.../attachment_storage_panel.dart | CoreUI `Misc/AttachmentStoragePanel.swift` (closures: usage, clear) |
| Image viewer zoom | core/widgets/image_viewer_dialog.dart | CoreUI `Dialogs/{ZoomableImage,ImageViewerDialog}.swift` |
| Coming soon, disabled tabs | core/widgets/coming_soon_view.dart, shared/shell_pane/feature_tab_strip.dart | CoreUI `Misc/ComingSoonView.swift`; `FeatureTabStrip` keeps unavailable sections as dimmed tabs |
| Row quick copy, drag dim, search popover, dead pins, multi-select, comment upload uid | widgets/zentao_bug_row.dart etc. | `ZentaoTitleCell` (hover button), `ZentaoBugBoardView` (`dragging` -> opacity 0.35), CoreUI `Misc/OutsideClickMonitor.swift` + `ContextualSearchField`, `ZentaoNavLogic.staleExecutionIds` + `ZentaoTaskModulePane`, `OptionMultiSelect` (draft applied on dismiss), `DetailExtensions.uploadImageWithUid` + `CommentComposer` |

### Differences from Flutter
- **Video position** is read from the AVPlayer clock every frame (`TimelineView`), so Flutter's `SmoothVideoPosition` ticker is not needed.
- **Formats**: mp4 / mov / m4v play in app (streamed with the session headers, else downloaded whole); webm / mkv / avi ... show "Open in another app".
- **Window full screen** for a video toggles the key window (`AppWindowFullScreen`) and the viewer fills it.
- **Table cells** with `rowspan` are laid out by the table's own `Layout` (spans honoured); borders are per cell.
- **Drag dim**: SwiftUI has no end-of-drag callback; the card is dimmed from the moment the drag lifts it until the pointer hovers the board again or a drop lands.
- **Drop targets** do not know whether their section is on screen (Flutter's `TickerMode`): a section kept alive but hidden must pass `enabled: false` or be removed from the hierarchy.

### Composition root wiring
- `\.zentaoCelebrate`: `.environment(\.zentaoCelebrate, { shell.celebrate() })` above `.dialogHost(...)`.
- Comment image uploads under one id per composer: `ext.uploadImageWithUid = { ticket, uid, data, name in await editor.uploadImage(accountId: ticket.accountId, uid: uid, bytes: data, fileName: name).value }` (HostWiring, next to `ext.uploadImage`).
- "+" menu / Cmd-N: `zentaoState.newBugRoute(accountId:)` / `newTaskRoute(accountId:)` give the route for the scope in view.
- Local-data settings: `AttachmentStoragePanel(usage: { sync.attachmentStorageBytes() }, clear: { sync.clearAttachmentStorage() })` (and `AppVideoStills.clearCache()` after clearing).

### macOS-only: team-leader tools on the Tasks / Bugs boards (not in the Flutter app)
Nothing here has a Dart counterpart, so `Scripts/upstream-diff.sh` will never point at it. When upstream changes the boards, keep these in step:
- **Leader bar** (`Boards/Leader/*`, `State/ZentaoUIState+Leader.swift`, domain `ZenTaoLeaderFilter` + `ZenTaoLeaderUseCases`): a people strip with each person's open / overdue count, quick chips (overdue, due soon, this week, unassigned, high priority, idle, no deadline, no estimate), a keyword filter, a card-sort menu (priority / deadline) and "load all" so the counts cover whole views. It is applied after `FilterTickets` in `BuildZenTaoTaskBoard` / `BuildZenTaoBugBoard`; the old "Due this week" tab is now a chip.
- **Deadline state** (`zentaoDeadlineState`, `ZentaoDeadlineTag`): late / due today / due soon by calendar day, open tickets only. `ZentaoFormatters.delayText` is kept for the list's Due colour parity but cards no longer use it.
- **Bulk actions** (`Boards/Bulk/*`, `BoardController+Selection`, domain `ZenTaoBulkUseCases`, `State/ZentaoBulkOps`): ⌘-click / ⇧-click picks cards or rows, then Assign / Priority / Close run one ticket after another through the detail panel's own paths (assign via the adapter, close via `ZenTaoWorkflowService`, priority via the ticket's edit form). Every run shows what will change and what is skipped first; failures can be retried.
- **Search**: ⌘K searches the whole account's cached tickets (`BoardController.searchPool`) and, for a typed id nothing cached has, asks the server (`fetchTicketByKey`).
- **Store**: `GRDBTicketRepository.upsertTickets` now rewrites a changed row even when its title / body hash is unchanged (as the Flutter store does) and carries the board-membership labels forward (`keepsLabel`).
- **Lists**: Bugs get a Due column, Tasks a Left / est. column; Due sorts by `TicketSortField.deadline`.
- **Auto refresh** (`Boards/ZentaoAutoRefresh.swift`, `ZentaoUIState.refreshShownBoards`, `PagedViewsController.refreshHeads`, `ApplyViewHead`): the Tasks / Bugs board on screen reads the first page of each loaded view again every 3 minutes and when the app comes back to the front (at most every 30 s), and merges new tickets in without dropping the pages already loaded. Nothing runs while the window is hidden or another place is shown; team boards are left to their own refresh.
- **Default status filters**: a task board opens on Not Started / In Progress / Paused (`BoardController.openTaskStatuses`), a bug board on New / Unconfirmed and Confirmed / To Fix (`openBugStatuses`); the filter the user leaves a board with is kept for the session. A status the filter leaves out is not scanned for further pages (`ZentaoTaskColumnFooter`, `ZentaoBugColumnFooter`).
- **Bugs tab** "With closed" shows the Closed column (it loads the all-bugs view on first use).
- Fix to the shared table: an empty cell no longer pulls the cells after it one column left (`TicketTableCells`).
- **Team groups** (`Boards/Team/*`, `State/ZentaoUIState+Team.swift`, `ZentaoTeamScope`, domain `ZenTaoTeamGroup` + `BuildTeamGroup`, table `zenTaoTeamGroups` in migration `zentao_v2`): a saved set of people shown on the Tasks or Bugs board *instead of* one execution / product. The header's Team menu creates, edits, deletes and opens groups; the board then holds what ZenTao lists for each person (`ZenTaoViewPages.syncAssignedWork`, three people at a time, 500 tickets each at most), and the leader bar's people strip is the group. Picking an execution / product leaves the team.
  - **Unverified against a real server**: the person pages `user-task-{userId}-assignedTo-…` / `user-bug-…` (ZenTao 18.x / 20+, and whether the signed-in user may see others' work). A refusal is shown per person ("Couldn't read N of the team", with a retry), never as an empty list. If a server refuses, the fallback is to merge the open views of the pinned executions/products - not built.

- **Pinned people** (`ZenTaoPinnedPeopleStore` ← `UserDefaultsZenTaoPinnedPeople`, `OrderWorkload`, `TogglePinnedPerson`, `MovePinnedPerson`): right-click a person in the people strip to pin them to the front; drag a person onto another to place them just before (pinning them). Kept per account on this Mac.
- **Team view leaves routine executions out** (`IsShownInTeamView`, `AppSettings.teamExecutionVisibility`): a team view of Tasks skips the tasks of executions named like a daily report ("VN_Daily_Tasks"); opening that execution still lists them. Right-click an execution in the Executions list to hide it from or show it in team views.
