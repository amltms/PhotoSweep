import SwiftUI

/// The KEEP / BIN stamp that fades onto a card as it is dragged.
///
/// The stamp reads the `Decision` rather than the drag direction, so it stays correct
/// for a user who has swapped the swipe directions over in Settings.
struct SwipeStamp: View {

    private let decision: Decision
    private let strength: Double

    /// `strength` is 0...1: how far through the swipe the finger is.
    init(decision: Decision, strength: Double) {
        self.decision = decision
        self.strength = strength
    }

    private var clampedStrength: Double {
        guard strength.isFinite else { return 0 }
        if strength < 0 { return 0 }
        if strength > 1 { return 1 }
        return strength
    }

    private var text: String {
        switch decision {
        case .keep: return Strings.stampKeep
        case .bin: return Strings.stampBin
        }
    }

    private var tint: Color {
        switch decision {
        case .keep: return Theme.keep
        case .bin: return Theme.bin
        }
    }

    /// The two stamps lean opposite ways so the card reads differently at a glance
    /// even to someone who cannot tell the two colours apart.
    private var angle: Double {
        switch decision {
        case .keep: return -14
        case .bin: return 14
        }
    }

    var body: some View {
        Text(text)
            .font(.system(size: 34, weight: .heavy, design: .rounded))
            .kerning(2)
            .foregroundStyle(tint)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(tint, lineWidth: 4)
            )
            .rotationEffect(.degrees(angle))
            .opacity(clampedStrength)
            .scaleEffect(CGFloat(0.85 + 0.15 * clampedStrength))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
