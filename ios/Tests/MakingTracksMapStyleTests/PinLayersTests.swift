import XCTest
import MakingTracksData
@testable import MakingTracksMapStyle

final class PinLayersTests: XCTestCase {
    private let matrix: [PinState] = [
        PinState(saved: false, visit: .none),
        PinState(saved: true, visit: .none),
        PinState(saved: false, visit: .visited),
        PinState(saved: true, visit: .visited),
        PinState(saved: false, visit: .loved),
        PinState(saved: true, visit: .loved),
    ]

    func testGeneratedExpressionsMatchPinAppearanceForEveryCell() {
        for state in matrix {
            let want = pinAppearance(state)
            let props = FeatureEncoding.featureProperties(state)
            guard case let .double(opacity) = Expression.evaluate(PinLayers.fadeOpacityExpression(), props) else {
                return XCTFail("opacity not a number for \(state)")
            }
            XCTAssertEqual(opacity, want.opacity, accuracy: 1e-9, "opacity \(state)")
            XCTAssertEqual(Expression.evaluate(PinLayers.bookmarkFilter(), props), .bool(want.showBookmarkBadge), "bookmark \(state)")
            XCTAssertEqual(Expression.evaluate(PinLayers.heartFilter(), props), .bool(want.showHeartBadge), "heart \(state)")
        }
    }

    func testPinSubstrateIsShapeSourcePlusStyleLayersNotAnnotations() {
        let layers = PinLayers.pinLayers()
        let circle = layer(id: "pins-circle", in: layers)
        let icon = layer(id: "pins-icon", in: layers)
        let bookmark = layer(id: "pins-bookmark", in: layers)
        let heart = layer(id: "pins-heart", in: layers)

        XCTAssertEqual(circle?["type"], .string("circle"), "circle pin layer")
        XCTAssertEqual(icon?["type"], .string("symbol"), "category icon symbol layer")
        XCTAssertEqual(bookmark?["type"], .string("symbol"), "bookmark badge symbol layer")
        XCTAssertEqual(heart?["type"], .string("symbol"), "heart badge symbol layer")
        XCTAssertEqual(layers.count, 4, "circle + category icon + bookmark/heart badges")
        for layer in [circle, icon, bookmark, heart] {
            XCTAssertEqual(layer?["source"], .string(PinLayers.sourceID))
        }
        XCTAssertNotEqual(PinLayers.bookmarkOffset, PinLayers.heartOffset, "badges would collide at one anchor")

        if case let .object(paint)? = circle?["paint"] {
            XCTAssertEqual(paint["circle-color"], PinLayers.pinColorExpression())
            XCTAssertEqual(paint["circle-opacity"], PinLayers.fadeOpacityExpression())
            XCTAssertEqual(paint["circle-radius"], PinSize().circleRadiusExpression)
        } else {
            XCTFail("pin circle paint")
        }

        XCTAssertEqual(bookmark?["filter"], PinLayers.bookmarkFilter())
        XCTAssertEqual(heart?["filter"], PinLayers.heartFilter())
        XCTAssertEqual(layoutValue("icon-image", in: icon), PinLayers.categoryIconExpression())
        XCTAssertEqual(layoutValue("icon-allow-overlap", in: icon), .bool(true))
        XCTAssertEqual(layoutValue("icon-ignore-placement", in: icon), .bool(true))
        XCTAssertEqual(layoutValue("icon-size", in: icon), PinSize().categoryIconScaleExpression)
        XCTAssertEqual(layoutValue("icon-image", in: bookmark), .string("badge-bookmark"))
        XCTAssertEqual(layoutValue("icon-image", in: heart), .string("badge-heart"))
        XCTAssertEqual(layoutValue("icon-allow-overlap", in: bookmark), .bool(true))
        XCTAssertEqual(layoutValue("icon-allow-overlap", in: heart), .bool(true))
        XCTAssertEqual(layoutValue("icon-size", in: bookmark), PinSize().badgeIconScaleExpression)
        XCTAssertEqual(layoutValue("icon-size", in: heart), PinSize().badgeIconScaleExpression)
        XCTAssertEqual(layoutValue("icon-offset", in: bookmark), PinSize().bookmarkOffset)
        XCTAssertEqual(layoutValue("icon-offset", in: heart), PinSize().heartOffset)
    }

