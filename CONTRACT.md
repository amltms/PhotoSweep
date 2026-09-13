# PhotoSweep — implementation contract

**This file is the frozen interface between every file in the app.** If you are implementing a
file, the declarations here are not suggestions: implement exactly these members with exactly
these signatures. Add private members freely. Never add, rename or re-type a declared member,
and never define a type that this document assigns to someone else's file.

Nothing in this project can be compiled before it ships, so correctness-by-construction beats
cleverness everywhere. When in doubt, write the boring version.

---

## 1. Ground rules

- **Swift 5, SwiftUI, iOS 17.0 minimum, portrait only, dark only, no third-party dependencies.**
- Frameworks available: `SwiftUI`, `Photos`, `PhotosUI` (only for `presentLimitedLibraryPicker`),
  `UIKit` (only for haptics, `openSettingsURLString`, and top-view-controller lookup), `Foundation`.
- **Identity is `PHAsset.localIdentifier` (a `String`) and nothing else.** No array index, no
  `PHFetchResult` position and no `PHAsset` reference is ever persisted, put in a `Set`, used as a
  dictionary key, or used as a SwiftUI `id`.
- **A swipe never deletes.** It appends a `String` to an array. `PHAssetChangeRequest.deleteAssets`
  appears exactly once in the codebase, in `DeletionService`.
- Observation: `@Observable` only. **Never** `ObservableObject`, `@Published`, `@StateObject`,
  `@ObservedObject`, `@EnvironmentObject`, or Combine. Never mix the two systems.
- The model is passed **down** as a plain `let model: AppModel` property. **Never**
  `@Environment(AppModel.self)` — a missing injection there is a runtime crash nobody can find
  without running the app.
- British English in every user-facing string, and every user-facing string comes from `Strings`.
- Colours come from `Theme`. Never write a literal `Color(red:...)` in a view, never write a
  `Color(hex:)` helper.

### Banned APIs (each has a silent or fatal failure mode)

| Banned | Use instead |
|---|---|
| `PHPhotoLibrary.authorizationStatus()` / `requestAuthorization(_:)` (no-argument forms) | the `(for: .readWrite)` variants — the legacy forms report `.limited` as `.authorized` |
| `PHAccessLevel.addOnly` | `.readWrite` |
| `PHImageRequestOptions.deliveryMode = .opportunistic` | `.highQualityFormat` — opportunistic calls the handler twice |
| `PHImageRequestOptions.isSynchronous = true` | async only; `true` watchdog-kills the app on an iCloud fetch |
| `PHImageManagerMaximumSize` | `ImageSpec.card` |
| `resizeMode = .fast` for card images | `.exact` |
| `PHFetchOptions.fetchLimit` | no limit; `PHFetchResult` is lazy |
| `fetchResult.objects(at: IndexSet(0..<count))`, `map` over a fetch result, iterating one | `AssetQueue.assets(in:)` with a clamped window |
| `PHAssetResource.value(forKey: "fileSize")` | nothing — the app never shows a byte figure |
| `.smartAlbumDuplicates`, `.smartAlbumRecentlyDeleted` | not available to third-party apps |
| `@GestureState` for the card offset | plain `@State` — `@GestureState` auto-resets before `onEnded` lands |
| `withAnimation(_:completion:)` as the trigger for a model mutation | mutate synchronously; animation is decorative only |
| `.animation(_:)` single-argument, `.animation(nil)` | `withAnimation { }` |
| `.onChange(of:perform:)` single-parameter | the two-parameter iOS 17 form `.onChange(of: x) { old, new in }` |
| `SwiftData`, Core Data, `UserDefaults`/`@AppStorage` for the identifier set | `ReviewStateStore` |
| `UIScreen.main` | `GeometryReader`, `@Environment(\.displayScale)` |
| `UndoManager` | the plain `undoStack` array |
| `NavigationStack` push or any `ScrollView` parent **for the deck** | `.fullScreenCover` |
| `Task.detached`, custom global actors, `nonisolated(unsafe)`, `MainActor.assumeIsolated`, `@unchecked Sendable` around PhotoKit types | keep PhotoKit objects on `@MainActor`; move `String`s across isolation instead |
| `applicationWillTerminate`, `.onDisappear` as the save hook | save forward: debounced, plus on `scenePhase` leaving `.active` |
| anything iOS 18+ (`@Entry`, `@Previewable`, `MeshGradient`, new `Tab` API, `.symbolEffect(.wiggle)`) | iOS 17 equivalents |

### PhotoKit rules that must be obeyed literally

