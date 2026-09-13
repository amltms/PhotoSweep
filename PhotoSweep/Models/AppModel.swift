import Foundation
import Observation
import Photos

/// Tuning constants for the deck. Kept out of `AppModel` itself so the `@Observable`
/// macro has nothing to think about, and `private` so the names cannot collide with a
/// type another file owns.
private enum DeckTuning {

    /// How many undecided cards the deck tries to keep ahead of the cursor. Comfortably
    /// more than the three that are drawn, so a fast swiper never out-runs the refill.
    static let lookahead = 14

    /// How many assets one `objects(at:)` fault pulls in. Big enough that a run of
    /// already-decided assets is skipped in a couple of calls, small enough that the
    /// fault is never noticeable.
    static let scanWindow = 30

    /// The card stack draws the top card plus two behind it.
    static let visibleDepth = 3

    /// Window size for the month histogram. Small, because the loop yields between
    /// windows and a large library would otherwise hold the main actor for seconds.
    static let monthScanWindow = 500
}

/// The hub: the single source of truth every screen reads and the only object allowed
/// to mutate a decision.
///
/// Two invariants carry most of the weight here and must not be broken casually.
///
/// 1. **The deck is append-only.** `cursor` walks forwards over `deck`; entries are never
///    removed. That keeps SwiftUI's view identity stable across a swipe (so the card
///    behind does not flicker as it is promoted), and it makes undo a decrement rather
///    than a re-fetch.
/// 2. **Identity is `PHAsset.localIdentifier`.** No integer index into a `PHFetchResult`
///    survives a library change, so the cursor is always re-anchored by identifier.
///
/// Nothing in this type deletes a photo. A decision appends a `String` to an array; the
/// only call into `DeletionService` is `commitDeletions()`, which the user has to press.
@MainActor
@Observable
final class AppModel {

    // MARK: - Collaborators

    let settings: AppSettings
    let store: ReviewStateStore
    let pipeline: ImagePipeline

    init(settings: AppSettings = AppSettings(),
         store: ReviewStateStore = ReviewStateStore(),
         pipeline: ImagePipeline = ImagePipeline()) {
        self.settings = settings
        self.store = store
        self.pipeline = pipeline
    }

    // MARK: - Authorisation

    private(set) var authStatus: PHAuthorizationStatus = .notDetermined
    private(set) var sharedAssetCount: Int = 0

    // MARK: - Session

    private(set) var filter: LibraryFilter = .all
    private(set) var deck: [DeckCard] = []
    private(set) var cursor: Int = 0
    private(set) var isPreparing: Bool = false
    private(set) var totalInPile: Int = 0
    private(set) var excludedCount: Int = 0
    private(set) var sessionError: String?

    // MARK: - Decisions

    private(set) var decidedIDs: Set<String> = []
    private(set) var pendingDeletionIDs: [String] = []
    private(set) var undoStack: [UndoEntry] = []
    private(set) var keptThisSession: Int = 0
    private(set) var binnedThisSession: Int = 0

    // MARK: - Commit

    private(set) var isCommitting: Bool = false
    private(set) var lastOutcome: CommitOutcome?

    // MARK: - Private state

    /// The lazy fetch result for the current pile. `nil` between sessions.
    private var queue: AssetQueue?

    /// How far through `queue` the deck has been filled from. Only ever moves forwards
    /// within one build of the deck; reset to 0 when the deck is rebuilt.
    private var scanIndex: Int = 0

    /// The most recent library change, held until the deck is idle enough to absorb it.
    /// Rebuilding the deck underneath a finger that is mid-swipe is the one thing the
    /// user would experience as the app losing their place.
    private var bufferedChange: PHChange?

