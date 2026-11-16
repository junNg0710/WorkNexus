import CoreDomain
import XCTest
@testable import FeatureMiniApps

// MARK: mini_app_dialog.dart, mini_app_permissions_section.dart, trusted_certificates_controller.dart, mini_app_browsing_data_controller.dart

private final class FixtureBrowsingData: MiniAppBrowsingDataRepository, @unchecked Sendable {
    var canClear = true
    var fail = false
    private(set) var calls: [String] = []
    func clearCache() async -> Outcome<Void> { calls.append("cache"); return fail ? .failure(.storage("x")) : .success(()) }
    func clearSite(url: String) async -> Outcome<Void> { calls.append("site:\(url)"); return fail ? .failure(.storage("x")) : .success(()) }
    func clearAll(urls: [String]) async -> Outcome<Void> { calls.append("all:\(urls.count)"); return fail ? .failure(.storage("x")) : .success(()) }
}

@MainActor
final class MiniAppFormModelTests: XCTestCase {
    func testAddingNamesTheAppAfterItsHostAndOpensIt() async throws {
        let h = try await Harness()
        await h.seed([app("a", "https://a.io")])
        let form = MiniAppFormModel(model: h.model)
        XCTAssertFalse(form.canSave, "no address yet")
        form.url = "  www.example.com/zentao  "
        XCTAssertTrue(form.canSave)
        let added = await form.save()
        XCTAssertEqual(added?.name, "example.com"); XCTAssertEqual(added?.url, "https://www.example.com/zentao")
        XCTAssertEqual(added?.position, 1, "last on the rail")
        XCTAssertNil(form.error); XCTAssertFalse(form.saving)
        await h.settle { h.model.apps.count == 2 }
        XCTAssertEqual(h.model.apps.map(\.id).count, 2)
    }

    func testABadAddressIsAnErrorInTheUsersWordsUntilItIsTypedAgain() async throws {
        let h = try await Harness()
        await h.seed([])
        let form = MiniAppFormModel(model: h.model)
        form.url = "not a url"
        let none = await form.save()
        XCTAssertNil(none)
        XCTAssertEqual(form.error, "Enter a web address such as example.com")
        form.clearError(); XCTAssertNil(form.error)
    }

    func testEditingAppliesTheNewAddressNameAndIcon() async throws {
        let h = try await Harness()
        var a = app("a", "https://a.io"); a.lastUrl = "https://a.io/last"; a.iconPath = "/icons/a.png"
        await h.seed([a])
        let form = MiniAppFormModel(model: h.model, existing: a)
        XCTAssertEqual(form.url, "https://a.io"); XCTAssertEqual(form.name, "A"); XCTAssertEqual(form.iconPath, "/icons/a.png")
        form.name = "  Work  "; form.url = "b.io"
        let saved = await form.save()
        XCTAssertEqual(saved?.name, "Work"); XCTAssertEqual(saved?.url, "https://b.io")
        XCTAssertNil(saved?.lastUrl, "a new address starts from its own page")
        XCTAssertEqual(saved?.iconPath, "/icons/a.png"); XCTAssertEqual(saved?.id, "a")
        await h.settle { h.model.apps.first?.name == "Work" }
        XCTAssertEqual(h.model.apps.first?.name, "Work")
    }

    func testEnterWithNoAddressDoesNothing() async throws {
        let h = try await Harness()
        await h.seed([])
        let form = MiniAppFormModel(model: h.model)
        form.url = "   "
        let none = await form.save()
        XCTAssertNil(none); XCTAssertNil(form.error)
    }

    func testTheIconComesFromAnImageOrTheSiteAndAFailureStaysInline() async throws {
        let h = try await Harness()
        let a = app("a", "https://a.io")
        await h.seed([a])
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("icon_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let image = dir.appendingPathComponent("x.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: image)
        let form = MiniAppFormModel(model: h.model, existing: a)
        await form.importIcon(from: image.path)
        XCTAssertNotNil(form.iconPath); XCTAssertNil(form.error); XCTAssertFalse(form.iconBusy)
        await form.importIcon(from: dir.appendingPathComponent("missing.png").path)
        XCTAssertEqual(form.error, "Couldn't get an icon this way")
        // A site with no icon is a failure too (nothing is reachable from a test).
        let offline = MiniAppFormModel(model: h.model, existing: a)
        offline.url = "http://localhost:9"
        await offline.useSiteIcon()
        XCTAssertEqual(offline.error, "Couldn't get an icon this way")
        // Adding has no icon to change.
        let adding = MiniAppFormModel(model: h.model)
        await adding.importIcon(from: image.path); await adding.useSiteIcon()
        XCTAssertNil(adding.iconPath)
    }
}

