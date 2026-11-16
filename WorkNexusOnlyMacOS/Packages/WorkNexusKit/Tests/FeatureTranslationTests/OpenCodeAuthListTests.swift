import XCTest
@testable import FeatureTranslation

/// What `opencode auth list` prints, as each CLI version words it, and whether that means a provider is linked.
final class OpenCodeAuthListTests: XCTestCase {
    /// Captured from the CLI on a Mac, piped as the app runs it: a row per credential, no count, no bullet. This is the
    /// wording that made the app say OpenCode was not linked while translation through it worked.
    func testTheNewTableWordingCountsAsLinked() {
        XCTAssertEqual(OpenCodeCliRunner.isAuthenticated(listing: "OpenCode Console  API key                     stored\n"), true)
        XCTAssertEqual(OpenCodeCliRunner.isAuthenticated(listing: "Anthropic  OAuth  stored\nOpenAI  API key  stored\n"), true)
        XCTAssertEqual(OpenCodeCliRunner.isAuthenticated(listing: "Environment\nGoogle  GEMINI_API_KEY  env\n"), true)
    }

    func testTheOlderWordingStillWorks() {
        let linked = "\u{1B}[0m\n┌  Credentials ~/.local/share/opencode/auth.json\n│\n●  OpenCode api\n│\n└  1 credentials\n"
        XCTAssertEqual(OpenCodeCliRunner.isAuthenticated(listing: linked), true)
        XCTAssertEqual(OpenCodeCliRunner.isAuthenticated(listing: "┌  Credentials\n│\n└  0 credentials\n"), false)
        XCTAssertEqual(OpenCodeCliRunner.isAuthenticated(listing: "\u{1B}[1m●\u{1B}[0m  Anthropic oauth\n"), true)
    }

    /// Wording this does not know says nothing either way (the credential file decides), and error text is not a credential.
    func testUnknownWordingIsLeftToTheCredentialFile() {
        XCTAssertNil(OpenCodeCliRunner.isAuthenticated(listing: ""))
        XCTAssertNil(OpenCodeCliRunner.isAuthenticated(listing: "Error: could not read credentials\n"))
        XCTAssertNil(OpenCodeCliRunner.isAuthenticated(listing: "No providers configured\n"))
    }
}

/// The ticket prompt: a ZenTao body is HTML, and its tags must come back so the translation is laid out as the original.
final class TicketPromptTests: XCTestCase {
    func testThePromptAsksToKeepHtmlTagsAsTheyAre() {
        let p = ticketPrompt(TicketSource(title: "T", body: "<p><strong>Steps</strong></p><ol><li>Open</li></ol>"), "Vietnamese")
        XCTAssertTrue(p.contains("keep every tag and attribute exactly as it is"))
        XCTAssertTrue(p.contains("<ol><li>Open</li></ol>"))
        XCTAssertTrue(p.contains("\"title\" and \"body\""))
    }
}