    /// Ids that still have an entry on `undoStack` but whose bin mark has since been
    /// settled somewhere else — taken back out of the bin, kept en masse, or emptied out
    /// of the bin without being deleted. All three of those paths re-score the photo from
    /// binned to kept and give `lifetimeBinned` back as they go.
    ///
    /// The entry itself has to stay on the stack. `undo()` pops exactly one entry and
    /// steps the cursor back exactly one card, so pulling an entry out of the *middle*
    /// would leave every entry below it describing the card one place further on: those
    /// undos would then fail the identity check and reverse a decision without moving the
    /// deck. Marking the entry keeps that lockstep while telling `undo()` which counter
    /// owes the photo back — the keep it has since become, not the bin it no longer is.
    /// Reversing it as a bin would take `lifetimeBinned` down a second time for a photo
    /// that is not in the bin, and leave the persisted total permanently low.
    private var settledUndoIDs: Set<String> = []

    /// Bumped every time this model changes something inside `store`.
    ///
    /// `ReviewStateStore` **is** `@Observable` (see its own header), and both `state` and
    /// `loadError` are observation-tracked, so `mutate(_:)` already invalidates any view
    /// that read them. This counter is therefore redundant reinforcement rather than the
    /// only invalidation: the derived properties below reach the store through two objects
    /// (`self` → `store` → `state`), and reading a stored property of *this* class as well
    /// makes the dependency unconditional however a view happens to be composed.
    ///
    /// Both halves are idempotent, so nothing misbehaves either way — but do not strip the
    /// counter out casually as "dead code": it is 18 call sites against a working
    /// invalidation path, and it should be removed on its own or not at all.
    private var storeRevision: Int = 0

    /// Call immediately after any `store` mutation, so the derived properties invalidate.
    private func noteStoreChanged() {
        storeRevision &+= 1
    }

    /// Registers the dependency described on `storeRevision`.
    private func trackStore() {
        _ = storeRevision
    }

    // MARK: - Onboarding

    var hasCompletedOnboarding: Bool {
        trackStore()
        return store.state.hasCompletedOnboarding
    }

    /// The practice cards are shown again after the directions are swapped: muscle memory
    /// built on the old mapping would otherwise bin a photo the user meant to keep.
    var needsRehearsal: Bool {
        trackStore()
        if !store.state.hasCompletedRehearsal { return true }
        return store.state.rehearsedWithInvert != settings.invertSwipeDirection
    }

    func completeOnboarding() {
        store.mutate { state in
            state.hasCompletedOnboarding = true
        }
        noteStoreChanged()
        store.flush()
    }

    func completeRehearsal() {
        let invert = settings.invertSwipeDirection
        store.mutate { state in
            state.hasCompletedRehearsal = true
            state.rehearsedWithInvert = invert
        }
        noteStoreChanged()
        store.flush()
    }

    // MARK: - Derived

    var currentCard: DeckCard? {
        guard cursor >= 0, cursor < deck.count else { return nil }
        return deck[cursor]
    }

    /// Up to three cards, top card first. Empty once the cursor has run off the end.
    var visibleCards: [DeckCard] {
        let start = clampedCursor
        guard start < deck.count else { return [] }
        let end = min(start + DeckTuning.visibleDepth, deck.count)
        return Array(deck[start ..< end])
    }

    /// How far behind the top card this one is drawn. Anything not currently visible is
    /// reported as 0, which is the safe answer: it is what the top card gets.
    func depth(of card: DeckCard) -> Int {
        let start = clampedCursor
        let end = min(start + DeckTuning.visibleDepth, deck.count)
        var index = start
        while index < end {
            if deck[index].id == card.id { return index - start }
            index += 1
        }
        return 0
    }

    var canUndo: Bool { !undoStack.isEmpty }

    var pendingCount: Int { pendingDeletionIDs.count }

    var reviewedThisSession: Int { keptThisSession + binnedThisSession }

    /// True only when the deck is exhausted *and* there is nothing left in the fetch
    /// result to refill it from — an empty deck alone just means "still filling".
    var isPileFinished: Bool {
        guard !isPreparing, let queue else { return false }
        return cursor >= deck.count && scanIndex >= queue.count
    }

    var progress: Double {
        let value = Double(reviewedThisSession) / Double(max(1, totalInPile))
        return min(1, max(0, value))
    }

    var mapping: SwipeMapping { settings.mapping }

    var lifetimeReviewed: Int {
        trackStore()
        return store.state.lifetimeReviewed
    }

