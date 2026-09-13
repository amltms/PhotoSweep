import Foundation

/// Every user-facing string in the app, in British English, in one auditable file.
///
/// Safety copy in particular must never drift: the words the app uses about deletion
/// are a promise, so they live here and nowhere else.
enum Strings {

    // MARK: - App

    static let appName = "PhotoSweep"
    static let tagline = "Tidy your photo library, one swipe at a time"

    // MARK: - Core verbs
    //
    // "Bin" rather than "Delete" throughout the swiping flow, because a swipe does not
    // delete anything. The word "Delete" is reserved for the single screen where a real
    // deletion actually happens.

    static let keep = "Keep"
    static let bin = "Bin"
    static let undo = "Undo"
    static let finish = "Finish"
    static let done = "Done"
    static let cancel = "Cancel"
    static let close = "Close"
    static let back = "Back"
    static let next = "Next"
    static let skip = "Skip"
    static let settings = "Settings"
    static let review = "Review"

    // MARK: - Onboarding

    static let onboardingTitle1 = "Swipe to tidy up"
    static let onboardingBody1 = """
        PhotoSweep shows your photos one at a time. One swipe decides each one, so you can \
        work through a whole library without ever opening a folder.
        """

    static let onboardingTitle2 = "Right bins, left keeps"
    static let onboardingBody2 = """
        This is the opposite way round to dating apps, so it is worth a moment to take in: \
        swipe RIGHT to put a photo in the bin, swipe LEFT to keep it.

        You can swap the directions over later in Settings.
        """

    static let onboardingTitle3 = "Swiping deletes nothing"
    static let onboardingBody3 = """
        A right swipe only adds a photo to a list. Nothing is removed from your library \
        until you open that list, look through it, and press the delete button yourself.

        Made a mistake? Undo goes back as far as you like.
        """

    static let onboardingTitle4 = "Where deleted photos go"
    static let onboardingBody4 = """
        Photos you confirm are moved to Recently Deleted in the Photos app, where they stay \
        for about 30 days before iOS removes them for good.

        iOS will ask you to confirm each batch as well. That second prompt is normal.
        """

    static let onboardingContinue = "Continue"
    static let onboardingBegin = "Get started"

    // MARK: - Rehearsal

    static let rehearsalTitle = "A quick practice"
    static let rehearsalBody = "Two practice cards, so the directions are in your fingers before we touch real photos."
    static let rehearsalPromptBin = "Swipe this one to the BIN"
    static let rehearsalPromptKeep = "Now KEEP this one"
    static let rehearsalWrongWay = "That was the other direction — try again"
    static let rehearsalDone = "That is the whole app. Ready?"
    static let rehearsalStart = "Start sweeping"

    // MARK: - Permission

    static let permissionTitle = "PhotoSweep needs your photo library"
    static let permissionBody = """
        To show you your photos and tidy them up, PhotoSweep needs permission to read your \
        library. Nothing is uploaded, and nothing is deleted without you confirming it.
        """
    static let permissionGrant = "Allow access"

    static let permissionDeniedTitle = "Photo access is switched off"
    static let permissionDeniedBody = """
        PhotoSweep cannot show you anything without access to your photo library. You can \
        switch it back on in the Settings app, under Privacy & Security ▸ Photos.
        """
    static let permissionOpenSettings = "Open Settings"

    static let permissionRestrictedTitle = "Photo access is not available"
    static let permissionRestrictedBody = """
        Access to the photo library is restricted on this device, probably by Screen Time \
        or a device management profile. PhotoSweep cannot continue.
        """

    static let limitedAccessTitle = "You have shared some photos"
    static let limitedChooseMore = "Choose more photos"
    static let limitedManage = "Manage selection"

    static func limitedAccessBody(count: Int) -> String {
        if count == 0 {
            return "You have not shared any photos with PhotoSweep yet. Choose some to get started, or allow full access in the Settings app."
        }
        return "PhotoSweep can only see the \(count.formatted()) \(count == 1 ? "photo" : "photos") you shared with it. You can add more at any time, or allow full access in the Settings app."
    }

    // MARK: - Home

    static let homeTitle = "What shall we tidy?"
    static let pileAll = "Everything"
    static let pileScreenshots = "Screenshots"
    static let pileVideos = "Videos"
    static let pileByMonth = "By month"

