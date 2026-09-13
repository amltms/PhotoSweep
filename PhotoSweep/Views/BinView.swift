import Photos
import SwiftUI
import UIKit

/// The bin — the only screen in PhotoSweep from which anything is ever deleted.
///
/// Everything here is deliberately calm and literal. The user sees exactly what they
/// marked, can take any of it back with a single tap, and afterwards is told in the app's
/// own words that the photos are sitting in Recently Deleted rather than gone. No figure
/// for reclaimed space is ever shown, because the space is not reclaimed yet.
struct BinView: View {

    let model: AppModel
    var onClose: () -> Void

    /// Resolved from `model.pendingDeletionIDs`, in that order. An id that no longer
    /// resolves is simply absent from this array; that is normal, never an error.
    @State private var assets: [PHAsset] = []

    @State private var isConfirming = false
    @State private var isShowingOutcome = false
    @State private var shownOutcome: CommitOutcome?

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 96), spacing: 10)]
    }

    var body: some View {
        ZStack {
            ScreenBackground()

            VStack(spacing: 0) {
                topBar
                header

                if assets.isEmpty {
                    emptyState
                } else {
                    grid
                }

                // Still keyed off `pendingCount`, so that a bin holding only ids that no
                // longer resolve keeps its "Keep them all" button — that is the user's only
                // way to clear such a bin. The destructive half of the footer is gated on
                // `assets` instead; see `footer`.
                if model.pendingCount > 0 {
                    footer
                }
            }
        }
        // `.onAppear` rather than `.task`: the work is synchronous and main-actor bound, and
        // `.task`'s closure is `@Sendable` and not actor-inherited, so calling a main-actor
        // helper from inside it is an isolation error waiting to happen.
        .onAppear {
            reloadAssets()
        }
        .alert(outcomeTitle, isPresented: $isShowingOutcome) {
            Button(Strings.done) {
                shownOutcome = nil
            }
        } message: {
            Text(outcomeMessage)
        }
    }

    // MARK: - Top bar and header

    private var topBar: some View {
        HStack {
            Text(Strings.binTitle)
                .font(.title2.bold())
                .foregroundStyle(Theme.textPrimary)

            Spacer(minLength: 12)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: Theme.minimumTapTarget, height: Theme.minimumTapTarget)
                    .background(Circle().fill(Theme.surfaceRaised))
            }
            .buttonStyle(.plain)
            .disabled(model.isCommitting)
            .accessibilityLabel(Strings.close)
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, Theme.screenPadding)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Strings.binHeader(binned: model.pendingCount, kept: model.keptThisSession))
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            Text(Strings.binTapToRestore)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 12)
        .padding(.bottom, Theme.stackSpacing)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Grid

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(assets, id: \.localIdentifier) { asset in
                    BinThumbnail(asset: asset, pipeline: model.pipeline) {
                        restore(asset)
                    }
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, Theme.stackSpacing)
        }
        .scrollIndicators(.hidden)
        .disabled(model.isCommitting)
    }

    private var emptyState: some View {
        VStack {
            Spacer(minLength: 0)
            EmptyStateView(
                systemImage: "trash",
                title: Strings.binEmptyTitle,
                message: Strings.binEmptyBody,
                actionTitle: Strings.close,
                action: onClose
            )
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Theme.screenPadding)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 12) {
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)
                .padding(.bottom, 4)

            if model.isCommitting {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(Theme.textPrimary)
                    Text(Strings.commitInProgress)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }

            // Shown, and counted, from `assets` rather than `model.pendingCount`: only the
            // resolved photos can actually be moved, so quoting the raw count would promise a
            // figure the receipt afterwards would contradict. It remains an upper bound —
            // `Eligibility` can still refuse a resolved asset — but it is the verified one.
            if !assets.isEmpty {
                Button(Strings.binCommitButton(assets.count)) {
                    if model.settings.confirmBeforeCommit {
                        isConfirming = true
                    } else {
                        commit()
                    }
                }
                .buttonStyle(PrimaryButtonStyle(role: .destructive))
                .disabled(model.isCommitting)
            }

            Button(Strings.binKeepAll) {
                keepAll()
            }
            .buttonStyle(PrimaryButtonStyle(role: .quiet))
            .disabled(model.isCommitting)
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.bottom, Theme.screenPadding)
        .alert(Strings.binConfirmTitle, isPresented: $isConfirming) {
            Button(Strings.cancel, role: .cancel) { }
            Button(Strings.binConfirmAction, role: .destructive) {
                commit()
            }
        } message: {
            Text(Strings.binConfirmBody(assets.count))
        }
    }

    // MARK: - Actions

    /// Re-reads the bin from the model. Called on appearance and after every commit, so the
    /// grid can never disagree with the list the delete button would actually act on.
    private func reloadAssets() {
        assets = AssetResolver.assets(for: model.pendingDeletionIDs)
    }

    private func restore(_ asset: PHAsset) {
        guard !model.isCommitting else { return }
        let id = asset.localIdentifier
        // `AppModel.restore(id:)` fires the haptic itself; a second one here doubles it.
        model.restore(id: id)
        withAnimation(.easeOut(duration: 0.2)) {
            assets.removeAll { $0.localIdentifier == id }
        }
    }

    private func keepAll() {
        guard !model.isCommitting else { return }
        // `AppModel.keepAllInBin()` fires its own haptic.
        model.keepAllInBin()
        withAnimation(.easeOut(duration: 0.2)) {
            assets.removeAll()
        }
    }

    private func commit() {
        guard !model.isCommitting else { return }
        Task {
            await model.commitDeletions()

            // Rebuilt from whatever the model still holds: on `.cancelledByUser` or
            // `.failed` the bin survives, and the grid must agree with it.
            withAnimation(.easeOut(duration: 0.25)) {
                reloadAssets()
            }

            // The outcome haptic is fired by `AppModel.commitDeletions()`, which owns that
            // behaviour for every branch. Firing one here as well plays it twice.
            //
            // `result` is read into a local rather than written to `shownOutcome` and read
            // straight back: an `@State` write is not guaranteed to be visible to a read in
            // the same run of a closure captured from an earlier body evaluation.
            if let result = model.lastOutcome {
                shownOutcome = result
                isShowingOutcome = true
            }
        }
    }

    // MARK: - Outcome copy

    private var outcomeTitle: String {
        guard let shownOutcome else { return Strings.binTitle }
        switch shownOutcome {
        case .deleted:
            // The success alert leads with recovery, because "deleted" is the word the user
            // is bracing for and it is not what has happened.
            return Strings.recoveryHowToTitle
        case .failed:
            return Strings.genericErrorTitle
        case .cancelledByUser, .nothingToDelete:
            return Strings.binTitle
        }
    }

    private var outcomeMessage: String {
        guard let shownOutcome else { return "" }
        switch shownOutcome {
        case .deleted:
            return shownOutcome.message + "\n\n" + Strings.recoveryHowTo
        case .cancelledByUser, .nothingToDelete, .failed:
            return shownOutcome.message
        }
    }
}

