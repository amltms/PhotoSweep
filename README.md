# PhotoSweep

A native iOS app for tidying up your photo library by swiping.

**Swipe right to bin a photo. Swipe left to keep it.**

That is deliberately the opposite way round to dating apps, so the app makes a point of teaching
it before you touch a real photo — a briefing you cannot skip, and a two-card practice round.

---

## The one thing worth knowing

**A swipe never deletes anything.**

Swiping right adds a photo to a list. Nothing is removed from your library until you open that
list, look through it, and press the delete button yourself. Then iOS asks you to confirm as well.

Photos you confirm go to **Recently Deleted** in the Photos app, where they stay for about 30 days.
No third-party app is allowed to empty that album, so nothing PhotoSweep does is irreversible, and
no space is actually freed until you empty it yourself.

---

## Building it

Requires **Xcode 16 or later** and **iOS 17.0+** on the device or simulator.

```bash
open PhotoSweep.xcodeproj
```

Then set your own signing team (target *PhotoSweep* ▸ Signing & Capabilities ▸ Team) and run.
The bundle identifier defaults to `com.example.PhotoSweep`; change it to something of your own
before you put it on a device.

There are **no dependencies** — no Swift Package Manager, no CocoaPods, no Carthage, nothing to
fetch. It is one app target and about thirty Swift files.

### If the project file will not open

`PhotoSweep.xcodeproj` uses Xcode 16's file-system-synchronised groups, so the source folder is
picked up automatically and the project file stays small. On an older Xcode, regenerate it instead:

```bash
brew install xcodegen
rm -rf PhotoSweep.xcodeproj
xcodegen generate
```

`project.yml` describes the same target.

### If you would rather start from a fresh Xcode project

Create a new iOS App (SwiftUI, no tests), delete its `ContentView.swift` and `*App.swift`, drag
the `PhotoSweep/` folder in, and set these in Build Settings / Info:

| Setting | Value |
|---|---|
| Deployment target | iOS 17.0 |
| `NSPhotoLibraryUsageDescription` | *(see `Info.plist` in this repo)* |
| `PHPhotoLibraryPreventAutomaticLimitedAccessAlert` | `YES` |
| `UIUserInterfaceStyle` | `Dark` |
| Supported orientations (iPhone) | Portrait only |

Do **not** add `NSPhotoLibraryAddUsageDescription`. The app never writes to your library, and an
unused purpose string is a mismatch Apple's reviewers ask about.

---

## What it does

**The sweep**

- One photo at a time, as a card stack, with the next few prefetched so swiping never stalls.
- Live feedback as you drag: a green **KEEP** stamp from one side, a red **BIN** stamp from the
  other, the card tilting with your finger.
- **Keep**, **Bin** and **Undo** buttons under the deck, mirroring the swipe directions. The app is
  fully usable without swiping at all — which also makes it usable with VoiceOver, since VoiceOver
  swallows custom drag gestures.
- **Undo** goes back as far as you like within a session.
- Press and hold a card to see the photo full size.

**Choosing what to work through**

- Everything, newest first.
- Screenshots — usually the quickest win.
- Videos, longest first.
- Month by month.

**Getting through a big library**

- It remembers every photo you have decided about, so you are never shown the same one twice, and
  you resume exactly where you left off.
- It never shows a photo it would not be able to delete, so a single awkward asset can never fail
  the whole batch at the end.
- Favourites are excluded by default. You can switch that on in Settings.

**The bin**

- A grid of everything you have marked. Tap any photo to take it back out.
- **Keep them all** empties the bin without deleting anything.
- One red button does the deletion, in a single batch, with a plain-English summary first.
- A deletion history in Settings records what was deleted and when.

**Settings**

- Swap the swipe directions (this re-runs the practice round, so muscle memory cannot catch you out).
- Haptics, confirmation prompt, sort order, whether favourites are included.
- Start again from scratch — forgets your progress, touches no photos.

