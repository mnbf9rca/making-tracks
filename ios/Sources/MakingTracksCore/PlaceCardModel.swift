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
    public let photo: PlaceCardPhoto?
    public let listNames: [String]
    public let sourceNames: [String]
    public let sourceArticleLink: SourceArticleLink?
    public let pinState: PinState

    public init(
        placeID: String,
        name: String,
        category: String,
        blurb: String?,
        altNames: [String],
        photo: PlaceCardPhoto?,
        listNames: [String],
        sourceNames: [String],
        sourceArticleLink: SourceArticleLink?,
        pinState: PinState
    ) {
        self.placeID = placeID
        self.name = name
        self.category = category
        self.blurb = blurb
        self.altNames = altNames
        self.photo = photo
        self.listNames = listNames
        self.sourceNames = sourceNames
        self.sourceArticleLink = sourceArticleLink
        self.pinState = pinState
    }

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
            object = strictPlaceObject(rawJSON, matching: fallback.placeID) ?? [:]
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
        let sourceArticleLink = SourceArticleLinks.link(
            wikipediaTitle: object["wikipedia_title"] as? String,
            sourceRefs: object["source_refs"] as? [String]
        )

        return PlaceCardModel(
            placeID: fallback.placeID,
            name: safeName,
            category: safeCategory,
            blurb: blurb,
            altNames: altNames,
            photo: nil,
            listNames: [],
            sourceNames: sourceNames,
            sourceArticleLink: sourceArticleLink,
            pinState: pinState
        )
    }

    public func enriching(photo: PlaceCardPhoto? = nil, listNames: [String]? = nil) -> PlaceCardModel {
        PlaceCardModel(
            placeID: placeID,
            name: name,
            category: category,
            blurb: blurb,
            altNames: altNames,
            photo: photo ?? self.photo,
            listNames: listNames ?? self.listNames,
            sourceNames: sourceNames,
            sourceArticleLink: sourceArticleLink,
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

    private static func strictPlaceObject(_ rawJSON: String, matching placeID: String) -> [String: Any]? {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(rawJSON.utf8))) as? [String: Any],
              Set(object.keys).isSubset(of: PlaceContentGuards.allowedPlaceKeys),
              object["place_id"] as? String == placeID
        else { return nil }
        return object
    }

    private static func safeTextArray(_ values: [String]?, maxItems: Int, maxScalars: Int) -> [String] {
        guard let values, values.count <= maxItems else { return [] }
        return values.compactMap { safeText($0, max: maxScalars) }
    }

}

public struct PlaceCardPhoto: Sendable, Equatable {
    public let image: PlaceImage?
    public let thumbURL: URL?
    public let thumbSHA256: String?
    public let bytes: Int?
    public let width: Int?
    public let height: Int?
    public let accessibilityLabel: String
    public let attribution: String

    public init(accessibilityLabel: String, attribution: String) {
        self.image = nil
        self.thumbURL = nil
        self.thumbSHA256 = nil
        self.bytes = nil
        self.width = nil
        self.height = nil
        self.accessibilityLabel = accessibilityLabel
        self.attribution = attribution
    }

    public init(placeName: String, image: PlaceImage) {
        self.image = image
        self.thumbURL = image.thumbURL
        self.thumbSHA256 = image.thumbSHA256
        self.bytes = image.bytes
        self.width = image.width
        self.height = image.height
        self.accessibilityLabel = "Photo of \(placeName)"
        self.attribution = image.attribution.displayText
    }
}

public struct SourceArticleLink: Sendable, Equatable {
    public let label: String
    public let sourceName: String
    public let url: URL
}

private struct Fallback {
    var placeID: String
    var name: String
    var category: String
}