1. `requestImage`'s result handler **may be called on a background queue**. Hop with
   `DispatchQueue.main.async` before touching any state.
2. Guard every delivery against staleness: capture the wanted `localIdentifier` before the
   request, and drop the result if the loader has since moved on.
3. Assign the `PHImageRequestID` **after** `requestImage` returns, never from inside the handler —
   a cached image can run the handler synchronously before the call returns.
4. `info?[PHImageCancelledKey] as? Bool == true` means cancelled: do not treat it as a failure.
5. Prefetch parameters must be **byte-identical** to request parameters, from the same
   `PHCachingImageManager` instance, or the cache silently never hits. Both read `ImageSpec`.
6. `PHFetchResult.objects(at:)` raises an **uncatchable** `NSRangeException` out of bounds. Read
   `count` and clamp in the same synchronous block as the call.
7. `photoLibraryDidChange(_:)` arrives on an arbitrary queue. Declare the witness `nonisolated`
   and hop with `DispatchQueue.main.async` (not `Task {}`, which adds a Sendable warning for
   `PHChange`).
8. `changeDetails(for:)` returning `nil` means "this change does not affect you" — return; it
   never means "everything went away".
9. `deleteAssets` is atomic: one undeletable asset fails the whole batch. Filter with
   `asset.canPerform(.delete)` immediately before the call, not only at fetch time.
10. The user cancelling the system deletion alert surfaces as an error with
    `(error as NSError).domain == PHPhotosErrorDomain` and code `3072`
    (`PHPhotosError.userCancelled`). That is **not** a failure — report `.cancelledByUser`.
11. Your own `performChanges` fires `photoLibraryDidChange` too. Removal from the model is always
    by identifier against a `Set`, so a repeated removal is a harmless no-op.

---

## 2. Files that already exist — do not modify, do not redeclare

Read them before you write anything; they are the shared vocabulary.

| File | Provides |
|---|---|
| `PhotoSweep/Core/Theme.swift` | `Theme` (palette, metrics), `ScreenBackground`, `.panel()`, `PrimaryButtonStyle` |
| `PhotoSweep/Core/Strings.swift` | `Strings` — every user-facing string |
| `PhotoSweep/Core/Formatters.swift` | `Formatters` — dates, durations, counts, pixel sizes |
| `PhotoSweep/Core/Haptics.swift` | `Haptics.keep()/bin()/undo()/crossedThreshold()/success()/warning()/failure()/prepare()`, `Haptics.isEnabled` |
| `PhotoSweep/Models/Decision.swift` | `Decision`, `SwipeMapping`, `SwipeMetrics`, `UndoEntry`, `CommitOutcome` |
| `PhotoSweep/Models/DeckCard.swift` | `DeckCard` |
| `PhotoSweep/Models/LibraryFilter.swift` | `LibraryFilter`, `MonthBucket` |
| `PhotoSweep/Models/ReviewState.swift` | `ReviewState`, `DeletionReceipt` |

---

## 3. The frozen surface

### 3.1 `PhotoSweep/Services/PhotoAuthoriser.swift`

```swift
@MainActor
enum PhotoAuthoriser {
    /// Always the `(for: .readWrite)` variant.
    static var status: PHAuthorizationStatus { get }
    static func request() async -> PHAuthorizationStatus
    /// How many assets a `.limited` user has actually shared. 0 when not limited.
    static func sharedAssetCount() -> Int
    static func openSystemSettings()
    /// Presents the system "select more photos" sheet from the top view controller.
    static func presentLimitedPicker()
    /// Stable per-install identifier for the library, for `ReviewState.fingerprint`.
    static func libraryFingerprint() -> String
}
```

`libraryFingerprint()` returns `"\(UIDevice.current.identifierForVendor?.uuidString ?? "unknown")-v1"`.

### 3.2 `PhotoSweep/Services/Eligibility.swift`

```swift
enum Eligibility {
    /// May this asset be shown in the deck at all?
    /// Excludes favourites (unless the user opted in), hidden assets, anything not in the
    /// user's own library, and anything the app is not permitted to delete.
    static func canEnterDeck(_ asset: PHAsset, includeFavourites: Bool) -> Bool
    /// Re-checked immediately before every commit.
    static func canDelete(_ asset: PHAsset) -> Bool
}
```

### 3.3 `PhotoSweep/Services/AssetResolver.swift`

```swift
enum AssetResolver {
    /// Fetches assets for `ids`, preserving the order of `ids` and silently dropping any that
    /// no longer exist. A result shorter than `ids` is normal, never an error.
    static func assets(for ids: [String]) -> [PHAsset]
}
```