    func testTrackLayerUsesSeparateDashedLineSourceBelowPins() throws {
        XCTAssertNotEqual(TrackLayers.sourceID, PinLayers.sourceID)
        let layer = try XCTUnwrap(layer(id: "tracks-line", in: TrackLayers.trackLayers()))
        XCTAssertEqual(layer["id"], .string("tracks-line"))
        XCTAssertEqual(layer["type"], .string("line"))
        XCTAssertEqual(layer["source"], .string(TrackLayers.sourceID))
        XCTAssertEqual(layoutValue("line-cap", in: layer), .string("round"))
        XCTAssertEqual(layoutValue("line-join", in: layer), .string("round"))

        guard case let .object(paint)? = layer["paint"] else { return XCTFail("line paint") }
        XCTAssertEqual(paint["line-color"], .string(TrackLayers.lineColor))
        XCTAssertEqual(paint["line-opacity"], .double(TrackLayers.lineOpacity))
        XCTAssertEqual(paint["line-width"], .double(TrackLayers.lineWidth))
        XCTAssertEqual(paint["line-dasharray"], TrackLayers.lineDashPattern)
    }

    func testTrackLineColorClearsPaperBackgroundContrastCommitment() throws {
        for theme in MapTheme.allCandidates {
            XCTAssertGreaterThanOrEqual(
                try contrastRatio(
                    compositedHex(
                        foreground: TrackLayers.lineColor,
                        alpha: TrackLayers.lineOpacity,
                        background: theme.background
                    ),
                    theme.background
                ),
                4.5,
                theme.id
            )
        }
    }

    func testPinSizeMetricsScaleCircleCategoryIconAndBadgesTogether() {
        XCTAssertEqual(PinSize.minimumMultiplier, 0.8)
        XCTAssertEqual(PinSize.defaultMultiplier, 1.2)
        XCTAssertEqual(PinSize.maximumMultiplier, 1.6)

        let defaultSize = PinSize()
        XCTAssertEqual(defaultSize.multiplier, PinSize.defaultMultiplier)
        XCTAssertEqual(defaultSize.circleRadius, PinLayers.baseCircleRadius * PinSize.defaultMultiplier, accuracy: 1e-9)
        XCTAssertEqual(defaultSize.categoryIconScale, PinLayers.baseCategoryIconScale * PinSize.defaultMultiplier, accuracy: 1e-9)
        XCTAssertEqual(defaultSize.badgeIconScale, PinLayers.baseBadgeIconScale * PinSize.defaultMultiplier, accuracy: 1e-9)
        XCTAssertEqual(defaultSize.bookmarkOffset, .array([.double(PinLayers.baseBadgeOffset * PinSize.defaultMultiplier), .double(-PinLayers.baseBadgeOffset * PinSize.defaultMultiplier)]))
        XCTAssertEqual(defaultSize.heartOffset, .array([.double(-PinLayers.baseBadgeOffset * PinSize.defaultMultiplier), .double(-PinLayers.baseBadgeOffset * PinSize.defaultMultiplier)]))
        XCTAssertEqual(defaultSize.accessibilityValue, "120%")

        XCTAssertEqual(PinSize(multiplier: 0.1).multiplier, PinSize.minimumMultiplier)
        XCTAssertEqual(PinSize(multiplier: 2.4).multiplier, PinSize.maximumMultiplier)
    }

