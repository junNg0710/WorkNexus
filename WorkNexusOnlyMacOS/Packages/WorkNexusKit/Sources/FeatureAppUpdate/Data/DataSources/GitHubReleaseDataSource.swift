import CryptoKit
import Foundation

/// Ported from: lib/features/app_update/data/datasources/github_release_datasource.dart
public struct GitHubRelease: Sendable, Equatable {
    public var tagName: String
    public var htmlUrl: String
    public var notes: String
    /// Asset name → browser download URL.
    public var assets: [String: String]
    public init(tagName: String, htmlUrl: String, notes: String, assets: [String: String]) {
        self.tagName = tagName; self.htmlUrl = htmlUrl; self.notes = notes; self.assets = assets
    }
}

/// HTTP / hashing seam so the repository is testable without a network.
public protocol GitHubReleaseSource: Sendable {
    func fetchLatestStableRelease() async throws -> GitHubRelease
    func readText(_ url: String) async throws -> String
    func downloadFile(_ url: String, to path: String, onProgress: @escaping @Sendable (Double) -> Void) async throws
    func sha256Of(_ path: String) throws -> String
}

struct ReleaseHTTPError: Error { let status: Int }
struct ReleaseFormatError: Error { let message: String }

public final class GitHubReleaseDataSource: GitHubReleaseSource, @unchecked Sendable {
    private let config: AppUpdateConfig
    private let session: URLSession

    public init(config: AppUpdateConfig, session: URLSession = .shared) {
        self.config = config; self.session = session
    }

    public func fetchLatestStableRelease() async throws -> GitHubRelease {
        var req = URLRequest(url: config.latestReleaseURL)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue(config.appName, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: req)
        try Self.check(response)
        return try Self.parseRelease(data)
    }

    static func parseRelease(_ data: Data) throws -> GitHubRelease {
        guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ReleaseFormatError(message: "Invalid GitHub release response")
        }
        guard let tag = body["tag_name"] as? String, let html = body["html_url"] as? String,
              (body["draft"] as? Bool) == false, (body["prerelease"] as? Bool) == false else {
            throw ReleaseFormatError(message: "GitHub did not return a stable release")
        }
        var assets: [String: String] = [:]
        for a in (body["assets"] as? [Any]) ?? [] {
            guard let m = a as? [String: Any], let n = m["name"] as? String, let u = m["browser_download_url"] as? String else { continue }
            assets[n] = u
        }
        let notes = (body["body"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return GitHubRelease(tagName: tag, htmlUrl: html, notes: notes, assets: assets)
    }

    public func readText(_ url: String) async throws -> String {
        guard let u = URL(string: url) else { throw ReleaseFormatError(message: "Bad URL") }
        let (data, response) = try await session.data(from: u)
        try Self.check(response)
        return String(decoding: data, as: UTF8.self)
    }

    /// Streams to `path`; the long timeout is the download's, not the API's.
    public func downloadFile(_ url: String, to path: String, onProgress: @escaping @Sendable (Double) -> Void) async throws {
        guard let u = URL(string: url) else { throw ReleaseFormatError(message: "Bad URL") }
        var req = URLRequest(url: u)
        req.timeoutInterval = 600
        let delegate = DownloadDelegate(destination: URL(fileURLWithPath: path), onProgress: onProgress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                delegate.continuation = cont
                session.downloadTask(with: req).resume()
            }
        } onCancel: { session.invalidateAndCancel() }
    }

    public func sha256Of(_ path: String) throws -> String {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func check(_ response: URLResponse) throws {
        if let h = response as? HTTPURLResponse, !(200..<300).contains(h.statusCode) { throw ReleaseHTTPError(status: h.statusCode) }
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let destination: URL
    let onProgress: @Sendable (Double) -> Void
    var continuation: CheckedContinuation<Void, Error>?
    private var moveError: Error?

    init(destination: URL, onProgress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination; self.onProgress = onProgress
    }

    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                    totalBytesWritten written: Int64, totalBytesExpectedToWrite total: Int64) {
        if total > 0 { onProgress(Double(written) / Double(total)) }
    }

    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let h = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(h.statusCode) {
            moveError = ReleaseHTTPError(status: h.statusCode); return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
        } catch { moveError = error }
    }

    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let c = continuation; continuation = nil
        if let e = error ?? moveError { c?.resume(throwing: e) } else { c?.resume() }
    }
}
