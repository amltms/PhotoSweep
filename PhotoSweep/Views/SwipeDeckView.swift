import Foundation
import SwiftUI

/// Sizing for the stack behind the top card.
///
/// Kept out of the view so the numbers are named once and cannot drift between the
/// scale and the offset, which is how a "deck" quietly turns into a wonky pile.
private enum DeckStackMetrics {

    /// How much smaller each card behind the top one is drawn.
    static let scaleStep: CGFloat = 0.045

    /// A floor, so a deep card never collapses to nothing.
    static let minimumScale: CGFloat = 0.86

    /// How far down each card behind the top one peeps out.
    static let verticalStep: CGFloat = 14

    /// Card rotation is capped: past this the card reads as falling over rather than tilting.
    static let maximumRotationDegrees: Double = 14

    /// How far off screen a decided card travels, as a multiple of the card width.
    static let flyAwayWidthMultiple: CGFloat = 1.6

    static let flyAwayDuration: Double = 0.28
    static let crossFadeDuration: Double = 0.2

    static func scale(depth: Int) -> CGFloat {
        max(minimumScale, 1 - scaleStep * CGFloat(depth))
    }

    static func verticalOffset(depth: Int) -> CGFloat {
        CGFloat(depth) * verticalStep
    }
}

/// A card that has already been decided and is still on screen only so that the swipe
/// has somewhere to land.
///
/// It holds only the flight path. The card itself is still drawn by the deck's one
/// `ForEach`, under its own id, so that it keeps its view identity and therefore the
/// photo it had already loaded. The model advanced the moment the finger lifted and never
/// waits for this to finish animating.
private struct DepartingCard {
    /// Distinguishes one departure from the next, so a late tidy-up cannot clear a card
    /// that a newer swipe has since put on screen.
    let token: UUID
    let card: DeckCard
    let start: CGSize
    let target: CGSize
}

/// The card stack, and the only drag gesture in the application.
///
/// Every rule in here exists because the obvious version of it is wrong in a way that
/// only shows up on a device: a decision taken in `onChanged` fires on every touch
/// sample, a `@GestureState` offset is reset before `onEnded` can use it, and a model
/// mutation hung off an animation completion handler never runs when that animation is
/// interrupted — which jams the deck for the rest of the session.
struct SwipeDeckView: View {

    let model: AppModel
    var onPeek: (DeckCard) -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Plain `@State` and never `@GestureState`: the system restores a `@GestureState`
    /// to its reset value before the `onEnded` body takes effect, so the card could
    /// never be animated anywhere from there.
    @State private var dragOffset: CGSize = .zero

    /// Re-entrancy gate around `commit`. `commit` is deliberately synchronous end to end,
    /// so in practice no callback can arrive while this is set; it is kept as a cheap
    /// belt-and-braces guard and is cleared on a scene-phase change so a cancelled
    /// gesture can never strand it. The thing that actually stops a double-fired gesture
    /// marking two photos is `AppModel.decide(_:expecting:)`, which ignores any id that
    /// is not the current card.
    @State private var isCommitting = false

    /// Latched so the threshold haptic fires once per crossing rather than once per
    /// touch sample. It is feedback only and never a decision.
    @State private var hasCrossedThreshold = false

    @State private var departing: DepartingCard?

    /// 0 = the departing card is where the finger left it, 1 = gone. One animatable
    /// scalar is easier to reason about than an animated copy of the whole card state.
    @State private var departProgress: Double = 0

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            VStack(spacing: 10) {
                ZStack {
                    // `renderedCards`, not `visibleCards`: a card swiped while the deck is
                    // refilling would otherwise be replaced by a spinner mid-flight.
                    if renderedCards.isEmpty && model.isPreparing {
                        ProgressView()
                            .tint(Theme.textSecondary)
                    } else {
                        // Empty and not preparing renders nothing at all: DeckScreen is
                        // showing the summary over the top of this.
                        //
                        // Exactly one `ForEach`, and the departing card is inside it. See
                        // `renderedCards` for why a separate overlay cannot work.
                        ForEach(renderedCards) { card in
                            cardLayer(for: card, width: width)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Text(model.mapping.legend)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.textTertiary)
                    .allowsHitTesting(false)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        // `onEnded` is not called when a gesture is cancelled — an incoming call, the app
        // going to the background, a multi-touch fumble — so the drag state is cleared
        // defensively rather than trusted to unwind itself.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                dragOffset = .zero
                isCommitting = false
                hasCrossedThreshold = false
                departing = nil
                departProgress = 0
            }
        }
        .onChange(of: model.cursor) { _, _ in
            dragOffset = .zero
        }
        .onAppear {
            Haptics.prepare()
        }
    }

