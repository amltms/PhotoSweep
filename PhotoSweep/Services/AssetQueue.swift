import Foundation
import Photos

/// A window onto a `PHFetchResult` that never materialises it.
///
/// A `PHFetchResult` is lazy: it answers `count` immediately over an arbitrarily large
/// library and faults assets in only as they are asked for. Every convenience that would
/// flatten it — `objects(at: IndexSet(0..<count))`, `map`, a `for`-`in` loop — pulls the
/// whole library into memory at once and is banned. This type is the only thing in the app
/// that touches a fetch result, so the laziness cannot be lost by accident somewhere else.
///
/// `PHFetchResult.objects(at:)` and `object(at:)` raise an Objective-C `NSRangeException`
/// when asked for an index they do not have. That exception is **uncatchable** from Swift:
/// there is no `try`, no `do`/`catch` and no recovery — the process dies. The count can also
/// change underneath the app whenever the library does. So every access below reads `count`
/// and clamps against it inside the same synchronous block that performs the access, with no
/// `await` in between, which is what makes the clamp trustworthy.
@MainActor
final class AssetQueue {

    private(set) var fetchResult: PHFetchResult<PHAsset>

    var count: Int { fetchResult.count }

    init(fetchResult: PHFetchResult<PHAsset>) {
        self.fetchResult = fetchResult
    }

    /// `nil` for any out-of-range index. Never traps.
    func asset(at index: Int) -> PHAsset? {
        let total = fetchResult.count
        guard index >= 0, index < total else { return nil }
        return fetchResult.object(at: index)
    }

    /// Faults in one clamped window with a single `objects(at:)` call. Returns `[]` if the
    /// clamped range is empty.
    ///
    /// One call rather than a loop of `object(at:)` because PhotoKit can satisfy a batch
    /// from a single backing query, and because a loop is the shape that later grows into
    /// an accidental full materialisation.
    func assets(in range: Range<Int>) -> [PHAsset] {
        let total = fetchResult.count
        guard total > 0 else { return [] }

        let lower = max(0, range.lowerBound)
        let upper = min(total, range.upperBound)
        guard lower < upper else { return [] }

        return fetchResult.objects(at: IndexSet(integersIn: lower..<upper))
    }

    func adopt(_ newResult: PHFetchResult<PHAsset>) {
        fetchResult = newResult
    }

    /// Searches outwards from `hint` before falling back to a full scan, so re-finding the
    /// user's place after a library change is cheap in the common case.
    ///
    /// After a library change the user's current photo has usually moved by a handful of
    /// positions at most — a few imports at the front, a few deletions behind — so probing
    /// `hint`, `hint - 1`, `hint + 1`, `hint - 2`, … finds it within a few reads.
    ///
    /// The fallback is a linear scan, and it is genuinely O(n) in faulted assets: the
    /// obvious alternative, `PHFetchResult.index(of:)`, takes a `PHAsset`, and all this app
    /// ever holds of a photo is its `localIdentifier` string, so there is no object to hand
    /// it. Re-fetching an asset by identifier purely to call `index(of:)` would be a second
    /// round trip to PhotoKit for the same answer. The scan therefore stays, and it stays
    /// cheap in practice because it only ever runs when the outward probe has already
    /// failed, which means the photo has moved further than `searchRadius` or has gone
    /// altogether — at which point a `nil` return is the right answer anyway.
    func firstIndex(ofLocalIdentifier id: String, near hint: Int, searchRadius: Int = 200) -> Int? {
        let total = fetchResult.count
        guard total > 0 else { return nil }

        let anchor = min(max(hint, 0), total - 1)

        if let asset = asset(at: anchor), asset.localIdentifier == id {
            return anchor
        }

        var offset = 1
        while offset <= searchRadius {
            let before = anchor - offset
            let after = anchor + offset

            // Both ends have run off the fetch result, so widening further cannot help.
            if before < 0 && after >= total { break }

            if let asset = asset(at: before), asset.localIdentifier == id {
                return before
            }
            if let asset = asset(at: after), asset.localIdentifier == id {
                return after
            }

            offset += 1
        }

        for index in 0..<total {
            if let asset = asset(at: index), asset.localIdentifier == id {
                return index
            }
        }

        return nil
    }
}
