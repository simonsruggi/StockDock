import AppKit
import CoreText

enum FontRegistration {
    static var familyName = "Inter Variable"
    static var sizeOffset: CGFloat = 0

    static let availableFonts: [(label: String, family: String)] = [
        ("Inter", "Inter Variable"),
        ("Avenir Next", "Avenir Next"),
        ("Baskerville", "Baskerville"),
        ("Charter", "Charter"),
        ("DIN Alternate", "DIN Alternate"),
        ("Futura", "Futura"),
        ("Galvji", "Galvji"),
        ("Georgia", "Georgia"),
        ("Gill Sans", "Gill Sans"),
        ("Helvetica Neue", "Helvetica Neue"),
        ("Menlo", "Menlo"),
        ("Monaco", "Monaco"),
        ("Optima", "Optima"),
        ("Palatino", "Palatino"),
        ("SF Mono", "SF Mono"),
    ]

    static func registerFonts() {
        guard let url = Bundle.module.url(forResource: "InterVariable", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    static func monospacedDigitsFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: familyName,
            .traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue]
        ])
        let base = NSFont(descriptor: descriptor, size: size) ?? .systemFont(ofSize: size, weight: weight)
        let tnum = base.fontDescriptor.addingAttributes([
            .featureSettings: [[
                kCTFontFeatureTypeIdentifierKey as NSFontDescriptor.AttributeName: kNumberSpacingType,
                kCTFontFeatureSelectorIdentifierKey as NSFontDescriptor.AttributeName: kMonospacedNumbersSelector
            ]]
        ])
        return NSFont(descriptor: tnum, size: size) ?? base
    }
}

import SwiftUI

extension Font {
    static func inter(_ size: CGFloat, weight: Weight? = nil, relativeTo style: TextStyle = .body) -> Font {
        let scaled = max(size + FontRegistration.sizeOffset, 6)
        let font = Font.custom(FontRegistration.familyName, size: scaled)
        if let weight { return font.weight(weight) }
        return font
    }
}
