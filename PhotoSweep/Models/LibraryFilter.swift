import Foundation
import Photos

/// A "pile" of photos to work through.
///
/// Every pile builds a `PHFetchResult` the same way, so the deck, the prefetcher and the
/// change observer behave identically no matter which one the user picked.
enum LibraryFilter: Hashable, Identifiable, Codable {
    case all
    case screenshots
    case videos
    case month(year: Int, month: Int)

    var id: String {
        switch self {
        case .all: return "all"
        case .screenshots: return "screenshots"
        case .videos: return "videos"
        case .month(let year, let month): return "month-\(year)-\(month)"
        }
    }

    var title: String {
        switch self {
        case .all: return Strings.pileAll
        case .screenshots: return Strings.pileScreenshots
        case .videos: return Strings.pileVideos
        case .month(let year, let month): return Formatters.monthYear(year: year, month: month)
        }
    }

    var subtitle: String {
        switch self {
        case .all: return Strings.pileAllHint
        case .screenshots: return Strings.pileScreenshotsHint
        case .videos: return Strings.pileVideosHint
        case .month: return ""
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "photo.on.rectangle.angled"
        case .screenshots: return "iphone.gen3"
        case .videos: return "video"
        case .month: return "calendar"
        }
    }

    /// Videos sort by length rather than date: the longest are the ones worth deciding about.
    var sortsByDuration: Bool {
        if case .videos = self { return true }
        return false
    }

    // MARK: - Fetching

    /// Shared options for every fetch.
    ///
    /// `fetchLimit` is deliberately never set: it breaks incremental change detection and
    /// silently hides the tail of the library. A `PHFetchResult` is lazy, so an unlimited
    /// fetch over 80,000 assets is cheap as long as nobody materialises it.
    func fetchOptions(sortNewestFirst: Bool) -> PHFetchOptions {
        let options = PHFetchOptions()

        if sortsByDuration {
            options.sortDescriptors = [NSSortDescriptor(key: "duration", ascending: false)]
        } else {
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: !sortNewestFirst)]
        }

        // Only assets that actually belong to this device's library can be deleted by a
        // third-party app. Excluding the rest here means the deck never shows a photo that
        // would fail at commit time and take the whole batch down with it.
        options.includeAssetSourceTypes = [.typeUserLibrary]
        options.includeHiddenAssets = false
        options.includeAllBurstAssets = false

        if let predicate = predicate {
            options.predicate = predicate
        }

        return options
    }

    private var predicate: NSPredicate? {
        switch self {
        case .all:
            return nil

        case .screenshots:
            return NSPredicate(
                format: "(mediaSubtypes & %d) != 0",
                PHAssetMediaSubtype.photoScreenshot.rawValue
            )

        case .videos:
            return NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)

        case .month(let year, let month):
            guard let range = LibraryFilter.monthRange(year: year, month: month) else { return nil }
            return NSPredicate(
                format: "creationDate >= %@ AND creationDate < %@",
                range.start as NSDate,
                range.end as NSDate
            )
        }
    }

    func fetch(sortNewestFirst: Bool) -> PHFetchResult<PHAsset> {
        PHAsset.fetchAssets(with: fetchOptions(sortNewestFirst: sortNewestFirst))
    }

    static func monthRange(year: Int, month: Int) -> (start: Date, end: Date)? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1

        guard
            let start = calendar.date(from: components),
            let end = calendar.date(byAdding: .month, value: 1, to: start)
        else { return nil }

        return (start, end)
    }
}

/// One entry in the "By month" list.
struct MonthBucket: Identifiable, Hashable {
    let year: Int
    let month: Int
    let total: Int
    let remaining: Int

    var id: String { "\(year)-\(month)" }
    var filter: LibraryFilter { .month(year: year, month: month) }
    var title: String { Formatters.monthYear(year: year, month: month) }
    var isComplete: Bool { remaining == 0 }
}
