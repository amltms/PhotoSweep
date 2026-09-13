import Foundation
import Observation

/// The user's preferences, each one a single scalar in `UserDefaults`.
///
/// Preferences live here rather than in `ReviewStateStore` because they are small, they
/// are not photo identifiers, and losing one costs the user a toggle rather than their
/// progress. The store's rule about never putting identifiers in `UserDefaults` still holds.
@MainActor
@Observable
final class AppSettings {

    /// Defaults keys in one place, so a typo cannot silently split a setting into two.
    private enum Key {
        static let invertSwipeDirection = "settings.invertSwipeDirection"
        static let hapticsEnabled = "settings.hapticsEnabled"
        static let confirmBeforeCommit = "settings.confirmBeforeCommit"
        static let sortNewestFirst = "settings.sortNewestFirst"
        static let includeFavourites = "settings.includeFavourites"
    }

    // MARK: - Backing storage
    //
    // The five settings below are stored here and exposed under the contract's names as
    // computed pairs. They cannot be plain stored properties carrying `didSet`: the
    // `@Observable` macro rewrites every stored property into its own `get`/`set` pair,
    // and one property cannot have both a setter and a `didSet`. Writing to
    // `UserDefaults` from the wrapper's setter is the same behaviour with no macro
    // conflict — and because the backing properties are ordinary stored properties, the
    // macro still tracks them, so `@Bindable` toggles refresh exactly as before.

    private var storedInvertSwipeDirection: Bool = false
    private var storedHapticsEnabled: Bool = true
    private var storedConfirmBeforeCommit: Bool = true
    private var storedSortNewestFirst: Bool = true
    private var storedIncludeFavourites: Bool = false

    // MARK: - Settings

    /// `false` — the default — means a rightward swipe bins the photo, as specified.
    var invertSwipeDirection: Bool {
        get { storedInvertSwipeDirection }
        set {
            storedInvertSwipeDirection = newValue
            UserDefaults.standard.set(newValue, forKey: Key.invertSwipeDirection)
        }
    }

    var hapticsEnabled: Bool {
        get { storedHapticsEnabled }
        set {
            storedHapticsEnabled = newValue
            UserDefaults.standard.set(newValue, forKey: Key.hapticsEnabled)
            // `Haptics` is a plain enum with no way to read a setting, so this is the one
            // place that keeps it in step with the toggle.
            Haptics.isEnabled = newValue
        }
    }

    var confirmBeforeCommit: Bool {
        get { storedConfirmBeforeCommit }
        set {
            storedConfirmBeforeCommit = newValue
            UserDefaults.standard.set(newValue, forKey: Key.confirmBeforeCommit)
        }
    }

    var sortNewestFirst: Bool {
        get { storedSortNewestFirst }
        set {
            storedSortNewestFirst = newValue
            UserDefaults.standard.set(newValue, forKey: Key.sortNewestFirst)
        }
    }

    var includeFavourites: Bool {
        get { storedIncludeFavourites }
        set {
            storedIncludeFavourites = newValue
            UserDefaults.standard.set(newValue, forKey: Key.includeFavourites)
        }
    }

    /// The only supported way to turn the invert flag into a direction. Nothing else in
    /// the app reads `invertSwipeDirection`.
    var mapping: SwipeMapping {
        SwipeMapping(invert: invertSwipeDirection)
    }

    init() {
        let defaults = UserDefaults.standard

        // Registered before anything is read: `bool(forKey:)` reports `false` for an absent
        // key, which is the wrong answer for the three settings that default to on.
        defaults.register(defaults: [
            Key.invertSwipeDirection: false,
            Key.hapticsEnabled: true,
            Key.confirmBeforeCommit: true,
            Key.sortNewestFirst: true,
            Key.includeFavourites: false
        ])

        // Straight into the backing storage, deliberately bypassing the setters above:
        // going through them would write every value the app has just read back out to
        // `UserDefaults` on every launch.
        storedInvertSwipeDirection = defaults.bool(forKey: Key.invertSwipeDirection)
        storedHapticsEnabled = defaults.bool(forKey: Key.hapticsEnabled)
        storedConfirmBeforeCommit = defaults.bool(forKey: Key.confirmBeforeCommit)
        storedSortNewestFirst = defaults.bool(forKey: Key.sortNewestFirst)
        storedIncludeFavourites = defaults.bool(forKey: Key.includeFavourites)

        // And because no setter ran, the haptics flag has to be pushed across by hand.
        Haptics.isEnabled = storedHapticsEnabled
    }
}
