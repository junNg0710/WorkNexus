# FeatureMiniApps (lib/features/mini_apps → Sources/FeatureMiniApps)

Public entry: `MiniAppsFeature` (`make`, `migrationRegistrar`, `.miniApps(feature)`, `MiniAppHostView(miniApp:)`, `MiniAppsHostStack`, `model: MiniAppsModel` = rail data source, `makeCookieImportModel()`).
Views: `MiniAppDialog(feature:existing:onSaved:onClose:)` (add + edit), `CookieImportDialog(cookies:site:source:onClose:)`, `MiniAppSettingsCard(feature:liveLimit:notifyInBackground:dateFormat:onLiveLimit:onNotifyInBackground:)` (all present with `.appDialog`); shared models `feature.cookies` (`CookieImportModel`), internal `trustedModel` / `browsingDataModel`. The rail section lives in `App/Sources/MiniAppViews.swift` (edit, confirm-before-remove, drag to reorder through `MiniAppsModel.move(id:onto:)`); the card is hosted by `App/Sources/Settings/SettingsPages.swift`.
Tabs (new, no Flutter counterpart): see "Tabs" below.
Not ported: Linux web view, Windows-only certificate guard and frame-rate / focus workarounds (WKWebView reports certificate errors itself), the toolbar's developer-tools button (⇧⌘I / F12 and right-click → Inspect Element instead).

