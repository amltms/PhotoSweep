import SwiftUI

/// The "there is nothing here" placeholder, used by the bin, the piles and the deck.
///
/// The action is optional because several empty states are simply statements of fact
/// with nothing useful for the user to press.
struct EmptyStateView: View {

    private let systemImage: String
    private let title: String
    private let message: String
    private let actionTitle: String?
    private let action: (() -> Void)?

    init(
        systemImage: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: Theme.stackSpacing) {
            Image(systemName: systemImage)
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)

            Text(title)
                .font(.title2.bold())
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(message)
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                Button(actionTitle) {
                    action()
                }
                .buttonStyle(PrimaryButtonStyle(role: .neutral, fullWidth: false))
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.vertical, Theme.screenPadding + 8)
        .frame(maxWidth: .infinity)
    }
}
