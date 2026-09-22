import XCTest
@testable import StockDock

final class LocalizationTests: XCTestCase {

    func testSimplifiedChineseIsAvailable() {
        let language = StorageService.supportedLanguages.first { $0.code == "zh-Hans" }
        XCTAssertEqual(language?.name, "简体中文")
    }

    func testEverySupportedLanguageHasTheEnglishStringKeys() throws {
        let referenceKeys = try localizationKeys(for: "en")
        XCTAssertFalse(referenceKeys.isEmpty)

        for language in StorageService.supportedLanguages {
            XCTAssertEqual(
                try localizationKeys(for: language.code),
                referenceKeys,
                "\(language.code) must keep the same keys as the English localization"
            )
        }
    }

    private func localizationKeys(for language: String) throws -> Set<String> {
        let resourcesURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("StockDock/Resources")
        let fileURL = resourcesURL
            .appendingPathComponent("\(language).lproj")
            .appendingPathComponent("Localizable.strings")
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let expression = try NSRegularExpression(
            pattern: #"^\s*"((?:\\.|[^"])*)"\s*="#,
            options: [.anchorsMatchLines]
        )
        let fullRange = NSRange(contents.startIndex..<contents.endIndex, in: contents)

        return Set(expression.matches(in: contents, range: fullRange).compactMap { match in
            guard let range = Range(match.range(at: 1), in: contents) else { return nil }
            return String(contents[range])
        })
    }
}
