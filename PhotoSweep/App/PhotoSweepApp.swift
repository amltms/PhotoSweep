import Photos
import SwiftUI

/// The application entry point.
///
/// It owns the two long-lived objects — the model and the photo-library observer —
/// and it owns the only place in the app that reacts to the app leaving the
/// foreground. Everything else receives the model as a plain `let` property, so a
/// missing injection is a compile error rather than a runtime crash.
@main
struct PhotoSweepApp: App {

    /// The single source of truth, created once for the lifetime of the process.
    @State private var model = AppModel()

    /// `LibraryObserver` is a plain `NSObject`, not `@Observable`, and it is held here
    /// purely to keep it alive: `PHPhotoLibrary` registers change observers **unowned**,
    /// so if nothing in the app retained this it would be deallocated moments after
    /// `start()` and the app would silently stop noticing library changes. `@State` is
    /// what retains it; the view never reads it for rendering.
    @State private var observer = LibraryObserver()

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .preferredColorScheme(.dark)
                .task {
                    await connectLibraryObserver()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await model.refreshAuthorisation() }
                    } else {
                        saveBeforeLeavingForeground(phase)
                    }
                }
        }
    }

    // MARK: - Wiring

    /// Connects the library observer.
    ///
    /// Deliberately not sequenced behind `AppModel.bootstrap()`, which `RootView` now owns
    /// so that exactly one thing knows when the launch route has been decided. Ordering is
    /// not needed here: until a session exists there is no fetch result for a change to be
    /// about, and `applyBufferedLibraryChange()` returns immediately when there is none.
    ///
    /// `LibraryObserver` guarantees it calls `onChange` on the main queue, and this
    /// closure is formed inside a `@MainActor` context, so calling straight into the
    /// `@MainActor` model is correct without any hop or isolation escape hatch.
    ///
    /// The capture list is load-bearing. Writing `model.handleLibraryChange(change)` bare
    /// means `self.model`, which captures the whole `PhotoSweepApp` value — including the
    /// `@State` storage that retains this very observer — and closes a strong cycle through
    /// `observer.onChange` that makes `LibraryObserver.deinit`, and so its `stop()`,
    /// unreachable. Capturing the `AppModel` reference by value at closure formation stores
    /// only the model, points nothing back at the `@State` box, and stays main-actor-correct.
    ///
    /// Marked `async` deliberately: the caller is `.task`, and an `async` member is
    /// callable with `await` whether or not that closure is already main-actor bound.
    @MainActor
    private func connectLibraryObserver() async {
        observer.onChange = { [model = self.model] change in
            model.handleLibraryChange(change)
        }
        observer.start()
    }

    /// Saves forward whenever the app stops being active, and drops the prefetch cache only
    /// when the app is genuinely backgrounded.
    ///
    /// This is the save hook rather than `applicationWillTerminate` or `.onDisappear`,
    /// neither of which is reliably delivered. `flush()` writes synchronously on the main
    /// actor before this method returns, so the write has already happened by the time iOS
    /// can suspend us — no background task assertion is needed, and UIKit is reserved in
    /// this project for haptics, `openSettingsURLString` and the top-view-controller lookup.
    ///
    /// The prefetch teardown is gated on `.background` deliberately. `.inactive` is reached
    /// by every Control Centre pull, notification banner, app-switcher peek and system
    /// deletion alert, and nothing on the way back to `.active` rebuilds the caching window
    /// — `refreshAuthorisation()` touches no prefetch state, and the window is only rebuilt
    /// by the next decision. Tearing the cache down for a two-second interruption would
    /// therefore fetch the following cards cold for no benefit; a real background transition
    /// is the only one where handing the memory back is worth it.
    @MainActor
    private func saveBeforeLeavingForeground(_ phase: ScenePhase) {
        model.flush()
        if phase == .background {
            model.pipeline.stopAllPrefetching()
        }
    }
}
