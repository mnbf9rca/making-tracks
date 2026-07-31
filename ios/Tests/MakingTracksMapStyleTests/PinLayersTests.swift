import XCTest
import MakingTracksData
@testable import DesignSystem
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

    func testPinAndTrackLayerValuesComeFromTheTokenSheet() throws {
        XCTAssertEqual(PinLayers.pinColor, PinTokenBlock.constant.pin.mapStyleString)
        XCTAssertEqual(PinLayers.hiddenPinColor, PinTokenBlock.constant.hiddenPin.mapStyleString)
        XCTAssertEqual(FADED_OPACITY, PinTokenBlock.constant.pinFaded.opacity)
        XCTAssertEqual(TrackLayers.lineColor, MaterialTheme.snow.tokens.trail.mapStyleString.lowercased())

        let tokens = tokenSheet(trail: MaterialColor(red: 0x01, green: 0x02, blue: 0x03))
        XCTAssertEqual(TrackLayers.lineStyle(tokens: tokens).color, "#010203")

        let layer = try XCTUnwrap(layer(id: TrackLayers.lineLayerID, in: TrackLayers.trackLayers(tokens: tokens)))
        guard case let .object(paint)? = layer["paint"] else { return XCTFail("line paint") }
        XCTAssertEqual(paint["line-color"], .string("#010203"))
    }

    func testTracksModeKeepsVisitedPinsFullStrengthWithoutLyingAboutVisitState() {
        let visited = PinState(saved: false, visit: .visited)
        let loved = PinState(saved: true, visit: .loved)

        let visitedProps = FeatureEncoding.featureProperties(visited, pinPresentation: .tracks)
        let lovedProps = FeatureEncoding.featureProperties(loved, pinPresentation: .tracks)

        XCTAssertEqual(visitedProps["visit"], .string("visited"))
        XCTAssertEqual(lovedProps["visit"], .string("loved"))
        XCTAssertEqual(Expression.evaluate(PinLayers.fadeOpacityExpression(), visitedProps), .double(FULL_OPACITY))
        XCTAssertEqual(Expression.evaluate(PinLayers.fadeOpacityExpression(), lovedProps), .double(FULL_OPACITY))
        XCTAssertEqual(Expression.evaluate(PinLayers.bookmarkFilter(), lovedProps), .bool(true))
        XCTAssertEqual(Expression.evaluate(PinLayers.heartFilter(), lovedProps), .bool(true))
    }

    func testTrackReplayPresentationFadesUnreachedPinsAndFullStrengthReachedPins() {
        let unreached = FeatureEncoding.featureProperties(
            PinState(saved: false, visit: .none),
            pinPresentation: .trackReplay
        )
        let reached = FeatureEncoding.featureProperties(
            PinState(saved: false, visit: .visited),
            pinPresentation: .trackReplay
        )
        let loved = FeatureEncoding.featureProperties(
            PinState(saved: true, visit: .loved),
            pinPresentation: .trackReplay
        )

        XCTAssertEqual(Expression.evaluate(PinLayers.fadeOpacityExpression(), unreached), .double(FADED_OPACITY))
        XCTAssertEqual(Expression.evaluate(PinLayers.fadeOpacityExpression(), reached), .double(FULL_OPACITY))
        XCTAssertEqual(Expression.evaluate(PinLayers.fadeOpacityExpression(), loved), .double(FULL_OPACITY))
        XCTAssertEqual(Expression.evaluate(PinLayers.bookmarkFilter(), loved), .bool(true))
        XCTAssertEqual(Expression.evaluate(PinLayers.heartFilter(), loved), .bool(true))
    }

    func testTrackReplayPulseScalesCircleAndCategoryIconOnlyWhenFlagged() {
        let base = JSONValue.double(10)
        let inactive = FeatureEncoding.featureProperties(PinState(saved: false, visit: .visited), pinPresentation: .trackReplay)
        let active = FeatureEncoding.featureProperties(
            PinState(saved: false, visit: .visited),
            pinPresentation: .trackReplay,
            trackReplayPulse: true
        )

        XCTAssertEqual(Expression.evaluate(PinLayers.trackReplayPulseExpression(base: base), inactive), .double(10))
        XCTAssertEqual(
            Expression.evaluate(PinLayers.trackReplayPulseExpression(base: base), active),
            .double(10 * PinLayers.trackReplayPulseScale)
        )
    }

    func testPinSubstrateIsShapeSourcePlusStyleLayersNotAnnotations() {
        let layers = PinLayers.pinLayers()
        let clusterCircle = layer(id: "pin-clusters-circle", in: layers)
        let clusterCount = layer(id: "pin-clusters-count", in: layers)
        let circle = layer(id: "pins-circle", in: layers)
        let icon = layer(id: "pins-icon", in: layers)
        let bookmark = layer(id: "pins-bookmark", in: layers)
        let heart = layer(id: "pins-heart", in: layers)

        XCTAssertEqual(clusterCircle?["type"], .string("circle"), "cluster bubble layer")
        XCTAssertEqual(clusterCount?["type"], .string("symbol"), "cluster count layer")
        XCTAssertEqual(circle?["type"], .string("circle"), "circle pin layer")
        XCTAssertEqual(icon?["type"], .string("symbol"), "category icon symbol layer")
        XCTAssertEqual(bookmark?["type"], .string("symbol"), "bookmark badge symbol layer")
        XCTAssertEqual(heart?["type"], .string("symbol"), "heart badge symbol layer")
        XCTAssertEqual(layers.count, 6, "cluster bubble/count + circle/category icon + bookmark/heart badges")
        for layer in [clusterCircle, clusterCount, circle, icon, bookmark, heart] {
            XCTAssertEqual(layer?["source"], .string(PinLayers.sourceID))
        }
        XCTAssertNotEqual(PinLayers.bookmarkOffset, PinLayers.heartOffset, "badges would collide at one anchor")

        XCTAssertEqual(clusterCircle?["filter"], PinLayers.clusterFilter())
        XCTAssertEqual(clusterCount?["filter"], PinLayers.clusterFilter())
        XCTAssertEqual(circle?["filter"], PinLayers.singlePinFilter())
        XCTAssertEqual(icon?["filter"], PinLayers.singlePinFilter())
        XCTAssertEqual(layoutValue("text-field", in: clusterCount), .array([.string("get"), .string("point_count_abbreviated")]))
        XCTAssertEqual(layoutValue("text-font", in: clusterCount), .array([.string("Noto Sans Regular")]))
        XCTAssertEqual(layoutValue("text-size", in: clusterCount), .double(PinLayers.clusterCountTextSize(pinSize: PinSize())))

        if case let .object(paint)? = circle?["paint"] {
            XCTAssertEqual(paint["circle-color"], PinLayers.pinColorExpression())
            XCTAssertEqual(paint["circle-opacity"], PinLayers.fadeOpacityExpression())
            XCTAssertEqual(
                paint["circle-radius"],
                PinLayers.trackReplayPulseExpression(base: PinSize().circleRadiusExpression)
            )
        } else {
            XCTFail("pin circle paint")
        }

        XCTAssertEqual(bookmark?["filter"], PinLayers.bookmarkFilter())
        XCTAssertEqual(heart?["filter"], PinLayers.heartFilter())
        XCTAssertEqual(layoutValue("icon-image", in: icon), PinLayers.categoryIconExpression())
        XCTAssertEqual(layoutValue("icon-allow-overlap", in: icon), .bool(true))
        XCTAssertEqual(layoutValue("icon-ignore-placement", in: icon), .bool(true))
        XCTAssertEqual(
            layoutValue("icon-size", in: icon),
            PinLayers.trackReplayPulseExpression(base: PinSize().categoryIconScaleExpression)
        )
        XCTAssertEqual(layoutValue("icon-image", in: bookmark), .string("badge-bookmark"))
        XCTAssertEqual(layoutValue("icon-image", in: heart), .string("badge-heart"))
        XCTAssertEqual(layoutValue("icon-allow-overlap", in: bookmark), .bool(true))
        XCTAssertEqual(layoutValue("icon-allow-overlap", in: heart), .bool(true))
        XCTAssertEqual(layoutValue("icon-size", in: bookmark), PinSize().badgeIconScaleExpression)
        XCTAssertEqual(layoutValue("icon-size", in: heart), PinSize().badgeIconScaleExpression)
        XCTAssertEqual(layoutValue("icon-offset", in: bookmark), PinSize().bookmarkOffset)
        XCTAssertEqual(layoutValue("icon-offset", in: heart), PinSize().heartOffset)
    }

    func testTrackLayerUsesSeparateDottedLineSourceBelowPins() throws {
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
        XCTAssertEqual(paint["line-dasharray"], .array(TrackLayers.lineDashPatternValues.map(JSONValue.double)))
        XCTAssertEqual(TrackLayers.lineColor, MaterialTheme.snow.tokens.trail.mapStyleString.lowercased())
        XCTAssertEqual(TrackLayers.lineWidth, 6.2, accuracy: 1e-9)
        XCTAssertEqual(TrackLayers.lineOpacity, 1.00, accuracy: 1e-9)
        XCTAssertEqual(TrackLayers.lineDotLength, 1.0, accuracy: 1e-9)
        XCTAssertEqual(TrackLayers.lineDotGap, 9.0, accuracy: 1e-9)
        XCTAssertEqual(TrackLayers.lineDashPatternValues.count, 2)
        XCTAssertEqual(TrackLayers.lineDashPatternValues[0], 1.0 / TrackLayers.lineWidth, accuracy: 1e-9)
        XCTAssertEqual(TrackLayers.lineDashPatternValues[1], 9.0 / TrackLayers.lineWidth, accuracy: 1e-9)
    }

    func testTrackLineColorClearsPaperBackgroundSC1411NonTextContrastFloor() throws {
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
                3.0,
                theme.id
            )
        }
    }

    func testTrackReplayActiveArcClearsPaperBackgroundSC1411NonTextContrastFloor() throws {
        for theme in MapTheme.allCandidates {
            XCTAssertGreaterThanOrEqual(
                try contrastRatio(
                    compositedHex(
                        foreground: TrackLayers.activeLineColor,
                        alpha: TrackLayers.activeLineOpacity,
                        background: theme.background
                    ),
                    theme.background
                ),
                3.0,
                theme.id
            )
        }
    }

    func testTrackLineSharedStyleValuesBackTheJSONLayer() throws {
        let style = TrackLayers.lineStyle
        let layer = try XCTUnwrap(layer(id: TrackLayers.lineLayerID, in: TrackLayers.trackLayers()))

        XCTAssertEqual(layoutValue("line-cap", in: layer), .string(style.cap))
        XCTAssertEqual(layoutValue("line-join", in: layer), .string(style.join))

        guard case let .object(paint)? = layer["paint"] else { return XCTFail("line paint") }
        XCTAssertEqual(paint["line-color"], .string(style.color))
        XCTAssertEqual(paint["line-opacity"], .double(style.opacity))
        XCTAssertEqual(paint["line-width"], .double(style.width))
        XCTAssertEqual(paint["line-dasharray"], .array(style.dashPattern.map(JSONValue.double)))
    }

    func testTrackReplayActiveArcUsesBookedTwoToneLayerAboveVisitedArc() throws {
        let layers = TrackLayers.trackLayers()
        XCTAssertNotNil(layer(id: TrackLayers.lineLayerID, in: layers))
        let active = try XCTUnwrap(layer(id: TrackLayers.activeLineLayerID, in: layers))
        let visitedIndex = try XCTUnwrap(layerIndex(id: TrackLayers.lineLayerID, in: layers))
        let activeIndex = try XCTUnwrap(layerIndex(id: TrackLayers.activeLineLayerID, in: layers))

        XCTAssertLessThan(visitedIndex, activeIndex)
        XCTAssertEqual(active["type"], .string("line"))
        XCTAssertEqual(active["source"], .string(TrackLayers.sourceID))
        XCTAssertEqual(layoutValue("line-cap", in: active), .string("round"))
        XCTAssertEqual(layoutValue("line-join", in: active), .string("round"))
        XCTAssertEqual(active["filter"], TrackLayers.activeArcFilter())

        guard case let .object(paint)? = active["paint"] else { return XCTFail("active line paint") }
        XCTAssertEqual(paint["line-color"], .string(TrackLayers.activeLineColor))
        XCTAssertEqual(paint["line-opacity"], .double(TrackLayers.activeLineOpacity))
        XCTAssertEqual(paint["line-width"], .double(TrackLayers.activeLineWidth))
        XCTAssertEqual(paint["line-dasharray"], .array(TrackLayers.activeLineDashPatternValues.map(JSONValue.double)))
        XCTAssertEqual(TrackLayers.lineColor, "#2d8c83")
        XCTAssertEqual(TrackLayers.lineWidth, 6.2, accuracy: 1e-9)
        XCTAssertEqual(TrackLayers.lineOpacity, 1.0, accuracy: 1e-9)
        XCTAssertEqual(TrackLayers.activeLineColor, "#db5344")
        XCTAssertEqual(TrackLayers.activeLineWidth, 7.2, accuracy: 1e-9)
        XCTAssertEqual(TrackLayers.activeLineOpacity, 0.90, accuracy: 1e-9)
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
            XCTAssertEqual(
                paint["circle-radius"],
                PinLayers.trackReplayPulseExpression(base: defaultSize.circleRadiusExpression)
            )
        } else {
            XCTFail("pin circle paint")
        }
        XCTAssertEqual(
            layoutValue("icon-size", in: icon),
            PinLayers.trackReplayPulseExpression(base: defaultSize.categoryIconScaleExpression)
        )
        XCTAssertEqual(layoutValue("icon-size", in: bookmark), defaultSize.badgeIconScaleExpression)
        XCTAssertEqual(layoutValue("icon-size", in: heart), defaultSize.badgeIconScaleExpression)
        XCTAssertEqual(layoutValue("icon-offset", in: bookmark), defaultSize.bookmarkOffset)
        XCTAssertEqual(layoutValue("icon-offset", in: heart), defaultSize.heartOffset)

        let maximumSize = PinSize(multiplier: PinSize.maximumMultiplier)
        let maximumLayers = PinLayers.pinLayers(pinSize: maximumSize)
        let maximumCircle = layer(id: "pins-circle", in: maximumLayers)
        let maximumIcon = layer(id: "pins-icon", in: maximumLayers)
        if case let .object(paint)? = maximumCircle?["paint"] {
            XCTAssertEqual(
                paint["circle-radius"],
                PinLayers.trackReplayPulseExpression(base: maximumSize.circleRadiusExpression)
            )
        } else {
            XCTFail("maximum pin circle paint")
        }
        XCTAssertEqual(
            layoutValue("icon-size", in: maximumIcon),
            PinLayers.trackReplayPulseExpression(base: maximumSize.categoryIconScaleExpression)
        )
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

        let sourceFeatures = PinFeatureFilter.discoveryFeatures(
            features,
            showHidden: true,
            showSaved: true
        )
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
        XCTAssertEqual(filter.count, 4)
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

    func testTrackSegmentFeaturesConnectEveryConsecutiveValidVisitWithSmoothArcs() {
        let visits = [
            trackVisit(id: 1, placeID: "a", seconds: 0, lat: 0, lon: 0),
            trackVisit(id: 2, placeID: "b", seconds: 300, lat: 0, lon: 1),
            trackVisit(id: 3, placeID: "c", seconds: 330, lat: 1, lon: 1),
            trackVisit(id: 4, placeID: "d", seconds: 86_400, lat: 1, lon: 2),
            trackVisit(id: 5, placeID: "e", seconds: 86_430, lat: 2, lon: 2),
        ]

        let features = FeatureEncoding.trackSegmentFeatures(
            visits,
            maxConnectorGap: 3_600,
            burstWindow: 120
        )

        XCTAssertEqual(features.count, 4)
        guard features.count == 4 else { return }
        XCTAssertEqual(trackProperty("from_visit_id", in: features[0]), .double(1))
        XCTAssertEqual(trackProperty("to_visit_id", in: features[0]), .double(2))
        XCTAssertEqual(trackProperty("from_visit_id", in: features[1]), .double(2))
        XCTAssertEqual(trackProperty("to_visit_id", in: features[1]), .double(3))
        XCTAssertEqual(trackProperty("from_visit_id", in: features[2]), .double(3))
        XCTAssertEqual(trackProperty("to_visit_id", in: features[2]), .double(4))
        XCTAssertEqual(trackProperty("from_visit_id", in: features[3]), .double(4))
        XCTAssertEqual(trackProperty("to_visit_id", in: features[3]), .double(5))

        guard case let .object(firstFeature) = features.first,
              case let .object(geometry) = firstFeature["geometry"],
              case let .array(coordinates) = geometry["coordinates"],
              coordinates.count >= 9,
              case let .array(start) = coordinates.first,
              case let .array(end) = coordinates.last
        else { return XCTFail("arc line string") }
        XCTAssertEqual(geometry["type"], .string("LineString"))
        XCTAssertEqual(start, [.double(0), .double(0)])
        XCTAssertEqual(end, [.double(1), .double(0)])
        XCTAssertTrue(
            coordinates.dropFirst().dropLast().contains { coordinate in
                guard case let .array(pair) = coordinate,
                      pair.count == 2,
                      case let .double(lat) = pair[1]
                else { return false }
                return lat != 0
            },
            "interior coordinates should make the connector visibly abstract, not a straight segment"
        )
    }

    func testTrackSegmentArcCurvatureIsConsistentInProjectedSpaceAtLondonLatitude() throws {
        let baseLat = 51.5
        let eastWest = FeatureEncoding.trackSegmentFeatures([
            trackVisit(id: 1, placeID: "west", seconds: 0, lat: baseLat, lon: -0.50),
            trackVisit(id: 2, placeID: "east", seconds: 600, lat: baseLat, lon: 0.50),
        ])
        let northSouth = FeatureEncoding.trackSegmentFeatures([
            trackVisit(id: 3, placeID: "south", seconds: 0, lat: baseLat - 0.50, lon: 0),
            trackVisit(id: 4, placeID: "north", seconds: 600, lat: baseLat + 0.50, lon: 0),
        ])

        let eastWestRatio = try projectedBendRatio(in: XCTUnwrap(eastWest.first), referenceLatitude: baseLat)
        let northSouthRatio = try projectedBendRatio(in: XCTUnwrap(northSouth.first), referenceLatitude: baseLat)

        XCTAssertEqual(eastWestRatio, TrackLayers.arcBendRatio, accuracy: 0.012)
        XCTAssertEqual(northSouthRatio, TrackLayers.arcBendRatio, accuracy: 0.012)
        XCTAssertEqual(eastWestRatio, northSouthRatio, accuracy: 0.012)
    }

    func testTrackSegmentRepeatedOutAndBackArcsUseDistinctLanes() throws {
        let features = FeatureEncoding.trackSegmentFeatures([
            trackVisit(id: 1, placeID: "a", seconds: 0, lat: 0, lon: 0),
            trackVisit(id: 2, placeID: "b", seconds: 60, lat: 0, lon: 1),
            trackVisit(id: 3, placeID: "a", seconds: 120, lat: 0, lon: 0),
            trackVisit(id: 4, placeID: "b", seconds: 180, lat: 0, lon: 1),
        ])

        XCTAssertEqual(features.count, 3)

        let midLats = try features.map { feature in
            let coordinates = try trackCoordinates(in: feature)
            XCTAssertFalse(coordinates.isEmpty)
            return coordinates[coordinates.count / 2].lat
        }

        XCTAssertGreaterThan(midLats[0], 0)
        XCTAssertLessThan(midLats[1], 0)
        XCTAssertGreaterThan(midLats[2], midLats[0])
    }

    func testTrackSegmentFeaturesKeepNonDatelineDerivedArcCoordinatesInWGS84Bounds() {
        let visits = [
            trackVisit(id: 1, placeID: "near-pole-west", seconds: 0, lat: 89.9, lon: -10),
            trackVisit(id: 2, placeID: "near-pole-east", seconds: 600, lat: 89.9, lon: 10),
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

    func testTrackSegmentFeaturesClampNonDatelineArcNearAntimeridian() throws {
        let visits = [
            trackVisit(id: 1, placeID: "edge-north", seconds: 0, lat: 20, lon: 179.0),
            trackVisit(id: 2, placeID: "edge-south", seconds: 3_600, lat: -10, lon: 179.5),
        ]

        let features = FeatureEncoding.trackSegmentFeatures(
            visits,
            maxConnectorGap: 12 * 60 * 60,
            burstWindow: 120
        )

        let longitudes = trackLongitudes(in: try XCTUnwrap(features.first))

        XCTAssertGreaterThanOrEqual(longitudes.count, 9)
        XCTAssertEqual(longitudes[0], 179.0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(longitudes.last), 179.5, accuracy: 1e-9)
    }

    func testTrackSegmentFeaturesPreserveNonDatelineEndpointLongitudeExactly() throws {
        let fromLat = 12.345678901
        let fromLon = 79.524723965298108
        let toLat = -23.456789012
        let toLon = -80.455733550403565
        let visits = [
            trackVisit(id: 1, placeID: "fractional-west", seconds: 0, lat: fromLat, lon: fromLon),
            trackVisit(id: 2, placeID: "fractional-east", seconds: 3_600, lat: toLat, lon: toLon),
        ]

        let features = FeatureEncoding.trackSegmentFeatures(
            visits,
            maxConnectorGap: 12 * 60 * 60,
            burstWindow: 120
        )

        let longitudes = trackLongitudes(in: try XCTUnwrap(features.first))

        XCTAssertGreaterThanOrEqual(longitudes.count, 9)
        XCTAssertEqual(longitudes.last, toLon)
    }

    func testTrackSegmentFeaturesWrapAntimeridianUsingShortestLongitudePath() throws {
        let visits = [
            trackVisit(id: 1, placeID: "fiji", seconds: 0, lat: -17.7134, lon: 178.0650),
            trackVisit(id: 2, placeID: "samoa", seconds: 3_600, lat: -13.7590, lon: -172.1046),
        ]

        let features = FeatureEncoding.trackSegmentFeatures(
            visits,
            maxConnectorGap: 12 * 60 * 60,
            burstWindow: 120
        )

        let longitudes = trackLongitudes(in: try XCTUnwrap(features.first))

        XCTAssertGreaterThanOrEqual(longitudes.count, 9)
        XCTAssertEqual(longitudes[0], 178.0650, accuracy: 1e-9)
        XCTAssertGreaterThan(longitudes[longitudes.count / 2], 180.0, "midpoint should stay near the dateline, not Greenwich")
        XCTAssertEqual(try XCTUnwrap(longitudes.last), 187.8954, accuracy: 1e-9)
        XCTAssertLessThan(abs(try XCTUnwrap(longitudes.last) - longitudes[0]), 20.0)
        for (from, to) in zip(longitudes, longitudes.dropFirst()) {
            XCTAssertLessThan(abs(to - from), 20.0, "adjacent arc segment should use the wrapped short path")
        }
    }

    func testTrackSegmentFeaturesWrapReverseAntimeridianUsingShortestLongitudePath() throws {
        let visits = [
            trackVisit(id: 1, placeID: "samoa", seconds: 0, lat: -13.7590, lon: -172.1046),
            trackVisit(id: 2, placeID: "fiji", seconds: 3_600, lat: -17.7134, lon: 178.0650),
        ]

        let features = FeatureEncoding.trackSegmentFeatures(
            visits,
            maxConnectorGap: 12 * 60 * 60,
            burstWindow: 120
        )

        let longitudes = trackLongitudes(in: try XCTUnwrap(features.first))

        XCTAssertGreaterThanOrEqual(longitudes.count, 9)
        XCTAssertEqual(longitudes[0], -172.1046, accuracy: 1e-9)
        XCTAssertLessThan(abs(longitudes[longitudes.count / 2] - (-180.0)), 10.0, "midpoint should stay near the dateline, not Greenwich")
        XCTAssertEqual(try XCTUnwrap(longitudes.last), -181.9350, accuracy: 1e-9)
        XCTAssertLessThan(abs(try XCTUnwrap(longitudes.last) - longitudes[0]), 20.0)
        for (from, to) in zip(longitudes, longitudes.dropFirst()) {
            XCTAssertLessThan(abs(to - from), 20.0, "adjacent arc segment should use the wrapped short path")
        }
    }

    func testTrackSegmentSummaryDoesNotSuppressBurstConnectors() {
        let visits = [
            trackVisit(id: 1, placeID: "desk-a", seconds: 0, lat: 3.14, lon: 101.69),
            trackVisit(id: 2, placeID: "desk-b", seconds: 45, lat: 3.16, lon: 101.70),
        ]

        let summary = FeatureEncoding.trackSegmentSummary(
            visits,
            maxConnectorGap: 3_600,
            burstWindow: 300
        )

        XCTAssertEqual(summary.features.count, 1)
        XCTAssertEqual(summary.suppressedBurstConnectorCount, 0)
        XCTAssertEqual(summary.connectableVisitCount, 2)
    }

    func testTrackSegmentSummaryMarksOnlyArrivingConnectorAsActiveForReplay() {
        let visits = [
            trackVisit(id: 1, placeID: "a", seconds: 0, lat: 0, lon: 0),
            trackVisit(id: 2, placeID: "b", seconds: 300, lat: 0, lon: 1),
            trackVisit(id: 3, placeID: "c", seconds: 600, lat: 1, lon: 1),
        ]

        let summary = FeatureEncoding.trackSegmentSummary(visits, activeToVisitID: 3)

        XCTAssertEqual(summary.features.count, 2)
        XCTAssertEqual(trackProperty(TrackLayers.trackSegmentPhaseProperty, in: summary.features[0]), .string("visited"))
        XCTAssertEqual(trackProperty(TrackLayers.trackSegmentPhaseProperty, in: summary.features[1]), .string(TrackLayers.activeArcPhase))
    }

    private func layer(id: String, in layers: [JSONValue]) -> [String: JSONValue]? {
        for case let .object(layer) in layers where layer["id"] == .string(id) {
            return layer
        }
        return nil
    }

    private func layerIndex(id: String, in layers: [JSONValue]) -> Int? {
        layers.firstIndex { value in
            guard case let .object(layer) = value else { return false }
            return layer["id"] == .string(id)
        }
    }

    private func trackProperty(_ key: String, in feature: JSONValue) -> JSONValue? {
        guard case let .object(object) = feature,
              case let .object(properties)? = object["properties"]
        else { return nil }
        return properties[key]
    }

    private func trackLongitudes(in feature: JSONValue) -> [Double] {
        guard case let .object(firstFeature) = feature,
              case let .object(geometry) = firstFeature["geometry"],
              case let .array(coordinates) = geometry["coordinates"]
        else {
            XCTFail("track feature geometry missing")
            return []
        }
        return coordinates.map { coordinate in
            guard case let .array(values) = coordinate,
                  values.count == 2,
                  case let .double(lon) = values[0]
            else {
                XCTFail("track coordinate missing longitude")
                return .nan
            }
            return lon
        }
    }

    private func trackCoordinates(in feature: JSONValue) throws -> [(lon: Double, lat: Double)] {
        guard case let .object(firstFeature) = feature,
              case let .object(geometry) = firstFeature["geometry"],
              case let .array(coordinates) = geometry["coordinates"]
        else {
            throw XCTSkip("track feature geometry missing")
        }
        return try coordinates.map { coordinate in
            guard case let .array(values) = coordinate,
                  values.count == 2,
                  case let .double(lon) = values[0],
                  case let .double(lat) = values[1]
            else {
                throw XCTSkip("track coordinate missing pair")
            }
            return (lon, lat)
        }
    }

    private func projectedBendRatio(in feature: JSONValue, referenceLatitude: Double) throws -> Double {
        let coordinates = try trackCoordinates(in: feature)
        let scale = cos(referenceLatitude * .pi / 180)
        let start = try XCTUnwrap(coordinates.first)
        let end = try XCTUnwrap(coordinates.last)
        let startPoint = (x: start.lon * scale, y: start.lat)
        let endPoint = (x: end.lon * scale, y: end.lat)
        let dx = endPoint.x - startPoint.x
        let dy = endPoint.y - startPoint.y
        let length = max((dx * dx + dy * dy).squareRoot(), 0.000_001)
        let maxBend = coordinates.map { coordinate in
            let point = (x: coordinate.lon * scale, y: coordinate.lat)
            let cross = (dy * point.x)
                - (dx * point.y)
                + (endPoint.x * startPoint.y)
                - (endPoint.y * startPoint.x)
            return abs(cross) / length
        }.max() ?? 0
        return maxBend / length
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

    private func tokenSheet(trail: MaterialColor) -> MaterialTokenSheet {
        let snow = MaterialTheme.snow.tokens
        return MaterialTokenSheet(
            ground: snow.ground,
            water: snow.water,
            park: snow.park,
            road: snow.road,
            roadMinor: snow.roadMinor,
            surface: snow.surface,
            surfaceRaised: snow.surfaceRaised,
            ink: snow.ink,
            muted: snow.muted,
            accent: snow.accent,
            accentContainer: snow.accentContainer,
            accentDeepContainer: snow.accentDeepContainer,
            accentContrast: snow.accentContrast,
            love: snow.love,
            loveContainer: snow.loveContainer,
            warning: snow.warning,
            warningContainer: snow.warningContainer,
            eyebrow: snow.eyebrow,
            hairline: snow.hairline,
            scrim: snow.scrim,
            shadow: snow.shadow,
            background: snow.background,
            labels: snow.labels,
            labelHalo: snow.labelHalo,
            boundaries: snow.boundaries,
            trail: trail,
            tonalContainerCompositeOpacity: snow.tonalContainerCompositeOpacity,
            disabledAlpha: snow.disabledAlpha,
            pressScale: snow.pressScale
        )
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
