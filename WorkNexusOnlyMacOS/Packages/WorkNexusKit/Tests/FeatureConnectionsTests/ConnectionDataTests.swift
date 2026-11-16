import CoreDomain
import CorePersistence
import GRDB
import XCTest
@testable import FeatureConnections

final class ConnectionDataTests: XCTestCase {
    private var db: AppDatabase!

    override func setUp() async throws {
        db = try AppDatabase.inMemory(registrars: [Self.extraTables])
    }

    /// Stand-ins for tables other modules own (ZenTao / chat), to prove the cascade and the cache list reach them.
    private static let extraTables: MigrationRegistrar = { m in
        m.registerMigration("test_extra") { d in
            for t in ["zenTaoProfiles", "dashboardSnapshots", "zenTaoNotifications", "sourceListSnapshots", "chatMessages"] {
                try d.execute(sql: "CREATE TABLE \(t) (accountId TEXT, x TEXT)")
            }
        }
    }

    private func seed() async throws {
        try await db.writer.write { d in
            try d.execute(sql: "INSERT INTO workspaces (id,name,shortCode,colorValue,iconKey,isPersonal,sortOrder) VALUES ('w1','One','O',1,'briefcase',0,0),('w2','Two','T',2,'briefcase',0,1)")
            try d.execute(sql: "INSERT INTO accounts (id,workspaceId,providerType,handle,baseUrl,credentialsRef) VALUES ('a1','w1','zentao','u','https://z','secret:a1'),('a2','w2','gitlab','v','https://g','secret:a2')")
            try d.execute(sql: "INSERT INTO projects (id,accountId,name) VALUES ('p1','a1','P1'),('p2','a2','P2')")
            for (id, acc) in [("t1", "a1"), ("t2", "a2")] {
                try d.execute(sql: "INSERT INTO tickets (id,accountId,projectId,providerType,externalKey,title,body,priorityLevel,statusNorm,providerStatus,sourceHash) VALUES (?,?,?, 'zentao','k','T','B',1,'todo','s','h')",
                              arguments: [id, acc, "p"])
                try d.execute(sql: "INSERT INTO comments (id,ticketId,authorName,body,createdAt) VALUES (?,?, 'x','y', CURRENT_TIMESTAMP)", arguments: ["c-" + id, id])
                try d.execute(sql: "INSERT INTO activities (id,ticketId,actor,action,at) VALUES (?,?, 'x','y', CURRENT_TIMESTAMP)", arguments: ["ac-" + id, id])
                try d.execute(sql: "INSERT INTO translations (ticketId,sourceHash,targetLang,translatedTitle,translatedBody,model,templateVersion,createdAt) VALUES (?, 'h','vi','a','b','m','1', CURRENT_TIMESTAMP)", arguments: [id])
            }
            try d.execute(sql: "INSERT INTO zenTaoProfiles (accountId,x) VALUES ('a1','p'),('a2','p')")
        }
    }

    private func count(_ table: String, _ whereSql: String = "1") async throws -> Int {
        try await db.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM \(table) WHERE \(whereSql)") ?? -1 }
    }

    func testAddAccountUpserts() async throws {
        let repo = GRDBConnectionRepository(db: db)
        var a = Account(id: "a1", workspaceId: "w1", providerType: .github, handle: "me", baseUrl: "https://github.com", credentialsRef: "secret:a1")
        let ok1 = await repo.addAccount(a).value
        XCTAssertNotNil(ok1)
        a.handle = "me2"
        let ok2 = await repo.addAccount(a).value
        XCTAssertNotNil(ok2)
        let rows = try await db.writer.read { try Row.fetchAll($0, sql: "SELECT handle FROM accounts") }
        XCTAssertEqual(rows.map { $0["handle"] as String }, ["me2"])
    }

