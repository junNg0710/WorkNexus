# Port map - ToolZenTao (Domain + Data). Presentation / ToolModule UI comes from a later pass.

Paths: Dart under `lib/`, Swift under `Packages/WorkNexusKit/Sources/ToolZenTao/`. Public entry points: see
`Data/Repositories/ZentaoModuleData.swift`.

| Area | Dart | Swift |
|---|---|---|
| Transport (REST v1 + classic channel, login, relogin on 401, language cookie, accept-any-TLS) | tools/zentao/data/datasources/zentao_client.dart, zentao_auth_interceptor.dart, zentao_language_interceptor.dart, zentao_api.dart | Data/Datasources/{ZenTaoClient,ZenTaoClient+V1,ZenTaoClient+Classic,ZenTaoClient+Bytes,ZenTaoTransport,ZenTaoError}.swift |
| Lenient JSON helpers (ordered objects, `zentaoInt`, ...) | tools/zentao/data/models/zentao_models.dart (helpers), dart:convert | Data/Datasources/ZenTaoJSON.swift |
| Classic payload / form parsing | tools/zentao/data/datasources/zentao_form_parsing.dart | Data/Datasources/ZenTaoFormParsing.swift |
| Docs remote (REST v1 + `action-ajaxGetList-doc`) | tools/zentao/data/datasources/zentao_docs_remote.dart | Data/Datasources/ZenTaoDocsRemote.swift |
| REST DTOs (entity, file, action, users, bugs/tasks views, assigned groups) | tools/zentao/data/models/zentao_models.dart | Data/Models/ZenTaoModels.swift |
| Container DTOs (products tree, projects, programs) | tools/zentao/data/models/zentao_container_models.dart | Data/Models/ZenTaoContainerModels.swift |
| `orderBy` of classic lists | tools/zentao/data/models/zentao_order_by.dart | Data/Models/ZenTaoOrderBy.swift |
| Ticket / entity / comment / activity mapping (status, priority, sourceHash) | tools/zentao/data/mappers/zentao_normalize.dart, core/util/{content_hash,html_entities}.dart | Data/Mappers/{ZenTaoNormalize,HtmlEntities}.swift |
| Profile / department mapper | tools/zentao/data/mappers/zentao_profile_mapper.dart | Data/Mappers/ZenTaoProfileMapper.swift |
| Doc / doc-history / doc-html mappers | tools/zentao/data/mappers/{zentao_doc_mapper,zentao_doc_history_mapper,zentao_doc_html}.dart | Data/Mappers/{ZenTaoDocMapper,ZenTaoDocHistoryMapper,ZenTaoDocHtml,MiniHTML}.swift |
| Notification mapper | features/notifications/data/mappers/zentao_notification_mapper.dart | Data/Mappers/ZenTaoNotificationMapper.swift |
| Dashboard (`GET /user?fields=`) snapshot parse | features/workspace_overview/data/mappers/zentao_dashboard_mapper.dart, domain/entities/zentao_dashboard.dart | Data/Mappers/ZenTaoDashboardMapper.swift, Domain/Entities/ZenTaoDashboard.swift |
| ProviderAdapter (list/detail/comments/activity/assign/resolve/activate/confirm/bytes, messages, user info, task bugs) | tools/zentao/data/repositories/zentao_adapter.dart | Data/Repositories/{ZenTaoProviderAdapter,ZenTaoProviderAdapter+Lists,ZenTaoProviderAdapter+Actions}.swift |
| Product / project lists with program grouping | tools/zentao/data/repositories/zentao_source_lists.dart | Data/Repositories/ZenTaoSourceLists.swift |
| Adapter factory (account + secret -> adapter) | app/di/provider_adapter_registry_impl.dart (ZenTao branch) | Data/Repositories/ZentaoAdapterFactory.swift |
| Module entry / wiring | tools/zentao/zentao_module.dart (data+domain only) | Data/Repositories/ZentaoModuleData.swift |
| Bug / task workflow actions (classic forms) | tools/zentao/data/models/{zentao_workflow,zentao_action_result}.dart | Data/Services/ZenTaoWorkflow.swift |
| Workflow service (optimistic) | tools/zentao/data/services/zentao_workflow_actions.dart | Data/Services/ZenTaoWorkflowActions.swift |
| Ticket forms (bug / task create+edit, kept fields, 18.x vs 20+) | tools/zentao/data/models/{zentao_ticket_forms,zentao_task_forms,zentao_link_options,zentao_bug_from_task}.dart | Data/Services/{ZenTaoTicketForms,ZenTaoTicketForms+Tasks,ZenTaoTicketForms+Links}.swift |
| Subtask batch form | tools/zentao/data/models/zentao_subtask_form.dart | Data/Services/ZenTaoSubtaskForm.swift |
| Ticket editor service, team members | tools/zentao/data/services/zentao_ticket_editor_service.dart, data/repositories/classic_zentao_team_members.dart | Data/Services/ZenTaoTicketEditorService.swift |
| Ticket / view-pages / task-bugs service | tools/zentao/data/services/zentao_ticket_service_impl.dart | Data/Services/{ZenTaoTicketServiceImpl,ZenTaoTicketServiceImpl+Views}.swift |
| Task-bugs coverage | tools/zentao/data/services/task_bugs_coverage.dart | Data/Services/TaskBugsCoverage.swift |
| Pooled client/adapter access (SyncCoordinator.rawClientFor/adapterFor) | shared/sync/data/sync_coordinator.dart | Data/Services/ZenTaoServiceContext.swift |
| Migrations (`zentao_v1`) | core/database/database.dart (ZenTaoProfiles, DashboardSnapshots, SourceListSnapshots, ZenTaoDocSnapshots, ZenTaoNotifications, TicketDrafts) | Data/Local/{ZenTaoMigrations,ZenTaoRecords}.swift |
| Profile repository | tools/zentao/data/repositories/local_zentao_profile_repository.dart | Data/Local/GRDBZenTaoProfileRepository.swift |
| Doc repository | tools/zentao/data/repositories/local_zentao_doc_repository.dart | Data/Local/GRDBZenTaoDocRepository.swift |
| Notification repository | features/notifications/data/repositories/zentao_notification_repository.dart, datasources/notification_local_datasource.dart | Data/Local/GRDBZenTaoNotificationRepository.swift |
| Dashboard repository | features/workspace_overview/data/repositories/zentao_dashboard_repository.dart, datasources/dashboard_local_datasource.dart | Data/Local/GRDBZenTaoDashboardRepository.swift |
| Source-list cache | shared/sync/data/source_list_cache.dart | Data/Local/GRDBZenTaoSourceListCache.swift |
| Ticket drafts (+ mapper) | features/ticket_editor/data/{repositories/local_ticket_draft_repository,datasources/ticket_draft_local_datasource,mappers/ticket_draft_mapper}.dart | Data/Local/GRDBZenTaoTicketDraftRepository.swift |
| Ticket id, ZenTaoType, synthetic labels | core/domain/value_objects/zentao_ticket_id.dart, core/util/synthetic_labels.dart, zentao_normalize.dart (ZenTaoType) | Domain/ValueObjects/ZenTaoType.swift |
| Task action / input, bug / create actions, action menu, effort | core/domain/value_objects/{zentao_action,zentao_task_action_input}.dart, tools/zentao/domain/value_objects/*.dart | Domain/ValueObjects/ZenTaoTaskAction.swift |
| Bug / task columns, resolution labels, status-of, module-of | core/domain/value_objects/{zentao_bug_column,zentao_task_column,zentao_board_status,zentao_module_of}.dart | Domain/ValueObjects/ZenTaoColumns.swift |
| Browse types / bug streams | tools/zentao/domain/value_objects/{zentao_bug_browse_type,zentao_bug_stream}.dart | Domain/ValueObjects/ZenTaoBrowse.swift |
| Coded-field labels, file size | core/util/zentao_labels.dart | Domain/ValueObjects/ZenTaoLabels.swift |
| Date parse / ISO string | dart:core DateTime.tryParse / toIso8601String | Domain/ValueObjects/ZenTaoDates.swift |
| Form entities (FormOption, Bug/Task draft, options, form) | core/domain/entities/zentao_ticket_form.dart | Domain/Entities/ZenTaoTicketForm.swift |
| Profile / department / update | tools/zentao/domain/entities/{zentao_profile,zentao_department,zentao_profile_update}.dart | Domain/Entities/ZenTaoProfile.swift |
| Doc entities (lib, summary, doc, person, action, change, pins, export format) | tools/zentao/domain/entities/zentao_doc*.dart | Domain/Entities/ZenTaoDocs.swift |
| Product / project trees | tools/zentao/domain/entities/{zentao_product_group,zentao_project_group}.dart | Domain/Entities/ZenTaoTrees.swift |
| Notification entity | features/notifications/domain/entities/zentao_notification.dart | Domain/Entities/ZenTaoNotifications.swift |
| Service protocols (workflow, editor, ticket service, view pages, task bugs, team members, messages adapter) | core/domain/adapters/{zentao_workflow_service,zentao_ticket_editor,zentao_ticket_service,zentao_messages_adapter}.dart, tools/zentao/domain/repositories/{zentao_view_pages,zentao_task_bugs,zentao_team_members}.dart | Domain/Repositories/ZenTaoServices.swift |
| Repository protocols (profile, docs, notifications, dashboard, drafts, source-list cache) | tools/zentao/domain/repositories/{zentao_profile_repository,zentao_doc_repository}.dart, features/*/domain/repositories/* | Domain/Repositories/ZenTaoRepositories.swift |
| Use cases: bug / task / create actions | tools/zentao/domain/usecases/{list_zentao_bug_actions,list_zentao_task_actions,list_zentao_create_actions}.dart | Domain/UseCases/ZenTaoActionUseCases.swift |
| Use cases: task input checks, assign-left check, effort summary | tools/zentao/domain/usecases/{check_zentao_task_input,check_zentao_assign_left,summarize_task_effort}.dart | Domain/UseCases/ZenTaoTaskInputUseCases.swift |
| Use cases: doc HTML render + export (Markdown / HTML / backup) | tools/zentao/domain/usecases/{render_zentao_doc_html,render_zentao_doc_markdown,export_zentao_doc}.dart | Domain/UseCases/ExportZenTaoDoc.swift, Data/Mappers/ZenTaoDocMarkdown.swift (compact html2md stand-in) |
| Use case: nest a task's flat subtask list by each subtask's parent | tools/zentao/domain/usecases/build_subtask_tree.dart | Domain/UseCases/BuildSubtaskTree.swift (+ `SubtaskTree.visible(expanded:)`, the list's `_visible` walk) |
| Use cases: module tree, task bugs, due this week, doc lib filter, pin toggle, profile update | tools/zentao/domain/usecases/{build_zentao_module_tree,list_task_bugs,is_due_this_week,filter_zentao_doc_libs,toggle_zentao_doc_pin,update_zentao_profile}.dart | Domain/UseCases/ZenTaoListUseCases.swift |

## Tests (Tests/ToolZenTaoTests)

| Dart test | Swift test |
|---|---|
| test/data/zentao_client_test.dart | ZenTaoAdapterTests.swift, ZenTaoViewPagesTests.swift (URLProtocol stub in StubServer.swift) |
| test/data/zentao_normalize_test.dart, zentao_order_by_test.dart | ZenTaoNormalizeTests.swift |
| test/unit/build_subtask_tree_test.dart, test/widget/subtask_list_tree_test.dart (visible rows) | BuildSubtaskTreeTests.swift |
| test/data/zentao_workflow_test.dart, zentao_workflow_actions_test.dart, zentao_language_interceptor_test.dart | ZenTaoWorkflowTests.swift |
| test/data/zentao_ticket_forms_test.dart | ZenTaoTicketFormsTests.swift |
| test/data/zentao_{doc_mapper,doc_history_mapper,doc_html,notification_mapper,dashboard_mapper,product_tree}_test.dart, test/unit/zentao_project_group_test.dart | ZenTaoMapperTests.swift |
| test/domain/{zentao_action_usecases,build_zentao_module_tree,zentao_doc_usecases}_test.dart, test/data/task_bugs_coverage_test.dart | ZenTaoDomainTests.swift |
| test/data/zentao_{notification,dashboard,doc}_repository_test.dart, source_list_cache_test.dart, local_ticket_draft_repository_test.dart | ZenTaoLocalTests.swift (in-memory GRDB) |

## Not ported (needs other targets or a Markdown library)

- `build_zentao_bug_board`, `build_zentao_task_board`, `build_zentao_facet_catalog`, `compute_zentao_metrics` (depend on SharedKit's board domain `BoardQuery` / `FilterTickets` / facet catalog and CoreTools' `ToolMetrics`) - Presentation pass.
- `html2md` itself: `ZenTaoDocMarkdown` is a compact converter for the editor's blocks (headings, paragraphs, emphasis, links, images, lists, quotes, code, GFM tables), not a full port.
- `zentao_ticket_id_migration_test` (core DB migration, owned by CorePersistence).