    func testPinLayerJSONUsesZoomAwareSizeExpressionsComposedWithMultiplier() {
        let layers = PinLayers.pinLayers()
        let circle = layer(id: "pins-circle", in: layers)
        let icon = layer(id: "pins-icon", in: layers)
        let bookmark = layer(id: "pins-bookmark", in: layers)
        let heart = layer(id: "pins-heart", in: layers)
        let defaultSize = PinSize()

        if case let .object(paint)? = circle?["paint"] {
            XCTAssertEqual(paint["circle-radius"], defaultSize.circleRadiusExpression)
        } else {
            XCTFail("pin circle paint")
        }
        XCTAssertEqual(layoutValue("icon-size", in: icon), defaultSize.categoryIconScaleExpression)
        XCTAssertEqual(layoutValue("icon-size", in: bookmark), defaultSize.badgeIconScaleExpression)
        XCTAssertEqual(layoutValue("icon-size", in: heart), defaultSize.badgeIconScaleExpression)
        XCTAssertEqual(layoutValue("icon-offset", in: bookmark), defaultSize.bookmarkOffset)
        XCTAssertEqual(layoutValue("icon-offset", in: heart), defaultSize.heartOffset)

        let maximumSize = PinSize(multiplier: PinSize.maximumMultiplier)
        let maximumLayers = PinLayers.pinLayers(pinSize: maximumSize)
        let maximumCircle = layer(id: "pins-circle", in: maximumLayers)
        let maximumIcon = layer(id: "pins-icon", in: maximumLayers)
        if case let .object(paint)? = maximumCircle?["paint"] {
            XCTAssertEqual(paint["circle-radius"], maximumSize.circleRadiusExpression)
        } else {
            XCTFail("maximum pin circle paint")
        }
        XCTAssertEqual(layoutValue("icon-size", in: maximumIcon), maximumSize.categoryIconScaleExpression)
        XCTAssertNotEqual(defaultSize.circleRadiusExpression, maximumSize.circleRadiusExpression)
        XCTAssertTrue(isZoomInterpolation(defaultSize.circleRadiusExpression))
        XCTAssertTrue(isZoomInterpolation(defaultSize.categoryIconScaleExpression))
    }

    func testWhiteCategoryGlyphHasEnoughContrastOnFullOpacityPinCircles() throws {
        let white = "#FFFFFF"
        XCTAssertGreaterThanOrEqual(try contrastRatio(white, PinLayers.pinColor), 3.0)
        XCTAssertGreaterThanOrEqual(try contrastRatio(white, PinLayers.hiddenPinColor), 3.0)
    }

    func testCategoryIconExpressionMapsKnownCategoriesAndFallsBackForUnknowns() {
        for (category, iconName) in PinLayers.categoryIconNames {
            let props = ["category": JSONValue.string(category)]
            XCTAssertEqual(Expression.evaluate(PinLayers.categoryIconExpression(), props), .string(iconName))
        }

        XCTAssertEqual(
            Expression.evaluate(PinLayers.categoryIconExpression(), ["category": .string("future_category")]),
            .string(PinLayers.fallbackCategoryIconName)
        )
        XCTAssertEqual(
            Expression.evaluate(PinLayers.categoryIconExpression(), [:]),
            .string(PinLayers.fallbackCategoryIconName)
        )
    }

