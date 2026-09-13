import Foundation
import Photos
import PhotosUI
import UIKit

/// Everything the app knows about its own photo-library permission.
///
/// Every call here uses the `(for: .readWrite)` variants. The legacy no-argument
/// `authorizationStatus()` and `requestAuthorization(_:)` report a `.limited` user as
/// `.authorized`, which would leave the app cheerfully presenting a six-photo library as
/// if it were the whole thing — a wrong answer that looks completely right.
@MainActor
enum PhotoAuthoriser {

    /// Always the `(for: .readWrite)` variant.
    static var status: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    /// Bridges the completion-handler API into `async`.
    ///
    /// The handler arrives on an arbitrary queue and is documented to fire once; the
    /// continuation is resumed there and nowhere else, so there is exactly one resume on
    /// every path.
    static func request() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }

    /// How many assets a `.limited` user has actually shared. 0 when not limited.
    ///
    /// Reading `count` off a fetch result does not fault the assets themselves, so this
    /// stays cheap even when the user has shared a large selection.
    static func sharedAssetCount() -> Int {
        guard status == .limited else { return 0 }
        // Typed explicitly: a bare `nil` leaves the compiler to pick between the
        // `fetchAssets(with:)` overloads by itself, and the annotation costs nothing.
        return PHAsset.fetchAssets(with: nil as PHFetchOptions?).count
    }

    /// Opens this app's page in Settings.
    ///
    /// Deliberately no `canOpenURL` pre-flight: `app-settings:` is not a scheme this app has
    /// declared in `LSApplicationQueriesSchemes`, and on several iOS versions `canOpenURL`
    /// answers `false` for exactly that reason. Guarding on it would turn the one button that
    /// rescues a denied user into a silent no-op. `open(_:)` handles the impossible case.
    static func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Presents the system "select more photos" sheet from the top view controller.
    ///
    /// Does nothing at all if no presenting controller can be found — there is no sensible
    /// fallback, and a missing sheet is far better than a crash.
    static func presentLimitedPicker() {
        guard let controller = topViewController() else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: controller)
    }

    /// Stable per-install identifier for the library, for `ReviewState.fingerprint`.
    static func libraryFingerprint() -> String {
        "\(UIDevice.current.identifierForVendor?.uuidString ?? "unknown")-v1"
    }

    // MARK: - Private

    /// Walks the scene graph to whatever is actually on screen right now.
    ///
    /// SwiftUI gives no supported handle on a `UIViewController`, and the limited-library
    /// picker is UIKit-only, so the controller has to be found the long way round. Every
    /// step is guarded because each one is genuinely optional: a scene may be backgrounded,
    /// a window may have no root, and any of it may be mid-teardown.
    private static func topViewController() -> UIViewController? {
        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = windowScenes.first { $0.activationState == .foregroundActive } ?? windowScenes.first

        guard let scene else { return nil }
        guard let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first else {
            return nil
        }
        guard var controller = window.rootViewController else { return nil }

        while let presented = controller.presentedViewController {
            controller = presented
        }
        return controller
    }
}