## Tabs
Flutter has no tab strip: a page's `window.open` / `target=_blank` goes through `onCreateWindow` (claimed by the link router: dropped; else a 520x720 pop-up). Swift keeps that and adds tabs:
- `MiniAppTabsModel` (one per running app, kept by `MiniAppsModel.tabsModel(for:)`) owns a `MiniAppBrowserModel` per tab (the old per-app browser model is now the per-tab one) — selected tab, new / close / select / next / previous, `maxTabs` = 10 (one web process each; the live-app LRU is unchanged, an app's tabs live and die with it, nothing is persisted). Only the selected tab keeps `lastUrl`.
- Every tab has its own `WKWebView` in the shared `WKWebsiteDataStore` (`MiniAppWebParts.make`), so cookies / sign-in are shared; capabilities (notifications, saved login, permissions, certificates) are per web view through its own bridge. A page-opened tab (`MiniAppWebParts.adopt`) is built from the opener's configuration, so it shares the opener's scripts and bridge and `window.opener` / `window.close()` work.
- A window opened by the page: claimed by the router → nothing; sign-in or sized window → pop-up; link on the app's own site (`IsMiniAppSite`: same host or registrable domain, http(s), not blank) → new tab in front; at the tab limit → pop-up. Middle / ⌘-click on such a link → background tab (⇧ brings it forward).
- Keys (`MiniAppShortcuts` + `MiniAppKeyMonitor`, a local event monitor so ⌘W / ⌘T beat the menu bar): ⌘R / F5, ⇧⌘R / ⌃F5, ⌘L / F6, ⌘[ ⌘] / ⌥← ⌥→, ⌥Home, ⇧⌘I / F12 (private `_inspector`, no-op if absent), ⌘T, ⌘W (the last tab is not closed: the key goes on to the window), ⇧⌘[ ⇧⌘] / ⌃Tab ⌃⇧Tab, mouse back / forward buttons. ⌥← / ⌥→ never take a text field's word-jump (the address field, or a page element that is editable).

| Area | Dart | Swift |
|---|---|---|
| Migration `miniapps_v1` (tables `miniApps`, `miniAppPermissions`) | lib/core/database/database.dart (MiniApps, MiniAppPermissions) | Data/Migrations/MiniAppsMigrations.swift |
| MiniApp entity | domain/entities/mini_app.dart | Domain/Entities/MiniApp.swift |
| Permission kind / decision / grant | domain/entities/mini_app_permission.dart | Domain/Entities/MiniAppPermission.swift |
| TrustedCertificate | domain/entities/trusted_certificate.dart | Domain/Entities/TrustedCertificate.swift |
| BrowserCookie, CookieSource, CookieSite, CookieImport(+State) | domain/entities/{browser_cookie,cookie_source,cookie_site,cookie_import}.dart | Domain/Entities/{BrowserCookie,CookieSource,CookieSite,CookieImport}.swift |
| CookieBrowser, CookieKey, CookieSameSite, cookieSiteOf | domain/value_objects/*.dart | Domain/ValueObjects/{CookieBrowser,CookieKey,CookieSameSite,CookieSiteOf}.swift |
| CertificateProblem (+ NSURLError → `net::ERR_CERT_*`) | domain/value_objects/certificate_problem.dart | Domain/ValueObjects/CertificateProblem.swift |
| Link targets / `findMiniAppForLink` | lib/core/navigation/mini_app_links.dart | Domain/ValueObjects/MiniAppLinkTarget.swift |
| Repository interfaces (+ `PinnedCertificateSource`) | domain/repositories/*.dart, lib/core/domain/repositories/pinned_certificate_repository.dart | Domain/Repositories/Repositories.swift |
| NormalizeMiniAppUrl | domain/usecases/normalize_mini_app_url.dart | Domain/UseCases/NormalizeMiniAppUrl.swift |
| Add / Update / Move / RefreshIcon | domain/usecases/{add,update,move,refresh_mini_app_icon}_mini_app.dart | Domain/UseCases/{AddMiniApp,UpdateMiniApp,MoveMiniApp,RefreshMiniAppIcon}.swift |
| ResolveMiniAppPermission | domain/usecases/resolve_mini_app_permission.dart | Domain/UseCases/ResolveMiniAppPermission.swift |
| IsMiniAppOrigin, IsSignInWindow | domain/usecases/{is_mini_app_origin,is_sign_in_window}.dart | Domain/UseCases/{IsMiniAppOrigin,IsSignInWindow}.swift |
| FindSavedWebLogin (ZenTao login, through `Account` + `CredentialStore`, no ZenTao import) | domain/usecases/find_saved_web_login.dart | Domain/UseCases/FindSavedWebLogin.swift |
| IsPinnedCertificate (SHA-256 of DER) | domain/usecases/is_pinned_certificate.dart | Domain/UseCases/IsPinnedCertificate.swift |
| Live-limit LRU | presentation/util/live_mini_apps.dart | Domain/UseCases/LiveMiniApps.swift |
| Group / Import / Check cookie imports | domain/usecases/{group_cookies_by_site,import_browser_cookies,check_cookie_imports}.dart | Domain/UseCases/{GroupCookiesBySite,ImportBrowserCookies,CheckCookieImports}.swift |
| GRDB rows + mappers | data/mappers/*.dart | Data/Models/{MiniAppRows,MiniAppMappers}.swift |
| MiniApp / permission repositories | data/repositories/local_mini_app{,_permission}_repository.dart (+ datasources) | Data/Repositories/{GRDBMiniAppRepository,GRDBMiniAppPermissionRepository}.swift |
| Icon files | data/datasources/mini_app_icon_storage.dart | Data/DataSources/MiniAppIconStorage.swift |
| Favicon fetching (regex `<link rel=…icon…>`, /favicon.ico) | data/datasources/{favicon_fetcher,site_icon_source}.dart | Data/DataSources/FaviconFetcher.swift |
| Trusted-certificate + cookie-import JSON stores (same file shapes) | data/datasources/{trusted_certificate_store,cookie_import_store}.dart, data/repositories/local_{trusted_certificate,cookie_import}_repository.dart | Data/DataSources/JSONFileStores.swift, Data/Repositories/{FileTrustedCertificateRepository,FileCookieImportRepository}.swift |
| Chromium cookie crypto (PBKDF2-SHA1 `saltysalt`/1003, AES-128-CBC, v10/v11, v24 domain hash) | data/datasources/browser_cookies/chromium_cookie_crypto.dart | Data/DataSources/BrowserCookies/ChromiumCookieCrypto.swift |
| Chromium reader (Local State names, `security find-generic-password`, WAL copy) | …/chromium_cookie_reader.dart, sqlite_snapshot.dart | Data/DataSources/BrowserCookies/{ChromiumCookieReader,SQLiteSnapshot}.swift |
| Firefox reader (profiles.ini, moz_cookies) | …/firefox_cookie_reader.dart | Data/DataSources/BrowserCookies/FirefoxCookieReader.swift |
| Safari reader + `Cookies.binarycookies` parser | …/safari_cookie_reader.dart | Data/DataSources/BrowserCookies/SafariCookieReader.swift |
| Browser cookie repository (+ refused-access mapping) | data/repositories/local_browser_cookie_repository.dart | Data/Repositories/LocalBrowserCookieRepository.swift |
| Cookie injection incl. HttpOnly (WKHTTPCookieStore) | data/datasources/web_view_cookie_datasource.dart, data/repositories/local_web_view_cookie_repository.dart | Data/DataSources/WebViewCookieDataSource.swift, Data/Repositories/WKWebViewCookieRepository.swift |
| Browsing data (WKWebsiteDataStore) | data/datasources/web_profile_datasource.dart, data/repositories/local_mini_app_browsing_data_repository.dart | Data/DataSources/WebViewCookieDataSource.swift (`WebProfileDataSource`), Data/Repositories/WKMiniAppBrowsingDataRepository.swift |
| Rail data source, running pages, links, notification taps | presentation/widgets/mini_apps_host.dart, providers/mini_app_providers.dart | Presentation/Providers/{MiniAppsModel,MiniAppsServices}.swift |
| Per-tab browsing state (+ the app's tabs) | presentation/providers/{mini_app_browser_controller,mini_app_browser_state}.dart | Presentation/Providers/{MiniAppBrowserModel,MiniAppTabsModel}.swift |
| Cookie-import controller | presentation/providers/cookie_import_controller.dart, util/cookie_browser_name.dart | Presentation/Providers/CookieImportModel.swift |
| Cookie dialog (state + view), site picker, feedback (toast, Safari Full Disk Access link, keychain hint) | widgets/{cookie_import_dialog,cookie_site_picker,cookie_import_feedback}.dart | Providers/CookieImportDialogModel.swift, Widgets/{CookieImportDialog,CookieSitePicker}.swift, Util/CookieImportFeedback.swift |
| Toolbar cookie button (expired tint), settings imports section | widgets/mini_app_cookie_button.dart, mini_app_cookie_imports_section.dart | Widgets/{MiniAppCookieButton,MiniAppCookieImportsSection}.swift |
| Add / edit dialog, icon picker | widgets/mini_app_dialog.dart, mini_app_icon_picker.dart | Providers/MiniAppFormModel.swift, Widgets/{MiniAppDialog,MiniAppFormField,MiniAppIconPicker}.swift |
| Permissions / certificate sections, trusted certificates list | widgets/mini_app_{permissions,certificate,trusted_certificates}_section.dart, providers/trusted_certificates_controller.dart | Providers/{MiniAppPermissionsModel,TrustedCertificatesModel}.swift, Widgets/{MiniAppPermissionsSection,MiniAppCertificateSection,MiniAppTrustedCertificatesSection}.swift |
| Browsing data (clear cache / all / site) | providers/mini_app_browsing_data_controller.dart | Providers/MiniAppBrowsingDataModel.swift, Widgets/MiniAppDataActions.swift |
| Settings card + app list, expandable card | widgets/mini_app_settings_{card,app_list}.dart, core/widgets/app_expandable_card.dart | Widgets/{MiniAppSettingsCard,MiniAppSettingsAppList}.swift, CoreUI/Widgets/Misc/AppExpandableCard.swift (new) |
| Rail section (edit, confirm remove, drag reorder) | widgets/mini_app_rail_section.dart | App/Sources/MiniAppViews.swift |
| Browser keys | util/mini_app_shortcuts.dart | Util/{MiniAppShortcuts,MiniAppKeyMonitor,MiniAppInspector}.swift |
| Tab strip, tab page, link → tab decision | (none) | Widgets/{MiniAppTabStrip,MiniAppTabPage}.swift, Domain/UseCases/IsMiniAppSite.swift, `MiniAppsModel.opensAsTab` |
| Page capability protocol + bridge (`window.webkit.messageHandlers.wnBridge`, token + main-frame check) | presentation/util/mini_app_page_capability.dart, mini_app_page_token.dart | Presentation/Util/MiniAppPageCapability.swift |
| Notification API shim → OS notification | presentation/util/mini_app_notifications.dart | Presentation/Util/{MiniAppScripts,MiniAppNotificationCapability}.swift |
| ZenTao login-form auto-fill | presentation/util/mini_app_login_capability.dart | Presentation/Util/{MiniAppScripts,MiniAppLoginCapability}.swift |
| Permission prompt (ask once, dedupe, wait until shown) | presentation/util/ask_mini_app_permission.dart, widgets/mini_app_permission_dialog.dart | Presentation/Util/MiniAppPermissionPrompter.swift |
| Permission kind names/icons, WebKit media-capture mapping | presentation/util/mini_app_permission_kind.dart | Presentation/Util/MiniAppPermissionKindView.swift |
| Certificate trust prompt | presentation/util/mini_app_certificate_prompt.dart, mini_app_certificate_guard.dart | Presentation/Util/MiniAppCertificatePrompt.swift, Presentation/Widgets/MiniAppWebDelegate.swift (server-trust challenge) |
| WKWebView host, delegates, popups, JS dialogs, file chooser, camera/mic | presentation/widgets/mini_app_web_view.dart, mini_app_popup.dart, util/in_app_web_view_page.dart | Presentation/Widgets/{MiniAppWebView,MiniAppWebDelegate,MiniAppWebDelegate+UI,MiniAppPopupView}.swift, Presentation/Util/WKMiniAppPage.swift, Presentation/Providers/MiniAppPopupWindow.swift |
| Browser bar, error cover, icon, host view, keep-alive stack | presentation/widgets/{mini_app_toolbar,mini_app_load_error,mini_app_icon,mini_app_view,mini_apps_host}.dart, util/mini_app_shortcuts.dart | Presentation/Widgets/{MiniAppToolbar,MiniAppLoadErrorView,MiniAppIconView,MiniAppHostView,MiniAppsHostStack}.swift |
| Route a page-opened window link | presentation/util/route_mini_app_window_link.dart | Presentation/Providers/MiniAppsModel.swift (`routeWindowLink`) |
| Tests | test/features/mini_apps/** | Tests/FeatureMiniAppsTests/{FeatureMiniAppsTests,MiniAppsCookieTests,MiniAppsDataTests,MiniAppsPresentationTests,MiniAppsTabsTests,MiniAppsCookieViewsTests,MiniAppsFormTests,MiniAppsRenderTests}.swift (+ MiniAppsFixtures.swift); renders in /tmp/wn-mini-render |
