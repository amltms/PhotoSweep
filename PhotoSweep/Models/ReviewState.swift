import Foundation

/// Everything that must survive a relaunch.
///
/// Every field after `schemaVersion` has a default, so an older file decodes into a newer
/// build without a migration step. New fields must always be added with a default or as
/// `Optional`, never as a bare required property.
struct ReviewState: Codable, Equatable {

    var schemaVersion: Int = 1

    /// Identifies the library this state belongs to. `localIdentifier` values are device-
    /// local: they do not survive a restore onto another device, and reusing them there
    /// would mean deciding about photos the user has never seen. On a mismatch the whole
    /// store is discarded rather than half-trusted.
    var fingerprint: String = ""

    /// Assets the user has already decided about, so they are never shown twice.
    var decidedIDs: [String] = []

    /// The bin: ordered, because the review grid shows them in the order they were binned.
    /// Still just strings — no `PHAsset` is ever persisted.
    var pendingDeletionIDs: [String] = []

    var lifetimeReviewed: Int = 0
    var lifetimeBinned: Int = 0
    var lifetimeDeleted: Int = 0

    var receipts: [DeletionReceipt] = []

    var hasCompletedOnboarding: Bool = false
    var hasCompletedRehearsal: Bool = false

    /// The invert setting in force when the rehearsal was last passed, so swapping the
    /// directions re-runs the practice rather than letting muscle memory bin a photo.
    var rehearsedWithInvert: Bool = false

    static let currentSchemaVersion = 1
}

/// A record of one batch actually being deleted. Shown in Settings so the user can see
/// what the app has done on their behalf.
struct DeletionReceipt: Codable, Equatable, Identifiable, Hashable {
    var id: UUID = UUID()
    var date: Date
    var count: Int
    var pile: String

    var summary: String {
        count == 1 ? "1 photo" : "\(Formatters.count(count)) photos"
    }
}