    var lifetimeBinned: Int {
        trackStore()
        return store.state.lifetimeBinned
    }

    var receipts: [DeletionReceipt] {
        trackStore()
        return store.state.receipts
    }

    private var clampedCursor: Int {
        min(max(cursor, 0), deck.count)
    }

    // MARK: - Lifecycle

    func bootstrap() async {
        await refreshAuthorisation()

        store.load(fingerprint: PhotoAuthoriser.libraryFingerprint())
        noteStoreChanged()
        decidedIDs = Set(store.state.decidedIDs)
        pendingDeletionIDs = store.state.pendingDeletionIDs

        Haptics.isEnabled = settings.hapticsEnabled
        Haptics.prepare()
    }

    func requestAuthorisation() async {
        authStatus = await PhotoAuthoriser.request()
        sharedAssetCount = authStatus == .limited ? PhotoAuthoriser.sharedAssetCount() : 0
    }

    func refreshAuthorisation() async {
        authStatus = PhotoAuthoriser.status
        sharedAssetCount = authStatus == .limited ? PhotoAuthoriser.sharedAssetCount() : 0
    }

    // MARK: - Session

    func startSession(filter: LibraryFilter) async {
        self.filter = filter
        sessionError = nil
        lastOutcome = nil
        bufferedChange = nil

        guard authStatus == .authorized || authStatus == .limited else {
            sessionError = Strings.accessRevokedBody
            deck.removeAll()
            cursor = 0
            scanIndex = 0
            totalInPile = 0
            excludedCount = 0
            // Left standing, `canUndo` would be true over an empty deck and `undo()` would
            // decrement session counters for a card that is no longer anywhere.
            undoStack.removeAll()
            settledUndoIDs.removeAll()
            queue = nil
            isPreparing = false
            return
        }

        isPreparing = true

        // Building the fetch result is synchronous PhotoKit work, on the main actor, on
        // purpose. `PHFetchResult` is lazy: this call reads a count and nothing else, so
        // it is cheap even over a six-figure library. Do NOT "optimise" it onto a
        // background queue — PhotoKit objects are kept main-actor-isolated throughout
        // this app, and moving one across isolation is the bug that cannot be found
        // without a device.
        let result = filter.fetch(sortNewestFirst: settings.sortNewestFirst)
        let newQueue = AssetQueue(fetchResult: result)
        queue = newQueue

        deck.removeAll()
        cursor = 0
        scanIndex = 0
        excludedCount = 0
        keptThisSession = 0
        binnedThisSession = 0
        undoStack.removeAll()
        settledUndoIDs.removeAll()
        totalInPile = newQueue.count

        refillDeck()
        updatePrefetchWindow()

        Haptics.prepare()
        isPreparing = false
    }

    /// Tears the deck down but deliberately leaves the session counters standing, because
    /// the summary that prompted this call is still on screen reading them.
    func endSession() {
        pipeline.stopAllPrefetching()
        deck.removeAll()
        cursor = 0
        scanIndex = 0
        undoStack.removeAll()
        settledUndoIDs.removeAll()
        queue = nil
        bufferedChange = nil
        isPreparing = false
        store.flush()
    }

    // MARK: - Decisions

    func decide(_ decision: Decision, expecting id: String) {
        // A drag that ends twice, or a button pressed while the card is already flying
        // away, arrives here as a second call for a card that is no longer on top. It
        // must be a no-op, never a decision about the next photo.
        guard !isCommitting, let card = currentCard, card.id == id else { return }

        undoStack.append(UndoEntry(id: card.id, decision: decision))
        // A fresh decision is reversible again, whatever happened to this photo's previous
        // trip through the bin.
        settledUndoIDs.remove(card.id)
        let isNewlyDecided = decidedIDs.insert(card.id).inserted

        switch decision {
        case .keep:
            keptThisSession += 1
            Haptics.keep()
        case .bin:
            if !pendingDeletionIDs.contains(card.id) {
                pendingDeletionIDs.append(card.id)
            }
            binnedThisSession += 1
            Haptics.bin()
        }

        cursor += 1
        refillDeck()
        updatePrefetchWindow()

        let pending = pendingDeletionIDs
        let decidedID = card.id
        store.mutate { state in
            if isNewlyDecided {
                state.decidedIDs.append(decidedID)
            }
            state.pendingDeletionIDs = pending
            state.lifetimeReviewed += 1
            if decision == .bin {
                state.lifetimeBinned += 1
            }
        }
        noteStoreChanged()
    }