### 3.4 `PhotoSweep/Services/AssetQueue.swift`

```swift
@MainActor
final class AssetQueue {
    private(set) var fetchResult: PHFetchResult<PHAsset>
    var count: Int { get }
    init(fetchResult: PHFetchResult<PHAsset>)
    /// `nil` for any out-of-range index. Never traps.
    func asset(at index: Int) -> PHAsset?
    /// Faults in one clamped window with a single `objects(at:)` call. Returns `[]` if the
    /// clamped range is empty.
    func assets(in range: Range<Int>) -> [PHAsset]
    func adopt(_ newResult: PHFetchResult<PHAsset>)
    /// Searches outwards from `hint` before falling back to a full scan, so re-finding the
    /// user's place after a library change is cheap in the common case.
    func firstIndex(ofLocalIdentifier id: String, near hint: Int, searchRadius: Int = 200) -> Int?
}
```

### 3.5 `PhotoSweep/Services/LibraryObserver.swift`

```swift
/// A retained `NSObject` — a SwiftUI `View` struct cannot conform to this protocol.
final class LibraryObserver: NSObject, PHPhotoLibraryChangeObserver {
    /// Called on the main queue.
    var onChange: ((PHChange) -> Void)?
    /// Registers with `PHPhotoLibrary.shared()`.
    func start()
    /// Safe to call twice.
    func stop()
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange)
}
```

`stop()` must also be called from `deinit`. The library holds the observer unowned.

### 3.6 `PhotoSweep/Services/ImagePipeline.swift`

```swift
enum ImageSpec {
    static let card: CGSize            // CGSize(width: 800, height: 1400) — pixels, fixed
    static let thumbnail: CGSize       // CGSize(width: 300, height: 300)
    static let cardOptions: PHImageRequestOptions
    static let thumbnailOptions: PHImageRequestOptions
    static let prefetchAhead: Int      // 8
    static let prefetchBehind: Int     // 2
}

enum ImageLoadResult {
    case image(UIImage)
    case failed
    case cancelled
}

@MainActor
final class ImagePipeline {
    init()
    @discardableResult
    func requestCardImage(
        for asset: PHAsset,
        progress: @escaping (Double) -> Void,
        completion: @escaping (ImageLoadResult) -> Void
    ) -> PHImageRequestID
    @discardableResult
    func requestThumbnail(for asset: PHAsset, completion: @escaping (UIImage?) -> Void) -> PHImageRequestID
    func cancel(_ id: PHImageRequestID)
    /// Diffs against the previous window and issues start/stopCachingImages accordingly.
    func updatePrefetchWindow(upcoming: [PHAsset])
    func stopAllPrefetching()
}

/// One per card view, held as `@State`.
@MainActor
@Observable
final class CardImageLoader {
    private(set) var image: UIImage?
    private(set) var isLoading: Bool
    private(set) var isDownloadingFromCloud: Bool
    private(set) var downloadProgress: Double
    private(set) var hasFailed: Bool
    var hasImage: Bool { get }
    /// Idempotent: calling it again for the same card while loading does nothing.
    func load(card: DeckCard, using pipeline: ImagePipeline)
    func retry(card: DeckCard, using pipeline: ImagePipeline)
    func cancel()
}
```

`cardOptions`: `deliveryMode = .highQualityFormat`, `resizeMode = .exact`,
`isNetworkAccessAllowed = true`, `isSynchronous = false`, `version = .current`.
`thumbnailOptions`: same but `resizeMode = .fast` is acceptable for thumbnails.

### 3.7 `PhotoSweep/Services/DeletionService.swift`

```swift
@MainActor
enum DeletionService {
    /// The only place in this app that deletes anything.
    /// Re-resolves `ids`, drops anything that has vanished or cannot be deleted, and commits
    /// the remainder in a single `performChanges`.
    static func delete(ids: [String]) async -> CommitOutcome
}
```

### 3.8 `PhotoSweep/Services/ReviewStateStore.swift`

```swift
@MainActor
final class ReviewStateStore {
    private(set) var state: ReviewState
    /// Set when a saved file existed but could not be read. Surfaced once, then cleared.
    private(set) var loadError: String?
    init()
    /// Reads the file. On a fingerprint mismatch or a decode failure, renames the bad file to
    /// `review-state.bak` and starts from `ReviewState()`.
    func load(fingerprint: String)
    /// Applies `change` and schedules a debounced (~1s) atomic write.
    func mutate(_ change: (inout ReviewState) -> Void)
    /// Writes immediately if dirty. Called on `scenePhase` leaving `.active`.
    func flush()
    /// Clears progress but keeps receipts and lifetime counters.
    func resetProgress()
    func clearLoadError()
}
```

