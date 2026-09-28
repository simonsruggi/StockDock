import SwiftUI

struct DSAlertModifier: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let message: String
    var confirmTitle: String = "OK"
    var cancelTitle: String? = "Cancel"
    var destructive: Bool = false
    var onConfirm: () -> Void = {}

    func body(content: Content) -> some View {
        content.overlay {
            if isPresented {
                ZStack {
                    Color.black.opacity(0.16).ignoresSafeArea()
                        .onTapGesture { isPresented = false }
                    VStack(alignment: .leading, spacing: 10) {
                        Text(LocalizedStringKey(title)).font(.inter(15, weight: .semibold, relativeTo: .headline)).foregroundStyle(DS.ink)
                        Text(LocalizedStringKey(message)).font(DS.body).foregroundStyle(DS.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            Spacer()
                            if let cancelTitle {
                                Button { isPresented = false } label: {
                                    Text(LocalizedStringKey(cancelTitle))
                                        .font(.inter(12.5, weight: .medium, relativeTo: .body)).foregroundStyle(DS.inkSecondary)
                                        .padding(.horizontal, 14).padding(.vertical, 7)
                                        .background(Capsule().fill(DS.cardAlt))
                                }.buttonStyle(.plain)
                            }
                            Button { isPresented = false; onConfirm() } label: {
                                Text(LocalizedStringKey(confirmTitle))
                                    .font(.inter(12.5, weight: .semibold, relativeTo: .body)).foregroundStyle(.white)
                                    .padding(.horizontal, 16).padding(.vertical, 7)
                                    .background(Capsule().fill(destructive ? DS.down : DS.brand))
                            }.buttonStyle(.plain)
                        }
                        .padding(.top, 4)
                    }
                    .padding(20)
                    .frame(width: 340)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DS.card))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(DS.hairline))
                    .shadow(color: .black.opacity(0.22), radius: 28, y: 12)
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
                }
                .animation(.easeOut(duration: 0.16), value: isPresented)
            }
        }
    }
}

extension View {
    func dsAlert(_ isPresented: Binding<Bool>, title: String, message: String,
                 confirmTitle: String = "OK", cancelTitle: String? = "Cancel",
                 destructive: Bool = false, onConfirm: @escaping () -> Void = {}) -> some View {
        modifier(DSAlertModifier(isPresented: isPresented, title: title, message: message,
                                 confirmTitle: confirmTitle, cancelTitle: cancelTitle,
                                 destructive: destructive, onConfirm: onConfirm))
    }
}
