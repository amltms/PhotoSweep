import Foundation
import Photos

/// Watches the photo library for changes and forwards them on the main queue.
///
/// A retained `NSObject` — a SwiftUI `View` struct cannot conform to
/// `PHPhotoLibraryChangeObserver`, and more importantly **`PHPhotoLibrary` holds its
/// observers unowned**. Nothing in PhotoKit keeps this object alive, so whoever creates it
/// must hold a strong reference to it for as long as changes matter (`PhotoSweepApp` owns
/// the single instance). An observer that is allowed to deallocate does not fail loudly:
/// updates simply stop arriving, which reads on screen as a stale deck rather than a crash.
///
/// This class is deliberately **not** `@MainActor`. Marking it so would compile in Swift 5
/// mode while the change callback still arrived on a background queue at runtime — an
/// isolation promise the compiler accepts and the framework ignores. Instead the callback is
/// `nonisolated` and hops explicitly, which is true to what actually happens.
final class LibraryObserver: NSObject, PHPhotoLibraryChangeObserver {

    /// Called on the main queue.
    var onChange: ((PHChange) -> Void)?

    /// `register` and `unregisterChangeObserver` are not reference counted, so both `start()`
    /// and `stop()` have to be idempotent themselves. Only ever touched from the main queue
    /// (`start`/`stop` are called from the app's own lifecycle code) and from `deinit`.
    private var isRegistered = false

    /// Registers with `PHPhotoLibrary.shared()`. Safe to call twice.
    func start() {
        guard !isRegistered else { return }
        isRegistered = true
        PHPhotoLibrary.shared().register(self)
    }

    /// Safe to call twice.
    func stop() {
        guard isRegistered else { return }
        isRegistered = false
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    /// The library's reference is unowned, so an observer that goes away while still
    /// registered leaves a dangling entry behind. Unregistering here closes that window.
    deinit {
        stop()
    }

    /// Delivered on an arbitrary background queue, hence `nonisolated`.
    ///
    /// The hop is `DispatchQueue.main.async` rather than `Task { @MainActor in … }` because
    /// `PHChange` is not `Sendable`: carrying it across a `Task` boundary warns, and the
    /// usual ways of silencing that warning are all banned in this project. A plain GCD hop
    /// moves the same object to the main queue with no isolation claim attached to it.
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onChange?(changeInstance)
        }
    }
}
