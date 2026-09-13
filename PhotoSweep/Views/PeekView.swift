import SwiftUI

/// A read-only, full-bleed look at one card.
///
/// It carries no gesture of any kind. The deck's drag state lives in `SwipeDeckView` and
/// is left completely untouched while this is on screen, so dismissing the peek returns
/// the user to exactly the card and exactly the finger position they left.
struct PeekView: View {

    let model: AppModel
    let card: DeckCard
    var onClose: () -> Void

    /// Its own loader: the peek asks for the same card image the deck already has, and a
    /// separate loader keeps the deck's own loading state out of it.
    @State private var loader = CardImageLoader()

    private var pixelSize: String {
        Formatters.pixels(width: card.pixelWidth, height: card.pixelHeight)
    }

    var body: some View {
        ZStack {
            Theme.deepBlue
                .ignoresSafeArea()

            imageLayer

            VStack(spacing: 0) {
                HStack {
                    Spacer(minLength: 0)
                    closeButton
                }

                Spacer(minLength: 0)

                metadata
            }
            .padding(Theme.screenPadding)
        }
        // Already on the main actor: a `View`'s `.task` closure inherits the isolation the
        // `View` conformance gives this type, so `CardImageLoader` is reachable directly.
        .task(id: card.id) {
            loader.load(card: card, using: model.pipeline)
        }
        .onDisappear {
            loader.cancel()
        }
    }

    // MARK: - Image

    @ViewBuilder
    private var imageLayer: some View {
        if let image = loader.image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .ignoresSafeArea()
                .accessibilityLabel(card.accessibilityLabel)
        } else if loader.hasFailed {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.icloud")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(Theme.textTertiary)

                Text(Strings.iCloudFailed)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)

                Button(Strings.iCloudRetry) {
                    loader.retry(card: card, using: model.pipeline)
                }
                .buttonStyle(PrimaryButtonStyle(role: .neutral, fullWidth: false))
            }
            .padding(Theme.screenPadding)
        } else {
            // `CloudDownloadBadge` carries its own `Strings.iCloudDownloading` caption, so
            // a second one here showed the line twice.
            VStack(spacing: 14) {
                if loader.isDownloadingFromCloud {
                    CloudDownloadBadge(progress: loader.downloadProgress)
                } else {
                    ProgressView()
                        .tint(Theme.textSecondary)
                }
            }
            .padding(Theme.screenPadding)
        }
    }

    // MARK: - Chrome

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: Theme.minimumTapTarget, height: Theme.minimumTapTarget)
                .background(Circle().fill(Theme.deepBlue.opacity(0.65)))
                .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.close)
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Formatters.dateAndTime(card.creationDate))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: 10) {
                if !pixelSize.isEmpty {
                    Text(pixelSize)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }

                if card.isVideo {
                    PillLabel(systemImage: "video.fill", text: Formatters.duration(card.duration))
                }

                if card.isFavourite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.yellow)
                }

                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.controlCornerRadius, style: .continuous)
                .fill(Theme.deepBlue.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.controlCornerRadius, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
    }
}