    static let pileAllHint = "Your whole library, newest first"
    static let pileScreenshotsHint = "Usually the quickest win"
    static let pileVideosHint = "Longest first — these take the most space"
    static let pileByMonthHint = "Work through one month at a time"

    static let resumeTitle = "Carry on where you left off"

    static func remainingCount(_ n: Int) -> String {
        n == 1 ? "1 photo left to review" : "\(n.formatted()) photos left to review"
    }

    // MARK: - Deck

    static let deckLegendBinRight = "← Keep · Bin →"
    static let deckLegendBinLeft = "← Bin · Keep →"

    static let stampKeep = "KEEP"
    static let stampBin = "BIN"

    static let iCloudDownloading = "Downloading from iCloud…"
    static let iCloudFailed = "This photo could not be loaded"
    static let iCloudRetry = "Try again"
    static let binDisabledWhileLoading = "Wait for the photo to load before binning it"

    static let peekHint = "Press and hold to see it full size"

    static func photoOfTotal(_ index: Int, _ total: Int) -> String {
        "\(index.formatted()) of \(total.formatted())"
    }

    // MARK: - Bin / review

    static let binTitle = "Your bin"
    static let binEmptyTitle = "Nothing in the bin"
    static let binEmptyBody = "Photos you swipe towards the bin will collect here. Nothing is deleted until you come back and confirm."
    static let binTapToRestore = "Tap a photo to take it back out"
    static let binKeepAll = "Keep them all"

    /// Shown on the home screen whenever the bin is not empty, including a bin left over
    /// from a previous session. It has to describe photos *waiting*, not an aftermath:
    /// a user who has never opened the deletion sheet must not be told about a deletion.
    static let binWaitingBody = "These photos are marked, not deleted. Open your bin to look through them and decide."

    static func binHeader(binned: Int, kept: Int) -> String {
        "Bin \(binned.formatted()) · Kept \(kept.formatted())"
    }

    static func binCommitButton(_ n: Int) -> String {
        n == 1 ? "Move 1 photo to Recently Deleted" : "Move \(n.formatted()) photos to Recently Deleted"
    }

    static let binConfirmTitle = "Move these to Recently Deleted?"

    static func binConfirmBody(_ n: Int) -> String {
        """
        \(n.formatted()) \(n == 1 ? "photo" : "photos") will be moved to Recently Deleted in the Photos app.

        They stay there for about 30 days, so you can still get them back. If iCloud Photos is \
        switched on, they will be removed from your other devices too.

        iOS will ask you to confirm as well.
        """
    }

    static let binConfirmAction = "Move to Recently Deleted"

    // MARK: - Commit outcomes

    static func commitSucceeded(_ n: Int) -> String {
        n == 1 ? "1 photo moved to Recently Deleted" : "\(n.formatted()) photos moved to Recently Deleted"
    }

    static let commitCancelled = "Nothing was deleted — your bin is still here."
    static let commitNothingToDo = "There was nothing left to delete."

    static func commitFailed(_ reason: String) -> String {
        "Nothing was deleted. \(reason)"
    }

    static let commitInProgress = "Moving photos…"

    static let recoveryHowTo = """
        To get a photo back, open Photos ▸ Albums ▸ Recently Deleted.

        To free up the space straight away, empty that album yourself — no other app is \
        allowed to do it for you.
        """
    static let recoveryHowToTitle = "How to get a deleted photo back"

    // MARK: - Summary

    static let summaryTitle = "Nicely done"
    static let summaryAllCaughtUp = "You are all caught up"
    static let summaryAllCaughtUpBody = "Every photo in this pile has been reviewed. New photos will appear here as you take them."
    static let summaryReviewBin = "Review your bin"
    static let summaryKeepSweeping = "Keep sweeping"
    static let summaryBackHome = "Back to the start"

    static func summaryLine(reviewed: Int, kept: Int, binned: Int) -> String {
        "\(reviewed.formatted()) reviewed · \(kept.formatted()) kept · \(binned.formatted()) binned"
    }

    static func excludedNote(_ n: Int) -> String {
        n == 1
            ? "1 photo was skipped because it cannot be deleted by another app (a favourite, a shared album, or synced from a computer)."
            : "\(n.formatted()) photos were skipped because they cannot be deleted by another app (favourites, shared albums, or photos synced from a computer)."
    }

