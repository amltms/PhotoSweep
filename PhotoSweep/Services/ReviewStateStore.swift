import Foundation
import Observation

/// The only thing in PhotoSweep that touches the disk.
///
/// Everything here is best-effort by design. Losing a saved file costs the user a repeat
/// of some swiping; crashing on a persistence path costs them the app. So there is no
/// `try!` and no `fatalError` below: a failed write leaves the state dirty and is retried
/// on the next mutation or flush, and a failed read starts from a clean `ReviewState()`.
///
/// `@Observable` because `AppModel` exposes `hasCompletedOnboarding`, `lifetimeReviewed`,
/// `lifetimeBinned` and `receipts` straight through from `state`. Without observation here
/// those are invisible to SwiftUI: finishing onboarding or committing a deletion would
/// change the state and leave every view showing the old value until something else
/// happened to invalidate it.
@MainActor
@Observable
final class ReviewStateStore {

    /// The live state. Mutated only through `mutate(_:)`, so no change can escape without
    /// being scheduled for a save.
    private(set) var state = ReviewState()

    /// Set when a saved file existed but could not be read. Surfaced once, then cleared.
    private(set) var loadError: String?

    // MARK: - Storage locations

    private let folderName = "PhotoSweep"
    private let fileName = "review-state.json"
    private let backupFileName = "review-state.bak"

    // MARK: - Save bookkeeping

    // None of the bookkeeping below is ever read by a view, so it is kept out of the
    // observation graph: only `state` and `loadError` should be able to invalidate a body.

    @ObservationIgnored private var isDirty = false

    /// The pending debounced write. A `Task` rather than a `Timer`, because a `Timer`
    /// needs a live run loop in a common mode, which a backgrounding app does not have.
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    /// Kept for diagnostics only. The user is never shown a save failure: the next
    /// mutation retries it, and a transient disk error is not something they can act on.
    @ObservationIgnored private var lastSaveErrorDescription: String?

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    // MARK: - Loading

    /// Reads the file. On a fingerprint mismatch or a decode failure the bad file is
    /// renamed to `review-state.bak` and the state starts from `ReviewState()`.
    func load(fingerprint: String) {
        saveTask?.cancel()
        saveTask = nil

        var loaded = ReviewState()

        if let url = try? fileURL(), FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                let decoded = try decoder.decode(ReviewState.self, from: data)

                if decoded.fingerprint.isEmpty || decoded.fingerprint == fingerprint {
                    loaded = decoded
                } else {
                    // `localIdentifier` values are device-local. After a restore onto
                    // another device they point at different photos, or at nothing, so
                    // trusting them would hide pictures the user has never seen.
                    moveFileAside(from: url)
                    log("Fingerprint mismatch - saved progress discarded.")
                }
            } catch {
                moveFileAside(from: url)
                loadError = Strings.stateLoadFailed
                log("Could not read saved state: \(error.localizedDescription)")
            }
        }

        loaded.fingerprint = fingerprint
        state = loaded

        // Write the fingerprint out even on a first run: until it reaches disk there is
        // nothing to compare against, so a restore onto another device would go unnoticed.
        isDirty = true
        scheduleSave()
    }

    func clearLoadError() {
        loadError = nil
    }

    // MARK: - Mutation

    /// Applies `change` and schedules a debounced (~1s) atomic write, so a burst of
    /// swipes costs one write rather than one per card.
    func mutate(_ change: (inout ReviewState) -> Void) {
        change(&state)
        isDirty = true
        scheduleSave()
    }

    /// Writes immediately if dirty. Called on `scenePhase` leaving `.active`, which is the
    /// last moment the app is reliably alive.
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        writeIfDirty()
    }

    /// Clears progress but keeps receipts, lifetime counters and the onboarding and
    /// rehearsal flags: the user asked to see their photos again, not to be told about
    /// the app again. Clearing `hasCompletedRehearsal` here would make `needsRehearsal`
    /// true and rebuild the root view out from under the Settings sheet the reset was
    /// tapped in; the rehearsal is re-run only when the swipe directions change.
    func resetProgress() {
        mutate { state in
            state.decidedIDs = []
            state.pendingDeletionIDs = []
        }
        flush()
    }

    // MARK: - Saving

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.writeIfDirty()
        }
    }

    private func writeIfDirty() {
        guard isDirty else { return }

        do {
            let data = try encoder.encode(state)
            var url = try fileURL()

            // Not `.completeFileProtection`: the app can be woken to save after a
            // background hop while the device is still locked, and a fully protected
            // file is unwritable then.
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            isDirty = false
            lastSaveErrorDescription = nil

            // Regenerable local bookkeeping, and the identifiers inside it mean nothing on
            // another device, so it must never travel in a backup.
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            do {
                // `setResourceValues` is mutating on `url` and takes its argument by
                // value — there is no `inout` parameter here.
                try url.setResourceValues(values)
            } catch {
                // The bytes are safely written; only the backup flag failed. Not worth a retry.
                log("Could not exclude state file from backup: \(error.localizedDescription)")
            }
        } catch {
            // Stays dirty deliberately: the next mutation or flush tries again.
            //
            // A failing disk tends to fail the same way on every retry, and every
            // mutation schedules one, so the same line would otherwise be printed on a
            // loop. Only a change of failure is worth a line.
            let description = error.localizedDescription
            if lastSaveErrorDescription != description {
                log("Could not save state: \(description)")
            }
            lastSaveErrorDescription = description
        }
    }

    // MARK: - Files

    private func directoryURL() throws -> URL {
        let manager = FileManager.default
        let base = try manager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent(folderName, isDirectory: true)

        // Application Support is not created for you, and neither is our subfolder.
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        return directory
    }

    private func fileURL() throws -> URL {
        try directoryURL().appendingPathComponent(fileName, isDirectory: false)
    }

    /// Keeps an unreadable file rather than deleting it, so a decode bug is still
    /// recoverable by hand instead of having quietly eaten someone's progress.
    private func moveFileAside(from url: URL) {
        let manager = FileManager.default
        let backup = url
            .deletingLastPathComponent()
            .appendingPathComponent(backupFileName, isDirectory: false)

        if manager.fileExists(atPath: backup.path) {
            try? manager.removeItem(at: backup)
        }

        do {
            try manager.moveItem(at: url, to: backup)
        } catch {
            // If it cannot even be moved, drop it: left in place it would fail the same
            // way on every launch.
            try? manager.removeItem(at: url)
            log("Could not move the unreadable state file aside: \(error.localizedDescription)")
        }
    }

    private func log(_ message: String) {
        #if DEBUG
        print("[ReviewStateStore] \(message)")
        #endif
    }
}
