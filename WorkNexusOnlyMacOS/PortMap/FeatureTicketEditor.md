# Port map - FeatureTicketEditor (lib/features/ticket_editor -> Packages/WorkNexusKit/Sources/FeatureTicketEditor)

Public entry: `TicketEditorFeature` (documented in `Presentation/TicketEditorFeature.swift`): `TicketEditorView(route:nav:)` /
`TicketEditorView(launch:nav:)`, `BugEditorController`, `TaskEditorController`. Services come from `AppServices`
(`zentaoEditor`, `zentaoDrafts`, `zentaoTeamMembers`, all optional - without `zentaoEditor` the page shows its error state).
Navigation: `nav:` or `.environment(\.ticketEditorNav, nav)`. No DB of its own: drafts live in ToolZenTao's `ticketDrafts`
table (`zentao_v1`) behind the hoisted `ZenTaoTicketDraftRepository`, so there is no migration registrar.

| Area | Dart | Swift |
|---|---|---|
| Validation (bug: title/builds/product; task: name/type/execution/date order) | domain/usecases/validate_ticket_draft.dart | Domain/UseCases/ValidateTicketDraft.swift, Domain/ValueObjects/DraftField.swift |
| ZenTao fixed choices, title colours, `withValue` | domain/value_objects/zentao_choices.dart | Domain/ValueObjects/ZenTaoChoices.swift |
| Route (copyOf / executionId / taskId / parentId / draftId) | core/navigation/ticket_editor_route.dart | Domain/ValueObjects/TicketEditorLaunch.swift (+ `TicketEditorView.launch(for:)` from CoreTools' `TicketEditorRoute`) |
| Scope-change rules, option merging, kept-draft values | presentation/providers/{bug,task}_editor_controller.dart (inline) | Domain/UseCases/EditorRules.swift |
| Date / hours / uid / draft-title formatting | editor_date_input, task_progress_fields, ticket_editor_state, ticket_draft_labels | Domain/ValueObjects/FormValueFormat.swift |
| After-save choice | task_form_fields.dart (`TaskAfterSave`) | Domain/ValueObjects/TaskAfterSave.swift |
| Saved draft entity + repository | domain/entities/saved_ticket_draft.dart, domain/repositories/ticket_draft_repository.dart, data/** | hoisted to CoreDomain (`ZenTaoSavedDraft`, `ZenTaoTicketDraftRepository`); impl `GRDBZenTaoTicketDraftRepository` stays in ToolZenTao/Data/Local |
| Draft autosave (debounce, flush, discard) | providers/ticket_draft_providers.dart (`DraftAutosave`) | Data/Services/DraftAutosave.swift (`Task`-based) |
| Services bundle from `AppServices` | core/di/providers.dart (`zenTaoTicketEditorProvider`...) | Data/Repositories/TicketEditorGateway.swift |
| Editor state | providers/ticket_editor_state.dart | Presentation/Providers/EditorState.swift |
| Bug / task controllers (load, restore draft, edit, scope, upload, save, discard) | providers/{bug,task}_editor_controller.dart | Presentation/Providers/{BugEditorController,TaskEditorController}.swift |
| Rich-text -> draft sync | widgets/rich_text_draft_sync.dart | Presentation/Providers/RichTextDraftSync.swift (polls `HtmlEditingController.document`) |
| Page | pages/ticket_editor_page.dart | Presentation/Pages/TicketEditorView.swift |
| Bug / task editor views | widgets/{bug,task}_editor_view.dart | Presentation/Widgets/{BugEditorView,TaskEditorView}.swift (+ `EditorActions`, `EditorLoadState`) |
| Header, shortcuts, columns, section, field | widgets/{editor_header,editor_shortcuts,editor_columns,editor_section,editor_field}.dart | Presentation/Widgets/{EditorHeader,EditorShortcuts,EditorColumns,EditorSection,EditorField}.swift |
| Bug fields | widgets/{bug_main_fields,bug_side_fields,bug_task_select}.dart | Presentation/Widgets/{BugMainFields,BugSideFields,BugTaskSelect}.swift |
| Task form (centered, simple/full toggle, progress, optional, timeframe, next action) | widgets/{task_form_centered,task_form_mode_toggle,task_progress_fields,task_optional_fields,task_form_fields}.dart | Presentation/Widgets/{TaskFormCentered,TaskFormModeToggle,TaskProgressFields,TaskOptionalFields,TaskFormFields}.swift |
| Inputs: text, date, level, select, multi-select (+dialog, check list), title colour, chip, attachments | widgets/{editor_inputs,editor_date_input,editor_level_input,option_select,option_multi_select,option_multi_select_dialog,option_check_list,title_color_input}.dart, core/widgets/{editor_chip,attachments_input}.dart | Presentation/Widgets/{EditorTextInput,EditorDateInput,EditorLevelInput,OptionSelect,OptionMultiSelect,OptionCheckList,TitleColorInput,EditorChip,AttachmentsInput}.swift |
| Draft picker menu + labels, discard confirm | widgets/{draft_picker_button,confirm_discard_draft}.dart, util/ticket_draft_labels.dart | Presentation/Widgets/DraftPickerButton.swift, `appConfirmDialog` in the editor views |

## Tests (Tests/FeatureTicketEditorTests)

| Swift test | Covers |
|---|---|
| DomainTests.swift | validate_ticket_draft, zentao_choices, scope rules, option merge, formats, launch / route mapping |
| ControllerTests.swift | controllers over fake `ZenTaoTicketEditor` / draft repository / team members: load, error state without an editor, autosave, flush on close, validation, save + draft discard, failure, scope change, draft restore, subtask launch, execution change, `DraftAutosave` |
| RenderSmokeTests.swift | NSHostingView PNGs in /tmp/wn-feat-render/editor-*.png |

## Deviations / not ported

- `TicketEditorRoute` (CoreTools) has only the four plain cases, so copy-of / bug-from-task / subtask / draft routes use the new `TicketEditorLaunch`; the nav route's `ticketId` is read as the WorkNexus ticket id (`{account}:{type}:{id}`) or a bare ZenTao id.
- Multi-select opens a popover checklist that applies each toggle at once (Flutter: modal dialog with Save).
- Files dropped on the rich editor do not join the attachments (CoreUI's `RichTextEditor` has no drop hook); the Attachments field takes files by button or drop.
- Flutter's unused `task_main_fields` / `task_side_fields` (superseded by the centered form) are not ported.
- Strings use `appString` / `appFormat` keys named like the `.arb` keys with English fallbacks; new key `addFiles` (attachments button) and `retry` must be added to `Localizable.xcstrings` by the app target.
- Package.swift: FeatureTicketEditor gained the `CoreTools` dependency (for `AppServices`, `AppNavController`).
