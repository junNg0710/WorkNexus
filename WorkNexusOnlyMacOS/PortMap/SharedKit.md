# SharedKit — Dart → Swift (lib/shared/{board,detail,sync,shell_pane} + CoreUI Widgets)

Dart under `lib/`, Swift under `Packages/WorkNexusKit/Sources/`. SharedKit paths are relative to `SharedKit/`; CoreUI rows to `CoreUI/Widgets/`.

## SharedKit

| Area | Dart | Swift |
|---|---|---|
| Board models | shared/board/domain/entities/{board_model,filter_state,paged_view_state}.dart | Board/Domain/Entities/{BoardModel,FilterState,PagedViewState}.swift |
| Board value objects | shared/board/domain/value_objects/*.dart | Board/Domain/ValueObjects/{SavedView,SavedFilter,PagingPolicy,PagedViewLoads,AssignedCounts}.swift |
| ZenTao board columns / status (needed by filters) | core/domain/value_objects/{zentao_board_status,zentao_bug_column,zentao_task_column,zentao_module_of}.dart, core/util/ticket_open.dart | Board/Domain/ValueObjects/ZenTaoBoardStatus.swift (internal copy; `isOpenForAssignee` public) |
| Synthetic board labels | core/util/synthetic_labels.dart | Board/Domain/ValueObjects/SyntheticLabels.swift |
| Filter + board build | usecases/{filter_tickets,build_board}.dart | Board/Domain/UseCases/{FilterTickets,BuildBoard}.swift |
| Paged table | usecases/build_paged_table.dart | Board/Domain/UseCases/BuildPagedTable.swift |
| Saved filters | usecases/{build_saved_filter,is_saved_filter_applied}.dart, repositories/saved_filter_repository.dart, data/mappers/saved_filter_mapper.dart, data/repositories/local_saved_filter_repository.dart | Board/Domain/UseCases/BuildSavedFilter.swift (+IsSavedFilterApplied), Board/Domain/Repositories/SavedFilterRepository.swift, Board/Data/Mappers/SavedFilterMapper.swift, Board/Data/Repositories/InMemorySavedFilterRepository.swift (+ `SavedFilterStorage`, the repository every `BoardController` defaults to; App installs `DatabaseSavedFilterRepository` over CorePersistence's `GRDBSavedFilterStore`) |
| People predicates | usecases/{is_assigned_to_me,is_related_to_me}.dart | Board/Domain/UseCases/IsAssignedToMe.swift |
| Counts / facets | usecases/{count_assigned_to_me,derive_board_facets}.dart, facet_labels.dart (`facetActive`) | Board/Domain/UseCases/{CountAssignedToMe,DeriveBoardFacets,FacetActive}.swift |
| Paged views | usecases/{merge_view_pages,apply_view_pages,plan_view_load,should_auto_load,scope_paged_view_tickets}.dart | Board/Domain/UseCases/{PagedViewUseCases,ScopeTickets}.swift |
| Scoping / search / memory | usecases/{scope_provider_tickets,search_local_tickets,switch_board_filter}.dart | Board/Domain/UseCases/ScopeTickets.swift |
| Board state | presentation/providers/{board_providers,filter_providers,board_loading_provider,saved_filter_providers}.dart, assigned_counts_provider.dart | Board/Presentation/Providers/{BoardController,BoardController+Filters}.swift |
| Paged controller | presentation/paged_views_controller.dart | Board/Presentation/Providers/PagedViewsController.swift |
| Host injection points | (Riverpod overrides: translation dot, person avatar/chip) | Board/Presentation/Providers/BoardEnvironment.swift (`\.ticketCardAccessory`, `\.personAvatar`, `\.personChip`) |
| Kanban | widgets/{board_view,board_column_frame,board_folded_column,board_column_empty_slot,board_horizontal_scroll,ticket_card_drag_feedback}.dart | Board/Presentation/Widgets/{BoardView,BoardColumnFrame}.swift |
| Cards | widgets/{ticket_card,ticket_card_meta,ticket_card_skeleton}.dart | Board/Presentation/Widgets/{TicketCard,TicketCardMeta,BoardSkeleton}.swift |
| Table | widgets/{ticket_table,ticket_table_cells,ticket_table_column,ticket_table_header}.dart | Board/Presentation/Widgets/{TicketTable,TicketTableCells,TicketTableColumn,TicketTableHeader}.swift |
| Toolbar | widgets/{board_toolbar,board_toolbar_layout,render_board_toolbar,board_refresh_button,board_layout_toggle,empty_state}.dart | Board/Presentation/Widgets/{BoardToolbar,BoardExtras}.swift (`ViewThatFits` replaces the slotted RenderObject) |
| Filters | widgets/{filters_button,filter_popover,filter_popover_anchor,filter_facet_groups,filter_generic_groups,filter_option_group,filter_chip,filter_dropdown_group,filter_people_block,active_filter_bar,facet_labels}.dart | Board/Presentation/Widgets/{FilterPopover,FilterGroups,FilterChips,FilterDropdownGroup,ActiveFilterBar,FacetLabels}.swift |
| Saved filters UI | widgets/{saved_filters_section,save_filter_dialog}.dart | Board/Presentation/Widgets/SavedFiltersSection.swift |
| Search | widgets/{contextual_search_field,search_results_overlay,search_trailing_affordance}.dart | Board/Presentation/Widgets/ContextualSearchField.swift |
| Paged footer | widgets/paged_column_footer.dart | Board/Presentation/Widgets/PagedColumnFooter.swift |
| Detail state | detail/presentation/detail_providers.dart | Detail/Presentation/Providers/{DetailController,TicketDetailModel,DetailExtensions}.swift |
| Detail overlay | detail/presentation/detail_overlay.dart | Detail/Presentation/Widgets/DetailOverlay.swift (`DetailOverlayHost`, `.detailOverlay`) |
| Detail panel / tabs | detail_panel.dart, widgets/{detail_tab_bar,detail_tab_body,detail_underline_tabs}.dart | Detail/Presentation/Widgets/{DetailPanel,DetailTabs}.swift |
| Detail header | widgets/{detail_header,detail_header_top_bar,detail_header_title,detail_back_button,detail_header_more_button,detail_people}.dart | Detail/Presentation/Widgets/DetailHeader.swift |
| Original tab / body | widgets/{original_tab,detail_scroll_body,detail_region_card,section_label,detail_section_title,item_description}.dart | Detail/Presentation/Widgets/{OriginalTab,DetailScrollBody}.swift |
| Fields | widgets/{detail_field_rows,detail_fields_card,empty_fields_toggle}.dart | Detail/Presentation/Widgets/DetailFields.swift |
| Comments / timeline | widgets/{comments_section,comment_tile,timeline_item,timeline_headline,comment_composer,detail_activity_timeline}.dart | Detail/Presentation/Widgets/{CommentsSection,TimelineViews,CommentComposer}.swift |
| Activity text logic | detail/presentation/util/activity_action_parts.dart, core/domain/value_objects/repo_change.dart | Detail/Domain/ActivityActionParts.swift |
| Attachments | widgets/{attachment_kinds,attachment_viewer_dialog,attachment_viewer_header}.dart | Detail/Presentation/Widgets/AttachmentViews.swift (images + AVKit video from the local copy) |
| Diff / commits / files | widgets/{unified_diff_view,commits_section,changed_files_section}.dart | Detail/Presentation/Widgets/DiffViews.swift |
| MR/PR frame | widgets/two_pane_tabbed_detail.dart | Detail/Presentation/Widgets/TwoPaneTabbedDetail.swift |
| Avatars | widgets/provider_user_avatar.dart | Detail/Presentation/Widgets/ProviderUserAvatar.swift |
| Status pill | widgets/ticket_status_pill.dart | Detail/Presentation/Widgets/TicketStatusPill.swift |
| Sync coordinator | shared/sync/data/sync_coordinator.dart | Sync/Data/SyncCoordinator.swift (actor; implements AccountSyncService + TicketDetailService) |
| Ticket store | shared/sync/data/ticket_store.dart, core/data/mappers (`*AsStored`) | Sync/Data/{TicketStore,StoredForm,RepositoryDetailWriter}.swift, Sync/Domain/SyncPorts.swift (`DetailWriting`) |
| Adapter pool | shared/sync/data/provider_adapter_pool.dart | Sync/Data/ProviderAdapterPool.swift |
| Source list cache | shared/sync/data/source_list_cache.dart | Sync/Data/SourceListCache.swift (+ `SourceListSnapshotStore` port) |
| Sync helpers | shared/sync/data/{merge_detail_labels,sync_status_tracking,attachment_file_cache}.dart, core/cache/byte_lru_cache.dart | Sync/Data/{MergeDetailLabels,SyncStatusTracking,AttachmentFileCache,ByteLruCache}.swift |
| Shell pane kit (extended) | shared/shell_pane/{scope_list_body,scope_rows,sidebar_primitives,sidebar_tree_rows,provider_pinned_projects}.dart | Presentation/ShellPane/{ScopeListBody,ScopeRows,SidebarPrimitives}.swift (`ScopeRow` of ShellPaneKit.swift stays; Dart `ScopeRow` is `ScopeEntryRow`) |
| Ticket semantics / badges (used by cards) | core/theme/semantic.dart, core/util/{labels,priority_labels,zentao_labels,relative_time,image_urls}.dart, core/widgets/badges.dart | CoreUI/Widgets/Support/{TicketSemantics,FormatWhen}.swift, CoreUI/Widgets/Badges/TicketBadges.swift |

## CoreUI/Widgets

| Area | Dart | Swift |
|---|---|---|
| Regex helpers | (dart:core RegExp) | Support/RegexKit.swift |
| String lookup | lib/l10n (AppL10n) | Support/AppL10n.swift |
| Date format / HH:mm parse | lib/core/util/relative_time.dart (formatDate), lib/core/widgets/app_time_input.dart | Support/AppDateFormat.swift |
| Link normalisation | lib/core/util/link_url.dart | Support/LinkURL.swift |
| Provider colour parsing | lib/core/theme/provider_color.dart | Support/ProviderColor.swift |
| Markdown normalise / linkify / detect | lib/core/util/markdown_normalize.dart, adjacent_mentions.dart | Support/MarkdownNormalize.swift |
| HTML DOM (parse/serialize) | package:html (parseFragment, outerHtml) | Support/HtmlDom.swift |
| Rich document model | flutter_quill Document/Delta | Support/RichDocument.swift |
| HTML → rich | flutter_quill_delta_from_html | Support/HtmlToRich.swift |
| Rich → HTML | vsc_quill_delta_to_html | Support/RichToHtml.swift |
| HtmlEditingController + table/width helpers | lib/core/widgets/html_editing_controller.dart | Support/HtmlEditing.swift |
| Body block model + Markdown parser | lib/core/widgets/markdown_text.dart | Support/BodyBlocks.swift |
| HTML body parser | lib/core/widgets/html_text.dart | Support/HtmlBlocks.swift |
| Body renderer (blocks, tables, link scope) | lib/core/widgets/markdown_text.dart, html_text.dart | Content/BodyBlocksView.swift |
| MarkdownText | lib/core/widgets/markdown_text.dart | Content/MarkdownText.swift |
| HtmlText, RichBodyText, isHtmlBody | lib/core/widgets/html_text.dart, rich_body_text.dart, lib/core/util/body_format.dart | Content/HtmlText.swift |
| InlineImage + loader typedefs | lib/core/widgets/inline_image.dart | Content/InlineImage.swift, Content/ImageLoading.swift |
| CodeBlock, CodeCopyButton | lib/core/widgets/code_block.dart | Content/CodeBlock.swift |
| ImageViewerDialog | lib/core/widgets/image_viewer_dialog.dart | Dialogs/ImageViewerDialog.swift |
| AppDialogFrame + `.appDialog` | lib/core/widgets/app_dialog_frame.dart | Dialogs/AppDialogFrame.swift |
| AppConfirmDialog + `.appConfirmDialog` | lib/core/widgets/app_confirm_dialog.dart | Dialogs/AppConfirmDialog.swift |
| AppPopupCard | lib/core/widgets/app_popup_card.dart | Menus/AppPopupCard.swift |
| AppMenuEntry / AppMenuPanel / `.appContextMenu` / `.appMenu` | lib/core/widgets/app_context_menu.dart | Menus/AppContextMenu.swift |
| AppDropdown | lib/core/widgets/app_dropdown.dart | Menus/AppDropdown.swift |
| SearchableDropdownField | lib/core/widgets/searchable_dropdown_field*.dart | Menus/SearchableDropdownField.swift |
| AppSegmentedTabs | lib/core/widgets/app_segmented_tabs.dart | Menus/AppSegmentedTabs.swift |
| Toasts (controller, card, host) | lib/core/widgets/app_toast_{controller,card,host}.dart | Menus/AppToast.swift |
| AppDateField, AppTimeInput | lib/core/widgets/app_date_field.dart, app_time_input.dart | Fields/AppDateField.swift |
| AppDatePickerPanel | lib/core/widgets/app_date_picker_panel.dart | Fields/AppDatePickerPanel.swift |
| LabelChips, FlowLayout | lib/core/widgets/label_chips.dart | Misc/LabelChips.swift |
| WorkspaceBadge, WorkspaceIcons | lib/core/widgets/workspace_badge.dart | Badges/WorkspaceBadge.swift |
| Brand logos | lib/core/widgets/badges.dart (provider logo) | Badges/BrandLogoBadge.swift |
| HoverRegion, HoverSurface | lib/core/widgets/hover_surface.dart | Misc/HoverSurface.swift |
| AppSearchField | lib/core/widgets/app_search_field.dart | Misc/AppSearchField.swift |
| AppInlineSpinner, AppInlineNote | lib/core/widgets/inline_status.dart | Misc/InlineStatus.swift |
| ResizeHandle | lib/core/widgets/resize_handle.dart | Misc/ResizeHandle.swift |
| AppSectionHeader | lib/core/widgets/app_section_header.dart | Misc/AppSectionHeader.swift |
| ZenTaoKindIcon | lib/core/widgets/zentao_kind_icon.dart | Misc/ZenTaoKindIcon.swift |
| NSAttributedString ↔ RichDocument | lib/core/widgets/rich_text_editor.dart | Editor/RichAttributedBridge.swift |
| Editor text view (markers, quote bar, paste image) | lib/core/widgets/rich_text_editor.dart | Editor/RichTextView.swift |
| Editor formatting commands | lib/core/widgets/editor_toolbar_buttons.dart | Editor/RichEditorCommands.swift |
| Editor toolbar, colour menu, link popover | lib/core/widgets/editor_toolbar_buttons.dart, editor_color_button.dart, editor_link_button.dart, editor_link_dialog.dart | Editor/RichEditorToolbar.swift |
| RichTextEditor | lib/core/widgets/rich_text_editor.dart | Editor/RichTextEditor.swift |

## Shell hosting (integration pass)
`Presentation/Shell/ShellHost.swift` (new, public `ShellHost`), `RailLabeledButton.swift` (new, public rail cell + `RailDivider`), `NavRail`/`TitleBar`/`ToolPaneHost`/`Viewport`/`AppShell` rewritten around `ShellModel.host` slots (chat, workspace / settings pages, mini-app rail + stack, editor, bell, update button / banner, overlay, quick settings), `ShellModel` now owns `detail: DetailController`, `toasts` and `connectRequested`. Dart: app/shell/{app_nav_rail,rail_*,tool_pane_host,viewport,app_shell,title_bar}.dart.

## Shell pass 2 (workspace switching, keep-alive, banners, launch)
| Area | Dart | Swift |
|---|---|---|
| Active workspace (id kept in `active_workspace.txt`, falls back to the first) | core/navigation/navigation_providers.dart (`activeWorkspaceIdProvider`, `activeWorkspaceProvider`, `sortedActiveAccountsProvider`) | Presentation/Providers/{ShellModel,ShellModel+Workspaces}.swift, Shell/Data/ActiveWorkspaceStore.swift. Rail accounts, rail section tools, the overview (`OverviewHolder` in App) and nav follow it |
| Workspace switcher | app/shell/workspace_switcher_{popover,row,footer}.dart | Presentation/Shell/{WorkspaceSwitcherPopover,WorkspaceSwitcherRow}.swift (row + footer) |
| Create / edit workspace dialogs | features/connections/.../create_workspace_dialog.dart | FeatureConnections `ConnectionsFeature.workspaceDialogs` (reuses `WorkspaceEditorDialog` with "Create workspace / Create & join") |
| Breadcrumb | app/shell/workspace_breadcrumb{,_trigger}.dart | Presentation/Shell/WorkspaceBreadcrumb.swift (clickable tool / section, `ToolModule.scopeTitle`, mini-app NAME via `ShellHost.miniAppName`) |
| Auth-expired banner + offline / error strips | app/shell/auth_expired_banner.dart | Presentation/Shell/{SyncBanners,SectionHealth}.swift (`SectionNoticeBanner` is public: tools show failed slice fetches with it) |
| Section error boundary | app/shell/section_error_boundary.dart | Presentation/Shell/AccountSectionView.swift (`SectionErrorBoundary`; an account whose sync failed with nothing cached shows error + Retry over the mounted section) |
| Keep-alive (LRU of 5) | app/shell/{viewport,tool_pane_host}.dart | Presentation/Shell/{KeepAliveStack,Viewport,ToolPaneHost}.swift, Shell/Domain/KeepAliveLRU.swift; hidden views see `\.sectionIsActive == false` |
| Detail panel per place | shared/detail/presentation/detail_overlay.dart | Detail/Presentation/Widgets/DetailOverlay.swift |
| Collapsible pane | app/shell/collapsible_pane.dart, core/navigation/collapsed_panes.dart | ToolPaneHost (strip) + `AppNavController.collapsedPanes/setPane/paneKey` + `\.paneCollapse` button in `ToolPaneScaffold` |
| New-ticket "+" menu, ⌘N | app/shell/new_ticket_menu.dart | Presentation/Shell/NewTicketMenu.swift; `ShellHost.newTicketTargets` filled in App/HostWiring |
| Launch: default app, chat at launch | app_shell.dart, chat_at_launch.dart | ShellModel+Launch.swift, `AppNavController.selectDefaultAppIfApplicable` |
| Celebration | core/widgets/{celebration_overlay,fireworks_painter}.dart, core/util/fireworks.dart | CoreUI/Widgets/Celebration/*; `ShellModel.celebrate()` / `\.celebrate` |
| Menu ⌘K / ⌘R routing, Esc | app shortcuts | Presentation/Shell/ShellCommands.swift (`\.boardSearch`, `\.boardRefresh` focused values; `EscapeKeyMonitor`) |
| Title-bar search (not in Dart) | - | Presentation/Shell/GlobalSearchField.swift (key / title over the active workspace's synced tickets) |
| Sync persistence | settings_sync_status_repository.dart, ticket_store.dart, source_list_cache.dart | CorePersistence `GRDBSyncStatusRepository` (migration `core_v2`, table `accountSyncState`), `GRDBDetailStore` (comments + activity replaced in one transaction, `DetailWriting.replaceDetail`), `GRDBSourceListSnapshots`; adapters in App/Sources/Persistence |
| Ticket links | features/chat/.../ticket_link_handler.dart | App/Sources/TicketLinkHandler.swift (`LinkStage.app`) |

### macOS-only: loading placeholders

- `KeepAliveStack` anchors every kept section to the top at the viewport's size (`minWidth/minHeight: 0`): a section whose content was still small while loading was centred in the window, leaving an empty band above its header.
- `BoardSkeleton` / `TableSkeleton` fill the board area from the top-left (no horizontal scroll view, which centred them vertically) and fade in after 120 ms, so a quick load shows no flash. `AppStateView(.loading)` shows `SkeletonRows` instead of a spinner.
- `SkeletonBox` draws a plain placeholder with one shared sweep of light (`SkeletonSheen`: same clock, positioned in window coordinates), still under Reduce Motion. The ZenTao people strip keeps its row as placeholders while a board loads, so the board does not jump.
- Body text blocks and list items keep their full height (`fixedSize(vertical:)` in `BodyBlocksView`): a long ZenTao comment with lists was measured shorter than it draws and spilled over the timeline rows around it.
- The title-bar search shows only where it has something to search (`ShellModel.showsGlobalSearch`): not over a mini app (a web page with its own search), Settings or the ticket editor. A board whose scope reads the settings re-scopes when they change (`BoardController.settings`).
- Message rows are `Equatable` (`ThreadRowView`) and the list keeps its scroll metrics out of SwiftUI state, so a scroll or a page arriving no longer re-runs every loaded row.
