import Foundation

/// Sends notifications to a Discord or Slack incoming webhook.
/// Format is auto-detected from the URL host. Only https URLs pointing at the
/// known webhook hosts are accepted (SSRF-safe — no arbitrary internal endpoints).
enum WebhookNotifier {

    /// Discord embed colors (decimal RGB).
    enum Color {
        static let green = 0x2ECC71
        static let red = 0xE74C3C
        static let neutral = 0x3498DB
    }

    /// Display name and avatar used for the webhook message (overrides the channel default).
    private static let botName = "StockDock"
    private static let avatarURL = "https://raw.githubusercontent.com/simonsruggi/StockDock/main/StockDock/Assets.xcassets/AppIcon.appiconset/icon_256.png"

    /// Returns true if the string is a usable Discord/Slack webhook URL.
    static func isValid(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString),
              url.scheme == "https",
              let host = url.host?.lowercased() else { return false }
        return host == "discord.com" || host == "discordapp.com"
            || host == "ptb.discord.com" || host == "canary.discord.com"
            || host == "hooks.slack.com"
    }

    private static func isSlack(_ urlString: String) -> Bool {
        urlString.lowercased().contains("hooks.slack.com")
    }

    /// Posts a message. Failures are swallowed (best-effort, never blocks the UI).
    static func send(to urlString: String, title: String, body: String, color: Int = Color.neutral) async {
        guard isValid(urlString), let url = URL(string: urlString) else { return }

        let payload: [String: Any]
        if isSlack(urlString) {
            payload = [
                "username": botName,
                "icon_url": avatarURL,
                "text": "*\(title)*\n\(body)"
            ]
        } else {
            payload = [
                "username": botName,
                "avatar_url": avatarURL,
                "embeds": [["title": title, "description": body, "color": color]]
            ]
        }

        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody
        request.timeoutInterval = 10

        _ = try? await URLSession.shared.data(for: request)
    }
}
