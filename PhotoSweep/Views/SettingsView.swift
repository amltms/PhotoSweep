import SwiftUI

/// Settings: the swipe directions, the safety switches, the deletion history and the
/// promises the app makes about what it will not do.
///
/// Every toggle writes straight through to `AppSettings`, which persists itself. There is
/// deliberately no "Save" button: a settings screen that can be dismissed with unsaved
/// changes is a settings screen that silently loses them.
struct SettingsView: View {

    let model: AppModel
    var onClose: () -> Void

    @State private var isShowingResetAlert = false
    @State private var isRecoveryExpanded = false

    var body: some View {
        // `@Bindable` is what turns the `@Observable` settings object into bindings the
        // toggles can write through. It has to be a `var`.
        @Bindable var settings = model.settings

        NavigationStack {
            ZStack {
                ScreenBackground()

                List {
                    Section {
                        toggleRow(Strings.settingsInvert, isOn: $settings.invertSwipeDirection)
                    } header: {
                        sectionHeader(Strings.settingsSwiping)
                    } footer: {
                        // Spells out the arrangement now in force, because "swap" alone
                        // does not say which way round the user has ended up.
                        sectionFooter(
                            settings.invertSwipeDirection
                                ? Strings.settingsInvertHintSwapped
                                : Strings.settingsInvertHintDefault
                        )
                    }
                    .listRowBackground(Theme.surface)

                    Section {
                        toggleRow(Strings.settingsHaptics, isOn: $settings.hapticsEnabled)
                        toggleRow(Strings.settingsConfirm, isOn: $settings.confirmBeforeCommit)
                    } footer: {
                        sectionFooter(Strings.settingsConfirmHint)
                    }
                    .listRowBackground(Theme.surface)

                    Section {
                        toggleRow(Strings.settingsSortNewest, isOn: $settings.sortNewestFirst)
                        toggleRow(Strings.settingsIncludeFavourites, isOn: $settings.includeFavourites)
                    } footer: {
                        sectionFooter(Strings.settingsIncludeFavouritesHint)
                    }
                    .listRowBackground(Theme.surface)

                    historySection

                    resetSection

                    aboutSection
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(Strings.settings)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(Strings.done) {
                        onClose()
                    }
                    .font(.headline)
                    .foregroundStyle(Theme.yellow)
                }
            }
            .alert(Strings.settingsResetConfirmTitle, isPresented: $isShowingResetAlert) {
                Button(Strings.cancel, role: .cancel) { }
                Button(Strings.settingsResetConfirmAction, role: .destructive) {
                    model.resetHistory()
                }
            } message: {
                // The count is read at presentation time so the warning names the photos
                // actually at risk, rather than describing the reset in the abstract.
                Text(Strings.settingsResetConfirmBody(pending: model.pendingCount))
            }
        }
    }

    // MARK: - Sections

    private var historySection: some View {
        Section {
            if model.receipts.isEmpty {
                Text(Strings.settingsReceiptsEmpty)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(model.receipts) { receipt in
                    receiptRow(receipt)
                }
            }

            DisclosureGroup(isExpanded: $isRecoveryExpanded) {
                Text(Strings.recoveryHowTo)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
            } label: {
                Text(Strings.recoveryHowToTitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Theme.yellow)
        } header: {
            sectionHeader(Strings.settingsHistory)
        }
        .listRowBackground(Theme.surface)
    }

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                isShowingResetAlert = true
            } label: {
                Text(Strings.settingsResetReviewed)
                    .font(.subheadline)
                    .foregroundStyle(Theme.red)
            }
        } footer: {
            sectionFooter(Strings.settingsResetHint)
        }
        .listRowBackground(Theme.surface)
    }

    private var aboutSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(Strings.settingsPromises)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text(Strings.settingsPromisesBody)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(Strings.lifetimeLine(reviewed: model.lifetimeReviewed, binned: model.lifetimeBinned))
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            sectionHeader(Strings.settingsAbout)
        }
        .listRowBackground(Theme.surface)
    }

    // MARK: - Rows

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .font(.subheadline)
            .foregroundStyle(Theme.textPrimary)
            .tint(Theme.green)
    }

    private func receiptRow(_ receipt: DeletionReceipt) -> some View {
        let detail = receipt.pile.isEmpty
            ? receipt.summary
            : "\(receipt.summary) · \(receipt.pile)"

        return VStack(alignment: .leading, spacing: 3) {
            Text(Formatters.dateAndTime(receipt.date))
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)

            Text(detail)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.textTertiary)
    }

    private func sectionFooter(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