    /// Steps back exactly one card. Safe because the deck is append-only: the card the
    /// popped entry describes is still sitting at `cursor - 1`.
    func undo() {
        guard !isCommitting, let entry = undoStack.popLast() else { return }

        // Step back only onto the card this entry is actually about. While the deck is
        // append-only that is always `cursor - 1`, but a library change rebuilds the deck
        // and skips everything already decided, and an unchecked decrement would then put
        // a photo the user has never been asked about on screen as though they had just
        // decided it. The decision itself is still reversed either way.
        if cursor > 0, cursor - 1 < deck.count, deck[cursor - 1].id == entry.id {
            cursor -= 1
        }

        // Which counter owes this photo back? Normally the one the swipe incremented. But
        // if the mark was settled from the bin screen — taken back out, kept en masse, or
        // the bin emptied — the photo has already been re-scored from binned to kept and
        // `lifetimeBinned` has already been given back with it, so reversing it as a bin
        // here would take that total down twice for a photo that is not in the bin.
        // Reversing the keep it has since become is the reading that leaves every counter
        // whole. Either way the decision itself is reversed, so the card the cursor is now
        // sitting on is undecided again — which is what the user is looking at.
        let wasSettled = settledUndoIDs.remove(entry.id) != nil
        let reversed: Decision = wasSettled ? .keep : entry.decision

        decidedIDs.remove(entry.id)
        pendingDeletionIDs.removeAll { $0 == entry.id }

        switch reversed {
        case .keep: keptThisSession = max(0, keptThisSession - 1)
        case .bin: binnedThisSession = max(0, binnedThisSession - 1)
        }

        updatePrefetchWindow()
        Haptics.undo()

        let pending = pendingDeletionIDs
        let restoredID = entry.id
        let wasBin = reversed == .bin
        store.mutate { state in
            state.decidedIDs.removeAll { $0 == restoredID }
            state.pendingDeletionIDs = pending
            state.lifetimeReviewed = max(0, state.lifetimeReviewed - 1)
            if wasBin {
                state.lifetimeBinned = max(0, state.lifetimeBinned - 1)
            }
        }
        noteStoreChanged()
    }

    /// Takes one photo back out of the bin, from the bin screen.
    ///
    /// The id stays in `decidedIDs`: taking a photo out of the bin is a decision to keep
    /// it, so offering it again on the next sweep would be asking the same question twice.
    func restore(id: String) {
        guard let index = pendingDeletionIDs.firstIndex(of: id) else { return }

        pendingDeletionIDs.remove(at: index)
        decidedIDs.insert(id)

        // If this photo was binned by a swipe in this session its undo entry is still on
        // the stack, and the counters are re-scored from binned to kept just below. Mark
        // the entry so that Undo gives back the keep it has become rather than the bin it
        // no longer is, which would take `binnedThisSession` and `lifetimeBinned` down a
        // second time for a photo that was only ever binned once.
        if undoStack.contains(where: { $0.id == id }) {
            settledUndoIDs.insert(id)
        }

        if binnedThisSession > 0 {
            binnedThisSession -= 1
            keptThisSession += 1
        }

        Haptics.undo()

        let pending = pendingDeletionIDs
        store.mutate { state in
            state.pendingDeletionIDs = pending
            state.lifetimeBinned = max(0, state.lifetimeBinned - 1)
        }
        noteStoreChanged()
    }

