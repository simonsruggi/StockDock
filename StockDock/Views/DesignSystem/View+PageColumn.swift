import SwiftUI

extension View {
    /// The shared content column: gutter padding, bottom padding, centered
    /// max-width. Apply to the root VStack inside a page's ScrollView.
    func pageColumn() -> some View {
        self
            .padding(.horizontal, DS.gutter)
            .padding(.bottom, DS.gutter)
            .frame(maxWidth: DS.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
    }
}
