import XCTest
@testable import FeatureChat

/// Port of test/data/chat/api_scheme_codec_test.dart: golden cases produced by the original JS optimizer.
final class ApiSchemeCodecTests: XCTestCase {
    func testRealSchemeCases() throws {
        let scheme = try Fixtures.json("api_scheme.json").object!
        let fixture = try Fixtures.json("codec_cases.json")
        XCTAssertEqual(ApiSchemeCodec(scheme).version, fixture["schemeVersion"]?.string)
        let cases = fixture["cases"]!.array!
        XCTAssertGreaterThan(cases.count, 20)
        for c in cases {
            let name = c["name"]!.string!
            let label = "\(name) #\(c["variant"].map { $0.serialized() } ?? "-")"
            let fallback = c["fallback"]?.string
            let codec = ApiSchemeCodec(scheme)
            if c["schemeError"] == .bool(true) {
                XCTAssertThrowsError(try codec.encode(name, .object(JSONObject())), label)
                continue
            }
            let input = c["input"] ?? .undefined
            if c["encodeError"] != nil {
                XCTAssertThrowsError(try codec.encode(name, input, fallback: fallback), "\(label) encodeError")
                continue
            }
            XCTAssertEqual(try codec.encode(name, input, fallback: fallback), c["encoded"], "\(label) encode")
            if let decoded = c["decoded"] {
                let encoded = c["encoded"]!.array!
                XCTAssertEqual(try codec.decode(.array(encoded)), decoded, "\(label) decode by name")
                XCTAssertEqual(codec.schemeIndexOf(name), c["index"]?.intValue, "\(label) index")
                XCTAssertEqual(try codec.decode(.array([c["index"]!, encoded[1]])), decoded, "\(label) decode by index")
            }
            if let mutatedDecoded = c["mutatedDecoded"] {
                XCTAssertEqual(try ApiSchemeCodec(scheme).decode(c["mutated"]!), mutatedDecoded, "\(label) mutated")
            }
        }
    }

    func testSyntheticEdgeScheme() throws {
        let fixture = try Fixtures.json("edge_cases.json")
        let scheme = fixture["scheme"]!.object!
        for c in fixture["cases"]!.array! {
            let name = c["name"]!.string!
            let fallback = c["fallback"]?.string
            let input = c["input"] ?? .undefined
            let label = "encode/decode \(name) \(input.serialized())"
            let codec = ApiSchemeCodec(scheme)
            if c["error"] != nil {
                XCTAssertThrowsError(try codec.encode(name, input, fallback: fallback), label)
                continue
            }
            XCTAssertEqual(try codec.encode(name, input, fallback: fallback), c["encoded"], label)
            XCTAssertEqual(try ApiSchemeCodec(scheme).decode(c["encoded"]!, fallback: fallback), c["decoded"], label)
        }
        for c in fixture["decodes"]!.array! {
            let codec = ApiSchemeCodec(scheme)
            let label = "decode \(c["encoded"]!.serialized())"
            if c["error"] != nil { XCTAssertThrowsError(try codec.decode(c["encoded"]!), label); continue }
            XCTAssertEqual(try codec.decode(c["encoded"]!), c["decoded"], label)
        }
        let index = fixture["index"]!
        XCTAssertEqual(ApiSchemeCodec(scheme).schemeIndexOf(index["name"]!.string!), index["index"]?.intValue)
    }

    func testDecodingWithoutASchemeNameThrows() throws {
        let scheme = try Fixtures.json("edge_cases.json")["scheme"]!.object!
        XCTAssertThrowsError(try ApiSchemeCodec(scheme).decode([9999, []]))
        XCTAssertThrowsError(try ApiSchemeCodec(scheme).decode("not an array"))
    }

    func testJSONRoundTripKeepsKeyOrderAndNumberKinds() throws {
        let text = #"{"b":1,"a":[1.5,true,null,"x\né"],"c":{"z":0,"y":-3}}"#
        let v = try JSONValue.parse(text)
        XCTAssertEqual(v.serialized(), #"{"b":1,"a":[1.5,true,null,"x\n\#u{e9}"],"c":{"z":0,"y":-3}}"#)
        XCTAssertEqual(v["b"], .int(1))
        XCTAssertEqual(JSONValue.int(1), .double(1))
    }
}
