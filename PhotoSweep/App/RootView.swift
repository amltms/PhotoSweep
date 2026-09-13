import Photos
import SwiftUI

/// Decides which screen the app is showing, and nothing else.
///
/// The order matters and is not arbitrary: onboarding runs *before* iOS is asked for
/// photo access, so that the user has already read "right bins, left keeps" by the time
/// the system alert appears. Asking first and explaining afterwards would mean the
/// permission prompt arrives with no context, which is how permissions get denied.
struct RootView: View {

    let model: AppModel

    /// Which screen is on show.
    ///
    /// Held as local state rather than recomputed inline so that moving between screens
    /// can be wrapped in `withAnimation` — the model is the source of truth, but a model
    /// mutation cannot itself carry an animation.
    @State private var phase: Phase = .checking

    /// True once `AppModel.bootstrap()` has returned.
    ///
    /// It lives here rather than on the model because `AppModel`'s surface is frozen and
    /// this view is its only reader — and because the bootstrap is started from here
    /// (`runBootstrap()` below), so the flag cannot drift from the work it describes.
    /// `bootstrap()` neither throws nor waits on anything open-ended: it reads the
    /// authorisation status and then a file, and a failed read still returns. `.checking`
    /// is therefore always left, which is what stops it becoming a dead end.
    @State private var hasBootstrapped = false

    /// Whether the user has already tapped the saved-state banner away.
    ///
    /// `clearLoadError()` alone would be enough to hide it once — `ReviewStateStore` is
    /// `@Observable`. This flag makes the dismissal stick for the rest of the launch, so a
    /// second failed read later in the session cannot put an already-dismissed banner back
    /// in front of the user: the message is worth showing once, not once per attempt.
    @State private var loadErrorDismissed = false

    /// The five places the app can be at launch. `checking` holds from the first frame
    /// until `AppModel.bootstrap()` has read the authorisation status and the saved state —
    /// usually a frame or two, longer if the disk is slow. It shows nothing but the
    /// background, which is the point: an undecided route must look like a launch, never
    /// like a wrong screen that then jumps.
    private enum Phase: Hashable {
        case checking
        case onboarding
        case permission
        case rehearsal
        case home
    }

    var body: some View {
        ZStack {
            ScreenBackground()

            Group {
                content
            }
            .transition(.opacity)
            .id(phase)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            loadErrorBanner
        }
        .onChange(of: resolvedPhase, initial: true) { _, newPhase in
            withAnimation(.easeInOut(duration: 0.28)) {
                phase = newPhase
            }
        }
        .task {
            await runBootstrap()
        }
    }

    // MARK: - Routing

    /// Reads the authorisation status and the saved state, then releases the route.
    ///
    /// The bootstrap is driven from here, and not from `PhotoSweepApp`, so that exactly
    /// one thing knows when `.checking` is over. `bootstrap()` re-reads the saved file,
    /// so a second caller elsewhere would not merely be redundant — it would reload the
    /// persisted decisions over whatever is already in memory.
    ///
    /// Marked `@MainActor` because `.task`'s closure is `@Sendable` and does not inherit
    /// this view's isolation: the `await` is what puts both the model call and the flag
    /// write on the main actor.
    @MainActor
    private func runBootstrap() async {
        await model.bootstrap()
        hasBootstrapped = true
    }

    /// Re-reads the routing decision and moves to it.
    ///
    /// Called explicitly after this view asks the model to complete onboarding or the
    /// rehearsal. Observation would eventually move `phase` on its own, but only as an
    /// un-animated jump: a model mutation cannot carry an animation with it, and wrapping
    /// the mutation in `withAnimation` is banned. Doing the move here means the screen
    /// change is a cross-fade rather than a cut. Harmlessly idempotent.
    private func advance() {
        withAnimation(.easeInOut(duration: 0.28)) {
            phase = resolvedPhase
        }
    }

    /// Where the model says we should be right now.
    ///
    /// The `hasBootstrapped` guard is load-bearing rather than defensive. Before
    /// `AppModel.bootstrap()` has run, `authStatus` is still its default `.notDetermined`
    /// and the store still holds a freshly constructed `ReviewState`, which reads as
    /// "never onboarded" — so without the guard the first body evaluation routes to
    /// `.onboarding`, commits it inside the 0.28s animation below, and every single
    /// relaunch flashes the welcome screen before cross-fading to Home. `.checking`
    /// shows the background and nothing else until the real values have landed.
    private var resolvedPhase: Phase {
        guard hasBootstrapped else { return .checking }

        switch model.authStatus {
        case .notDetermined:
            // Explain first, ask second.
            return model.hasCompletedOnboarding ? .permission : .onboarding

        case .denied, .restricted:
            return .permission

        case .authorized, .limited:
            if !model.hasCompletedOnboarding { return .onboarding }

            // Deliberately *not* `model.needsRehearsal`. That property is also true when
            // the user swaps the swipe directions in Settings, and routing on it from here
            // would rebuild `Group { content }.id(phase)` the instant the toggle moved —
            // tearing `HomeView` out from under the Settings sheet that holds the toggle,
            // so the sheet vanishes mid-gesture and the rehearsal fades in over it. Only
            // the very first rehearsal is a routing decision; re-running it after a swap
            // belongs to `HomeView`, immediately before the deck opens, where nothing is
            // destroyed and the user meets the new mapping just as they are about to use it.
            if !model.store.state.hasCompletedRehearsal { return .rehearsal }
            return .home

        @unknown default:
            // A status this build does not recognise is treated as "not usable yet",
            // which shows an explanation rather than an empty deck.
            return .permission
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .checking:
            Color.clear

        case .onboarding:
            OnboardingView(model: model, onFinished: {
                model.completeOnboarding()
                advance()
            })

        case .permission:
            PermissionGateView(model: model)

        case .rehearsal:
            RehearsalView(model: model, onFinished: {
                model.completeRehearsal()
                advance()
            })

        case .home:
            HomeView(model: model)
        }
    }

    // MARK: - Saved-state failure

    /// Shown once if the saved progress file could not be read. Tapping it dismisses it,
    /// which is also what clears the error in the store.
    @ViewBuilder
    private var loadErrorBanner: some View {
        if !loadErrorDismissed, let message = model.store.loadError {
            Button {
                loadErrorDismissed = true
                model.store.clearLoadError()
            } label: {
                InfoBanner(systemImage: "exclamationmark.triangle.fill", text: message)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, Theme.stackSpacing)
            .accessibilityLabel(message)
            .accessibilityHint(Strings.close)
        }
    }
}