Storage: `~/Library/Application Support/PhotoSweep/review-state.json`. Create the directory with
`createDirectory(at:withIntermediateDirectories: true)` — it does not exist by default. Write with
`Data.write(to:options:[.atomic, .completeFileProtectionUntilFirstUserAuthentication])`. Set
`isExcludedFromBackup = true`. Never `try!`, never `fatalError` on a persistence path.

### 3.9 `PhotoSweep/Models/AppSettings.swift`

```swift
@MainActor
@Observable
final class AppSettings {
    var invertSwipeDirection: Bool   // default false  → right bins, as specified
    var hapticsEnabled: Bool         // default true
    var confirmBeforeCommit: Bool    // default true
    var sortNewestFirst: Bool        // default true
    var includeFavourites: Bool      // default false
    var mapping: SwipeMapping { get }
    init()
}
```

Backed by `UserDefaults.standard` scalars written in `didSet`. Setting `hapticsEnabled` also
assigns `Haptics.isEnabled`. Defaults registered with `UserDefaults.register(defaults:)` so an
absent key reads as the documented default rather than `false`.

### 3.10 `PhotoSweep/Models/AppModel.swift` — the hub

Exactly these members. Everything else is private.

```swift
@MainActor
@Observable
final class AppModel {

    // Collaborators — constructed once, never replaced.
    let settings: AppSettings
    let store: ReviewStateStore
    let pipeline: ImagePipeline

    // Passed as nil rather than as default expressions: a default argument is evaluated
    // at the call site in a NONISOLATED context, so `= AppSettings()` on a @MainActor
    // type is an isolation error. They are built inside the body instead.
    init(settings: AppSettings? = nil,
         store: ReviewStateStore? = nil,
         pipeline: ImagePipeline? = nil)

    // Authorisation
    private(set) var authStatus: PHAuthorizationStatus
    private(set) var sharedAssetCount: Int          // meaningful only when .limited

    // Onboarding
    var hasCompletedOnboarding: Bool { get }
    var needsRehearsal: Bool { get }
    func completeOnboarding()
    func completeRehearsal()

    // Session
    private(set) var filter: LibraryFilter
    private(set) var deck: [DeckCard]               // append-only within a session
    private(set) var cursor: Int                    // index into `deck`
    private(set) var isPreparing: Bool
    private(set) var totalInPile: Int
    private(set) var excludedCount: Int
    private(set) var sessionError: String?

    // Decisions
    private(set) var decidedIDs: Set<String>
    private(set) var pendingDeletionIDs: [String]
    private(set) var undoStack: [UndoEntry]
    private(set) var keptThisSession: Int
    private(set) var binnedThisSession: Int

    // Commit
    private(set) var isCommitting: Bool
    private(set) var lastOutcome: CommitOutcome?

    // Derived
    var currentCard: DeckCard? { get }
    var visibleCards: [DeckCard] { get }            // up to 3; index 0 is the top card
    func depth(of card: DeckCard) -> Int            // 0 for the top card
    var canUndo: Bool { get }
    var pendingCount: Int { get }
    var reviewedThisSession: Int { get }
    var isPileFinished: Bool { get }
    var progress: Double { get }                    // 0...1
    var mapping: SwipeMapping { get }
    var lifetimeReviewed: Int { get }
    var lifetimeBinned: Int { get }
    var receipts: [DeletionReceipt] { get }

    // Entry points — the ONLY mutators. Gestures, buttons and accessibility
    // actions all funnel through these and nothing else.
    func bootstrap() async
    func requestAuthorisation() async
    func refreshAuthorisation() async
    func startSession(filter: LibraryFilter) async
    func endSession()
    func decide(_ decision: Decision, expecting id: String)
    func undo()
    func restore(id: String)
    func keepAllInBin()
    func commitDeletions() async
    func clearBin()
    func monthBuckets() async -> [MonthBucket]
    func flush()
    func resetHistory()
    func handleLibraryChange(_ change: PHChange)
    func applyBufferedLibraryChange()
}
```

Behavioural requirements:

- `decide(_:expecting:)` opens with
  `guard !isCommitting, let card = currentCard, card.id == id else { return }` so a duplicate call
  from a double-fired gesture is a harmless no-op.
- `decide` appends to `undoStack`, inserts into `decidedIDs`, appends to `pendingDeletionIDs` on
  `.bin`, increments the session counters, advances `cursor` by 1, refills the deck, updates the
  prefetch window, fires the haptic, and asks the store to save. It never touches PhotoKit.