@MainActor
final class MiniAppSettingsModelsTests: XCTestCase {
    func testPermissionsAreListedInKindOrderAndFlippedOrForgotten() async throws {
        let h = try await Harness()
        await h.seed([app("a", "https://a.io")])
        let model = MiniAppPermissionsModel(miniAppId: "a", repository: h.feature.permissions)
        let watching = Task { await model.watch() }
        defer { watching.cancel() }
        var ok = await model.remember(.location, .block)
        XCTAssertTrue(ok)
        ok = await model.remember(.camera, .allow)
        XCTAssertTrue(ok)
        await h.settle { model.grants.count == 2 }
        XCTAssertEqual(model.grants.map(\.kind), [.camera, .location], "the order the kinds are listed in")
        ok = await model.remember(.camera, .block)
        XCTAssertTrue(ok)
        await h.settle { model.grants.first?.decision == .block }
        XCTAssertEqual(model.grants.first?.decision, .block)
        ok = await model.forget(.camera)
        XCTAssertTrue(ok)
        await h.settle { model.grants.count == 1 }
        XCTAssertEqual(model.grants.map(\.kind), [.location])
        // The page is asked again for what was forgotten.
        let decision = await h.feature.permissions.decision(miniAppId: "a", kind: .camera).value ?? nil
        XCTAssertNil(decision)
    }

    func testTrustedCertificatesAreListedTrustedAndForgotten() async throws {
        let h = try await Harness()
        let model = TrustedCertificatesModel(repository: h.feature.trustedCertificates)
        await model.load()
        XCTAssertTrue(model.items.isEmpty)
        var ok = await model.trust(origin: "https://a.io:443", error: trustedByChoice)
        XCTAssertTrue(ok)
        ok = await model.trust(origin: "https://b.io:8443", error: "net::ERR_CERT_DATE_INVALID")
        XCTAssertTrue(ok)
        XCTAssertTrue(model.isTrusted("https://a.io:443")); XCTAssertFalse(model.isTrusted("https://c.io:443"))
        let trustedNow = await h.model.isTrusted("https://a.io:443")
        XCTAssertTrue(trustedNow, "the pages see a change at once")
        ok = await model.forget(model.items[0])
        XCTAssertTrue(ok)
        XCTAssertEqual(model.items.map(\.origin), ["https://b.io:8443"])
        ok = await model.forgetAll()
        XCTAssertTrue(ok)
        XCTAssertTrue(model.items.isEmpty)
        let trustedLater = await h.model.isTrusted("https://b.io:8443")
        XCTAssertFalse(trustedLater)
    }

    func testTheCertificateReasonsAreTheSameAsThePrompts() {
        XCTAssertEqual(MiniAppTrustedCertificatesSection.reason(trustedByChoice), "Trusted from the mini app's settings, without a prompt")
        XCTAssertEqual(MiniAppTrustedCertificatesSection.reason("net::ERR_CERT_DATE_INVALID"), "has expired, or is not valid yet")
        XCTAssertTrue(MiniAppTrustedCertificatesSection.reason("net::ERR_CERT_REVOKED").contains("net::ERR_CERT_REVOKED"))
    }

    func testClearingDataReloadsTheOpenPagesOfTheClearedApps() async throws {
        let h = try await Harness()
        await h.seed([app("a", "https://a.io"), app("b", "https://b.io")])
        h.model.show("a"); h.model.show("b")
        let apps = h.model.apps
        let pa = FixturePageDriver(), pb = FixturePageDriver()
        h.model.tabsModel(for: apps[0]).selected.attach(pa); h.model.tabsModel(for: apps[1]).selected.attach(pb)
        let data = FixtureBrowsingData()
        let model = MiniAppBrowsingDataModel(data: data, model: h.model)
        var ok = await model.clearSite(apps[0])
        XCTAssertTrue(ok); XCTAssertEqual([pa.reloads, pb.reloads], [1, 0])
        ok = await model.clearCache(apps)
        XCTAssertTrue(ok); XCTAssertEqual([pa.reloads, pb.reloads], [2, 1])
        ok = await model.clearAll(apps)
        XCTAssertTrue(ok); XCTAssertEqual([pa.reloads, pb.reloads], [3, 2])
        XCTAssertEqual(data.calls, ["site:https://a.io", "cache", "all:2"])
        XCTAssertNil(model.running)
    }

    func testAFailedClearReloadsNothingAndSaysSo() async throws {
        let h = try await Harness()
        await h.seed([app("a", "https://a.io")])
        h.model.show("a")
        let page = FixturePageDriver(); h.model.tabsModel(for: h.model.apps[0]).selected.attach(page)
        let data = FixtureBrowsingData(); data.fail = true
        let model = MiniAppBrowsingDataModel(data: data, model: h.model)
        let ok = await model.clearCache(h.model.apps)
        XCTAssertFalse(ok); XCTAssertEqual(page.reloads, 0); XCTAssertNil(model.running)
        data.canClear = false
        XCTAssertFalse(model.canClear)
    }
}