    func testAddWorkspaceAppendsAndKeepsOrderOnUpdate() async throws {
        let repo = GRDBConnectionRepository(db: db)
        _ = await repo.addWorkspace(Workspace(id: "a", name: "A", shortCode: "A", colorValue: 1))
        _ = await repo.addWorkspace(Workspace(id: "b", name: "B", shortCode: "B", colorValue: 2))
        _ = await repo.addWorkspace(Workspace(id: "a", name: "A2", shortCode: "A", colorValue: 1))
        _ = await repo.updateWorkspace(Workspace(id: "b", name: "B2", shortCode: "B", colorValue: 5, iconKey: "rocket"))
        let rows = try await db.writer.read { try Row.fetchAll($0, sql: "SELECT id,name,colorValue,iconKey,sortOrder FROM workspaces ORDER BY sortOrder") }
        XCTAssertEqual(rows.map { $0["id"] as String }, ["a", "b"])
        XCTAssertEqual(rows.map { $0["name"] as String }, ["A2", "B2"])
        XCTAssertEqual(rows[1]["iconKey"] as String, "rocket")
        XCTAssertEqual(rows.map { $0["sortOrder"] as Int }, [0, 1])
    }

    func testRemoveAccountDropsItsRowsOnly() async throws {
        try await seed()
        let ok3 = await GRDBConnectionRepository(db: db).removeAccount(id: "a1").value
        XCTAssertNotNil(ok3)
        for t in ["accounts", "projects", "tickets", "comments", "activities", "translations", "zenTaoProfiles"] {
            let n = try await count(t)
            XCTAssertEqual(n, t == "accounts" || t == "projects" || t == "zenTaoProfiles" ? 1 : 1, t)
        }
        let left = try await db.writer.read { try String.fetchAll($0, sql: "SELECT id FROM tickets") }
        XCTAssertEqual(left, ["t2"])
    }

    func testDeleteWorkspaceCascadesAndReturnsCredentialRefs() async throws {
        try await seed()
        let refs = await GRDBConnectionRepository(db: db).deleteWorkspace(id: "w1").value
        XCTAssertEqual(refs, ["secret:a1"])
        let w = try await count("workspaces"), a = try await count("accounts"), t = try await count("tickets")
        let c = try await count("comments"), p = try await count("zenTaoProfiles")
        XCTAssertEqual([w, a, t, c, p], [1, 1, 1, 1, 1])
    }

    func testClearKeepsAccountsAndOnlyClearsPickedSections() async throws {
        try await seed()
        let repo = GRDBLocalCacheRepository(db: db)
        let r = await ClearLocalCache(repo)([.tickets, .chat])   // chat: a table that exists here; others absent are skipped
        XCTAssertNotNil(r.value)
        for t in ["tickets", "comments", "activities", "projects"] { let n = try await count(t); XCTAssertEqual(n, 0, t) }
        let kept = try await count("translations"), prof = try await count("zenTaoProfiles"), acc = try await count("accounts"), ws = try await count("workspaces")
        XCTAssertEqual([kept, prof, acc, ws], [2, 2, 2, 2])
        _ = await ClearLocalCache(repo)([.translations, .dashboard])
        let tr = try await count("translations"), pr = try await count("zenTaoProfiles")
        XCTAssertEqual([tr, pr], [0, 0])
        let acc2 = try await count("accounts")
        XCTAssertEqual(acc2, 2)
    }

    func testEmptySelectionDoesNothing() async throws {
        try await seed()
        let ok4 = await ClearLocalCache(GRDBLocalCacheRepository(db: db))([]).value
        XCTAssertNotNil(ok4)
        let n = try await count("tickets")
        XCTAssertEqual(n, 2)
    }

    func testSectionTablesMatchFlutter() {
        XCTAssertEqual(GRDBLocalCacheRepository.tables(of: .tickets), ["comments", "activities", "tickets", "projects", "sourceListSnapshots"])
        XCTAssertEqual(GRDBLocalCacheRepository.tables(of: .dashboard), ["dashboardSnapshots", "zenTaoNotifications", "zenTaoProfiles"])
        XCTAssertEqual(GRDBLocalCacheRepository.tables(of: .translations), ["translations", "chatMessageTranslations"])
        XCTAssertEqual(CacheSection.allCases.count, 4)
    }
}
