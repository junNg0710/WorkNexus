# Quy ước port Flutter → Swift

Clean Architecture feature-first, giống `AGENTS.md` của repo cha. Mỗi file Swift bắt đầu bằng `/// Ported from: <đường dẫn dart>` (ghi vào `PORT_MAP.md`).

## Cấu trúc (Packages/WorkNexusKit/Sources)
`CoreDomain` (thuần Foundation) · `CorePersistence` (GRDB, Keychain) · `CoreUI` (theme, component) · `CoreTools` (ToolModule, nav, `AppServices`) · `SharedKit` (shell, board, detail, sync) · `ToolZenTao|GitLab|GitHub` · `Feature*`.
Trong mỗi tool/feature: `Domain/ Data/ Presentation/` (tên thư mục đúng như vậy — `ArchitectureTests` dựa vào nó).
- `Domain/`: không import SwiftUI/AppKit/GRDB/CorePersistence; trả `Outcome<T>`, không throw qua ranh giới layer.
- `Presentation/`: không import GRDB/CorePersistence; chỉ gọi protocol (`AppServices`), ≤ 300 dòng/file. Tách view bằng struct riêng, không dùng `func xxxView() -> some View`.
- Mọi file khác ≤ 400 dòng. Một repository một file. DTO không rò ra ngoài `Data/`.
- Màu/spacing/radius/font chỉ lấy từ `@Environment(\.appTheme)`; chuỗi UI qua l10n key trong `Localizable.xcstrings` (sinh từ `lib/l10n/*.arb`).
- Mở rộng DB: module tự đăng ký migration qua `MigrationRegistrar` (đặt tên `"<module>_v1"`), composition root truyền vào `AppDatabase.open(registrars:)`. Không sửa `CoreMigrations`.
- Tool/feature không import nhau (target graph chặn); giao tiếp qua `CoreDomain`/`CoreTools`/`AppServices`.

## Quy trình
- Build/test từng target: `cd Packages/WorkNexusKit && swift build --scratch-path <riêng> --target X && swift test --scratch-path <riêng> --filter XTests`.
- Test: port test Dart tương ứng (`test/...`) làm test vector — đặc biệt codec/parser/mapper. Mock ở ranh giới protocol.
- Không sửa `App/`, `Package.swift`, `project.yml`, hay target của người khác. Mỗi module công khai đúng một điểm vào để composition root nối (ví dụ `ZentaoModule`), không tự đăng ký.
- Swift language mode 5, `@MainActor` cho view-model `@Observable`.
- Mỗi module ghi bảng port vào `PortMap/<Module>.md` (cùng định dạng PORT_MAP.md) — không sửa PORT_MAP.md.
