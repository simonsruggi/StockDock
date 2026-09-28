import SwiftUI

/// A toggle row in the app's emerald.
struct SettingToggle: View {
    let label: String
    var caption: String? = nil
    @Binding var isOn: Bool

    init(_ label: String, caption: String? = nil, isOn: Binding<Bool>) {
        self.label = label
        self.caption = caption
        self._isOn = isOn
    }

    var body: some View {
        SettingRow(label, caption: caption) {
            DSToggle(isOn: $isOn)
        }
    }
}
