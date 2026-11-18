# FeatureTranslation (lib/features/translation → Sources/FeatureTranslation)

Public entry: `TranslationFeature` (`make(database:credentials:)` → `service`, `repository`, `apiConfig`, `openCodeKeys`, `modelCatalog`, `openCodeCli`, `resolveState`).
The views live in the app target (`App/Sources/TranslationViews.swift`, `TranslationTabView.swift`, `TranslationFooterView.swift`, `OpenCodeLinkGate.swift`, `Settings/Translation*.swift`); the decisions they make are in `Domain/UseCases/{CheckTranslationReady,TranslationSettingsLogic}.swift` (testable without UI). Not ported: the Riverpod providers (the app's `TranslationHub` keeps one `TranslationTabModel` per ticket, shared by the tab and the footer).

| Area | Dart | Swift |
|---|---|---|
| TranslationService interface, TicketSource, TextTranslation | domain/adapters/translation_service.dart | Domain/Adapters/TranslationService.swift |
| TranslationRecord / TranslationApiConfig / OpenCodeProviderAuth | domain/entities/*.dart | Domain/Entities/*.swift |
| Presets (Gemini/Groq/OpenRouter/Ollama/custom, OpenCode) | domain/value_objects/translation_api_preset.dart | Domain/ValueObjects/TranslationApiPreset.swift |
| OpenCode key links, `openCodeProvider(of:)` | domain/value_objects/opencode_key_links.dart | Domain/ValueObjects/OpenCodeKeyLinks.swift |
| Languages | lib/core/util/translation_languages.dart | Domain/ValueObjects/TranslationLanguage.swift |
| TranslationState, ResolveTranslationState | lib/core/domain/value_objects/translation_state.dart, domain/usecases/resolve_translation_state.dart | Domain/ValueObjects/TranslationState.swift, Domain/UseCases/ResolveTranslationState.swift |
| Content hash (UTF-16, same hex as Dart) | lib/core/util/content_hash.dart | Domain/ValueObjects/ContentHash.swift |
| Repository interfaces + `OpenCodeCli` | domain/repositories/*.dart, lib/core/domain/adapters/opencode_cli.dart | Domain/Repositories/Repositories.swift |
| Prompts, reply JSON extraction | data/translation_prompts.dart | Data/Services/TranslationPrompts.swift |
| API backend (OpenAI-compatible `POST {base}/chat/completions`, cancel, error mapping) | data/api_translation_service.dart | Data/Services/ApiTranslationService.swift |
| OpenCode CLI backend (`opencode run`, timeout + kill tree, ANSI strip) | data/opencode_translation_service.dart | Data/Services/OpenCodeTranslationService.swift, Data/DataSources/PipeCapture.swift |
| Router (API when usable, else OpenCode; cancel reaches the right backend) | data/routing_translation_service.dart | Data/Services/RoutingTranslationService.swift |
| `complete(key:prompt:model:)`: a free-form prompt on the same backend (chat's AI help; adapted by the app as `TranslationChatAiTextGenerator`) | domain/adapters/translation_service.dart, data/{api,opencode,routing}_translation_service.dart (0001c975) | Domain/Adapters/TranslationService.swift, Data/Services/*TranslationService.swift |
| Binary discovery through a login shell + PATH scan, kill tree | data/datasources/cli_runner.dart | Data/DataSources/CliRunner.swift |
| `opencode auth list` / `models` queries | data/datasources/opencode_cli_runner.dart | Data/DataSources/OpenCodeCliRunner.swift |
| `auth.json` (atomic write, 0600, XDG/`~/.local/share`) | data/datasources/opencode_auth_file.dart | Data/DataSources/OpenCodeAuthFile.swift |
| OpenCode key repository (masked preview) | data/repositories/opencode_auth_file_key_repository.dart | Data/Repositories/OpenCodeAuthFileKeyRepository.swift |
| `/models` catalog | data/datasources/openai_model_catalog_datasource.dart | Data/DataSources/OpenAIModelCatalogDataSource.swift |
| API config in the credential store (`CredentialKey.translationApi`, same JSON) | data/repositories/credential_translation_api_config_repository.dart | Data/Repositories/CredentialTranslationApiConfigRepository.swift |
| Translation cache (core `translations` table) | data/repositories/local_translation_repository.dart, data/mappers/translation_mappers.dart | Data/Repositories/GRDBTranslationRepository.swift, Data/Models/{TranslationRow,TranslationMapper}.swift |
| Tests | test/features/translation/*, test/domain/translation_{state,languages}_test.dart | Tests/FeatureTranslationTests/FeatureTranslationTests.swift |
| `ensureOpenCodeLinked` (API key usable, or OpenCode has an authenticated provider) | lib/core/widgets/opencode_not_linked_dialog.dart | Domain/UseCases/CheckTranslationReady.swift + App `OpenCodeLinkGate` / `OpenCodeNotLinkedDialog` (gate before ticket and chat-message translation) |
| Settings decisions (active backend, summary, model choices, save rules, restore on pick, key status) | presentation/widgets/{translation_settings_card,translation_api_form,translation_model_picker,translation_api_model_field,translation_opencode_key_field}.dart | Domain/UseCases/TranslationSettingsLogic.swift; views in App `Settings/Translation{SettingsPage,ApiForm,ApiModelField,ModelPicker,OpenCodeKeyField}.swift` |
| Ticket translation footer (Translate / Retry / Retranslate, Cancel, machine note, language control) | lib/shared/detail/presentation/widgets/translation_footer.dart, core/widgets/translation_language_control.dart | App `TranslationFooterView.swift` (`DetailExtensions.translationFooter`) |
| Ticket translation tab (outdated / failure banners, skeleton, empty state, Description + Markdown with authenticated images, "via OpenCode") | lib/shared/detail/presentation/widgets/translation_tab.dart | App `TranslationTabView.swift` + `TranslationViews.swift` (`TranslationHub`, `TranslationTabModel`) |
| Tests (readiness, settings logic) | test/features/translation/* | Tests/FeatureTranslationTests/TranslationSettingsTests.swift |