    func testHiddenPinsUseDistinctVisualsAndSuppressBadges() {
        let hiddenLovedSaved = FeatureEncoding.featureProperties(
            PinState(saved: true, visit: .loved, hidden: true)
        ).merging(["category": .string("museum")]) { _, new in new }
        let visibleLovedSaved = FeatureEncoding.featureProperties(
            PinState(saved: true, visit: .loved, hidden: false)
        ).merging(["category": .string("museum")]) { _, new in new }

        XCTAssertEqual(
            Expression.evaluate(PinLayers.pinColorExpression(), hiddenLovedSaved),
            .string(PinLayers.hiddenPinColor)
        )
        XCTAssertEqual(
            Expression.evaluate(PinLayers.pinColorExpression(), visibleLovedSaved),
            .string(PinLayers.pinColor)
        )
        XCTAssertEqual(
            Expression.evaluate(PinLayers.categoryIconExpression(), hiddenLovedSaved),
            .string(PinLayers.hiddenIconName)
        )
        XCTAssertEqual(
            Expression.evaluate(PinLayers.categoryIconExpression(), visibleLovedSaved),
            .string(PinLayers.categoryIconNames["museum"]!)
        )
        XCTAssertEqual(Expression.evaluate(PinLayers.fadeOpacityExpression(), hiddenLovedSaved), .double(FULL_OPACITY))
        XCTAssertEqual(Expression.evaluate(PinLayers.bookmarkFilter(), hiddenLovedSaved), .bool(false))
        XCTAssertEqual(Expression.evaluate(PinLayers.heartFilter(), hiddenLovedSaved), .bool(false))
        XCTAssertEqual(Expression.evaluate(PinLayers.bookmarkFilter(), visibleLovedSaved), .bool(true))
        XCTAssertEqual(Expression.evaluate(PinLayers.heartFilter(), visibleLovedSaved), .bool(true))
    }

    func testEveryEmittedCategoryIconHasARegisteredSymbolImage() {
        var emittedIconNames = Set(PinLayers.categoryIconNames.values)
        emittedIconNames.insert(PinLayers.fallbackCategoryIconName)
        emittedIconNames.insert(PinLayers.hiddenIconName)

        XCTAssertEqual(emittedIconNames, Set(PinLayers.categorySymbolNames.keys))
    }

    func testCategoryVisibilityFilterComposesWithHiddenVisibility() {
        XCTAssertNil(PinLayers.categoryVisibilityFilter(visibleCategories: nil))
        let museumAndOtherFilter = PinLayers.categoryVisibilityFilter(
            visibleCategories: ["museum", PinLayers.fallbackCategoryID]
        )
        XCTAssertEqual(Expression.evaluate(museumAndOtherFilter!, ["category": .string("museum")]), .bool(true))
        XCTAssertEqual(Expression.evaluate(museumAndOtherFilter!, ["category": .string("future_category")]), .bool(true))
        XCTAssertEqual(Expression.evaluate(museumAndOtherFilter!, ["category": .string("future_category"), "hidden": .bool(true)]), .bool(true))
        XCTAssertEqual(Expression.evaluate(museumAndOtherFilter!, ["category": .string("artwork")]), .bool(false))

        let museumOnlyFilter = PinLayers.categoryVisibilityFilter(visibleCategories: ["museum"])
        XCTAssertEqual(Expression.evaluate(museumOnlyFilter!, ["category": .string("museum")]), .bool(true))
        XCTAssertEqual(Expression.evaluate(museumOnlyFilter!, ["category": .string("museum"), "hidden": .bool(true)]), .bool(true))
        XCTAssertEqual(Expression.evaluate(museumOnlyFilter!, ["category": .string("future_category")]), .bool(false))
        XCTAssertEqual(Expression.evaluate(museumOnlyFilter!, ["category": .string("future_category"), "hidden": .bool(true)]), .bool(false))
        XCTAssertEqual(Expression.evaluate(museumOnlyFilter!, ["category": .string("artwork"), "hidden": .bool(true)]), .bool(false))

        XCTAssertEqual(
            Expression.evaluate(PinLayers.categoryVisibilityFilter(visibleCategories: [])!, ["category": .string("museum")]),
            .bool(false)
        )
        XCTAssertEqual(
            Expression.evaluate(PinLayers.categoryVisibilityFilter(visibleCategories: [])!, ["category": .string("museum"), "hidden": .bool(true)]),
            .bool(false)
        )
    }

