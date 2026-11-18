import CoreDomain
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import FeaturePets

/// Installing pets into a folder: staged, checked, moved into place; nothing left behind when it fails.
final class DiskPetLibraryTests: XCTestCase {
    private var root: URL!
    private let source = FakePetSource()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("pets-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func png(width: Int, height: Int) -> Data {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
        return data as Data
    }

    private func pet(_ id: String, name: String? = nil, sheet: Data, poster: Data? = nil) -> CatalogPet {
        let sheetURL = URL(string: "https://codex-pets.net/assets/pets/v/1/\(id)/spritesheet.png")!
        let posterURL = URL(string: "https://codex-pets.net/assets/pets/v/1/\(id)/poster.png")!
        source.files[sheetURL] = sheet
        if let poster { source.files[posterURL] = poster }
        return CatalogPet(id: id, displayName: name ?? id, description: "d", kind: .animal, tags: [], ownerHandle: "maker",
                          likeCount: 0, downloadCount: 0, spriteVersion: 2, spritesheetURL: sheetURL, posterURL: posterURL, previewURL: nil)
    }

    private var library: DiskPetLibrary { DiskPetLibrary(root: root, source: source) }

    func testInstallingKeepsTheSheetPosterAndManifest() async throws {
        let p = pet("fox", name: "Fox", sheet: png(width: 1536, height: 2288), poster: png(width: 10, height: 10))
        let installed = try unwrap(await InstallPet(library)(p))
        XCTAssertEqual(installed.spritesheetURL.lastPathComponent, "spritesheet.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.spritesheetURL.path))
        XCTAssertEqual(installed.posterURL?.lastPathComponent, "poster.png")
        let manifest = try JSONDecoder().decode(PetManifestDTO.self, from: Data(contentsOf: root.appendingPathComponent("fox/pet.json")))
        XCTAssertEqual(manifest.id, "fox"); XCTAssertEqual(manifest.source, "codex-pets.net")
        XCTAssertEqual(manifest.ownerHandle, "maker"); XCTAssertEqual(manifest.spriteVersionNumber, 2)
        let listed = try unwrap(await ListInstalledPets(library)())
        XCTAssertEqual(listed, [installed])
        XCTAssertFalse(try stagingLeftovers())
    }

    func testAV1SheetInstallsAndAMissingPosterDoesNotStopIt() async throws {
        let installed = try unwrap(await library.install(pet("old", sheet: png(width: 1536, height: 1872))))
        XCTAssertNil(installed.posterURL)
    }

    func testASheetOfTheWrongSizeIsRejectedAndNothingIsLeft() async throws {
        let outcome = await library.install(pet("bad", sheet: png(width: 512, height: 512)))
        guard case .failure(.validation) = outcome else { return XCTFail("expected a validation failure, got \(outcome)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("bad").path))
        XCTAssertFalse(try stagingLeftovers())
        let notAnImage = await library.install(pet("junk", sheet: Data("nope".utf8)))
        XCTAssertNotNil(notAnImage.failure)
    }

    func testAFailedDownloadIsANetworkFailure() async {
        var p = pet("gone", sheet: Data())
        p.spritesheetURL = URL(string: "https://codex-pets.net/missing.webp")!
        let outcome = await library.install(p)
        guard case .failure(.network) = outcome else { return XCTFail("expected a network failure") }
    }

    func testReinstallingReplacesAndRemovingDeletes() async throws {
        _ = await library.install(pet("fox", name: "Old fox", sheet: png(width: 1536, height: 1872)))
        _ = await library.install(pet("fox", name: "New fox", sheet: png(width: 1536, height: 2288)))
        _ = await library.install(pet("ant", name: "Ant", sheet: png(width: 1536, height: 1872)))
        let listed = try unwrap(await library.list())
        XCTAssertEqual(listed.map(\.displayName), ["Ant", "New fox"])          // by name, the old fox replaced
        _ = try unwrap(await RemovePet(library)(id: "fox"))
        let after = try unwrap(await library.list())
        XCTAssertEqual(after.map(\.id), ["ant"])
        _ = try unwrap(await library.remove(id: "never-there"))        // removing twice is fine
        let outcome = await RemovePet(library)(id: "../x")
        guard case .failure(.validation) = outcome else { return XCTFail("unsafe id removed") }
    }

    func testFoldersWithoutAUsableManifestAreSkipped() async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("empty"), withIntermediateDirectories: true)
        let broken = root.appendingPathComponent("broken")
        try fm.createDirectory(at: broken, withIntermediateDirectories: true)
        try Data("{\"id\":\"broken\",\"displayName\":\"B\",\"description\":\"\",\"spritesheetPath\":\"spritesheet.webp\"}".utf8)
            .write(to: broken.appendingPathComponent("pet.json"))   // names a sheet that is not there
        let none = try unwrap(await library.list())
        XCTAssertEqual(none, [])
        let missingRoot = DiskPetLibrary(root: root.appendingPathComponent("nope"), source: source)
        let noRoot = try unwrap(await missingRoot.list())
        XCTAssertEqual(noRoot, [])
    }

    private func stagingLeftovers() throws -> Bool {
        let staging = root.appendingPathComponent(DiskPetLibrary.stagingName)
        guard FileManager.default.fileExists(atPath: staging.path) else { return false }
        return !(try FileManager.default.contentsOfDirectory(atPath: staging.path)).isEmpty
    }
}
