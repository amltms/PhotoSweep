import SwiftUI

/// A small capsule badge: a video length, a count, a short piece of metadata.
///
/// `systemImage` is optional because several call sites are a bare number, where an
/// icon would only add clutter.
struct PillLabel: View {

    private let systemImage: String?
    private let text: String

    init(systemImage: String?, text: String) {
        self.systemImage = systemImage
        self.text = text
    }

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
            }

            Text(text)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Theme.deepBlue.opacity(0.65))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
    }
}
