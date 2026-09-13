import Photos
import SwiftUI

/// The pile picker: the screen the user starts and finishes on.
///
/// The `NavigationStack` here exists for the toolbar and for Settings, and for nothing
/// else. The deck is raised as a `.fullScreenCover`, never pushed: UIKit's interactive
/// pop gesture owns the left screen edge and drags rightwards, which is exactly the bin
/// direction, and it wins against a SwiftUI `DragGesture` every time.
struct HomeView: View {

    let model: AppModel

    @State private var isSweeping = false
    @State private var isRehearsing = false
    @State private var isShowingBin = false
    @State private var isShowingSettings = false
    @State private var isShowingMonths = false
    @State private var monthBuckets: [MonthBucket] = []
    @State private var isLoadingMonths = false
    @State private var hasLoadedMonths = false

    /// The pile the user asked for while the practice cards were still owed to them, so
    /// the tap is postponed rather than swallowed: the sweep resumes on the same pile the
    /// moment the rehearsal is finished.
    @State private var filterAwaitingRehearsal: LibraryFilter?

    /// Bumped whenever the month counts are known to be stale (the user has just been
    /// through the deck). It is part of the `.task` id, so bumping it re-runs the load
    /// without having to collapse and re-open the list.
    @State private var monthsReloadCount = 0

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.stackSpacing) {
                        header

                        if model.authStatus == .limited {
                            limitedAccessSection
                        }

                        // A bin left over from a previous session is put in front of the
                        // user for review. It is never committed for them and never
                        // quietly emptied.
                        if model.pendingCount > 0 {
                            binSection
                        }

                        pilesSection
                    }
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.vertical, Theme.screenPadding)
                }
                .scrollIndicators(.hidden)
                .sheet(isPresented: $isShowingBin) {
                    BinView(model: model, onClose: { isShowingBin = false })
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(
                                width: Theme.minimumTapTarget,
                                height: Theme.minimumTapTarget,
                                alignment: .trailing
                            )
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(Strings.settings)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $isShowingSettings) {
                SettingsView(model: model, onClose: { isShowingSettings = false })
            }
        }
        .tint(Theme.accent)
        .fullScreenCover(isPresented: $isSweeping, onDismiss: {
            // Nothing else in the app calls `endSession()`, so without this the deck's
            // `AssetQueue` and the prefetch window stay alive for the whole time the
            // user is back on this screen. `endSession()` does not touch the bin.
            // Done on dismissal rather than in `onClose` so the deck is not emptied
            // underneath itself while the cover is still animating away.
            model.endSession()

            // The remaining-per-month counts were computed before the sweep.
            hasLoadedMonths = false
            monthsReloadCount += 1
        }) {
            DeckScreen(model: model, onClose: { isSweeping = false })
                .interactiveDismissDisabled(true)
        }
        // The practice cards, when the user has swapped the swipe directions since they
        // last rehearsed. `RootView` routes only the very first rehearsal — routing on
        // `model.needsRehearsal` from there would tear this screen out from under the
        // Settings sheet holding the toggle — so the re-run belongs here, one step before
        // the deck. Raised and dismissed before the deck cover, never alongside it.
        .fullScreenCover(isPresented: $isRehearsing, onDismiss: {
            // Resumed from `onDismiss` rather than from `onFinished`, so the practice
            // cover is fully off screen before the deck cover is raised.
            guard let filter = filterAwaitingRehearsal else { return }
            filterAwaitingRehearsal = nil
            Task { await beginSweeping(with: filter) }
        }) {
            RehearsalView(model: model, onFinished: {
                model.completeRehearsal()
                isRehearsing = false
            })
            .interactiveDismissDisabled(true)
        }
        .task(id: monthsTaskID) {
            await loadMonthsIfNeeded()
        }
    }

    /// Changes when the month list is opened, and when its contents go stale.
    private var monthsTaskID: String {
        "\(isShowingMonths)-\(monthsReloadCount)"
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Strings.appName)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Theme.textPrimary)

            Text(Strings.tagline)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)

            Text(Strings.lifetimeLine(reviewed: model.lifetimeReviewed, binned: model.lifetimeBinned))
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Limited access

    private var limitedAccessSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            InfoBanner(
                systemImage: "info.circle.fill",
                text: Strings.limitedAccessBody(count: model.sharedAssetCount)
            )

            // `presentLimitedPicker()` takes no completion handler — its signature is
            // frozen — and the sheet is a UIKit modal presented over this app, so the
            // scene never leaves `.active` while it is up. The count in the banner above
            // is therefore refreshed by the `scenePhase` hook in `PhotoSweepApp` the next
            // time the app returns to the foreground, not the moment the sheet closes.
            // The copy says "you can add more at any time", which stays true either way.
            Button(Strings.limitedChooseMore) {
                PhotoAuthoriser.presentLimitedPicker()
            }
            .buttonStyle(PrimaryButtonStyle(role: .neutral))
        }
    }

    // MARK: - Bin

    private var binSection: some View {
        SectionCard(title: Strings.binTitle) {
            VStack(alignment: .leading, spacing: 14) {
                // Every user-facing string comes from `Strings`; safety copy about
                // deletion is never written inline.
                //
                // This card is shown for any non-empty bin, including one the user has
                // never tried to commit, so the copy has to describe waiting rather than
                // aftermath. `Strings.commitCancelled` ("Nothing was deleted…") belongs
                // to the `.cancelledByUser` outcome and would otherwise report a
                // cancellation to a user who never reached the deletion sheet.
                InfoBanner(
                    systemImage: "trash.fill",
                    text: Strings.binWaitingBody,
                    tint: Theme.red
                )

                HStack {
                    PillLabel(systemImage: "trash.fill", text: Formatters.count(model.pendingCount))
                    Spacer(minLength: 0)
                }

                Button(Strings.review) {
                    isShowingBin = true
                }
                .buttonStyle(PrimaryButtonStyle(role: .destructive))
                .accessibilityLabel(Strings.a11yOpenBin)
            }
        }
    }

    // MARK: - Piles

    private var pilesSection: some View {
        SectionCard(title: Strings.homeTitle) {
            VStack(spacing: 0) {
                pileRow(for: .all)
                rowDivider
                pileRow(for: .screenshots)
                rowDivider
                pileRow(for: .videos)
                rowDivider
                monthDisclosureRow

                if isShowingMonths {
                    monthList
                }
            }
        }
    }

    private func pileRow(for filter: LibraryFilter) -> some View {
        Button {
            Task { await beginSweeping(with: filter) }
        } label: {
            HomeRowLabel(
                systemImage: filter.systemImage,
                title: filter.title,
                subtitle: filter.subtitle,
                trailingSystemImage: "chevron.right",
                indented: false
            )
        }
        .buttonStyle(.plain)
    }

    private var monthDisclosureRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isShowingMonths.toggle()
            }
        } label: {
            HomeRowLabel(
                systemImage: "calendar",
                title: Strings.pileByMonth,
                subtitle: Strings.pileByMonthHint,
                trailingSystemImage: isShowingMonths ? "chevron.down" : "chevron.right",
                indented: false
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var monthList: some View {
        if isLoadingMonths {
            HStack {
                Spacer(minLength: 0)
                ProgressView()
                    .tint(Theme.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 20)
        } else if monthBuckets.isEmpty {
            Text(Strings.emptyPileBody)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 14)
        } else {
            ForEach(monthBuckets) { bucket in
                rowDivider

                Button {
                    Task { await beginSweeping(with: bucket.filter) }
                } label: {
                    HomeRowLabel(
                        systemImage: "calendar",
                        title: bucket.title,
                        subtitle: bucket.isComplete
                            ? Strings.summaryAllCaughtUp
                            : Strings.remainingCount(bucket.remaining),
                        trailingSystemImage: "chevron.right",
                        indented: true
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 1)
    }

    // MARK: - Actions

    /// The session is built before the cover is raised, so the deck is never presented
    /// empty and then filled in underneath the user.
    @MainActor
    private func beginSweeping(with filter: LibraryFilter) async {
        // Swapping the swipe directions in Settings makes the practice cards owed again,
        // and they are owed *before* a real photo is on screen. `completeRehearsal()`
        // records the mapping that was rehearsed, so the resumed call below passes this
        // guard rather than looping back into the practice cards.
        guard !model.needsRehearsal else {
            filterAwaitingRehearsal = filter
            isRehearsing = true
            return
        }

        await model.startSession(filter: filter)

        // A session can fail to start because access was withdrawn while the app was open.
        // Raising the cover anyway would strand the user in an empty deck with no
        // explanation and no way to understand why, so re-read the authorisation instead
        // and let RootView route to the permission screen.
        guard model.sessionError == nil else {
            await model.refreshAuthorisation()
            return
        }

        isSweeping = true
    }

    /// Counting a whole library by month is expensive, so it happens once, and only if
    /// the user actually opens the month list.
    @MainActor
    private func loadMonthsIfNeeded() async {
        guard isShowingMonths, !hasLoadedMonths, !isLoadingMonths else { return }

        isLoadingMonths = true
        let buckets = await model.monthBuckets()
        monthBuckets = buckets
        hasLoadedMonths = true
        isLoadingMonths = false
    }
}

/// The shared look of every tappable row on this screen.
///
/// One label type rather than a repeated `HStack`, so that each row keeps the same tap
/// target height even when a title wraps onto a second line.
private struct HomeRowLabel: View {

    let systemImage: String
    let title: String
    let subtitle: String
    let trailingSystemImage: String
    let indented: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 28, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: trailingSystemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.leading, indented ? 16 : 0)
        .padding(.vertical, 12)
        .frame(minHeight: Theme.minimumTapTarget)
        .contentShape(Rectangle())
    }
}