- `undo()` pops the stack, removes the id from `decidedIDs` and from `pendingDeletionIDs`, steps
  `cursor` back by one, and decrements the matching counter. Unlimited within a session.
- The deck is **append-only**: `cursor` advances over it, entries are never removed, so SwiftUI
  identity is stable. Refill keeps at least `cursor + 14` entries by pulling further windows from
  `AssetQueue`, skipping anything in `decidedIDs` or failing `Eligibility.canEnterDeck`.
  `excludedCount` counts what was skipped for ineligibility.
- `commitDeletions()` sets `isCommitting`, calls `DeletionService.delete(ids:)`, and **clears the
  bin only inside the `.deleted` branch**. On success it appends a `DeletionReceipt` and bumps
  `lifetimeDeleted`. On `.cancelledByUser` the bin survives untouched.
- `handleLibraryChange` buffers; `applyBufferedLibraryChange` applies it only when
  `!isCommitting` and the deck is idle. Adopt `fetchResultAfterChanges` first, always. Re-anchor
  the cursor by the current card's `localIdentifier`, never by the old integer. New assets go to
  the end, never in front of the user.
- `progress` is `reviewed / max(1, totalInPile)`, clamped to `0...1`.

### 3.11 `PhotoSweep/Views/Components/` — shared components

One file each, exactly these:

```swift
struct SweepProgressBar: View { init(progress: Double) }
struct EmptyStateView: View {
    init(systemImage: String, title: String, message: String,
         actionTitle: String? = nil, action: (() -> Void)? = nil)
}
struct SwipeStamp: View { init(decision: Decision, strength: Double) }   // strength 0...1
struct CloudDownloadBadge: View { init(progress: Double) }
struct InfoBanner: View { init(systemImage: String, text: String, tint: Color = Theme.yellow) }
struct PillLabel: View { init(systemImage: String?, text: String) }
struct SectionCard<Content: View>: View {
    init(title: String?, @ViewBuilder content: () -> Content)
}
```

### 3.12 Screens

```swift
// App/PhotoSweepApp.swift
@main struct PhotoSweepApp: App          // owns AppModel as @State, owns LibraryObserver,
                                         // wires scenePhase -> model.flush()

// App/RootView.swift
struct RootView: View { let model: AppModel }

// Views/OnboardingView.swift
struct OnboardingView: View { let model: AppModel; var onFinished: () -> Void }

// Views/RehearsalView.swift
struct RehearsalView: View { let model: AppModel; var onFinished: () -> Void }

// Views/PermissionGateView.swift
struct PermissionGateView: View { let model: AppModel }

// Views/HomeView.swift
struct HomeView: View { let model: AppModel }

// Views/DeckScreen.swift          — the fullScreenCover container
struct DeckScreen: View { let model: AppModel; var onClose: () -> Void }

// Views/SwipeDeckView.swift       — the card stack and the gesture
struct SwipeDeckView: View { let model: AppModel; var onPeek: (DeckCard) -> Void }

// Views/PhotoCardView.swift
struct PhotoCardView: View {
    let model: AppModel
    let card: DeckCard
    let depth: Int
    let dragTranslation: CGSize      // .zero for cards below the top
    let cardWidth: CGFloat
}

// Views/DeckControlsView.swift
struct DeckControlsView: View { let model: AppModel; var onOpenBin: () -> Void }

// Views/PeekView.swift
struct PeekView: View { let model: AppModel; let card: DeckCard; var onClose: () -> Void }

// Views/BinView.swift
struct BinView: View { let model: AppModel; var onClose: () -> Void }

// Views/SummaryView.swift
struct SummaryView: View {
    let model: AppModel
    var onReviewBin: () -> Void
    var onKeepSweeping: () -> Void
    var onFinish: () -> Void
}

// Views/SettingsView.swift
struct SettingsView: View { let model: AppModel; var onClose: () -> Void }
```

### 3.13 Navigation shape

- `RootView` switches on `model.authStatus` and the onboarding flags. It presents `HomeView` when
  authorised or limited.
- `HomeView` owns `@State private var isSweeping = false` and presents `DeckScreen` with
  `.fullScreenCover(isPresented:)`. **Never** a `NavigationStack` push, because UIKit's interactive
  pop gesture owns the left screen edge and pulls rightwards — exactly the bin direction.
- `DeckScreen` owns the bin sheet, the peek overlay and the summary, all as `.sheet` /
  `.fullScreenCover` from inside the cover.
- `HomeView` uses a `NavigationStack` for Settings only.