    // MARK: - Empty states

    static let emptyLibraryTitle = "Your library is empty"
    static let emptyLibraryBody = "There are no photos for PhotoSweep to show. Take a few and come back."

    static let emptyPileTitle = "Nothing here"
    static let emptyPileBody = "There are no photos in this pile. Try another one."

    static let accessRevokedTitle = "Photo access was withdrawn"
    static let accessRevokedBody = "PhotoSweep lost access to your library while you were using it. Your bin has been kept safe."

    // MARK: - Settings

    static let settingsSwiping = "Swiping"
    static let settingsInvert = "Swap swipe directions"
    static let settingsInvertHintDefault = "Right bins, left keeps"
    static let settingsInvertHintSwapped = "Left bins, right keeps"
    static let settingsHaptics = "Vibrate on each swipe"
    static let settingsConfirm = "Ask before deleting"
    static let settingsConfirmHint = "Shows a summary before iOS asks you to confirm"
    static let settingsSortNewest = "Newest photos first"
    static let settingsIncludeFavourites = "Include favourites"
    static let settingsIncludeFavouritesHint = "Off by default, so a photo you have starred never reaches the bin"

    static let settingsHistory = "History"
    static let settingsReceipts = "Deletion history"
    static let settingsReceiptsEmpty = "You have not deleted anything yet"
    static let settingsResetReviewed = "Start again from scratch"
    static let settingsResetHint = "Forgets which photos you have already reviewed, and empties your bin. No photo in your library is deleted or changed."
    static let settingsResetConfirmTitle = "Start again from scratch?"
    static let settingsResetConfirmAction = "Forget my progress"

    /// Names the number of photos currently in the bin, because resetting empties it.
    ///
    /// Emptying the bin is deliberate — clearing `decidedIDs` while leaving photos staged
    /// would let a photo the user re-swipes to KEEP stay on the deletion list — but the
    /// user has to be told, or the reset silently discards work they did on purpose.
    static func settingsResetConfirmBody(pending: Int) -> String {
        let base = "PhotoSweep will forget which photos you have already reviewed and show you the whole pile again. No photo in your library is deleted or changed."
        guard pending > 0 else { return base }
        let bin = pending == 1
            ? "The 1 photo waiting in your bin will be taken back out"
            : "The \(pending.formatted()) photos waiting in your bin will be taken back out"
        return "\(base)\n\n\(bin), so nothing is left marked for deletion."
    }

    static let settingsAbout = "About"
    static let settingsPromises = "What PhotoSweep will not do"
    static let settingsPromisesBody = """
        • It never deletes anything from a swipe — only from the delete button you press yourself.
        • It never uploads, shares or copies a photo anywhere. The only thing that crosses \
        the network is iOS fetching your own iCloud photos so it can show them to you.
        • It never touches favourites unless you switch that on.
        • It never empties Recently Deleted. Only you can do that, in the Photos app.
        • It never collects anything about you. There are no accounts and no analytics.
        """

    static func lifetimeLine(reviewed: Int, binned: Int) -> String {
        "\(reviewed.formatted()) photos reviewed · \(binned.formatted()) binned, all time"
    }

    // MARK: - Errors

    static let genericErrorTitle = "Something went wrong"
    static let stateLoadFailed = "Your saved progress could not be read, so PhotoSweep has started fresh. No photos were affected."

    // MARK: - Accessibility

    static let a11yKeepAction = "Keep this photo"
    static let a11yBinAction = "Mark this photo for the bin"
    static let a11yUndoAction = "Undo the last decision"
    static let a11yOpenBin = "Open the bin"
    static let a11yCardHintBinRight = "Swipe right to mark for the bin, swipe left to keep. Or use the actions rotor."
    static let a11yCardHintBinLeft = "Swipe left to mark for the bin, swipe right to keep. Or use the actions rotor."

    static func a11yCardLabel(date: String, isVideo: Bool, duration: String?) -> String {
        var parts: [String] = [isVideo ? "Video" : "Photo", "taken \(date)"]
        if let duration { parts.append("lasting \(duration)") }
        return parts.joined(separator: ", ")
    }
}