    /// "Keep them all": empties the bin without deleting anything, leaving every id
    /// decided so none of them comes round again.
    func keepAllInBin() {
        let ids = pendingDeletionIDs
        guard !ids.isEmpty else { return }

        decidedIDs.formUnion(ids)
        pendingDeletionIDs.removeAll()

        // Same reason as `restore(id:)`, multiplied by the size of the bin: every one of
        // these photos has just been re-scored as kept, so any undo entry still standing
        // for one of them describes a keep now.
        let settled = Set(ids)
        for entry in undoStack where settled.contains(entry.id) {
            settledUndoIDs.insert(entry.id)
        }

        keptThisSession += min(binnedThisSession, ids.count)
        binnedThisSession = max(0, binnedThisSession - ids.count)

        Haptics.success()

        store.mutate { state in
            state.pendingDeletionIDs = []
            var known = Set(state.decidedIDs)
            for id in ids {
                if known.contains(id) { continue }
                known.insert(id)
                state.decidedIDs.append(id)
            }
            state.lifetimeBinned = max(0, state.lifetimeBinned - ids.count)
        }
        noteStoreChanged()
        store.flush()
    }

    /// Empties the bin without deleting anything. The ids stay in `decidedIDs`, so nothing
    /// dropped here comes round again; no photo is touched.
    func clearBin() {
        let ids = pendingDeletionIDs
        guard !ids.isEmpty else { return }

        // Dropping a bin mark is a decision to keep the photo, so the tallies move across
        // exactly as they do in `keepAllInBin()`. Leaving them counted as binned would have
        // the summary describing a bin that no longer exists, and would leave `undo()`
        // unable to tell which counter a settled entry owes back.
        let emptied = Set(ids)
        for entry in undoStack where emptied.contains(entry.id) {
            settledUndoIDs.insert(entry.id)
        }

        pendingDeletionIDs.removeAll()
        keptThisSession += min(binnedThisSession, ids.count)
        binnedThisSession = max(0, binnedThisSession - ids.count)

        store.mutate { state in
            state.pendingDeletionIDs = []
            state.lifetimeBinned = max(0, state.lifetimeBinned - ids.count)
        }
        noteStoreChanged()
    }

    // MARK: - Commit

    func commitDeletions() async {
        guard !isCommitting else { return }

        guard !pendingDeletionIDs.isEmpty else {
            lastOutcome = .nothingToDelete
            return
        }

        isCommitting = true

        let ids = pendingDeletionIDs
        let pileTitle = filter.title
        let outcome = await DeletionService.delete(ids: ids)
        lastOutcome = outcome

        switch outcome {
        case .deleted(let count):
            // The bin is emptied here and nowhere else in this method: every other
            // branch means the photos are still in the library, so the list of them
            // must survive untouched.
            //
            // "Emptied" means "minus whatever was actually deleted", not "cleared".
            // `DeletionService` narrows the batch twice before it commits — ids that no
            // longer resolve, then anything failing `Eligibility.canDelete` — so `count`
            // can be smaller than `ids.count`: a photo moved into a shared library since
            // it was binned is still in the library afterwards. Clearing outright would
            // drop it from the bin while `decidedIDs` still holds it, and `refillDeck()`
            // skips anything decided, so it would never be seen or offered again.
            //
            // Anything still fetchable after an atomic `deleteAssets` was, by definition,
            // not in the batch, so re-resolving is an exact answer rather than a guess.
            // Ids that vanish here are genuinely gone from the library and belong out of
            // the bin whether this app deleted them or the Photos app did.
            //
            // Only ids this commit actually attempted may be dropped: anything that
            // reached the bin while the system alert was up was never in this batch, and
            // silently discarding it would lose a mark the user had just made.
            let attempted = Set(ids)
            let survivors = Set(AssetResolver.assets(for: ids).map(\.localIdentifier))
            let stillPending = pendingDeletionIDs.filter {
                !attempted.contains($0) || survivors.contains($0)
            }
            pendingDeletionIDs = stillPending

            // A deletion cannot be undone, and the cards it removed are still sitting in
            // the deck until the library change lands, so an Undo pressed now would step
            // back onto a photo that no longer exists and decrement `lifetimeBinned` for
            // one already counted in `lifetimeDeleted`. Dropping the whole stack is the
            // honest answer and keeps the remaining entries in lockstep with the deck.
            undoStack.removeAll()
            settledUndoIDs.removeAll()

            let receipt = DeletionReceipt(date: Date(), count: count, pile: pileTitle)
            store.mutate { state in
                state.pendingDeletionIDs = stillPending
                state.lifetimeDeleted += count
                state.receipts.insert(receipt, at: 0)
            }
            noteStoreChanged()
            Haptics.success()

        case .cancelledByUser:
            Haptics.warning()

        case .nothingToDelete:
            Haptics.warning()

        case .failed:
            Haptics.failure()
        }

        isCommitting = false
        store.flush()

        // Our own deletion fires `photoLibraryDidChange`, which was buffered while the
        // commit was in flight. Absorb it now that the deck is idle again.
        applyBufferedLibraryChange()
    }

