import CoreDomain

/// Not in the Flutter app. Names a Mac app on the rail and gives it an icon of the user's: an empty name goes back to the
/// app's own, and a nil icon to the app's own icon (the file of the one it had is forgotten).
public struct EditNativeApp: Sendable {
    private let repository: NativeAppRepository
    public init(_ repository: NativeAppRepository) { self.repository = repository }

    public func callAsFunction(_ app: NativeApp, name: String, iconPath: String?) async -> Outcome<NativeApp> {
        var next = app
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        next.customName = trimmed.isEmpty || trimmed == app.name ? nil : trimmed
        next.iconPath = iconPath
        guard next != app else { return .success(app) }
        if case .failure(let f) = await repository.save(next) { return .failure(f) }
        if iconPath == nil, app.iconPath != nil { await repository.deleteIcon(id: app.id) }
        return .success(next)
    }
}
