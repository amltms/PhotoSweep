import SwiftUI

/// Two practice swipes on cards made of SF Symbols, before any real photo is shown.
///
/// Reading about a direction and performing it are different kinds of learning, and only
/// the second one survives contact with a thumb. No real asset is loaded, touched or
/// decided about here: the practice cards are drawings, so a mistake during practice costs
/// nothing at all.
///
/// The required direction is always read from `model.mapping`, never assumed, so a user who
/// has already swapped the directions in Settings rehearses the arrangement they will
/// actually use.
@MainActor
struct RehearsalView: View {

    let model: AppModel
    var onFinished: () -> Void

    /// 0 = practise the bin swipe, 1 = practise the keep swipe, 2 = finished.
    @State private var stepIndex: Int = 0

    /// Plain `@State`, never `@GestureState`: a gesture state resets itself before
    /// `onEnded` runs, which silently turns every swipe into a spring-back.
    @State private var offset: CGSize = .zero

    @State private var showWrongWay: Bool = false

    private static let stepCount = 2

    private var isFinished: Bool { stepIndex >= Self.stepCount }

    private var requiredDecision: Decision {
        stepIndex == 0 ? .bin : .keep
    }

    private var promptText: String {
        stepIndex == 0 ? Strings.rehearsalPromptBin : Strings.rehearsalPromptKeep
    }

    private var practiceSymbol: String {
        stepIndex == 0 ? "photo.fill" : "sun.max.fill"
    }

    private var directionArrow: String {
        model.mapping.horizontalSign(for: requiredDecision) > 0 ? "arrow.right" : "arrow.left"
    }

    private var directionTint: Color {
        requiredDecision == .bin ? Theme.bin : Theme.keep
    }

    var body: some View {
        ZStack {
            ScreenBackground()

            GeometryReader { geo in
                let cardWidth = practiceCardWidth(in: geo.size)

                VStack(spacing: Theme.stackSpacing) {
                    header
                    progressIndicator

                    Spacer(minLength: 8)

                    if isFinished {
                        finishedBlock
                    } else {
                        practiceBlock(cardWidth: cardWidth)
                    }

                    Spacer(minLength: 8)

                    if isFinished {
                        Button(Strings.rehearsalStart) {
                            onFinished()
                        }
                        .buttonStyle(PrimaryButtonStyle(role: .positive))
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.vertical, Theme.screenPadding)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            }
        }
        .onAppear {
            Haptics.prepare()
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(spacing: 8) {
            Text(Strings.rehearsalTitle)
                .font(.title2.bold())
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)

            Text(Strings.rehearsalBody)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(model.mapping.legend)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    /// Two bars, one per practice swipe. A completed step turns green so the reward for
    /// getting it right is visible as well as felt.
    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<Self.stepCount, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(barColour(forStep: index))
                    .frame(height: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func barColour(forStep index: Int) -> Color {
        if index < stepIndex { return Theme.green }
        if index == stepIndex { return Theme.lightBlue }
        return Theme.hairline
    }

    /// Points reserved for everything on this screen that is not the practice card: the
    /// header, the progress bars, the prompt and its arrow, the wrong-way line, the stack
    /// spacing and the screen padding. Measured generously on purpose.
    private static let chromeHeight: CGFloat = 380

    /// The practice card is clamped by the available height as well as by the width.
    ///
    /// Sizing it from the width alone gives a 240x320 card on a small phone, which is
    /// taller than the space left once the header and the prompt have taken theirs. A
    /// `.frame(width:height:)` cannot shrink to make room, so the overflow is silent
    /// clipping of the prompt and the progress bars — on the one screen where the prompt
    /// is the entire point of the exercise.
    private func practiceCardWidth(in size: CGSize) -> CGFloat {
        let byWidth = min(size.width - Theme.screenPadding * 4, 280)
        let byHeight = max(0, size.height - Self.chromeHeight) * 3 / 4
        return max(120, min(byWidth, byHeight))
    }

    private func practiceBlock(cardWidth: CGFloat) -> some View {
        VStack(spacing: Theme.stackSpacing) {

            VStack(spacing: 10) {
                Text(promptText)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)

                Image(systemName: directionArrow)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(directionTint)
                    .accessibilityHidden(true)
            }

            practiceCard(cardWidth: cardWidth)

            // Always laid out and only faded, so the card does not jump when the message
            // appears. `minHeight` rather than `height`: this sentence wraps to two lines
            // on a narrow phone and at almost any accessibility text size, and a hard
            // height would clip it rather than reserve room for it.
            Text(Strings.rehearsalWrongWay)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.yellow)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 22)
                .opacity(showWrongWay ? 1 : 0)
                .accessibilityHidden(!showWrongWay)
        }
    }

    private func practiceCard(cardWidth: CGFloat) -> some View {
        let preview = model.mapping.previewDecision(forHorizontal: offset.width)

        return RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
            .fill(Theme.surfaceRaised)
            .overlay {
                Image(systemName: practiceSymbol)
                    .font(.system(size: 84, weight: .light))
                    .foregroundStyle(Theme.textTertiary)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .stroke(borderColour(for: preview), lineWidth: 3)
            }
            .frame(width: cardWidth, height: cardWidth * 4 / 3)
            .rotationEffect(.degrees(offset.width / SwipeMetrics.rotationDivisor))
            .offset(x: offset.width, y: offset.height * 0.2)
            .gesture(dragGesture(cardWidth: cardWidth))
            .id(stepIndex)
            .transition(.opacity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(promptText)
            .accessibilityHint(model.mapping.accessibilityHint)
            .accessibilityAction(named: Text(Strings.a11yBinAction)) {
                complete(.bin)
            }
            .accessibilityAction(named: Text(Strings.a11yKeepAction)) {
                complete(.keep)
            }
    }

    private func borderColour(for preview: Decision?) -> Color {
        switch preview {
        case .some(.bin): return Theme.bin
        case .some(.keep): return Theme.keep
        case .none: return Theme.hairline
        }
    }

    private var finishedBlock: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64, weight: .regular))
                .foregroundStyle(Theme.green)
                .accessibilityHidden(true)

            Text(Strings.rehearsalDone)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - The gesture

    /// Judged with exactly the same `SwipeMetrics.outcome` call the real deck uses, so the
    /// distance and flick speed that work here are the ones that will work on a photo.
    private func dragGesture(cardWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                offset = value.translation
                if showWrongWay {
                    showWrongWay = false
                }
            }
            .onEnded { value in
                let outcome = SwipeMetrics.outcome(
                    translation: value.translation.width,
                    predictedEnd: value.predictedEndTranslation.width,
                    velocity: value.velocity.width,
                    cardWidth: cardWidth,
                    mapping: model.mapping
                )

                guard let outcome else {
                    // Not far enough to mean anything: no telling-off, just a spring back.
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                        offset = .zero
                    }
                    return
                }

                complete(outcome)
            }
    }

    /// The single place a practice swipe is judged, shared by the gesture and by the
    /// VoiceOver actions so that a rotor user can finish the rehearsal too.
    private func complete(_ decision: Decision) {
        guard !isFinished else { return }

        guard decision == requiredDecision else {
            Haptics.warning()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                showWrongWay = true
                offset = .zero
            }
            return
        }

        switch decision {
        case .bin: Haptics.bin()
        case .keep: Haptics.keep()
        }

        withAnimation(.easeOut(duration: 0.22)) {
            showWrongWay = false
            offset = .zero
            stepIndex += 1
        }
    }
}
