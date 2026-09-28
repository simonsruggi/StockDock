import SwiftUI

/// Label (+ optional caption) on the left, control on the right.
struct SettingRow<Control: View>: View {
    let label: String
    var caption: String? = nil
    @ViewBuilder var control: Control

    init(_ label: String, caption: String? = nil, @ViewBuilder control: () -> Control) {
        self.label = label
        self.caption = caption
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(label)).font(DS.body).foregroundStyle(DS.ink)
                if let caption {
                    Text(LocalizedStringKey(caption)).font(DS.micro).foregroundStyle(DS.inkTertiary)
                }
            }
            Spacer(minLength: 16)
            control
        }
        .padding(.vertical, 7)
    }
}
