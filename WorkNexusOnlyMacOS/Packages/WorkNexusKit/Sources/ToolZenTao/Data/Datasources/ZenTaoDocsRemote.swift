import Foundation

/// Ported from: lib/tools/zentao/data/datasources/zentao_docs_remote.dart
/// The ZenTao REST v1 document endpoints. Only REST v1 is used: on ZenTao 21.x the classic `doc-*.json` pages
/// are rendered client-side and carry no document data.
struct ZenTaoDocsRemote {
    let client: ZenTaoClient

    var baseUrl: String { client.baseUrl }

    func libs() async throws -> JSON { try await client.getV1Json("/doclibs") }
    func docs(_ libId: String) async throws -> JSON { try await client.getV1Json("/docs", query: [("lib", libId)]) }
    func doc(_ docId: String) async throws -> JSON { try await client.getV1Json("/docs/\(docId)") }

    /// The document's history (classic `action-ajaxGetList-doc-{id}`: REST v1 has none), wrapped as `{actions: [...]}`.
    func history(_ docId: String) async throws -> JSON {
        guard let list = try await client.getClassicJson("action-ajaxGetList-doc-\(docId)") as? [Any] else {
            throw ZenTaoError.format("ZenTao sent no document history")
        }
        return ["actions": list]
    }

    func image(_ url: String) async throws -> Data? { try await client.fetchBytes(url) }
    func download(_ url: String) async throws -> Data? { try await client.downloadBytes(url) }
}
