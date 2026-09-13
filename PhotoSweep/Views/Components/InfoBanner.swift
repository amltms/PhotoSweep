import SwiftUI

/// A single line of explanatory or cautionary copy on a tinted background.
///
/// The tint carries the meaning (yellow for a note, red for a warning), so the caller
/// passes a `Theme` colour rather than the banner guessing from the text.
struct InfoBanner: View {

    private let systemImage: String
    private let text: String
    private let tint: Color

    init(systemImage: String, text: String, tint: Color = Theme.yellow) {
        self.systemImage = systemImage
        self.text = text
        self.tint = tint
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Theme.controlCornerRadius, style: .continuous)
                .fill(tint.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.controlCornerRadius, style: .continuous)
                .stroke(tint.opacity(0.35), lineWidth: 1)
        )
    }
}