    // MARK: - Layers

    /// The live deck, with the departing card prepended when there is one.
    ///
    /// The departing card is drawn from the same `ForEach`, under its own `DeckCard.id`,
    /// and never from a second structural position such as `if let item = departing`. An
    /// optional branch going `nil -> non-nil` is an *insertion*: SwiftUI has no identity
    /// to reuse, so it builds a brand new `PhotoCardView` with a brand new
    /// `CardImageLoader` whose `image` is `nil`, while the old top card leaves the
    /// `ForEach` and its `.onDisappear` cancels the load that had the photo in it. The
    /// replacement request cannot come back in the same frame — `ImageSpec.cardOptions`
    /// is asynchronous and the pipeline hops to the main queue even on a cache hit — so
    /// every swipe used to fly a blank spinner card off screen. Keeping the id inside one
    /// `ForEach` keeps the view, the loader and the loaded photo.
    private var renderedCards: [DeckCard] {
        let live = model.visibleCards
        guard let item = departing, departingCopy(matching: item.card) != nil else { return live }
        return [item.card] + live
    }

    /// The departure this card is the flying copy of, or `nil` if this card is a live one.
    ///
    /// The one rule, asked in both places, so that the list of rows and the way a row is
    /// drawn can never disagree. Undo is live throughout the tidy-up window
    /// (`DeckControlsView`) and it puts the departing card straight back into
    /// `visibleCards`, so between the undo and the tidy-up timer the same id is both
    /// "departing" and live. Two `ForEach` rows with one id is undefined behaviour in
    /// SwiftUI, so the copy yields to the live card — and, because it has yielded, that
    /// row must then be drawn as a live card. Matching on `departing?.card.id` alone drew
    /// the restored card with the flight transform instead: off screen, faded to nothing
    /// and refusing the gesture until the timer happened to fire.
    private func departingCopy(matching card: DeckCard) -> DepartingCard? {
        guard let item = departing, item.card.id == card.id else { return nil }
        guard !model.visibleCards.contains(where: { $0.id == card.id }) else { return nil }
        return item
    }

