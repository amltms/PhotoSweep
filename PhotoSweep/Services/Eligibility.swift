import Photos

/// The single rule about which assets this app is allowed to touch.
///
/// `PHAssetChangeRequest.deleteAssets` is atomic: one undeletable asset fails the entire
/// batch, so a photo that could never be deleted must never reach the deck in the first
/// place. Filtering here — rather than apologising at commit time — is what stops a single
/// iTunes-synced or shared-album photo taking a hundred good decisions down with it.
enum Eligibility {

    /// May this asset be shown in the deck at all?
    ///
    /// Excludes favourites (unless the user opted in), hidden assets, anything not in the
    /// user's own library, and anything the app is not permitted to delete.
    static func canEnterDeck(_ asset: PHAsset, includeFavourites: Bool) -> Bool {
        // A starred photo is the user saying "this one matters"; binning it by accident is
        // the worst thing this app could do, so it is opt-in only.
        if asset.isFavorite && !includeFavourites { return false }

        // Hidden assets are hidden for a reason, and showing one in a full-screen card is
        // a privacy failure regardless of what the user then decides.
        if asset.isHidden { return false }

        // Shared-album and computer-synced assets cannot be deleted by a third-party app.
        //
        // `PHAssetSourceType` is an NS_OPTIONS bitfield, so it arrives in Swift as an
        // `OptionSet`, not a plain enum. `!= .typeUserLibrary` compiles but asks the wrong
        // question: it rejects any asset that carries a second bit alongside the one that
        // matters. Membership is the only correct test.
        if !asset.sourceType.contains(.typeUserLibrary) { return false }

        if !asset.canPerform(.delete) { return false }

        return true
    }

    /// Re-checked immediately before every commit.
    ///
    /// Permission can change between the swipe and the delete button — an asset can be
    /// edited, shared, or have its source change — so the fetch-time answer is not trusted.
    static func canDelete(_ asset: PHAsset) -> Bool {
        asset.canPerform(.delete) && asset.sourceType.contains(.typeUserLibrary)
    }
}