    // MARK: - Piles

    /// The "By month" list: one entry per distinct (year, month) that has photos in it.
    ///
    /// Walked in small windows with a yield between each, so even an enormous library
    /// cannot hold the main actor long enough to drop frames on the screen that is
    /// waiting for this.
    func monthBuckets() async -> [MonthBucket] {
        let scanner = AssetQueue(fetchResult: LibraryFilter.all.fetch(sortNewestFirst: true))
        let assetCount = scanner.count
        guard assetCount > 0 else { return [] }

        var totals: [String: Int] = [:]
        var remainings: [String: Int] = [:]
        var keys: [String] = []
        var years: [String: Int] = [:]
        var months: [String: Int] = [:]

        let calendar = Calendar(identifier: .gregorian)
        var index = 0

        while index < assetCount {
            let upper = min(index + DeckTuning.monthScanWindow, assetCount)
            for asset in scanner.assets(in: index ..< upper) {
                guard let date = asset.creationDate else { continue }
                let parts = calendar.dateComponents([.year, .month], from: date)
                guard let year = parts.year, let month = parts.month else { continue }
                let key = "\(year)-\(month)"
                if let running = totals[key] {
                    totals[key] = running + 1
                } else {
                    totals[key] = 1
                    remainings[key] = 0
                    years[key] = year
                    months[key] = month
                    keys.append(key)
                }

                // Counted here rather than estimated later: this loop has the `PHAsset` in
                // hand already, so the two tests below cost nothing beyond what the date
                // read above has already paid for. They are deliberately the same two the
                // deck applies in `refillDeck()`, so "left to review" is the number of
                // cards this month would actually put on screen.
                if decidedIDs.contains(asset.localIdentifier) { continue }
                if !Eligibility.canEnterDeck(asset, includeFavourites: settings.includeFavourites) {
                    continue
                }
                remainings[key, default: 0] += 1
            }
            index = upper
            await Task.yield()
        }

        return keys.compactMap { key -> MonthBucket? in
            guard
                let bucketTotal = totals[key],
                let year = years[key],
                let month = months[key]
            else { return nil }

            // `remaining` is a real count, not the total: the row says "left to review"
            // and `isComplete` drives the "all caught up" subtitle, so reporting the whole
            // month would mean a month swept to the end still claiming a full pile of work
            // and that branch never being reached. The count was taken in the scan loop
            // above, which already had every asset faulted in, so nothing extra was
            // materialised to get it.
            return MonthBucket(year: year, month: month, total: bucketTotal, remaining: remainings[key] ?? 0)
        }
    }

    // MARK: - Persistence

    func flush() {
        store.flush()
    }

    /// "Start again from scratch": forgets every decision and shows the whole library again.
    ///
    /// The bin is emptied too, and that is deliberate rather than an oversight. Leaving it
    /// populated while `decidedIDs` is cleared would put binned photos back into the deck
    /// with their ids still in `pendingDeletionIDs`, and `decide(_:expecting:)` only ever
    /// *appends* on `.bin` — it never removes on `.keep` — so a photo the user then swiped
    /// to keep would still be deleted by the next commit. No photo is touched here; the
    /// marks are.
    ///
    /// The confirmation copy in `Strings` must therefore say that the bin is emptied.
    func resetHistory() {
        store.resetProgress()
        noteStoreChanged()
        decidedIDs.removeAll()
        pendingDeletionIDs.removeAll()
        undoStack.removeAll()
        settledUndoIDs.removeAll()
        store.flush()
    }

