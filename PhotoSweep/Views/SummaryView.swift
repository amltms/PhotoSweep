import SwiftUI

/// The end of a pile.
///
/// Short and warm on purpose: the user has just finished a repetitive job, so this screen
/// says what they did, explains anything the deck quietly held back, and offers the three
/// things they might sensibly want next. It never nags and never counts anything down.
struct SummaryView: View {

    let model: AppModel
    var onReviewBin: () -> Void
    var onKeepSweeping: () -> Void
    var onFinish: () -> Void

    /// A pile can finish without a single decision — everything in it was reviewed on an
    /// earlier run. That deserves congratulations rather than a row of zeroes.
    private var didReviewAnything: Bool {
        model.reviewedThisSession > 0
    }

    var body: some View {
        ZStack {
            ScreenBackground()

            VStack(spacing: Theme.stackSpacing) {
                ScrollView {
                    VStack(spacing: Theme.stackSpacing) {
                        headline

                        if model.excludedCount > 0 {
                            InfoBanner(
                                systemImage: "info.circle",
                                text: Strings.excludedNote(model.excludedCount)
                            )
                        }
                    }
                    .padding(.top, 32)
                    .padding(.bottom, Theme.stackSpacing)
                }
                .scrollIndicators(.hidden)

                buttons
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, Theme.screenPadding)
        }
    }

    // MARK: - Headline

    private var headline: some View {
        VStack(spacing: 12) {
            Image(systemName: didReviewAnything ? "sparkles" : "checkmark.circle.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(Theme.yellow)

            Text(didReviewAnything ? Strings.summaryTitle : Strings.summaryAllCaughtUp)
                .font(.title.bold())
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)

            Text(bodyLine)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 18)
        .panel()
        .accessibilityElement(children: .combine)
    }

    private var bodyLine: String {
        guard didReviewAnything else { return Strings.summaryAllCaughtUpBody }
        return Strings.summaryLine(
            reviewed: model.reviewedThisSession,
            kept: model.keptThisSession,
            binned: model.binnedThisSession
        )
    }

    // MARK: - Buttons

    private var buttons: some View {
        VStack(spacing: 12) {
            if model.pendingCount > 0 {
                Button(Strings.summaryReviewBin, action: onReviewBin)
                    .buttonStyle(PrimaryButtonStyle(role: .neutral))
            }

            Button(Strings.summaryKeepSweeping, action: onKeepSweeping)
                .buttonStyle(PrimaryButtonStyle(role: .positive))

            Button(Strings.summaryBackHome, action: onFinish)
                .buttonStyle(PrimaryButtonStyle(role: .quiet))
        }
    }
}
