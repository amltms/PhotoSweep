import Foundation
import Photos

/// The one and only place in PhotoSweep that deletes anything.
///
/// `PHAssetChangeRequest.deleteAssets` appears exactly once in this entire codebase, and it
/// appears here. Nothing else — no gesture, no view, no model mutation — may call it. A swipe
/// only ever appends a `String` to an array; this type is reached solely from the explicit
/// delete button on the bin screen, and it is the last gate before a photo leaves the user's
/// library. If you are about to add a second call site, the answer is no: route it through
/// `delete(ids:)` instead, so the re-resolution, the eligibility filter and the cancellation
/// handling below can never be bypassed.
///
/// Note that this still does not destroy anything permanently: deleted assets land in the
/// Photos app's Recently Deleted album for roughly 30 days. No third-party app is permitted to
/// empty that album, and PhotoSweep never tries.
@MainActor
enum DeletionService {

    /// The only place in this app that deletes anything.
    /// Re-resolves `ids`, drops anything that has vanished or cannot be deleted, and commits
    /// the remainder in a single `performChanges`.
    static func delete(ids: [String]) async -> CommitOutcome {
        guard !ids.isEmpty else { return .nothingToDelete }

        // Re-resolve at the moment of deletion rather than trusting anything captured at swipe
        // time: an asset can be removed from the library by the Photos app, by another app, or
        // by an iCloud sync between the swipe and this button press. A shorter result than
        // `ids` is the normal case, not an error, so the missing ones are dropped in silence.
        let resolved = AssetResolver.assets(for: ids)
        guard !resolved.isEmpty else { return .nothingToDelete }

        // `deleteAssets` is atomic: a single asset the app is not allowed to delete fails the
        // entire batch and nothing at all is removed. So eligibility is re-checked here, as
        // late as possible, even though it was already checked when the card entered the deck.
        let survivingAssets = resolved.filter { Eligibility.canDelete($0) }
        guard !survivingAssets.isEmpty else { return .nothingToDelete }

        // Read the count here, on the main actor, so the completion handler below captures a
        // plain `Int` rather than the `[PHAsset]` array. PhotoKit objects never cross an
        // isolation boundary in this app; numbers and strings do.
        let deletedCount = survivingAssets.count

        return await withCheckedContinuation { (continuation: CheckedContinuation<CommitOutcome, Never>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.deleteAssets(survivingAssets as NSArray)
            }, completionHandler: { success, error in
                // This handler arrives on a private background queue, and PhotoKit calls it
                // exactly once, so the continuation is resumed exactly once here and nowhere
                // else in this function. Nothing here touches state, so there is no hop to
                // main: `outcome` is deliberately `nonisolated` and pure.
                continuation.resume(returning: outcome(success: success,
                                                       error: error,
                                                       deletedCount: deletedCount))
            })
        }
    }

    /// Turns PhotoKit's `(Bool, Error?)` pair into something the user can be told honestly.
    ///
    /// Kept separate from the continuation so the cancellation rule is readable: the user
    /// tapping "Don't Allow" on the system confirmation is reported as an error, and treating
    /// that as a failure would accuse the app of breaking when the user simply changed their
    /// mind.
    ///
    /// `nonisolated` because PhotoKit runs the completion handler on its own queue: this
    /// function reads no state, only its arguments and a constant string, so it is safe to
    /// call from there and from the main actor alike.
    private nonisolated static func outcome(success: Bool, error: Error?, deletedCount: Int) -> CommitOutcome {
        if success {
            // The count actually committed, never the count originally requested.
            return .deleted(count: deletedCount)
        }

        guard let error else {
            // performChanges failing with no error at all is not documented; report it as a
            // failure rather than quietly claiming a deletion that did not happen.
            return .failed(reason: Strings.genericErrorTitle)
        }

        let nsError = error as NSError
        if nsError.domain == PHPhotosErrorDomain,
           nsError.code == PHPhotosError.Code.userCancelled.rawValue {
            return .cancelledByUser
        }

        return .failed(reason: error.localizedDescription)
    }
}
