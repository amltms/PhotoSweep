import Foundation
import Photos

/// One card in the deck.
///
/// The interesting properties are captured once, at the moment the `PHAsset` is faulted
/// in, so that drawing a card never touches PhotoKit again. `PHAsset` is held only so the
/// image pipeline can request pixels; it is never used as identity, never stored, never
/// put in a `Set` or used as a dictionary key, and never persisted.
struct DeckCard: Identifiable, Equatable {

    /// `PHAsset.localIdentifier`. The only identity this app recognises.
    let id: String

    let asset: PHAsset
    let creationDate: Date?
    let isVideo: Bool
    let duration: TimeInterval
    let pixelWidth: Int
    let pixelHeight: Int
    let isFavourite: Bool

    init(asset: PHAsset) {
        self.id = asset.localIdentifier
        self.asset = asset
        self.creationDate = asset.creationDate
        self.isVideo = asset.mediaType == .video
        self.duration = asset.duration
        self.pixelWidth = asset.pixelWidth
        self.pixelHeight = asset.pixelHeight
        self.isFavourite = asset.isFavorite
    }

    /// Two cards are the same card when they are the same asset. `PHAsset` does not
    /// implement a useful `==`, so identity is compared explicitly.
    static func == (lhs: DeckCard, rhs: DeckCard) -> Bool {
        lhs.id == rhs.id
    }

    var aspectRatio: CGFloat {
        guard pixelWidth > 0, pixelHeight > 0 else { return 3.0 / 4.0 }
        return CGFloat(pixelWidth) / CGFloat(pixelHeight)
    }

    var accessibilityLabel: String {
        Strings.a11yCardLabel(
            date: Formatters.accessibleDate(creationDate),
            isVideo: isVideo,
            duration: isVideo ? Formatters.duration(duration) : nil
        )
    }
}
