import SwiftUI

/// The always-visible controls beneath the deck: keep, undo, bin, plus the bin door.
///
/// The left/right placement of Keep and Bin mirrors the swipe directions, so a user who
/// has swapped the directions in Settings sees the buttons swap too. Pressing a button
/// and swiping that way must never mean two different things, or the buttons become a
/// second source of truth that quietly contradicts the gesture.
struct DeckControlsView: View {

    let model: AppModel
    var onOpenBin: () -> Void

    private var leadingDecision: Decision {
        model.mapping.binIsRight ? .keep : .bin
    }

    private var trailingDecision: Decision {
        model.mapping.binIsRight ? .bin : .keep
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                decisionButton(leadingDecision)
                undoButton
                decisionButton(trailingDecision)
            }

            // No legend here: `SwipeDeckView` already draws `model.mapping.legend`
            // directly beneath the card stack, and `DeckScreen` stacks that immediately
            // above these controls, so a second copy printed the same line twice.

            binButton
        }
        .padding(.horizontal, Theme.screenPadding)
    }

    // MARK: - Decision buttons

    private func decisionButton(_ decision: Decision) -> some View {
        Button {
            // `decide` guards on the identifier itself, so a stale press after the deck
            // has moved on is a harmless no-op rather than a wrong decision.
            guard let id = model.currentCard?.id else { return }
            model.decide(decision, expecting: id)
        } label: {
            VStack(spacing: 5) {
                Image(systemName: decision == .keep ? "hand.thumbsup.fill" : "trash.fill")
                    .font(.system(size: 20, weight: .semibold))

                Text(decision == .keep ? Strings.keep : Strings.bin)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: Theme.minimumTapTarget)
            .background(
                RoundedRectangle(cornerRadius: Theme.controlCornerRadius, style: .continuous)
                    .fill(decision == .keep ? Theme.green : Theme.red)
            )
        }
        .buttonStyle(.plain)
        .disabled(model.currentCard == nil)
        .opacity(model.currentCard == nil ? 0.45 : 1)
        .accessibilityLabel(decision == .keep ? Strings.a11yKeepAction : Strings.a11yBinAction)
    }

    private var undoButton: some View {
        Button {
            model.undo()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 18, weight: .semibold))

                Text(Strings.undo)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.vertical, 12)
            .frame(width: 78, alignment: .center)
            .frame(minHeight: Theme.minimumTapTarget)
            .background(
                RoundedRectangle(cornerRadius: Theme.controlCornerRadius, style: .continuous)
                    .fill(Theme.surfaceRaised)
            )
        }
        .buttonStyle(.plain)
        .disabled(!model.canUndo)
        .opacity(model.canUndo ? 1 : 0.45)
        .accessibilityLabel(Strings.a11yUndoAction)
    }

    // MARK: - Bin door

    private var binButton: some View {
        Button(action: onOpenBin) {
            HStack(spacing: 8) {
                Image(systemName: "tray.full")
                    .font(.system(size: 15, weight: .semibold))

                Text(Strings.binTitle)
                    .font(.subheadline.weight(.semibold))

                Text(Formatters.count(model.pendingCount))
                    .font(.footnote.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.red))
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 18)
            .frame(minHeight: Theme.minimumTapTarget)
        }
        .buttonStyle(.plain)
        .panel(cornerRadius: Theme.controlCornerRadius)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Strings.a11yOpenBin)
        .accessibilityValue(Formatters.count(model.pendingCount))
    }
}
