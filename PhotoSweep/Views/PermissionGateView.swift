import Photos
import SwiftUI

/// The screen shown whenever the app is not allowed to look at the library.
///
/// `.authorized` and `.limited` both mean the app can work, and `RootView` routes those
/// to `HomeView` instead, so they render nothing here. A status this build does not
/// recognise is *not* rendered as nothing: `RootView` sends its `@unknown default` to
/// this screen, so an empty body there would be a dead end the user cannot leave.
struct PermissionGateView: View {

    let model: AppModel

    var body: some View {
        ZStack {
            ScreenBackground()

            // `EmptyStateView` already applies `Theme.screenPadding` horizontally;
            // adding it again here would double the gutter.
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.authStatus {

        case .notDetermined:
            EmptyStateView(
                systemImage: "photo.on.rectangle.angled",
                title: Strings.permissionTitle,
                message: Strings.permissionBody,
                actionTitle: Strings.permissionGrant,
                action: {
                    // The system prompt is asynchronous; the model republishes `authStatus`
                    // when it returns, which is what moves the user off this screen.
                    Task { await model.requestAuthorisation() }
                }
            )

        case .denied:
            EmptyStateView(
                systemImage: "lock.fill",
                title: Strings.permissionDeniedTitle,
                message: Strings.permissionDeniedBody,
                actionTitle: Strings.permissionOpenSettings,
                action: {
                    PhotoAuthoriser.openSystemSettings()
                }
            )

        case .restricted:
            // Restricted is not the user's decision to make, so offering them a button
            // that cannot work would be a lie.
            EmptyStateView(
                systemImage: "exclamationmark.triangle.fill",
                title: Strings.permissionRestrictedTitle,
                message: Strings.permissionRestrictedBody
            )

        case .authorized, .limited:
            // The app can work; `RootView` is already showing `HomeView`.
            EmptyView()

        @unknown default:
            // A status added by a later iOS. `RootView` routes it here, so it must say
            // something true rather than leave a blank screen with no way forward.
            EmptyStateView(
                systemImage: "exclamationmark.triangle.fill",
                title: Strings.permissionRestrictedTitle,
                message: Strings.permissionRestrictedBody,
                actionTitle: Strings.permissionOpenSettings,
                action: {
                    PhotoAuthoriser.openSystemSettings()
                }
            )
        }
    }
}
