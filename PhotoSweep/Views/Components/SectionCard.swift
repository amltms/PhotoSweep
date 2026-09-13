import SwiftUI

/// A titled panel used to group related content outside of a `List`.
///
/// The title sits above the panel rather than inside it, so several cards in a column
/// line up with one another the way grouped list sections do.
struct SectionCard<Content: View>: View {

    private let title: String?
    private let content: Content

    init(title: String?, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .kerning(0.8)
                    .foregroundStyle(Theme.textTertiary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 4)
                    .accessibilityAddTraits(.isHeader)
            }

            VStack(alignment: .leading, spacing: Theme.stackSpacing) {
                content
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel()
        }
    }
}
