import CoreDomain
import XCTest
@testable import ToolZenTao

/// Adding a module to a board's tree: the name check, what goes to ZenTao, and the tree afterwards.
final class ZenTaoModuleTests: XCTestCase {
    // MARK: Name

    func testANameIsCheckedAgainstTheModulesUnderTheSameParent() {
        let check = CheckZenTaoModuleName()
        let paths = ["Chat", "Chat/Share", "Wallet"]
        XCTAssertEqual(check("  ", parentPath: nil, paths: paths), .empty)
        XCTAssertEqual(check(String(repeating: "x", count: 61), parentPath: nil, paths: paths), .tooLong)
        XCTAssertNil(check(String(repeating: "x", count: 60), parentPath: nil, paths: paths))
        XCTAssertEqual(check("a/b", parentPath: nil, paths: paths), .hasSlash)
        XCTAssertEqual(check(" chat ", parentPath: nil, paths: paths), .exists, "trimmed, whatever its case")
        XCTAssertEqual(check("Share", parentPath: "Chat", paths: paths), .exists)
        XCTAssertNil(check("Share", parentPath: nil, paths: paths), "another parent's module of that name is no clash")
        XCTAssertNil(check("Share", parentPath: "Wallet", paths: paths))
    }

    func testARefusedNameNeverReachesZenTao() async {
        let editor = RecordingModuleEditor()
        let add = AddZenTaoModule(editor)
        let refused = await add(accountId: "zt1", rootId: "e1", bugs: false, name: "Chat", parent: nil, paths: ["Chat"])
        guard case .failure(.validation) = refused else { return XCTFail("expected a validation failure") }
        XCTAssertEqual(editor.calls, [])
        _ = await add(accountId: "zt1", rootId: "e1", bugs: false, name: "  Share ", parent: (id: "7", path: "Chat"), paths: ["Chat"])
        XCTAssertEqual(editor.calls, ["zt1|e1|task|Share|7"])
    }

    // MARK: ZenTao's module page

    /// A stub ZenTao whose task form lists `modules`, growing by what is posted to the module page when `accepts`.
    private func forms(modules initial: [String: String], accepts: Bool = true,
                       reply: Any = ["result": "success"]) -> (ZenTaoTicketForms, StubServer) {
        let lock = NSLock()
        nonisolated(unsafe) var modules = initial
        let server = StubServer { req in
            if req.path.hasSuffix("/tokens") { return .json(["token": "t"]) }
            if req.path.contains("tree-manageChild") {
                if accepts, let name = req.field("modules[]") { lock.withLock { modules["99"] = "/" + name } }
                return .json(reply)
            }
            if req.path.contains("tree-browse") { return .json(["sons": [["id": "3", "order": "30"], ["id": "4", "order": 20]]]) }
            return .json(["modulePairs": lock.withLock { modules }, "moduleOptionMenu": lock.withLock { modules }])
        }
        return (ZenTaoTicketForms(client: makeClient(server, base: "https://z.example.com/zentao")), server)
    }

    func testAModuleIsPostedToTheModulePageAndTheListIsReadBack() async throws {
        let (f, server) = forms(modules: ["0": "/", "3": "/Chat"])
        let after = try await f.addModule(rootId: "12", bugs: false, name: "Speech To Text", parentId: nil)
        XCTAssertEqual(Set(after.map(\.label)), ["/Chat", "/Speech To Text"])
        let post = try XCTUnwrap(server.requests.last { $0.method == "POST" })
        XCTAssertTrue(post.path.hasSuffix("/tree-manageChild-12-task.json"))
        XCTAssertEqual(post.form["modules[]"], ["Speech To Text"])
        XCTAssertEqual(post.field("parentModuleID"), "0")
        XCTAssertEqual(post.field("maxOrder"), "30", "after the modules already there")
        XCTAssertEqual(post.header("Referer"), "https://z.example.com/zentao/index.html")
        // The execution's own module page was read for the order.
        XCTAssertTrue(server.requests.contains { $0.path.hasSuffix("/tree-browsetask-12-0-0.json") })
    }

