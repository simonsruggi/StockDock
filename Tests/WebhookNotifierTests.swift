import XCTest
@testable import StockDock

/// Locks the SSRF guard on webhook URLs: only https URLs pointing at known
/// Discord/Slack hosts may ever be accepted (a user pastes this URL in Settings).
final class WebhookNotifierTests: XCTestCase {

    func testAcceptsKnownDiscordAndSlackHosts() {
        let ok = [
            "https://discord.com/api/webhooks/123/abc",
            "https://discordapp.com/api/webhooks/123/abc",
            "https://ptb.discord.com/api/webhooks/123/abc",
            "https://canary.discord.com/api/webhooks/123/abc",
            "https://hooks.slack.com/services/T000/B000/xxx",
        ]
        for url in ok {
            XCTAssertTrue(WebhookNotifier.isValid(url), "should accept \(url)")
        }
    }

    func testRejectsNonHttpsScheme() {
        XCTAssertFalse(WebhookNotifier.isValid("http://discord.com/api/webhooks/1/a"))
    }

    func testRejectsArbitraryAndInternalHosts() {
        let bad = [
            "https://evil.com/api/webhooks/1/a",
            "https://discord.com.evil.com/api/webhooks/1/a",
            "https://localhost/api/webhooks/1/a",
            "https://169.254.169.254/latest/meta-data",
            "https://hooks.slack.com.attacker.net/x",
            "file:///etc/passwd",
            "",
            "not a url",
        ]
        for url in bad {
            XCTAssertFalse(WebhookNotifier.isValid(url), "should reject \(url)")
        }
    }

    func testHostMatchingIsCaseInsensitive() {
        XCTAssertTrue(WebhookNotifier.isValid("https://Discord.com/api/webhooks/1/a"))
    }
}
