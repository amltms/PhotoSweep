import Foundation
import Observation
import Photos
import UIKit

// MARK: - ImageSpec

/// The one and only description of how PhotoSweep asks PhotoKit for pixels.
///
/// Every size, content mode and options value lives here so that a prefetch and the matching
/// request are guaranteed to use the *same values*. `PHCachingImageManager` keys its cache on
/// that whole tuple of values — target size, content mode and the fields of the options — so a
/// target size that differs by a single point produces a permanent, silent, 100% cache miss
/// with no error anywhere.
///
/// It keys on the *values*, not on object identity. `PHImageRequestOptions` is `NSCopying` and
/// PhotoKit copies it at request time, so a second, identically configured instance still hits
/// the cache. That matters: `requestCardImage` must attach a per-request `progressHandler`, and
/// it can only do that safely on its own instance (see `makeCardOptions()`). Do not "simplify"
/// that back to one shared object.
enum ImageSpec {

    /// Fixed pixel dimensions, deliberately not derived from the screen. A size that varies
    /// with `displayScale` or a `GeometryReader` would differ between the prefetch call and
    /// the request call, which is the cache miss described above.
    static let card: CGSize = CGSize(width: 800, height: 1400)

    static let thumbnail: CGSize = CGSize(width: 300, height: 300)

    /// `.highQualityFormat` guarantees the result handler is called exactly **once**.
    /// `.opportunistic` calls it twice — a low-quality placeholder and then the real image —
    /// which turns any "have I finished loading?" flag into a lie.
    ///
    /// Used for `startCachingImages` / `stopCachingImages` only, and never mutated. A
    /// `progressHandler` must never be attached to it: caching calls have no one card to report
    /// to, and the deck has three or four loaders in flight at once.
    static let cardOptions: PHImageRequestOptions = ImageSpec.makeCardOptions()

    /// A fresh options object with exactly the same field values as `cardOptions`, for one
    /// single `requestImage` call that needs its own `progressHandler`.
    ///
    /// One options object shared across every request would mean one `progressHandler` alive in
    /// the whole process, and that handler carries no asset identity, so the receiver cannot
    /// filter it. The deck shows up to `DeckTuning.visibleDepth` cards plus the departing one,
    /// each with its own `CardImageLoader` requesting at the same time, so the last request to
    /// be issued would capture the handler and every iCloud download fraction in the app would
    /// be routed to that one card — the top card would never show `CloudDownloadBadge`, and a
    /// card behind it would draw a ring advancing on another photo's bytes.
    ///
    /// The values below are the ones the contract freezes, and must stay identical to the
    /// caching path's or the cache silently never hits.
    fileprivate static func makeCardOptions() -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        options.version = .current
        return options
    }

    /// Thumbnails may be resized fast: they are decoration on the bin grid, not something
    /// the user judges a deletion by.
    static let thumbnailOptions: PHImageRequestOptions = {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        options.version = .current
        return options
    }()

    static let prefetchAhead: Int = 8
    static let prefetchBehind: Int = 2

    /// Cropping is forbidden everywhere in this app: you cannot fairly judge a photo for
    /// deletion when part of it has been cut off by an aspect-fill.
    fileprivate static let contentMode: PHImageContentMode = .aspectFit
}

// MARK: - ImageLoadResult

/// The three things that can happen to an image request.
///
/// `cancelled` is separated from `failed` because a cancellation is a normal consequence of
/// the deck moving on, and must never show the user an error or a retry button.
enum ImageLoadResult {
    case image(UIImage)
    case failed
    case cancelled
}

// MARK: - ImagePipeline

/// The app's single owner of PhotoKit image delivery.
///
/// It holds one long-lived `PHCachingImageManager` for the lifetime of the app. Caching only
/// works within one manager instance, so a per-screen or per-request manager would quietly
/// throw away every prefetched image. This is also the only file in the codebase that is
/// allowed to name `PHCachingImageManager` or `PHImageRequestOptions`.
@MainActor
final class ImagePipeline {

    private let manager: PHCachingImageManager

    /// The assets currently registered with the caching manager, keyed by `localIdentifier`.
    ///
    /// Keyed by identifier rather than by `PHAsset` because `PHAsset` has no useful equality
    /// and must never be used as a dictionary key; two `PHAsset` objects for the same photo
    /// are common after a library change.
    private var cachedWindow: [String: PHAsset] = [:]

    init() {
        let manager = PHCachingImageManager()
        // Caching full-quality images for a whole window is a fast route to a memory
        // termination on an older device, and the deck only ever shows a fitted card.
        manager.allowsCachingHighQualityImages = false
        self.manager = manager
    }