    private func cardLayer(for card: DeckCard, width: CGFloat) -> some View {
        // Non-nil only for the one card that is currently flying away. Every modifier
        // below is applied unconditionally, with values switched on this, because
        // *adding* or *removing* a modifier would change the view's structural identity
        // and cost the loaded image all over again.
        let departingItem: DepartingCard? = departingCopy(matching: card)
        let isDeparting = departingItem != nil

        // A card that is no longer visible reports depth 0, which is what a departing
        // card wants anyway: it left from the top of the stack.
        let depth = isDeparting ? 0 : model.depth(of: card)

        // A departing card is never the top card: the model advanced the instant the
        // finger lifted, so the live top card is the next photo, and only that one takes
        // the gesture, the hit testing and the VoiceOver focus.
        let isTop = !isDeparting && depth == 0
        let mask: GestureMask = isTop ? .all : .none

        let progress = CGFloat(departProgress)
        let translation: CGSize
        if let item = departingItem {
            // 0 = where the finger left it, 1 = gone.
            translation = CGSize(
                width: item.start.width + (item.target.width - item.start.width) * progress,
                height: item.start.height + (item.target.height - item.start.height) * progress
            )
        } else {
            translation = isTop ? dragOffset : CGSize.zero
        }

        return PhotoCardView(
            model: model,
            card: card,
            depth: depth,
            dragTranslation: translation,
            cardWidth: width
        )
        .scaleEffect(isTop ? 1 : DeckStackMetrics.scale(depth: depth))
        .offset(
            x: translation.width,
            y: isDeparting || isTop
                ? translation.height
                : DeckStackMetrics.verticalOffset(depth: depth)
        )
        .rotationEffect(
            .degrees(rotationDegrees(forHorizontal: translation.width)),
            anchor: .bottom
        )
        .opacity(isDeparting ? 1 - departProgress : 1)
        .gesture(dragGesture(for: card, width: width), including: mask)
        // Long press is simultaneous so that it does not fight the drag for the touch.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.3).onEnded { _ in
                // Presenting the peek cover cancels whatever drag is in flight, and a
                // cancelled gesture never delivers `onEnded`, so the drag state is
                // cleared here rather than left to a callback that will not arrive.
                // Without this the card comes back from the peek still nudged sideways
                // and tilted, for the rest of the session.
                dragOffset = .zero
                hasCrossedThreshold = false
                onPeek(card)
            },
            including: mask
        )
        .allowsHitTesting(isTop)
        .accessibilityHidden(!isTop)
        // No accessibility actions here. `PhotoCardView` is an `.accessibilityElement`
        // in its own right and already publishes Keep, Bin, Undo and Try again on it;
        // adding Keep and Bin again at this level put two of each in the actions rotor.
        //
        // The departing card sits above the whole live stack: it shares depth 0 with the
        // new top card, so without this it would flicker underneath it on its way out.
        .zIndex(isDeparting ? 10 : Double(3 - depth))
    }

    // MARK: - Gesture

    private func dragGesture(for card: DeckCard, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                guard !isCommitting else { return }
                dragOffset = value.translation

                // Feedback only. A decision must never be taken here: `onChanged` fires
                // on every touch sample, so it would mark several photos per swipe and
                // then mark one more in `onEnded`.
                let crossed = abs(value.translation.width) >= SwipeMetrics.threshold(forCardWidth: width)
                if crossed != hasCrossedThreshold {
                    hasCrossedThreshold = crossed
                    if crossed { Haptics.crossedThreshold() }
                }
            }
            .onEnded { value in
                guard !isCommitting else { return }
                hasCrossedThreshold = false

                let outcome = SwipeMetrics.outcome(
                    translation: value.translation.width,
                    predictedEnd: value.predictedEndTranslation.width,
                    velocity: value.velocity.width,
                    cardWidth: width,
                    mapping: model.mapping
                )

                guard let decision = outcome else {
                    withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.75)) {
                        dragOffset = .zero
                    }
                    return
                }

                commit(decision, card: card, width: width)
            }
    }

    /// Records the decision and starts the departure animation, in that order of importance.
    ///
    /// The fly-off is purely decorative. `model.decide` is called synchronously while the
    /// finger is still lifting, and nothing in the model waits for the animation to
    /// finish, because an animation interrupted by the next swipe would otherwise leave
    /// the deck stuck forever.
    private func commit(_ decision: Decision, card: DeckCard, width: CGFloat) {
        isCommitting = true

        let id = card.id
        let token = UUID()
        let start = dragOffset
        let target: CGSize

        if reduceMotion {
            // Reduced motion gets a cross-fade in place: same information, no travel.
            target = start
        } else {
            let flyX = model.mapping.horizontalSign(for: decision) * width * DeckStackMetrics.flyAwayWidthMultiple
            target = CGSize(width: flyX, height: start.height)
        }

        departProgress = 0
        departing = DepartingCard(token: token, card: card, start: start, target: target)

        model.decide(decision, expecting: id)

        // The live top card must snap to its resting place with no animation at all,
        // otherwise the incoming photo slides in from wherever the last one was dropped.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dragOffset = .zero
        }

        isCommitting = false

        let duration = reduceMotion ? DeckStackMetrics.crossFadeDuration : DeckStackMetrics.flyAwayDuration

        // Started on the next turn of the run loop so that the copy is on screen at its
        // starting position for one frame before it is animated away; without that,
        // SwiftUI only ever sees the finished state and there is nothing to animate.
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: duration)) {
                departProgress = 1
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.1) {
            guard departing?.token == token else { return }
            departing = nil
            departProgress = 0
        }
    }

    // MARK: - Geometry

    private func rotationDegrees(forHorizontal dx: CGFloat) -> Double {
        guard !reduceMotion else { return 0 }
        let raw = Double(dx / SwipeMetrics.rotationDivisor)
        return min(max(raw, -DeckStackMetrics.maximumRotationDegrees), DeckStackMetrics.maximumRotationDegrees)
    }
}
