import SwiftUI

/// One photo, drawn as a card in the deck.
///
/// The view is deliberately inert: it owns no gesture, mutates nothing, and reads the
/// drag from the parent. `SwipeDeckView` owns the single `DragGesture` for the whole
/// stack, because two gestures competing for the same finger is a class of bug that only
/// shows up on a device.
struct PhotoCardView: View {

    let model: AppModel
    let card: DeckCard
    let depth: Int
    let dragTranslation: CGSize
    let cardWidth: CGFloat

    /// One loader per card view. `@State` so a recycled view keeps its loader and the
    /// `.task(id:)` below re-points it at the new card.
    @State private var loader = CardImageLoader()

    // MARK: - Derived swipe feedback

    /// Only the top card reacts to the drag. Cards underneath are handed `.zero`, but
    /// checking depth as well means a stale translation can never leak downwards.
    private var isTop: Bool { depth == 0 }

    /// How far through the commit threshold the finger is, 0...1.
    private var swipeStrength: Double {
        let limit = SwipeMetrics.threshold(forCardWidth: cardWidth)
        guard limit > 0 else { return 0 }
        return min(1, Double(abs(dragTranslation.width) / limit))
    }

    /// `SwipeMapping` is the only thing allowed to turn a direction into a decision, so
    /// this view never compares the translation against zero itself.
    private var previewDecision: Decision? {
        guard isTop else { return nil }
        return model.mapping.previewDecision(forHorizontal: dragTranslation.width)
    }

    // The card's rotation, offset and scale are all applied by `SwipeDeckView`, which
    // owns the drag. Rotating here as well compounded with the parent's transform and
    // tilted the card roughly twice as far as intended — and past the parent's cap.
    // `dragTranslation` is read here only for the wash and the stamp.

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            cardShape.fill(Theme.cardBackground)

            imageLayer

            chrome

            if isTop, let decision = previewDecision {
                // Filled into a `Rectangle` rather than dropped in bare: `LinearGradient`
                // conforms to both `View` and `ShapeStyle`, and iOS 17 added
                // `ShapeStyle.opacity(_:)`, so `gradient.opacity(x)` is an overload the
                // compiler can read two ways. `fill` pins it to the view form.
                // Both washes are authored leading->trailing with the colour pooled on
                // the side a *default* swipe travels towards: green at the left for keep,
                // red at the right for bin. Swapping the directions has to mirror the
                // pair together, on `binIsRight` — the single owner of direction — and not
                // per-decision, or the default layout flips too and the bug just moves.
                Rectangle()
                    .fill(decision == .keep ? Theme.keepWash : Theme.binWash)
                    .scaleEffect(x: model.mapping.binIsRight ? 1 : -1, y: 1)
                    .opacity(swipeStrength)
                    .allowsHitTesting(false)

                SwipeStamp(decision: decision, strength: swipeStrength)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(cardShape)
        .overlay(cardShape.stroke(Theme.hairline, lineWidth: 1))
        // Applied after the clip, so the shadow follows the rounded corners rather than
        // the square bounds. Deeper for the top card so the stack reads front-to-back.
        .shadow(
            color: Theme.cardShadow,
            radius: isTop ? Theme.cardShadowRadius : Theme.cardShadowRadius * 0.6,
            y: isTop ? Theme.cardShadowY : Theme.cardShadowY * 0.5
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.accessibilityLabel)
        .accessibilityHint(model.mapping.accessibilityHint)
        // VoiceOver swallows custom drag gestures entirely, so without these the deck is
        // unusable with the screen reader on. They are load-bearing, not decoration.
        .accessibilityAction(named: Text(Strings.a11yKeepAction)) {
            model.decide(.keep, expecting: card.id)
        }
        .accessibilityAction(named: Text(Strings.a11yBinAction)) {
            model.decide(.bin, expecting: card.id)
        }
        .accessibilityAction(named: Text(Strings.a11yUndoAction)) {
            model.undo()
        }
        .accessibilityAction(named: Text(Strings.iCloudRetry)) {
            if loader.hasFailed {
                loader.retry(card: card, using: model.pipeline)
            }
        }
        // Cards behind the top one are scenery; announcing three photos at once is noise.
        .accessibilityHidden(!isTop)
        // `.task(id:)` rather than `.onAppear`: the deck recycles this view as the cursor
        // advances, and `onAppear` would not fire again for the card that replaces this one.
        // No actor hop is needed — a `View`'s `.task` closure inherits the main-actor
        // isolation the `View` conformance gives this type, so the call is already on the
        // main actor. (An `await` here compiles, but warns that nothing asynchronous happens.)
        .task(id: card.id) {
            loader.load(card: card, using: model.pipeline)
        }
        .onDisappear {
            loader.cancel()
        }
    }

    // MARK: - Layers

    @ViewBuilder
    private var imageLayer: some View {
        if let image = loader.image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else if loader.hasFailed {
            failureLayer
        } else {
            loadingLayer
        }
    }

    private var loadingLayer: some View {
        // `CloudDownloadBadge` already draws its own `Strings.iCloudDownloading` caption,
        // so a second one here printed the line twice. It is also determinate, which is
        // strictly better than a spinner, so it replaces the spinner rather than joining it.
        VStack(spacing: 14) {
            if loader.isDownloadingFromCloud {
                CloudDownloadBadge(progress: loader.downloadProgress)
            } else {
                ProgressView()
                    .tint(Theme.textSecondary)
            }
        }
        .padding(Theme.screenPadding)
    }

    private var failureLayer: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.icloud")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(Theme.textTertiary)

            Text(Strings.iCloudFailed)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            Button(Strings.iCloudRetry) {
                loader.retry(card: card, using: model.pipeline)
            }
            .buttonStyle(PrimaryButtonStyle(role: .neutral, fullWidth: false))
        }
        .padding(Theme.screenPadding)
    }

    /// Date, length and favourite marker, floated over the photo.
    private var chrome: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)

                if card.isFavourite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.yellow)
                        .padding(8)
                        .background(Circle().fill(Theme.deepBlue.opacity(0.55)))
                }
            }

            Spacer(minLength: 0)

            HStack(alignment: .bottom, spacing: 10) {
                Text(Formatters.cardDate(card.creationDate))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.deepBlue.opacity(0.55)))

                Spacer(minLength: 0)

                if card.isVideo {
                    PillLabel(systemImage: "video.fill", text: Formatters.duration(card.duration))
                }
            }
        }
        .padding(14)
        .allowsHitTesting(false)
    }
}
