import SwiftUI

/// How long the summary waits before it takes the screen from the deck.
///
/// The last swipe of a pile finishes the pile *while the card is still on screen*:
/// `AppModel.decide` advances the cursor and the refill finds nothing left, so
/// `isPileFinished` turns true in the same update pass that starts the fly-away. Swapping
/// the deck out at that moment tears `SwipeDeckView` down mid-departure and the final card
/// simply vanishes under the finger. Waiting this long lets it leave like every other card.
///
/// The two durations mirror the private ones in `SwipeDeckView` and the slack is the same
/// 0.1s its own tidy-up allows. If those numbers move, move these with them: too short
/// clips the last card, too long leaves an empty deck sitting on screen.
private enum SummaryHandoff {
    static let flyAwayDuration: Double = 0.28
    static let crossFadeDuration: Double = 0.2
    static let slack: Double = 0.1
    static let fadeInDuration: Double = 0.2
}

/// The full-screen sweeping surface: header, progress, card stack, controls.
///
/// It is always reached through `.fullScreenCover` and never pushed onto a
/// `NavigationStack`, because UIKit's interactive pop gesture owns the left screen edge
/// and drags rightwards — which is exactly the bin direction. Everything the deck can
/// lead to (the bin, a peek, the summary) is presented from here rather than from a
/// parent, so the deck itself never has to be dismissed to show it.
struct DeckScreen: View {

    let model: AppModel
    var onClose: () -> Void

    @State private var isShowingBin = false

    /// `DeckCard` is `Identifiable` on `localIdentifier`, so the peek can be driven by
    /// the card itself rather than by a separate flag plus a nullable card, which can
    /// disagree with each other.
    @State private var peekCard: DeckCard?

    /// Whether the summary has taken over, held separately from `model.isPileFinished` so
    /// the hand-over can be delayed by `SummaryHandoff` (see above).
    ///
    /// `nil` means "nobody has decided yet", in which case the model is followed directly:
    /// a pile that was already finished when the deck opened shows its summary on the
    /// first frame instead of flashing an empty deck for one pass.
    ///
    /// It stays `nil` for that one frame only. `.onAppear` latches it to whatever the
    /// model said at the start, because following the model *indefinitely* would undo the
    /// whole point of the delay below: the moment a swipe finished the pile, `nil` would
    /// read straight through as `true` and the summary would replace the deck while the
    /// last card was still flying away.
    @State private var showSummary: Bool?

    /// A card that never travels needs no time to travel in.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isShowingSummary: Bool { showSummary ?? model.isPileFinished }

    private var summaryHandoffDelay: Double {
        let departure = reduceMotion ? SummaryHandoff.crossFadeDuration : SummaryHandoff.flyAwayDuration
        return departure + SummaryHandoff.slack
    }

    var body: some View {
        ZStack {
            ScreenBackground()

            if isShowingSummary {
                SummaryView(
                    model: model,
                    onReviewBin: { isShowingBin = true },
                    // This pile is finished by definition, so "keep sweeping" can only
                    // mean the whole library. If that turns out to have nothing undecided
                    // left in it either, the pile chooser is the honest destination —
                    // restarting into an instantly finished pile just looks broken.
                    onKeepSweeping: {
                        Task {
                            await model.startSession(filter: .all)
                            if model.isPileFinished { onClose() }
                        }
                    },
                    onFinish: { onClose() }
                )
                .transition(.opacity)
            } else {
                deck
            }
        }
        .onAppear {
            // Close the tri-state after the first frame has used it. `HomeView` builds the
            // session before it raises this cover, so the model's answer is already final
            // here and there is nothing to wait for. Guarded on `nil` because SwiftUI
            // disappears and re-appears this view when the peek cover is presented over
            // it, and a second latch would throw away a summary decision already taken.
            if showSummary == nil {
                showSummary = model.isPileFinished
            }
        }
        .onChange(of: model.isPileFinished) { _, isFinished in
            guard isFinished else {
                // A session started from the summary must not open on the old one.
                showSummary = false
                return
            }

            Task {
                try? await Task.sleep(for: .seconds(summaryHandoffDelay))

                // Re-read rather than captured: an undo taken during the fly-away puts a
                // card back, and the summary must never arrive over a live deck.
                guard model.isPileFinished else { return }
                withAnimation(.easeInOut(duration: SummaryHandoff.fadeInDuration)) {
                    showSummary = true
                }
            }
        }
        .sheet(isPresented: $isShowingBin) {
            BinView(model: model, onClose: { isShowingBin = false })
        }
        .fullScreenCover(item: $peekCard) { card in
            PeekView(model: model, card: card, onClose: { peekCard = nil })
        }
        // Deliberately no `.onDisappear` teardown here. `HomeView` already calls
        // `model.endSession()` from this cover's `onDismiss`, and `endSession()` stops
        // prefetching itself. Repeating it here also fired when the peek cover was
        // presented *over* the deck — SwiftUI disappears the presenting view — which
        // threw the caching manager's window away in the middle of a session and left
        // the next card to load from scratch.
    }

    // MARK: - Deck

    private var deck: some View {
        VStack(spacing: Theme.stackSpacing) {
            topBar

            SweepProgressBar(progress: model.progress)

            SwipeDeckView(model: model, onPeek: { card in peekCard = card })
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            DeckControlsView(model: model, onOpenBin: { isShowingBin = true })
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 8)
        .padding(.bottom, Theme.screenPadding)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: Theme.minimumTapTarget, height: Theme.minimumTapTarget)
                    .background(Circle().fill(Theme.surface))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(Strings.close))

            Spacer(minLength: 0)

            Text(positionText)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)

            Spacer(minLength: 0)

            Button {
                isShowingBin = true
            } label: {
                PillLabel(systemImage: "trash", text: Formatters.count(model.pendingCount))
            }
            .buttonStyle(.plain)
            .frame(minWidth: Theme.minimumTapTarget, minHeight: Theme.minimumTapTarget)
            .accessibilityLabel(Text(Strings.a11yOpenBin))
        }
    }

    /// "12 of 4,182". Counted from what has been reviewed rather than from an array
    /// index, because the deck is append-only and its indices mean nothing to the user.
    private var positionText: String {
        let total = max(model.totalInPile, 1)
        let position = min(model.reviewedThisSession + 1, total)
        return Strings.photoOfTotal(position, total)
    }
}
