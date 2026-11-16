import CoreDomain
import CorePersistence
import GRDB
import XCTest
@testable import FeatureChat

/// Port of the intent of chat_credentials_resolver.dart: xxd matches the account case-sensitively, so chat signs in with
/// the account name ZenTao reports (stored profile), falling back to the typed handle.
final class ChatCredentialsResolverTests: XCTestCase {
    private func setUp(profileJson: String?, handle: String) async throws -> ChatCredentialsResolver {
        let db = try AppDatabase.inMemory(registrars: [ChatMigrations.registrar, { m in
            m.registerMigration("test_profiles") { d in
                try d.create(table: "zenTaoProfiles") { t in t.primaryKey("accountId", .text); t.column("profileJson", .text).notNull() }
            }
        }])
        try await db.writer.write { d in
            try d.execute(sql: "INSERT INTO accounts(id, workspaceId, providerType, handle, baseUrl, credentialsRef) VALUES ('a','w','zentao',?,'https://zt.example.com','secret:a')", arguments: [handle])
            if let profileJson { try d.execute(sql: "INSERT INTO zenTaoProfiles(accountId, profileJson) VALUES ('a', ?)", arguments: [profileJson]) }
        }
        let store = InMemoryCredentialStore()
        _ = await store.write("secret:a", value: "pw")
        return ChatCredentialsResolver(local: ChatLocalDatasource(db: db), store: store)
    }

    func testUsesTheAccountNameZenTaoReports() async throws {
        let r = try await setUp(profileJson: #"{"profile":{"account":" Abc "}}"#, handle: "abc")
        let out = await r.resolve("a")
        let c = try XCTUnwrap(out.value)
        XCTAssertEqual(c.account, "Abc")
        XCTAssertEqual(c.password, "pw")
        XCTAssertEqual(c.server.absoluteString, "https://zt.example.com:11443")
    }

    func testFallsBackToTheHandleWithoutAProfile() async throws {
        let r = try await setUp(profileJson: nil, handle: "abc")
        let out = await r.resolve("a")
        let c = try XCTUnwrap(out.value)
        XCTAssertEqual(c.account, "abc")
    }
}
