# Flutter → Swift porting rules

Clean Architecture, feature-first, as in the parent repository's `AGENTS.md`. Every Swift file starts with `/// Ported from: <dart path>` (recorded in `PORT_MAP.md`).

## Layout (Packages/WorkNexusKit/Sources)
`CoreDomain` (Foundation only) · `CorePersistence` (GRDB, Keychain) · `CoreUI` (theme, components) · `CoreTools` (ToolModule, nav, `AppServices`) · `SharedKit` (shell, board, detail, sync) · `ToolZenTao|GitLab|GitHub` · `Feature*`.
Inside each tool/feature: `Domain/ Data/ Presentation/` (the folder names must be exactly these — `ArchitectureTests` relies on them).
- `Domain/`: no SwiftUI/AppKit/GRDB/CorePersistence imports; returns `Outcome<T>`, never throws across a layer boundary.
- `Presentation/`: no GRDB/CorePersistence imports; calls protocols only (`AppServices`), ≤ 300 lines per file. Split views into their own structs, not `func xxxView() -> some View`.
- Every other file ≤ 400 lines. One repository per file. DTOs do not leak out of `Data/`.
- Colours/spacing/radii/fonts come only from `@Environment(\.appTheme)`; UI strings go through l10n keys in `Localizable.xcstrings` (generated from `lib/l10n/*.arb`).
- Extending the database: a module registers its own migration through `MigrationRegistrar` (named `"<module>_v1"`), and the composition root passes it to `AppDatabase.open(registrars:)`. Do not edit `CoreMigrations`.
- Tools/features do not import each other (the target graph forbids it); they talk through `CoreDomain`/`CoreTools`/`AppServices`.

## Workflow
- Build/test one target at a time: `cd Packages/WorkNexusKit && swift build --scratch-path <own> --target X && swift test --scratch-path <own> --filter XTests`.
- Tests: port the matching Dart test (`test/...`) as test vectors — codecs/parsers/mappers above all. Mock at the protocol boundary.
- Do not edit `App/`, `Package.swift`, `project.yml`, or someone else's target. Each module exposes exactly one entry point for the composition root to wire (e.g. `ZentaoModule`); nothing registers itself.
- Swift language mode 5, `@MainActor` for `@Observable` view models.
- Each module records its port table in `PortMap/<Module>.md` (same format as PORT_MAP.md) — do not edit PORT_MAP.md.
