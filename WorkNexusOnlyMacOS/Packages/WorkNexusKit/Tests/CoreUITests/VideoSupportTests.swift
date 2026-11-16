import AVFoundation
import CoreDomain
import XCTest
@testable import CoreUI

/// Ported from: test/core/util/load_speed_meter_test.dart (+ the video time / speed / loaded-share helpers and the
/// player model's states).
@MainActor
final class VideoSupportTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ ms: Int) -> Date { t0.addingTimeInterval(Double(ms) / 1000) }

    // MARK: load speed meter

    func testNoSpeedUntilTwoSamplesAreApart() {
        var meter = VideoLoadSpeedMeter()
        XCTAssertNil(meter.bytesPerSecond)
        meter.add(at(0), bytes: 1000)
        XCTAssertNil(meter.bytesPerSecond)
    }

    func testBytesGainedOverTimeGiveTheSpeed() {
        var meter = VideoLoadSpeedMeter()
        meter.add(at(0), bytes: 0); meter.add(at(500), bytes: 500_000); meter.add(at(1000), bytes: 1_000_000)
        XCTAssertEqual(meter.bytesPerSecond, 1_000_000)
    }

    func testOnlyTheLastWindowCounts() {
        var meter = VideoLoadSpeedMeter(window: 1)
        meter.add(at(0), bytes: 0); meter.add(at(500), bytes: 4_000_000)       // a fast start
        meter.add(at(1500), bytes: 5_000_000); meter.add(at(2500), bytes: 6_000_000)   // then a steady 1 MB/s
        XCTAssertEqual(meter.bytesPerSecond, 1_000_000)
    }

    func testABufferThatRestartsLowerStartsANewRun() {
        var meter = VideoLoadSpeedMeter()
        meter.add(at(0), bytes: 0); meter.add(at(1000), bytes: 8_000_000); meter.add(at(1500), bytes: 2_000_000)
        XCTAssertNil(meter.bytesPerSecond)
        meter.add(at(2500), bytes: 2_500_000)
        XCTAssertEqual(meter.bytesPerSecond, 500_000)
    }

    // MARK: helpers

    func testVideoTimeReadsMinutesSecondsAndHoursForLongVideos() {
        XCTAssertEqual(formatVideoTime(0), "0:00")
        XCTAssertEqual(formatVideoTime(9.9), "0:09")
        XCTAssertEqual(formatVideoTime(75), "1:15")
        XCTAssertEqual(formatVideoTime(3_725), "1:02:05")
        XCTAssertEqual(formatVideoTime(-3), "0:00")
        XCTAssertEqual(formatVideoTime(.nan), "0:00")
    }

    func testSpeedsReadWithoutATrailingZero() {
        XCTAssertEqual(VideoSpeeds.options.map(VideoSpeeds.label), ["0.5x", "0.75x", "1x", "1.25x", "1.5x", "2x"])
    }

    func testLoadedShareIsTheEndOfTheFurthestBufferedRange() {
        XCTAssertEqual(videoLoadedFraction(ranges: [0...10, 40...60], duration: 100), 0.6)
        XCTAssertEqual(videoLoadedFraction(ranges: [], duration: 100), 0)
        XCTAssertEqual(videoLoadedFraction(ranges: [0...10], duration: 0), 0)
        XCTAssertEqual(videoLoadedFraction(ranges: [0...200], duration: 100), 1)
    }

    func testOnlyMp4MovAndM4vPlayInApp() {
        XCTAssertTrue(AppVideoFormats.isNative("MP4")); XCTAssertTrue(AppVideoFormats.isNative("mov"))
        XCTAssertFalse(AppVideoFormats.isNative("webm")); XCTAssertFalse(AppVideoFormats.isNative("mkv"))
        XCTAssertTrue(AppVideoFormats.isVideo("webm")); XCTAssertFalse(AppVideoFormats.isVideo("pdf"))
    }

    func testTheLoadingTextKeepsItsLiteralPercentSign() {
        XCTAssertEqual(VideoLoadingText.make(percent: "32", bytesPerSecond: nil), "Loading 32%")
        XCTAssertEqual(VideoLoadingText.make(percent: "32", bytesPerSecond: 1_048_576), "Loading 32% · 1.0 MB/s")
    }

    func testTheSessionRidesInTheStreamsRequestHeaders() {
        let req = MediaRequest(url: URL(string: "https://z/x.mp4?zentaosid=t")!, headers: ["Cookie": "zentaosid=t", "Token": "t"])
        XCTAssertEqual(AppVideoPlayerModel.asset(req).url, req.url)
    }

    // MARK: the model

    func testAFormatAVFoundationCannotPlayEndsInTheExternalState() async {
        var asked = false
        let model = AppVideoPlayerModel(source: AppVideoSource(title: "a.webm", fileExtension: "webm", stream: { asked = true; return nil }, download: { nil }))
        await model.start()
        XCTAssertEqual(model.phase, .external)
        XCTAssertFalse(asked, "nothing is fetched to show the button")
    }

    func testNoStreamAndNoDownloadFails() async {
        let model = AppVideoPlayerModel(source: AppVideoSource(title: "a.mp4", fileExtension: "mp4", stream: { nil }, download: { nil }))
        await model.start()
        XCTAssertEqual(model.phase, .failed)
    }

    func testAFileThatIsNotAVideoFailsAfterTheDownloadFallback() async throws {
        let junk = FileManager.default.temporaryDirectory.appendingPathComponent("wn-junk-\(UUID().uuidString).mp4")
        try Data("not a video".utf8).write(to: junk)
        defer { try? FileManager.default.removeItem(at: junk) }
        var downloads = 0
        let model = AppVideoPlayerModel(source: AppVideoSource(title: "a.mp4", fileExtension: "mp4", stream: { nil }, download: { downloads += 1; return junk.path }))
        await model.start()
        XCTAssertEqual(model.phase, .failed); XCTAssertEqual(downloads, 1)
    }

    func testControlsClampAndToggle() {
        let model = AppVideoPlayerModel(source: .file(path: "/nonexistent.mp4"))
        model.setVolume(7); XCTAssertEqual(model.volume, 1)
        model.toggleMute(); XCTAssertTrue(model.isMuted); XCTAssertEqual(model.player.volume, 0)
        model.toggleMute(); XCTAssertEqual(model.volume, 1)
        model.setSpeed(1.5); XCTAssertEqual(model.speed, 1.5)
        model.toggleLoop(); XCTAssertTrue(model.isLooping)
        model.seek(to: -5); XCTAssertEqual(model.currentSeconds, 0)
        XCTAssertEqual(model.positionVersion, 1, "a seek makes paused views redraw")
    }

    func testAShortRealVideoPlaysSeeksAndReportsItsState() async throws {
        let url = try await TestVideo.make(seconds: 2)
        defer { try? FileManager.default.removeItem(at: url) }
        let model = AppVideoPlayerModel(source: .file(path: url.path))
        await model.start()
        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.duration, 2, accuracy: 0.3)
        XCTAssertEqual(model.aspectRatio, 16.0 / 9.0, accuracy: 0.05)
        XCTAssertTrue(model.isPlaying)
        model.pause()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(model.isPlaying)
        model.seek(to: 1.0)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(model.currentSeconds, 1.0, accuracy: 0.25)
        model.seek(by: 10)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(model.currentSeconds, model.duration, accuracy: 0.3, "seeking past the end stops at the end")
        model.stop()
    }

    func testAStillComesOutOfAStreamedVideoOnlyOverRealHTTPSoALocalURLIsReadDirectly() async throws {
        let url = try await TestVideo.make(seconds: 1)
        defer { try? FileManager.default.removeItem(at: url) }
        let png = await AppVideoStills.frame(from: MediaRequest(url: url), at: 0.2)
        XCTAssertNotNil(png.flatMap(NSImage.init(data:)))
        let none = await AppVideoStills.frame(from: MediaRequest(url: URL(fileURLWithPath: "/nonexistent.mp4")), timeout: .seconds(2))
        XCTAssertNil(none)
    }
}

/// Writes a tiny real H.264 video (a moving bar on 16:9) so the player and the still grabber run on something playable.
enum TestVideo {
    static func make(seconds: Int, fps: Int32 = 10) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wn-test-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let (w, h) = (320, 180)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? NSError(domain: "TestVideo", code: 1) }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<(seconds * Int(fps)) {
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_32ARGB, nil, &buffer)
            guard let buffer else { throw NSError(domain: "TestVideo", code: 2) }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset(base, 40, CVPixelBufferGetBytesPerRow(buffer) * h)
                let bar = (frame * 8) % (w - 20), row = CVPixelBufferGetBytesPerRow(buffer)
                for y in 0..<h { for x in bar..<(bar + 20) { base.storeBytes(of: 255, toByteOffset: y * row + x * 4 + 1, as: UInt8.self) } }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? NSError(domain: "TestVideo", code: 3) }
        return url
    }
}