    func testABugModuleGoesToTheProductUnderItsParent() async throws {
        let (f, server) = forms(modules: ["3": "/Chat"])
        _ = try await f.addModule(rootId: "5", bugs: true, name: "Share", parentId: "3")
        let post = try XCTUnwrap(server.requests.last { $0.method == "POST" })
        XCTAssertTrue(post.path.hasSuffix("/tree-manageChild-5-bug.json"))
        XCTAssertEqual(post.field("parentModuleID"), "3")
        XCTAssertTrue(server.requests.contains { $0.path.hasSuffix("/tree-browse-5-bug-3.json") })
    }

    /// 18.x answers the page with a script either way: only the list says whether the module was made.
    func testAModuleThatIsNotListedAfterwardsWasNotAdded() async {
        let (f, _) = forms(modules: ["3": "/Chat"], accepts: false, reply: "<script>parent.location.reload()</script>")
        do {
            _ = try await f.addModule(rootId: "12", bugs: false, name: "Location", parentId: nil)
            XCTFail("expected a failure")
        } catch {
            guard case .validation(let message, _) = error as? Failure else { return XCTFail("expected a validation failure") }
            XCTAssertTrue(message.contains("did not add the module"))
        }
    }

    func testWhatZenTaoRefusedIsToldAsItSaidIt() async {
        let (f, _) = forms(modules: ["3": "/Chat"], accepts: false, reply: ["result": "fail", "message": "No privilege"])
        do {
            _ = try await f.addModule(rootId: "12", bugs: false, name: "Location", parentId: nil)
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? Failure, .validation("No privilege"))
        }
        XCTAssertEqual(ZenTaoTicketForms.refusal(["result": "fail", "message": ["name": ["Already there."]]] as JSON), "Already there.")
        XCTAssertNil(ZenTaoTicketForms.refusal(["result": "success"] as JSON))
        XCTAssertNil(ZenTaoTicketForms.refusal("<script>parent.location.reload()</script>"))
    }

    // MARK: The tree

    @MainActor
    func testAnAddedModuleIsInTheTreeEvenWithEmptyModulesHidden() async {
        let editor = RecordingModuleEditor()
        editor.result = [FormOption(value: "3", label: "/Chat"), FormOption(value: "99", label: "/Chat/Share")]
        let env = BoardsEnv(section: ZentaoSection.tasks, moduleEditor: editor)
        env.state.openExecution(env.execution("e1"))
        env.state.moduleNames["t:zt1:e1"] = .loaded([ZentaoModulePath(id: "3", path: "Chat")])
        env.state.hideEmptyModules = true
        XCTAssertEqual(env.state.moduleNameProblem("chat", parentId: nil, bugs: false), .exists)
        XCTAssertNil(env.state.moduleNameProblem("Share", parentId: "3", bugs: false))

        let failure = await env.state.addModule("Share", parentId: "3", bugs: false)
        XCTAssertNil(failure)
        XCTAssertEqual(editor.calls, ["zt1|e1|task|Share|3"])
        XCTAssertEqual(env.state.boardModuleNames(bugs: false).value, [ZentaoModulePath(id: "3", path: "Chat"), ZentaoModulePath(id: "99", path: "Chat/Share")])
        XCTAssertFalse(env.state.hideEmptyModules, "the new module holds nothing yet and must still show")
    }

    @MainActor
    func testARefusalLeavesTheTreeAsItWas() async {
        let editor = RecordingModuleEditor()
        let env = BoardsEnv(section: ZentaoSection.tasks, moduleEditor: editor)
        env.state.openExecution(env.execution("e1"))
        env.state.moduleNames["t:zt1:e1"] = .loaded([ZentaoModulePath(id: "3", path: "Chat")])
        editor.failure = .validation("No privilege")
        let failure = await env.state.addModule("Share", parentId: nil, bugs: false)
        XCTAssertEqual(failure, .validation("No privilege"))
        XCTAssertEqual(env.state.boardModuleNames(bugs: false).value, [ZentaoModulePath(id: "3", path: "Chat")])
    }
}

private final class RecordingModuleEditor: ZenTaoModuleEditor, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    var result: [FormOption] = []
    var failure: Failure?
    var calls: [String] { lock.withLock { recorded } }

    func addModule(accountId: String, rootId: String, bugs: Bool, name: String, parentId: String?) async -> Outcome<[FormOption]> {
        lock.withLock { recorded.append("\(accountId)|\(rootId)|\(bugs ? "bug" : "task")|\(name)|\(parentId ?? "-")") }
        if let failure { return .failure(failure) }
        return .success(result)
    }
}