    func testCategoryVisibilityHelperMatchesLayerFilterSemantics() {
        XCTAssertTrue(PinLayers.isCategoryVisible("future_category", visibleCategories: nil))
        XCTAssertTrue(PinLayers.isCategoryVisible("museum", visibleCategories: ["museum", PinLayers.fallbackCategoryID]))
        XCTAssertTrue(PinLayers.isCategoryVisible("future_category", visibleCategories: ["museum", PinLayers.fallbackCategoryID]))
        XCTAssertFalse(PinLayers.isCategoryVisible("artwork", visibleCategories: ["museum", PinLayers.fallbackCategoryID]))

        XCTAssertTrue(PinLayers.isCategoryVisible("museum", visibleCategories: ["museum"]))
        XCTAssertFalse(PinLayers.isCategoryVisible("future_category", visibleCategories: ["museum"]))
        XCTAssertFalse(PinLayers.isCategoryVisible("future_category", visibleCategories: []))
        XCTAssertFalse(PinLayers.isCategoryVisible("museum", visibleCategories: []))
    }

    func testShowHiddenSourceStillComposesWithCategoryLayerFilters() {
        let visibleMuseum = MapPlace(id: "visible-museum", lat: 51.5, lon: -0.12, tier: 1, category: "museum")
        let hiddenMuseum = MapPlace(id: "hidden-museum", lat: 51.6, lon: -0.11, tier: 2, category: "museum")
        let hiddenArtwork = MapPlace(id: "hidden-artwork", lat: 51.7, lon: -0.10, tier: 2, category: "artwork")
        let features = [
            (visibleMuseum, PinState(saved: false, visit: .none, hidden: false)),
            (hiddenMuseum, PinState(saved: false, visit: .none, hidden: true)),
            (hiddenArtwork, PinState(saved: false, visit: .none, hidden: true)),
        ]

        let sourceFeatures = PinFeatureFilter.discoveryFeatures(features, showHidden: true)
        XCTAssertEqual(sourceFeatures.map(\.0.id), ["visible-museum", "hidden-museum", "hidden-artwork"])

        let museumFilter = PinLayers.categoryVisibilityFilter(visibleCategories: ["museum"])!
        let visibleIDs = sourceFeatures.compactMap { place, state -> String? in
            let props = FeatureEncoding.featureProperties(state)
                .merging(["category": .string(place.category)]) { _, new in new }
            return Expression.evaluate(museumFilter, props) == .bool(true) ? place.id : nil
        }
        XCTAssertEqual(visibleIDs, ["visible-museum", "hidden-museum"])

        let noCategoryFilter = PinLayers.categoryVisibilityFilter(visibleCategories: [])!
        let noCategoryIDs = sourceFeatures.compactMap { place, state -> String? in
            let props = FeatureEncoding.featureProperties(state)
                .merging(["category": .string(place.category)]) { _, new in new }
            return Expression.evaluate(noCategoryFilter, props) == .bool(true) ? place.id : nil
        }
        XCTAssertEqual(noCategoryIDs, [])
    }

    func testCombinesCategoryFilterWithBadgeFilters() {
        let categoryFilter = PinLayers.categoryVisibilityFilter(visibleCategories: ["museum"])

        XCTAssertNil(PinLayers.combinedFilter([nil, nil]))
        XCTAssertEqual(PinLayers.combinedFilter([categoryFilter]), categoryFilter)
        XCTAssertEqual(
            PinLayers.combinedFilter([categoryFilter, PinLayers.bookmarkFilter()]),
            .array([
                .string("all"),
                categoryFilter!,
                PinLayers.bookmarkFilter(),
            ])
        )
    }

    func testFoundationObjectBridgePreservesRecursiveShapeAndBooleanNSNumber() {
        let number = JSONValue.bool(true).foundationObject as? NSNumber
        XCTAssertNotNil(number)
        XCTAssertEqual(CFGetTypeID(number!), CFBooleanGetTypeID(), "bool must bridge to a boolean NSNumber, not 0/1")

        let object = JSONValue.object([
            "array": .array([.string("x"), .double(2), .bool(false), .null]),
            "filter": PinLayers.bookmarkFilter(),
        ]).foundationObject
        guard let dict = object as? [String: Any],
              let array = dict["array"] as? [Any],
              let filter = dict["filter"] as? [Any]
        else { return XCTFail("recursive bridge shape") }
        XCTAssertEqual(array[0] as? String, "x")
        XCTAssertEqual(array[1] as? Double, 2)
        XCTAssertEqual(CFGetTypeID(array[2] as! NSNumber), CFBooleanGetTypeID())
        XCTAssertTrue(array[3] is NSNull)
        XCTAssertEqual(filter.count, 3)
    }