    // MARK: Requests

    /// Requests the card-sized image for `asset`.
    ///
    /// `progress` reports iCloud download fraction and is only called for assets that are not
    /// already local. Both closures are always called on the main queue.
    @discardableResult
    func requestCardImage(
        for asset: PHAsset,
        progress: @escaping (Double) -> Void,
        completion: @escaping (ImageLoadResult) -> Void
    ) -> PHImageRequestID {

        // `progressHandler` is a property of the options object, not an argument of the
        // request, and it carries no asset identity — so a handler set on the one shared
        // `ImageSpec.cardOptions` would be the only handler in the process, and whichever
        // card asked last would swallow the download progress of every other card. The deck
        // has three or four loaders requesting at once, so this request gets its own options
        // object. The field values are identical to the caching path's, which is what the
        // cache actually matches on.
        let options = ImageSpec.makeCardOptions()
        options.progressHandler = { fraction, _, _, _ in
            guard fraction.isFinite else { return }
            // PhotoKit runs this on a background queue.
            DispatchQueue.main.async {
                progress(fraction)
            }
        }

        let requestID = manager.requestImage(
            for: asset,
            targetSize: ImageSpec.card,
            contentMode: ImageSpec.contentMode,
            options: options
        ) { image, info in
            // Read everything needed off the info dictionary here, then hand only plain
            // values to the main queue. A cancellation is not a failure.
            let wasCancelled = (info?[PHImageCancelledKey] as? Bool) == true

            DispatchQueue.main.async {
                if wasCancelled {
                    completion(.cancelled)
                } else if let image {
                    completion(.image(image))
                } else {
                    completion(.failed)
                }
            }
        }

        return requestID
    }