    // MARK: - Library changes

    /// Buffers the change, then tries to absorb it straight away.
    ///
    /// The try is safe even with a finger on a card: the rebuild re-anchors the cursor by
    /// the current card's `localIdentifier`, so the card under the finger keeps both its
    /// place and its SwiftUI identity, and if that photo is the one the change deleted
    /// then `decide(_:expecting:)` rejects the gesture outright rather than applying it to
    /// whatever card took its place. `applyBufferedLibraryChange()` stays public so the
    /// deck screen can also drain the buffer at a moment it knows to be idle, and
    /// `commitDeletions()` drains it for the change our own deletion fires.
    func handleLibraryChange(_ change: PHChange) {
        bufferedChange = change
        applyBufferedLibraryChange()
    }

    func applyBufferedLibraryChange() {
        guard !isCommitting, !isPreparing else { return }
        guard let change = bufferedChange else { return }

        // Consume the buffer whatever happens below. A change that cannot be applied to
        // the fetch result we hold now will never become applicable later, and keeping it
        // would re-run this work on every idle moment from here on.
        bufferedChange = nil

        guard let queue else { return }

        // A nil result means "this change has nothing to do with your fetch". It never
        // means the library emptied, so bailing out is the only correct response.
        guard let details = change.changeDetails(for: queue.fetchResult) else { return }

        // Adopt the new fetch result before anything else reads it. Every index held
        // anywhere is stale from this line onwards, which is why none are reused below.
        queue.adopt(details.fetchResultAfterChanges)

        let anchorID = currentCard?.id

        deck.removeAll()
        cursor = 0
        scanIndex = 0
        excludedCount = 0

        // The undo stack survives deliberately — undo is unlimited within a session — and
        // `undo()` checks the card at `cursor - 1` before stepping, so an entry that no
        // longer lines up with the rebuilt deck still reverses its decision without
        // dragging a stranger's photo onto the screen.
        refillDeck()

        // Re-anchor by identifier, never by the old integer. Everything before the old
        // cursor is in `decidedIDs` and so is skipped by the refill, which is what keeps
        // the rebuilt deck short and puts the user's card near its front. New assets are
        // appended at the end of the fetch result, so they queue up behind the user
        // rather than jumping in front of them.
        if let anchorID, let index = deck.firstIndex(where: { $0.id == anchorID }) {
            cursor = index
        }

        totalInPile = queue.count
        updatePrefetchWindow()
    }

    // MARK: - Deck plumbing

    /// Tops the deck up to `cursor + lookahead` undecided cards by faulting in further
    /// windows from the fetch result. Never materialises the whole result.
    private func refillDeck() {
        guard let queue else { return }

        let total = queue.count
        let target = cursor + DeckTuning.lookahead

        while deck.count < target && scanIndex < total {
            let upper = min(scanIndex + DeckTuning.scanWindow, total)
            let window = queue.assets(in: scanIndex ..< upper)

            for asset in window {
                if decidedIDs.contains(asset.localIdentifier) { continue }

                if !Eligibility.canEnterDeck(asset, includeFavourites: settings.includeFavourites) {
                    excludedCount += 1
                    continue
                }

                deck.append(DeckCard(asset: asset))
            }

            // Advance by the window, not by the number of cards appended: a window that
            // yielded nothing usable must still move the scan on, or this loop spins.
            scanIndex = upper
        }
    }

    /// Keeps the caching manager pointed at the cards around the cursor. The few cards
    /// behind are included because undo puts one of them straight back on screen.
    private func updatePrefetchWindow() {
        let start = clampedCursor

        var upcoming: [PHAsset] = []

        let aheadEnd = min(start + ImageSpec.prefetchAhead, deck.count)
        if start < aheadEnd {
            for card in deck[start ..< aheadEnd] {
                upcoming.append(card.asset)
            }
        }

        let behindStart = max(0, start - ImageSpec.prefetchBehind)
        if behindStart < start {
            for card in deck[behindStart ..< start] {
                upcoming.append(card.asset)
            }
        }

        pipeline.updatePrefetchWindow(upcoming: upcoming)
    }
}
