import Photos

/// Turns stored identifiers back into live assets.
///
/// Identifiers are the only thing this app persists, so every screen that works from saved
/// state — the bin, the commit path — comes through here. A photo can be deleted from the
/// Photos app between one launch and the next, so a missing asset is an ordinary fact of
/// life rather than an error worth telling the user about.
enum AssetResolver {

    /// Fetches assets for `ids`, preserving the order of `ids` and silently dropping any
    /// that no longer exist. A result shorter than `ids` is normal, never an error.
    ///
    /// PhotoKit returns its own ordering from `fetchAssets(withLocalIdentifiers:options:)`,
    /// which is why the results are put through a dictionary and re-emitted in the caller's
    /// order: the bin grid must show photos in the order they were binned.
    static func assets(for ids: [String]) -> [PHAsset] {
        guard !ids.isEmpty else { return [] }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)

        var byIdentifier: [String: PHAsset] = [:]
        byIdentifier.reserveCapacity(fetchResult.count)

        // `enumerateObjects` is the only supported way to walk a fetch result: subscripting
        // or mapping it faults every asset in at once, and `objects(at:)` raises an
        // uncatchable exception if the range is ever wrong.
        fetchResult.enumerateObjects { asset, _, _ in
            byIdentifier[asset.localIdentifier] = asset
        }

        return ids.compactMap { byIdentifier[$0] }
    }
}
