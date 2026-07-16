import Foundation
import MakingTracksData
import MakingTracksTiles

public struct PlaceCardModel: Sendable, Equatable {
    public static let maxSnapshotJSONBytes = PlaceRef.maxRawJSONBytes

    public let placeID: String
    public let name: String
    public let category: String
    public let blurb: String?
    public let altNames: [String]
    public let imageURL: URL?
    public let sourceNames: [String]
    public let pinState: PinState

    public static func from(placeRef: PlaceRef, pinState: PinState) -> PlaceCardModel? {
        decode(
            rawJSON: placeRef.rawJSON,
            fallback: Fallback(
                placeID: placeRef.placeID,
                name: placeRef.name,
                category: placeRef.category
            ),
            enforceByteCap: true,
            pinState: pinState
        )
    }

    public static func from(snapshot: PlaceSnapshot, pinState: PinState) -> PlaceCardModel? {
        decode(
            rawJSON: snapshot.snapshotJSON,
            fallback: Fallback(
                placeID: snapshot.placeID,
                name: snapshot.name,
                category: snapshot.category
            ),
            enforceByteCap: true,
            pinState: pinState
        )
    }

    private static func decode(
        rawJSON: String,
        fallback: Fallback,
        enforceByteCap: Bool,
        pinState: PinState
    ) -> PlaceCardModel? {
        let object: [String: Any]
        if enforceByteCap, rawJSON.utf8.count > maxSnapshotJSONBytes {
            object = [:]
        } else {
            object = (try? JSONSerialization.jsonObject(with: Data(rawJSON.utf8))) as? [String: Any] ?? [:]
        }

        let safeName = safeText(object["name"] as? String, max: PlaceRef.maxNameLength)
            ?? safeText(fallback.name, max: PlaceRef.maxNameLength)
            ?? "Unnamed place"
        let safeCategory = safeText(object["category"] as? String, max: PlaceRef.maxCategoryLength)
            ?? safeText(fallback.category, max: PlaceRef.maxCategoryLength)
            ?? "place"
        let blurb = safeText(object["blurb"] as? String, max: 600)
        let altNames = safeTextArray(object["alt_names"] as? [String], maxItems: 8, maxScalars: PlaceRef.maxNameLength)
        let sourceNames = SourceNames.names(from: object["source_refs"] as? [String])

        return PlaceCardModel(
            placeID: fallback.placeID,
            name: safeName,
            category: safeCategory,
            blurb: blurb,
            altNames: altNames,
            imageURL: imageURL(from: object["image_url"]),
            sourceNames: sourceNames,
            pinState: pinState
        )
    }

    private static func safeText(_ text: String?, max: Int) -> String? {
        guard let text,
              (1...max).contains(text.unicodeScalars.count),
              PlaceContentGuards.isSafeText(text)
        else { return nil }
        return text
    }

    private static func safeTextArray(_ values: [String]?, maxItems: Int, maxScalars: Int) -> [String] {
        guard let values, values.count <= maxItems else { return [] }
        return values.compactMap { safeText($0, max: maxScalars) }
    }

    private static func imageURL(from value: Any?) -> URL? {
        guard let raw = value as? String,
              raw.unicodeScalars.count <= 2_048,
              PlaceContentGuards.isSafeURLString(raw),
              let url = URL(string: raw),
              PlaceContentGuards.isAllowedImageURL(url)
        else { return nil }
        return url
    }

}

private struct Fallback {
    var placeID: String
    var name: String
    var category: String
}