    func testFeatureIsGeoJSONPointWithLonLatOrder() {
        let feature = FeatureEncoding.feature(
            MapPlace(id: "mt1_x", lat: 3.14, lon: 101.69, tier: 2, category: "museum"),
            PinState(saved: true, visit: .loved)
        )
        guard case let .object(feat) = feature,
              case let .object(geometry) = feat["geometry"],
              case let .array(coords) = geometry["coordinates"] else {
            return XCTFail("geometry")
        }
        XCTAssertEqual(feat["type"], .string("Feature"))
        XCTAssertEqual(geometry["type"], .string("Point"))
        XCTAssertEqual(coords, [.double(101.69), .double(3.14)])
        guard case let .object(props) = feat["properties"] else { return XCTFail("props") }
        XCTAssertEqual(props["place_id"], .string("mt1_x"))
        XCTAssertEqual(props["tier"], .double(2))
        XCTAssertEqual(props["category"], .string("museum"))
        XCTAssertEqual(props["visit"], .string("loved"))
        XCTAssertEqual(props["saved"], .bool(true))
        XCTAssertEqual(props["hidden"], .bool(false))

        let collection = FeatureEncoding.featureCollection([feature])
        guard case let .object(root) = collection,
              case let .array(features) = root["features"]
        else { return XCTFail("feature collection") }
        XCTAssertEqual(root["type"], .string("FeatureCollection"))
        XCTAssertEqual(features, [feature])
    }

    func testTrackSegmentFeaturesUseShallowArcsAndSuppressBurstAndGapConnectors() {
        let visits = [
            trackVisit(id: 1, placeID: "a", seconds: 0, lat: 0, lon: 0),
            trackVisit(id: 2, placeID: "b", seconds: 300, lat: 0, lon: 1),
            trackVisit(id: 3, placeID: "c", seconds: 330, lat: 1, lon: 1),
            trackVisit(id: 4, placeID: "d", seconds: 7_200, lat: 1, lon: 2),
            trackVisit(id: 5, placeID: "e", seconds: 7_500, lat: 2, lon: 2),
        ]

        let features = FeatureEncoding.trackSegmentFeatures(
            visits,
            maxConnectorGap: 3_600,
            burstWindow: 120
        )

        XCTAssertEqual(features.count, 2)
        XCTAssertEqual(trackProperty("from_visit_id", in: features[0]), .double(1))
        XCTAssertEqual(trackProperty("to_visit_id", in: features[0]), .double(2))
        XCTAssertEqual(trackProperty("from_visit_id", in: features[1]), .double(4))
        XCTAssertEqual(trackProperty("to_visit_id", in: features[1]), .double(5))

        guard case let .object(firstFeature) = features.first,
              case let .object(geometry) = firstFeature["geometry"],
              case let .array(coordinates) = geometry["coordinates"],
              coordinates.count == 3,
              case let .array(start) = coordinates.first,
              case let .array(mid) = coordinates[1],
              case let .array(end) = coordinates.last
        else { return XCTFail("arc line string") }
        XCTAssertEqual(geometry["type"], .string("LineString"))
        XCTAssertEqual(start, [.double(0), .double(0)])
        XCTAssertEqual(end, [.double(1), .double(0)])
        XCTAssertNotEqual(mid, [.double(0.5), .double(0)], "middle coordinate should make the connector visibly abstract, not a straight segment")
    }

