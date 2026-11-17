import AppKit
import SwiftUI
import XCTest
@testable import CoreUI

/// How big the picture and video viewers open, and the bigger / smaller buttons.
@MainActor
final class ViewerSizeTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "viewer-size-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testTheSizeFollowsTheWindowAndTheLevel() {
        let window = CGSize(width: 1900, height: 1100)
        XCTAssertEqual(ViewerSize.of(window: window, level: .large).width, 1900 * 0.92, accuracy: 0.5)
        XCTAssertEqual(ViewerSize.of(window: window, level: .small).height, 1100 * 0.6, accuracy: 0.5)
        XCTAssertEqual(ViewerSize.of(window: window, level: .full), window)
        XCTAssertEqual(ViewerSize.of(window: nil, level: .large), ViewerSize.fallback)
        // Never smaller than the minimum, nor larger than a small window.
        XCTAssertEqual(ViewerSize.of(window: CGSize(width: 700, height: 500), level: .small), ViewerSize.minimum)
        XCTAssertEqual(ViewerSize.of(window: CGSize(width: 400, height: 300), level: .small), CGSize(width: 400, height: 300))
        XCTAssertEqual(AdaptiveViewerFrame<EmptyView>.size(in: window, expanded: true), window)
    }

    func testTheButtonsStepThroughTheLevelsAndTheChoiceIsKept() {
        let d = defaults()
        let pref = ViewerSizePreference(defaults: d)
        XCTAssertEqual(pref.level, .large, "a viewer opens large by default")
        pref.grow(); XCTAssertEqual(pref.level, .full); XCTAssertFalse(pref.canGrow)
        pref.grow(); XCTAssertEqual(pref.level, .full)
        pref.shrink(); pref.shrink(); pref.shrink(); XCTAssertEqual(pref.level, .small); XCTAssertFalse(pref.canShrink)
        pref.shrink(); XCTAssertEqual(pref.level, .small)
        XCTAssertEqual(ViewerSizePreference(defaults: d).level, .small, "the next viewer opens at the size picked")
    }
}