// MARK: - Thumbnail

/// One tile in the bin grid.
///
/// It owns its own request id rather than sharing a loader, so scrolling a long bin can
/// cancel exactly the requests that left the screen. `CardImageLoader` is deliberately not
/// used here: it is sized and priced for full-screen card images.
private struct BinThumbnail: View {

    let asset: PHAsset
    let pipeline: ImagePipeline
    var onTap: () -> Void

    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        Button(action: onTap) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    ZStack {
                        Theme.cardBackground

                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            ProgressView()
                                .tint(Theme.textTertiary)
                        }
                    }
                }
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 18))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Theme.textPrimary, Theme.darkBlue.opacity(0.85))
                        .padding(5)
                }
                .overlay(alignment: .bottomLeading) {
                    if asset.mediaType == .video {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(5)
                            .background(Circle().fill(Theme.darkBlue.opacity(0.7)))
                            .padding(5)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.tileCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.tileCornerRadius, style: .continuous)
                        .stroke(Theme.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            Strings.a11yCardLabel(
                date: Formatters.accessibleDate(asset.creationDate),
                isVideo: asset.mediaType == .video,
                duration: asset.mediaType == .video ? Formatters.duration(asset.duration) : nil
            )
        )
        .accessibilityHint(Strings.binTapToRestore)
        .onAppear(perform: load)
        .onDisappear(perform: cancel)
    }

    private func load() {
        guard image == nil, requestID == nil else { return }

        // Captured before the request: a cached image can call the handler synchronously,
        // and a recycled tile must never accept pixels for a photo it no longer shows.
        let wanted = asset.localIdentifier

        let id = pipeline.requestThumbnail(for: asset) { result in
            guard wanted == asset.localIdentifier else { return }
            guard let result else { return }
            image = result
        }

        // Assigned only now, and unconditionally. A cached image can run the handler before
        // `requestThumbnail` returns, so an id written from inside the handler would be
        // overwritten here a moment later. Cancelling an id whose request has already
        // finished is a documented no-op, so tracking it either way is safe.
        requestID = id
    }

    private func cancel() {
        guard let requestID else { return }
        pipeline.cancel(requestID)
        self.requestID = nil
    }
}
