import SwiftUI

/// A named placeholder reads intentional; a lone glyph reads broken.
struct NewsPlaceholder: View {
    let publisher: String
    var body: some View {
        Rectangle().fill(DS.cardAlt)
            .overlay(
                VStack(spacing: 5) {
                    Image(systemName: "newspaper").font(.system(size: 20)).foregroundStyle(DS.inkTertiary)
                    if !publisher.isEmpty {
                        Text(publisher).font(DS.micro).foregroundStyle(DS.inkTertiary)
                    }
                }
            )
    }
}
