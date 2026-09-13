import UIKit

/// Haptic feedback, via plain `UIFeedbackGenerator`.
///
/// Deliberately not SwiftUI's `.sensoryFeedback`: that fires on a *change* of a trigger
/// value, so a `Bool` set and cleared within one update cycle nets to no change and is
/// silently never felt. A direct call has no such failure mode.
@MainActor
enum Haptics {

    /// Mirrors the user's setting. `AppSettings` writes it; nothing else does.
    static var isEnabled: Bool = true

    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let notification = UINotificationFeedbackGenerator()
    private static let selection = UISelectionFeedbackGenerator()

    /// Warms the generators so the first tap is not late. Cheap, and safe to call often.
    static func prepare() {
        guard isEnabled else { return }
        light.prepare()
        medium.prepare()
        rigid.prepare()
    }

    static func keep() {
        guard isEnabled else { return }
        light.impactOccurred()
        light.prepare()
    }

    static func bin() {
        guard isEnabled else { return }
        rigid.impactOccurred()
        rigid.prepare()
    }

    static func undo() {
        guard isEnabled else { return }
        medium.impactOccurred(intensity: 0.7)
        medium.prepare()
    }

    /// The moment a drag crosses the commit threshold, so the decision is felt before
    /// the finger lifts.
    static func crossedThreshold() {
        guard isEnabled else { return }
        selection.selectionChanged()
        selection.prepare()
    }

    static func success() {
        guard isEnabled else { return }
        notification.notificationOccurred(.success)
    }

    static func warning() {
        guard isEnabled else { return }
        notification.notificationOccurred(.warning)
    }

    static func failure() {
        guard isEnabled else { return }
        notification.notificationOccurred(.error)
    }
}