---

## What it deliberately does not do

These were considered and cut, on purpose:

- **No "you freed 2.3 GB" figure.** The only ways to get a real per-photo size are an undocumented
  private API or downloading the iCloud original. An estimate would be a confident-looking number
  that is wrong, and the space is not freed at that moment anyway.
- **No duplicate or similar-photo detection.** Doing it properly with the Vision framework means
  tens of minutes of sustained compute on a large library, forced iCloud downloads, and thermal
  throttling — and a wrong grouping silently pre-marks photos you wanted.
- **No emptying of Recently Deleted.** No app is allowed to, and claiming otherwise would be a lie.
- **No network code at all.** No accounts, no analytics, no uploads. There is nothing in this app
  that can talk to a server.
- **No notifications or streaks.** The core loop should earn the next session on its own.

---

## How it is put together

```
PhotoSweep/
├── App/           PhotoSweepApp, RootView
├── Core/          Theme, Strings, Formatters, Haptics
├── Models/        AppModel (the hub), AppSettings, Decision, DeckCard,
│                  LibraryFilter, ReviewState
├── Services/      PhotoAuthoriser, Eligibility, AssetQueue, AssetResolver,
│                  ImagePipeline, LibraryObserver, DeletionService, ReviewStateStore
└── Views/         Onboarding, Rehearsal, PermissionGate, Home, Deck, Card,
                   Controls, Peek, Bin, Summary, Settings, Components/
```

A few rules hold the whole thing together, and `CONTRACT.md` spells them out in full:

- **One mutable object.** `AppModel` is `@MainActor @Observable` and owns all state. Gestures,
  buttons and VoiceOver actions all funnel through the same handful of methods, so there is one
  code path per decision rather than three that can drift apart.
- **One currency of identity.** `PHAsset.localIdentifier`, a `String`. No array index, no fetch
  position and no `PHAsset` is ever persisted or used as a key. Assets are re-resolved from
  identifiers at the moment of use, and again immediately before deletion.
- **One deletion site.** `PHAssetChangeRequest.deleteAssets` appears once, in `DeletionService`.
- **One place that knows what "right" means.** `SwipeMapping`. Nothing else compares a horizontal
  translation against zero, which is why inverting the directions cannot half-apply.
- **The deck is append-only.** A cursor advances over it; entries are never removed. That keeps
  SwiftUI's view identity stable while cards animate, and makes undo a decrement.
- **Progress is saved forwards**, debounced and again whenever the app leaves the foreground —
  never in a termination hook, which is not called on a force-quit or a crash.

Your progress lives in a single JSON file in Application Support, written atomically and excluded
from backup (the identifiers inside it are device-local and would be meaningless after a restore
onto another device).

---

## Status

**Not yet compiled or run.** It was written on a Windows machine with no Apple toolchain, so no
build has ever happened. Expect to fix a handful of small build errors on first open.

What *was* done instead, since the compiler was not available: the PhotoKit and SwiftUI-gesture
failure modes were catalogued up front and written into `CONTRACT.md` as rules before any code
existed; every file was then reviewed in isolation, reviewed again across file boundaries by
seven independent lenses, had each finding adversarially re-checked against the source before
being acted on, and was re-read once more after the fixes landed. That caught a number of real
defects — an `OptionSet` compared with `==` that would have silently shrunk the deck, a
double-applied rotation, views observing a non-`@Observable` store, a reset that emptied the bin
while the confirmation promised it would not.

The parts most worth trusting are the ones that were worth getting right up front: the staging
model, the PhotoKit usage, and the gesture handling. The parts most likely to need a nudge are
layout and animation timing, which cannot be judged without running them.

Test it on a real device with a real library before trusting it with anything. The staging design
means the worst a bug can do is show you the wrong photo — the only code that deletes is behind a
button you press yourself, and behind iOS's own confirmation after that.
