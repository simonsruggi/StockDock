import SwiftUI

/// Small uppercase label splitting a settings card into blocks (e.g. "Price alerts").
struct SettingSubheader: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(LocalizedStringKey(text))
            .font(DS.micro)
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(DS.inkTertiary)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }
}