    func testTrackSegmentFeaturesKeepDerivedArcCoordinatesInWGS84Bounds() {
        let visits = [
            trackVisit(id: 1, placeID: "near-pole-west", seconds: 0, lat: 89.9, lon: -170),
            trackVisit(id: 2, placeID: "near-pole-east", seconds: 600, lat: 89.9, lon: 170),
        ]

        let features = FeatureEncoding.trackSegmentFeatures(
            visits,
            maxConnectorGap: 3_600,
            burstWindow: 120
        )

        guard case let .object(firstFeature) = features.first,
              case let .object(geometry) = firstFeature["geometry"],
              case let .array(coordinates) = geometry["coordinates"]
        else { return XCTFail("track feature") }
        for coordinate in coordinates {
            guard case let .array(values) = coordinate,
                  values.count == 2,
                  case let .double(lon) = values[0],
                  case let .double(lat) = values[1]
            else { return XCTFail("coordinate pair") }
            XCTAssertTrue(lon.isFinite)
            XCTAssertTrue(lat.isFinite)
            XCTAssertTrue((-180.0...180.0).contains(lon), "longitude \(lon)")
            XCTAssertTrue((-90.0...90.0).contains(lat), "latitude \(lat)")
        }
    }

    private func layer(id: String, in layers: [JSONValue]) -> [String: JSONValue]? {
        for case let .object(layer) in layers where layer["id"] == .string(id) {
            return layer
        }
        return nil
    }

    private func trackProperty(_ key: String, in feature: JSONValue) -> JSONValue? {
        guard case let .object(object) = feature,
              case let .object(properties)? = object["properties"]
        else { return nil }
        return properties[key]
    }

    private func trackVisit(
        id: Int64,
        placeID: String,
        seconds: TimeInterval,
        lat: Double,
        lon: Double
    ) -> TrackVisit {
        TrackVisit(
            id: id,
            placeID: placeID,
            visitedAt: Date(timeIntervalSince1970: seconds),
            verdict: nil,
            name: placeID,
            category: "history",
            tier: 2,
            lat: lat,
            lon: lon
        )
    }

    private func layoutValue(_ key: String, in layer: [String: JSONValue]?) -> JSONValue? {
        guard case let .object(layout)? = layer?["layout"] else { return nil }
        return layout[key]
    }

    private func isZoomInterpolation(_ value: JSONValue) -> Bool {
        guard case let .array(expression) = value,
              expression.count >= 5,
              expression.first == .string("interpolate"),
              case let .array(input) = expression[2]
        else { return false }
        return input == [.string("zoom")]
    }

    private func contrastRatio(_ first: String, _ second: String) throws -> Double {
        let firstLuminance = try relativeLuminance(first)
        let secondLuminance = try relativeLuminance(second)
        let lighter = max(firstLuminance, secondLuminance)
        let darker = min(firstLuminance, secondLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func compositedHex(foreground: String, alpha: Double, background: String) throws -> String {
        let foregroundRGB = try rgb(foreground)
        let backgroundRGB = try rgb(background)
        let channels = zip(foregroundRGB, backgroundRGB).map { foreground, background in
            Int(((foreground * alpha) + (background * (1 - alpha))).rounded())
        }
        return String(format: "#%02X%02X%02X", channels[0], channels[1], channels[2])
    }

    private func rgb(_ hex: String) throws -> [Double] {
        let scalars = Array(hex.dropFirst())
        XCTAssertEqual(hex.first, "#")
        XCTAssertEqual(scalars.count, 6)
        return try stride(from: 0, to: scalars.count, by: 2).map { index -> Double in
            let channel = String(scalars[index..<(index + 2)])
            return Double(try XCTUnwrap(Int(channel, radix: 16)))
        }
    }

    private func relativeLuminance(_ hex: String) throws -> Double {
        let channels = try rgb(hex).map { value -> Double in
            let component = Double(value) / 255.0
            return component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return (0.2126 * channels[0]) + (0.7152 * channels[1]) + (0.0722 * channels[2])
    }
}
