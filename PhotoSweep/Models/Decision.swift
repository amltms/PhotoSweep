import CoreGraphics
import Foundation

/// What the user decided about one photo.
///
/// `bin` means "put this on the list" — it never means "delete this". Deletion happens
/// only in `DeletionService`, only from the bin screen, and only on an explicit press.
enum Decision: String, Codable, Hashable, Sendable {
    case keep
    case bin
}

/// The single place in this codebase allowed to decide what a horizontal direction means.
///
/// Nothing else may compare a horizontal translation against zero, and nothing else may
/// read `invertSwipeDirection`. Applying the flag in two places inverts it back; hard-coding
/// "right is red" anywhere shows the wrong label to anyone who has swapped the directions.
struct SwipeMapping: Equatable, Sendable {

    /// `false` — the default — means a rightward swipe bins the photo, as specified.
    var invert: Bool

    init(invert: Bool = false) {
        self.invert = invert
    }

    var binIsRight: Bool { !invert }

    /// The decision a horizontal translation of `dx` represents.
    func decision(forHorizontal dx: CGFloat) -> Decision {
        let rightward = dx > 0
        return rightward == binIsRight ? .bin : .keep
    }

    /// `+1` if this decision flies the card to the right, `-1` if to the left.
    func horizontalSign(for decision: Decision) -> CGFloat {
        switch decision {
        case .bin: return binIsRight ? 1 : -1
        case .keep: return binIsRight ? -1 : 1
        }
    }

    /// The decision the user is currently heading towards, or `nil` below the dead zone.
    func previewDecision(forHorizontal dx: CGFloat, deadZone: CGFloat = 12) -> Decision? {
        guard abs(dx) > deadZone else { return nil }
        return decision(forHorizontal: dx)
    }

    var legend: String {
        binIsRight ? Strings.deckLegendBinRight : Strings.deckLegendBinLeft
    }

    var accessibilityHint: String {
        binIsRight ? Strings.a11yCardHintBinRight : Strings.a11yCardHintBinLeft
    }
}

/// Geometry for the swipe gesture. Symmetric by design: making the bin direction
/// harder to reach is exactly the kind of feel tuning that cannot be validated
/// without running the app on a device.
enum SwipeMetrics {

    /// How much of a card's width must be crossed before a swipe counts.
    static let thresholdFraction: CGFloat = 0.28

    /// A floor, so the threshold stays sane on a narrow card.
    static let minimumThreshold: CGFloat = 90

    /// A flick this fast counts even if it did not travel far.
    static let escapeVelocity: CGFloat = 500

    /// How much of the predicted end translation to trust.
    static let projectionFactor: CGFloat = 0.35

    /// Degrees of card rotation per point of horizontal drag.
    static let rotationDivisor: CGFloat = 22

    static func threshold(forCardWidth width: CGFloat) -> CGFloat {
        max(minimumThreshold, width * thresholdFraction)
    }

    /// Where the drag is predicted to end up, blending travel with momentum.
    static func projectedTranslation(translation: CGFloat, predictedEnd: CGFloat) -> CGFloat {
        translation + (predictedEnd - translation) * projectionFactor
    }

    /// The decision a finished drag represents, or `nil` if the card should spring back.
    static func outcome(
        translation: CGFloat,
        predictedEnd: CGFloat,
        velocity: CGFloat,
        cardWidth: CGFloat,
        mapping: SwipeMapping
    ) -> Decision? {
        let limit = threshold(forCardWidth: cardWidth)
        let projected = projectedTranslation(translation: translation, predictedEnd: predictedEnd)

        if projected > limit || velocity > escapeVelocity {
            return mapping.decision(forHorizontal: 1)
        }
        if projected < -limit || velocity < -escapeVelocity {
            return mapping.decision(forHorizontal: -1)
        }
        return nil
    }
}

/// One reversible step. The stack is a plain array, never `UndoManager`, whose
/// responder-chain scoping in SwiftUI is subtle enough to get wrong invisibly.
struct UndoEntry: Equatable, Hashable {
    let id: String
    let decision: Decision
}

/// What actually happened when the user pressed the delete button.
///
/// There is no `.success` without a count and no silent failure: every branch says
/// something true to the user.
enum CommitOutcome: Equatable {
    case deleted(count: Int)
    case cancelledByUser
    case nothingToDelete
    case failed(reason: String)

    var message: String {
        switch self {
        case .deleted(let count): return Strings.commitSucceeded(count)
        case .cancelledByUser: return Strings.commitCancelled
        case .nothingToDelete: return Strings.commitNothingToDo
        case .failed(let reason): return Strings.commitFailed(reason)
        }
    }

    var isSuccess: Bool {
        if case .deleted = self { return true }
        return false
    }
}
