import Foundation
@testable import FeatureChat

enum Fixtures {
    static func json(_ name: String, file: StaticString = #filePath) throws -> JSONValue {
        let dir = URL(fileURLWithPath: "\(file)").deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/xxd")
        return try JSONValue.parse(data: Data(contentsOf: dir.appendingPathComponent(name)))
    }
}
