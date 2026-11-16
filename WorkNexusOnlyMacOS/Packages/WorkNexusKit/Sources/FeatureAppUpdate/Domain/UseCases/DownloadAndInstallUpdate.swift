import CoreDomain

/// Ported from: lib/features/app_update/domain/usecases/{download_update,install_update}.dart
public struct DownloadUpdate: Sendable {
    private let repository: UpdateRepository
    public init(_ repository: UpdateRepository) { self.repository = repository }
    public func callAsFunction(_ update: AvailableUpdate, onProgress: @escaping @Sendable (Double) -> Void = { _ in }) async -> Outcome<String> {
        await repository.download(update, onProgress: onProgress)
    }
}

public struct InstallUpdate: Sendable {
    private let repository: UpdateRepository
    public init(_ repository: UpdateRepository) { self.repository = repository }
    public func callAsFunction(stagedPath: String) async -> Outcome<Void> { await repository.install(stagedPath: stagedPath) }
}
