import AppKit
import SwiftUI
import XCTest
@testable import FeatureChat

/// The one-pass stacks of a message row put their children where the stacks they replace did.
@MainActor
final class ChatRowLayoutsTests: XCTestCase {
    private final class Frames { var byName: [String: CGRect] = [:] }

    /// Lays `view` out `width` wide and returns the frames of the views tagged with `mark`, in the root's space.
    private func frames<V: View>(_ width: CGFloat, @ViewBuilder _ view: (Frames) -> V) async throws -> [String: CGRect] {
        let box = Frames()
        let host = NSHostingView(rootView: view(box).frame(width: width, alignment: .topLeading).fixedSize(horizontal: false, vertical: true)
            .coordinateSpace(name: "root"))
        host.frame = NSRect(x: 0, y: 0, width: width, height: 600)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(120))
        return box.byName
    }

    private func mark<V: View>(_ view: V, _ name: String, _ box: Frames) -> some View {
        view.background(GeometryReader { g in Color.clear.onAppear { box.byName[name] = g.frame(in: .named("root")) } })
    }

    private let long = String(repeating: "một đoạn chữ dài để phải xuống dòng ", count: 9)

    private func assertSame(_ a: [String: CGRect], _ b: [String: CGRect], _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Set(a.keys), Set(b.keys), what, file: file, line: line)
        for (name, fa) in a {
            guard let fb = b[name] else { continue }
            for (x, y) in [(fa.minX, fb.minX), (fa.minY, fb.minY), (fa.width, fb.width), (fa.height, fb.height)] {
                XCTAssertEqual(x, y, accuracy: 0.6, "\(what): \(name) \(fa) vs \(fb)", file: file, line: line)
            }
        }
    }

    func testAColumnPlacesItsChildrenAsAVStackWithoutSpacingDoes() async throws {
        for trailing in [false, true] {
            for width: CGFloat in [260, 520, 900] {
                let old = try await frames(width) { box in
                    VStack(alignment: trailing ? .trailing : .leading, spacing: 0) {
                        mark(Text("Tên"), "name", box)
                        mark(Text(long).fixedSize(horizontal: false, vertical: true), "text", box)
                        mark(Color.gray.frame(maxWidth: .infinity, minHeight: 12, maxHeight: 12), "fills", box)
                        mark(Text("12:30").padding(.top, 4), "time", box)
                    }
                }
                let new = try await frames(width) { box in
                    ChatColumn(trailing: trailing) {
                        mark(Text("Tên"), "name", box)
                        mark(Text(long).fixedSize(horizontal: false, vertical: true), "text", box)
                        mark(Color.gray.frame(maxWidth: .infinity, minHeight: 12, maxHeight: 12), "fills", box)
                        mark(Text("12:30").padding(.top, 4), "time", box)
                    }
                }
                assertSame(old, new, "column, trailing \(trailing), \(width) wide")
            }
        }
    }

    func testAColumnHugsItsWidestChild() async throws {
        let f = try await frames(900) { box in
            mark(ChatColumn { Text("ngắn"); Text("dài hơn một chút") }, "column", box)
        }
        XCTAssertLessThan(f["column"]?.width ?? 900, 200, "as wide as the widest child, not as what it was offered")
    }

    func testTheRowSidesPlaceAvatarAndMessageAsTheStackWithSpacersDid() async throws {
        for alignEnd in [false, true] {
            for hasAvatar in [false, true] {
                for bottom in [false, true] {
                    for text in ["ok", long] {
                        let old = try await frames(700) { box in
                            HStack(alignment: bottom ? .bottom : .top, spacing: 0) {
                                if alignEnd { Spacer(minLength: 0) }
                                if hasAvatar && !alignEnd { mark(Color.blue.frame(width: 32, height: 32), "avatar", box); Spacer().frame(width: 8) }
                                mark(Text(text).fixedSize(horizontal: false, vertical: true), "message", box)
                                if hasAvatar && alignEnd { Spacer().frame(width: 8); mark(Color.blue.frame(width: 32, height: 32), "avatar", box) }
                                if !alignEnd { Spacer(minLength: 0) }
                            }
                        }
                        let new = try await frames(700) { box in
                            ChatRowSides(hasAvatar: hasAvatar, alignEnd: alignEnd, gap: 8, bottom: bottom) {
                                if hasAvatar { mark(Color.blue.frame(width: 32, height: 32), "avatar", box) }
                                mark(Text(text).fixedSize(horizontal: false, vertical: true), "message", box)
                            }
                        }
                        assertSame(old, new, "row, end \(alignEnd), avatar \(hasAvatar), bottom \(bottom), \(text.prefix(4))")
                    }
                }
            }
        }
    }
}