    /// Requests a small square-ish image for the bin grid. `nil` means "nothing to show",
    /// which the grid renders as a placeholder rather than as an error.
    @discardableResult
    func requestThumbnail(
        for asset: PHAsset,
        completion: @escaping (UIImage?) -> Void
    ) -> PHImageRequestID {

        return manager.requestImage(
            for: asset,
            targetSize: ImageSpec.thumbnail,
            contentMode: ImageSpec.contentMode,
            options: ImageSpec.thumbnailOptions
        ) { image, _ in
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    func cancel(_ id: PHImageRequestID) {
        guard id != PHInvalidImageRequestID else { return }
        manager.cancelImageRequest(id)
    }

    // MARK: Prefetching

    /// Registers `upcoming` with the caching manager and unregisters whatever has fallen out
    /// of the window.
    ///
    /// The target size, content mode and options values passed here are read from `ImageSpec`,
    /// field for field the same as `requestCardImage` passes to `requestImage` — that call uses
    /// its own options instance so it can carry a per-request `progressHandler`, which the cache
    /// does not match on. Any divergence in the *values* is a silent total cache miss, so
    /// nothing in this method is allowed to compute a size.
    func updatePrefetchWindow(upcoming: [PHAsset]) {
        var wanted: [String: PHAsset] = [:]
        var order: [String] = []

        for asset in upcoming {
            let id = asset.localIdentifier
            if wanted[id] == nil {
                wanted[id] = asset
                order.append(id)
            }
        }

        // Diff by identifier: the same photo may arrive as a different PHAsset object after a
        // library change, and re-caching it would throw away a perfectly good cached image.
        //
        // Written as plain loops rather than `compactMap` with a ternary returning `nil`, so
        // that the element type of each array is stated rather than inferred through two
        // levels of optionality.
        var leaving: [PHAsset] = []
        for (id, asset) in cachedWindow where wanted[id] == nil {
            leaving.append(asset)
        }

        var arriving: [PHAsset] = []
        for id in order where cachedWindow[id] == nil {
            if let asset = wanted[id] {
                arriving.append(asset)
            }
        }

        if !leaving.isEmpty {
            manager.stopCachingImages(
                for: leaving,
                targetSize: ImageSpec.card,
                contentMode: ImageSpec.contentMode,
                options: ImageSpec.cardOptions
            )
        }

        if !arriving.isEmpty {
            manager.startCachingImages(
                for: arriving,
                targetSize: ImageSpec.card,
                contentMode: ImageSpec.contentMode,
                options: ImageSpec.cardOptions
            )
        }

        cachedWindow = wanted
    }

    func stopAllPrefetching() {
        manager.stopCachingImagesForAllAssets()
        cachedWindow.removeAll()
    }
}

// MARK: - CardImageLoader

/// The loading state of exactly one card view.
///
/// SwiftUI recycles a card view as the deck advances, so this object will be asked to load a
/// different photo while an earlier request is still in the air. It therefore remembers which
/// card it is loading for and drops any delivery that no longer matches — otherwise the user
/// sees the previous photo appear on the card they are about to judge.
@MainActor
@Observable
final class CardImageLoader {

    private(set) var image: UIImage?
    private(set) var isLoading: Bool = false
    private(set) var isDownloadingFromCloud: Bool = false
    private(set) var downloadProgress: Double = 0
    private(set) var hasFailed: Bool = false

    var hasImage: Bool { image != nil }

    /// The card this loader is currently serving. Every delivery is checked against it.
    @ObservationIgnored private var loadingID: String?

    @ObservationIgnored private var requestID: PHImageRequestID = PHInvalidImageRequestID

    /// Bumped by every `load` and every `cancel`.
    ///
    /// The card identifier alone is not enough to spot a stale delivery: `retry` and an
    /// `.onDisappear` / `.onAppear` pair both cancel and immediately re-request *the same*
    /// card. The cancelled request's handler then arrives on the main queue after the
    /// replacement has already been issued, passes an id-only guard, and clears `requestID`
    /// and `isLoading` out from under the live request — leaving a request that can no longer
    /// be cancelled and a spinner that stops early. The token makes each request identifiable.
    @ObservationIgnored private var generation: Int = 0

    /// Kept so `cancel()` can reach the manager that issued the request. There is no cycle:
    /// the pipeline knows nothing about its loaders.
    @ObservationIgnored private var pipeline: ImagePipeline?

    /// Starts loading `card`, unless this loader is already dealing with it.
    ///
    /// Idempotent on purpose: `onAppear`, a re-render and a deck refill can all ask for the
    /// same card within one frame, and three requests for one photo would each cancel nothing
    /// and each deliver.
    func load(card: DeckCard, using pipeline: ImagePipeline) {
        if loadingID == card.id, isLoading || image != nil || hasFailed {
            return
        }

        if loadingID != card.id {
            cancel()
            image = nil
            downloadProgress = 0
            isDownloadingFromCloud = false
            hasFailed = false
        }

        self.pipeline = pipeline
        loadingID = card.id
        isLoading = true
        hasFailed = false
        isDownloadingFromCloud = false
        downloadProgress = 0

        // Captured now, while the card is definitely the right one. Nothing below reads
        // `card` again, so a recycled view cannot make an old delivery look current.
        let wantedID = card.id

        generation &+= 1
        let token = generation

        let issuedID = pipeline.requestCardImage(
            for: card.asset,
            progress: { [weak self] fraction in
                guard let self, self.generation == token, self.loadingID == wantedID else { return }
                // A local photo never reports a fraction below 1, so the spinner is shown
                // only for a genuine iCloud download and never flashes on a local one.
                if fraction < 1.0 {
                    self.isDownloadingFromCloud = true
                }
                self.downloadProgress = min(max(fraction, 0), 1)
            },
            completion: { [weak self] result in
                guard let self, self.generation == token, self.loadingID == wantedID else { return }

                self.requestID = PHInvalidImageRequestID
                self.isLoading = false
                self.isDownloadingFromCloud = false

                switch result {
                case .image(let loaded):
                    self.image = loaded
                    self.downloadProgress = 1
                    self.hasFailed = false
                case .cancelled:
                    // Normal: the deck moved on, or the view went away. Say nothing.
                    self.downloadProgress = 0
                case .failed:
                    self.hasFailed = true
                    self.downloadProgress = 0
                }
            }
        )

        // Assigned only now. A cached image can run the result handler synchronously, before
        // `requestCardImage` returns, so assigning inside the handler would be overwritten
        // here a moment later and leave a stale id to cancel.
        requestID = issuedID
    }

    /// Clears the failure and tries once more. Driven by the retry button on the card.
    func retry(card: DeckCard, using pipeline: ImagePipeline) {
        cancel()
        hasFailed = false
        isLoading = false
        isDownloadingFromCloud = false
        downloadProgress = 0
        image = nil
        load(card: card, using: pipeline)
    }

    /// Cancels any request in flight. Called from the view's `.onDisappear`; there is
    /// deliberately no `deinit` doing this, because a `deinit` cannot touch main-actor state.
    func cancel() {
        // Retire the in-flight request's token first, so its cancellation callback — which
        // still carries the same card id — cannot write over the state of whatever is
        // started next.
        generation &+= 1

        if requestID != PHInvalidImageRequestID {
            pipeline?.cancel(requestID)
            requestID = PHInvalidImageRequestID
        }
        isLoading = false
        isDownloadingFromCloud = false
    }
}
