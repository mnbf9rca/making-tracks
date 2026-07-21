import Foundation
import SwiftUI
import UIKit
import XCTest
import MakingTracksData
import MakingTracksMapStyle
import MakingTracksTiles
@testable import MakingTracks

final class AppShellTests: XCTestCase {
    func testPlaceCardVisualSpecMatchesApprovedCardLayout() {
        XCTAssertEqual(PlaceCardVisualSpec.closeSystemImageName, "ellipsis")
        XCTAssertFalse(PlaceCardVisualSpec.showsMediaSlotWhenPhotoMissing)
        XCTAssertEqual(PlaceCardVisualSpec.actionCornerRadius, 8)
        XCTAssertEqual(PlaceCardVisualSpec.actionMinimumHeight, 44)
        XCTAssertEqual(PlaceCardVisualSpec.mediaSlotHeight, 132)
        XCTAssertEqual(PlaceCardVisualSpec.cardCornerRadius, 22)
        XCTAssertEqual(PlaceCardVisualSpec.typeSwatchSide, 14)
        XCTAssertEqual(PlaceCardVisualSpec.actionBarHorizontalPadding, 18)
        assertColor(PlaceCardVisualSpec.cardBackground, red: 0.985, green: 0.98, blue: 0.95)
        assertColor(PlaceCardVisualSpec.mediaBackground, red: 0.82, green: 0.79, blue: 0.70)
        assertColor(PlaceCardVisualSpec.neutralActionBackground, red: 0.93, green: 0.92, blue: 0.88)
        assertColor(PlaceCardVisualSpec.primaryActionBackground, red: 0.02, green: 0.46, blue: 0.39)
        assertColor(PlaceCardVisualSpec.loveActionBackground, red: 0.99, green: 0.89, blue: 0.89)
        assertColor(PlaceCardVisualSpec.warningActionBackground, red: 0.95, green: 0.91, blue: 0.82)
        assertColor(PlaceCardVisualSpec.disabledActionBackground, red: 0.96, green: 0.95, blue: 0.91)
        assertColor(PlaceCardVisualSpec.primaryText, red: 0.12, green: 0.12, blue: 0.11)
        assertColor(PlaceCardVisualSpec.secondaryText, red: 0.43, green: 0.42, blue: 0.38)
        assertColor(PlaceCardVisualSpec.linkText, red: 0.0, green: 0.43, blue: 0.37)
        assertColor(PlaceCardVisualSpec.loveText, red: 0.77, green: 0.19, blue: 0.17)
        assertColor(PlaceCardVisualSpec.warningText, red: 0.46, green: 0.34, blue: 0.12)
        assertColor(PlaceCardVisualSpec.disabledText, red: 0.68, green: 0.66, blue: 0.61)
    }

    func testPlaceCardActionTonesFollowRuledSlotsWithoutDestructiveHide() {
        XCTAssertEqual(PlaceCardVisualSpec.tone(for: .save), .neutral)
        XCTAssertEqual(PlaceCardVisualSpec.tone(for: .seen), .primary)
        XCTAssertEqual(PlaceCardVisualSpec.tone(for: .hide), .neutral)
        XCTAssertEqual(PlaceCardVisualSpec.tone(for: .love), .love)
        XCTAssertEqual(PlaceCardVisualSpec.tone(for: .unlove), .love)
        XCTAssertEqual(PlaceCardVisualSpec.tone(for: .unsee(isEnabled: true)), .warning)
        XCTAssertEqual(PlaceCardVisualSpec.tone(for: .unsee(isEnabled: false)), .disabled)
        XCTAssertEqual(PlaceCardVisualSpec.tone(for: .seenDisabled), .disabled)
        XCTAssertEqual(PlaceCardVisualSpec.tone(for: .unhide), .neutral)
    }

    func testMapHomeChromeUsesFilterGlyphAndChiplessMenuSpec() {
        XCTAssertEqual(MapHomeChromeSpec.layersSymbolName(isActive: false), "line.3.horizontal.decrease.circle")
        XCTAssertEqual(MapHomeChromeSpec.layersSymbolName(isActive: true), "line.3.horizontal.decrease.circle.fill")
        XCTAssertEqual(MapHomeChromeSpec.menuSymbolName, "line.3.horizontal")
        XCTAssertGreaterThanOrEqual(MapHomeChromeSpec.menuGlyphPointSize, 28)
        XCTAssertGreaterThanOrEqual(MapHomeChromeSpec.hitTargetSide, 44)
        XCTAssertGreaterThan(MapHomeChromeSpec.glyphHaloRadius, 0)
    }

    func testAppShellModelSeparatesMenuPresentationFromDeepLinkRouting() {
        let shell = AppShellModel()

        XCTAssertFalse(shell.isMenuPresented)
        XCTAssertNil(shell.deepLinkPath)

        shell.isMenuPresented = true
        XCTAssertTrue(shell.isMenuPresented)
        XCTAssertNil(shell.deepLinkPath)

        shell.deepLinkPath = .offlineMaps
        XCTAssertTrue(shell.isMenuPresented)
        XCTAssertEqual(shell.deepLinkPath, .offlineMaps)
    }

    func testAppShellModelCanRouteOfflineMapsDeepLink() {
        let shell = AppShellModel()

        shell.openOfflineMapsDeepLink()

        XCTAssertTrue(shell.isMenuPresented)
        XCTAssertEqual(shell.deepLinkPath, .offlineMaps)
    }

    func testAppShellModelCanRouteListsDeepLink() {
        let shell = AppShellModel()

        shell.openListsDeepLink()

        XCTAssertTrue(shell.isMenuPresented)
        XCTAssertEqual(shell.deepLinkPath, .lists)
    }

    func testAppShellModelCanRouteTracksDeepLink() {
        let shell = AppShellModel()

        shell.openTracksDeepLink()

        XCTAssertTrue(shell.isMenuPresented)
        XCTAssertEqual(shell.deepLinkPath, .tracks)
        XCTAssertNil(shell.tracksFocusPlaceID)
    }

    func testAppShellModelCanRouteTracksDeepLinkWithFocusedPlace() {
        let shell = AppShellModel()

        shell.openTracksDeepLink(focusingPlaceID: "p_repeat")

        XCTAssertTrue(shell.isMenuPresented)
        XCTAssertEqual(shell.deepLinkPath, .tracks)
        XCTAssertEqual(shell.tracksFocusPlaceID, "p_repeat")
    }

    func testAppShellModelClearsTracksFocusForNormalMenuAndOtherDeepLinks() {
        let shell = AppShellModel()
        shell.openTracksDeepLink(focusingPlaceID: "p_repeat")

        shell.openMenu()

        XCTAssertTrue(shell.isMenuPresented)
        XCTAssertNil(shell.deepLinkPath)
        XCTAssertNil(shell.tracksFocusPlaceID)

        shell.openTracksDeepLink(focusingPlaceID: "p_repeat")
        shell.openOfflineMapsDeepLink()

        XCTAssertEqual(shell.deepLinkPath, .offlineMaps)
        XCTAssertNil(shell.tracksFocusPlaceID)
    }

    func testListProgressCopyLeadsWithVisitedAndRemainingCounts() {
        XCTAssertEqual(
            ListsCopy.progress(visited: 3, total: 10),
            "you've been to 3 of these · 7 to go"
        )
        XCTAssertEqual(ListsCopy.progress(visited: 0, total: 0), "No places yet")
        XCTAssertEqual(ListsCopy.progress(visited: 2, total: 2), "you've been to 2 of these · all seen")
    }

    func testTracksCopySummarizesVisibleVisitCounts() {
        XCTAssertEqual(TracksCopy.summary(visible: 0, lovedOnly: false), "No visits yet")
        XCTAssertEqual(TracksCopy.summary(visible: 0, lovedOnly: true), "No loved visits yet")
        XCTAssertEqual(TracksCopy.summary(visible: 2, lovedOnly: false), "2 visits")
        XCTAssertEqual(TracksCopy.summary(visible: 1, lovedOnly: true), "1 visit for loved places")
    }

    func testTracksCopyLabelsSortDirection() {
        XCTAssertEqual(TracksCopy.sortDirectionLabel, "Oldest first")
    }

    func testListMapModeCopyUsesThemeSpecificFreshPhrases() {
        XCTAssertEqual(ListMapModeCopy.freshLayerTitle(theme: .snow), "Fresh snow")
        XCTAssertEqual(ListMapModeCopy.freshLayerTitle(theme: .definedPaper), "Unmarked paper")
        XCTAssertEqual(ListMapModeCopy.freshLayerTitle(theme: .streetContrast), "Open streets")
        XCTAssertEqual(ListMapModeCopy.freshLayerTitle(theme: .verdantKL), "Virgin forest")
        XCTAssertFalse(MapTheme.allCandidates.contains { theme in
            ListMapModeCopy.freshLayerTitle(theme: theme) == theme.displayName
        })
        XCTAssertEqual(ListMapModeCopy.tracksLayerTitle, "My tracks")
    }

    func testTrackTimelinePositionsAreVisitEventsNotElapsedTime() {
        let timeline = TrackTimelineModel(visits: [
            trackVisit(id: 1, seconds: 0),
            trackVisit(id: 2, seconds: 60),
            trackVisit(id: 3, seconds: 60 * 60 * 24 * 12),
        ])

        XCTAssertEqual(timeline.sliderRange, 0...2)
        XCTAssertEqual(timeline.eventIndex(forSliderValue: 0.0), 0)
        XCTAssertEqual(timeline.eventIndex(forSliderValue: 1.0), 1)
        XCTAssertEqual(timeline.eventIndex(forSliderValue: 2.0), 2)
        XCTAssertEqual(timeline.eventIndex(forSliderValue: 1.6), 2)
        XCTAssertEqual(timeline.dateMarkers.map(\.eventIndex), [0, 2])
        XCTAssertEqual(timeline.dateMarkers.map(\.position), [0, 1])
        XCTAssertEqual(timeline.dateMarkers.map(\.label), ["1 Jan", "13 Jan"])
    }

    func testTrackTimelineDateMarkersUseEventIndexPositions() {
        let timeline = TrackTimelineModel(visits: [
            trackVisit(id: 1, seconds: 0),
            trackVisit(id: 2, seconds: 60 * 60 * 24),
            trackVisit(id: 3, seconds: 60 * 60 * 24),
            trackVisit(id: 4, seconds: 60 * 60 * 24),
            trackVisit(id: 5, seconds: 60 * 60 * 24),
            trackVisit(id: 6, seconds: 60 * 60 * 24),
            trackVisit(id: 7, seconds: 60 * 60 * 24),
            trackVisit(id: 8, seconds: 60 * 60 * 24),
            trackVisit(id: 9, seconds: 60 * 60 * 24),
            trackVisit(id: 10, seconds: 60 * 60 * 24 * 2),
        ])

        XCTAssertEqual(timeline.dateMarkers.map(\.eventIndex), [0, 1, 9])
        XCTAssertEqual(timeline.dateMarkers.map(\.position), [0, 1.0 / 9.0, 1])
    }

    func testTrackTimelineAutoplayAdvancesByEventAndPulsesOnArrival() {
        let timeline = TrackTimelineModel(visits: [
            trackVisit(id: 1, seconds: 0),
            trackVisit(id: 2, seconds: 60),
            trackVisit(id: 3, seconds: 120),
        ])

        XCTAssertEqual(timeline.autoplayStep(after: nil), .event(index: 0))
        XCTAssertEqual(timeline.autoplayStep(after: 0), .event(index: 1))
        XCTAssertEqual(timeline.autoplayStep(after: 1), .event(index: 2))
        XCTAssertEqual(timeline.autoplayStep(after: 2), .finished)
        XCTAssertTrue(timeline.shouldPulseArrival(previousIndex: 0, nextIndex: 1))
        XCTAssertFalse(timeline.shouldPulseArrival(previousIndex: 1, nextIndex: 1))
    }

    func testTrackTimelineAccessibilityNamesSelectedVisitAndLovedState() {
        let timeline = TrackTimelineModel(visits: [
            trackVisit(id: 1, seconds: 0),
            trackVisit(id: 2, seconds: 60, verdict: .loved, name: "Blue Mansion"),
        ])

        XCTAssertTrue(timeline.accessibilityValue(for: 1).contains("Visit 2 of 2, Blue Mansion"))
        XCTAssertTrue(timeline.accessibilityValue(for: 1).contains("loved"))
    }

    func testTrackTimelineRequiresAtLeastTwoVisitsForInteractiveReplayControls() {
        XCTAssertFalse(TrackTimelineModel(visits: []).hasInteractiveReplayControls)
        XCTAssertFalse(TrackTimelineModel(visits: [trackVisit(id: 1, seconds: 0)]).hasInteractiveReplayControls)
        XCTAssertTrue(TrackTimelineModel(visits: [
            trackVisit(id: 1, seconds: 0),
            trackVisit(id: 2, seconds: 60),
        ]).hasInteractiveReplayControls)
    }

    func testTrackReplaySnapshotUsesEventPrefix() {
        let visits = [
            trackVisit(id: 1, seconds: 0),
            trackVisit(id: 2, seconds: 60),
            trackVisit(id: 3, seconds: 120),
        ]
        let context = TrackGeometryContext(visits: visits)
        let prefix = context.clipped(throughEventIndex: 1)
        let snapshot = TrackSourceSnapshot.make(context: prefix)

        XCTAssertEqual(prefix.visits.map(\.id), [1, 2])
        XCTAssertEqual(snapshot.segmentCount, 1)
    }

    func testTrackReplayPinsBeyondSelectedEventRenderAsUnvisitedUntilArrival() {
        let features = [
            (MapPlace(id: "p1", lat: 51.501, lon: -0.101, tier: 2, category: "history"), PinState(saved: false, visit: .visited)),
            (MapPlace(id: "p2", lat: 51.502, lon: -0.102, tier: 2, category: "history"), PinState(saved: true, visit: .loved)),
            (MapPlace(id: "p3", lat: 51.503, lon: -0.103, tier: 2, category: "history"), PinState(saved: false, visit: .visited, hidden: true)),
        ]
        let visits = [
            trackVisit(id: 1, placeID: "p1", seconds: 0),
            trackVisit(id: 2, placeID: "p2", seconds: 60, verdict: .loved),
            trackVisit(id: 3, placeID: "p3", seconds: 120),
        ]

        let replayed = TrackReplayPinPresentation.features(
            features,
            context: TrackGeometryContext(visits: visits),
            throughEventIndex: 1
        )

        XCTAssertEqual(replayed.map(\.1.visit), [.visited, .loved, .none])
        XCTAssertEqual(replayed.map(\.1.saved), [false, true, false])
        XCTAssertEqual(replayed.map(\.1.hidden), [false, false, true])
    }

    func testTrackReplayRepeatedPlaceUsesLatestReachedEventStateOnly() {
        let features = [
            (MapPlace(id: "p1", lat: 51.501, lon: -0.101, tier: 2, category: "history"), PinState(saved: false, visit: .loved)),
        ]
        let visits = [
            trackVisit(id: 1, placeID: "p1", seconds: 0, verdict: nil),
            trackVisit(id: 2, placeID: "p1", seconds: 60, verdict: .loved),
        ]
        let context = TrackGeometryContext(visits: visits)

        let firstArrival = TrackReplayPinPresentation.features(
            features,
            context: context,
            throughEventIndex: 0
        )
        let lovedArrival = TrackReplayPinPresentation.features(
            features,
            context: context,
            throughEventIndex: 1
        )

        XCTAssertEqual(firstArrival[0].1.visit, .visited)
        XCTAssertEqual(lovedArrival[0].1.visit, .loved)
    }

    func testTrackMapFeatureFilterUsesOnlyFilteredReplayContextPlaces() {
        let features = [
            (MapPlace(id: "loved", lat: 51.501, lon: -0.101, tier: 2, category: "history"), PinState(saved: false, visit: .loved)),
            (MapPlace(id: "ordinary", lat: 51.502, lon: -0.102, tier: 2, category: "history"), PinState(saved: false, visit: .visited)),
            (MapPlace(id: "repeat", lat: 51.503, lon: -0.103, tier: 2, category: "history"), PinState(saved: true, visit: .loved)),
        ]
        let context = TrackGeometryContext(
            visits: [
                trackVisit(id: 1, placeID: "loved", seconds: 0, verdict: .loved),
                trackVisit(id: 2, placeID: "repeat", seconds: 60, verdict: .loved),
                trackVisit(id: 3, placeID: "repeat", seconds: 120, verdict: .loved),
            ]
        )

        let visible = TrackMapFeatureFilter.visibleFeatures(features, context: context)

        XCTAssertEqual(visible.map(\.0.id), ["loved", "repeat"])
    }

    func testTrackReplayPulsePlaceIDsOnlyExposeCurrentArrival() {
        let context = TrackGeometryContext(
            visits: [
                trackVisit(id: 1, placeID: "p1", seconds: 0),
                trackVisit(id: 2, placeID: "p2", seconds: 60),
            ]
        )

        XCTAssertEqual(
            TrackReplayPinPresentation.pulsePlaceIDs(
                context: context,
                throughEventIndex: 1,
                isArrivalPulsing: true
            ),
            ["p2"]
        )
        XCTAssertEqual(
            TrackReplayPinPresentation.pulsePlaceIDs(
                context: context,
                throughEventIndex: 1,
                isArrivalPulsing: false
            ),
            []
        )
    }

    func testCollectionListMapDoesNotUseTrackReplayPresentationOrControls() {
        let collection = MapScreen.ActiveListMap(
            listID: 42,
            name: "KL walk",
            kind: PlaceList.defaultKind,
            visitFilter: .all,
            showVisited: true
        )
        let track = MapScreen.ActiveListMap(
            listID: 1,
            name: "My tracks",
            kind: PlaceList.trackKind,
            visitFilter: .all,
            showVisited: true
        )

        XCTAssertFalse(collection.usesTrackReplay)
        XCTAssertTrue(track.usesTrackReplay)
        XCTAssertFalse(MapScreen.TrackReplayControlVisibility.showOnMap(
            list: collection,
            timeline: TrackTimelineModel(visits: [
                trackVisit(id: 1, seconds: 0),
                trackVisit(id: 2, seconds: 60),
            ])
        ))
        XCTAssertFalse(MapScreen.TrackReplayControlVisibility.showOnMap(
            list: track,
            timeline: TrackTimelineModel(visits: [trackVisit(id: 1, seconds: 0)])
        ))
        XCTAssertTrue(MapScreen.TrackReplayControlVisibility.showOnMap(
            list: track,
            timeline: TrackTimelineModel(visits: [
                trackVisit(id: 1, seconds: 0),
                trackVisit(id: 2, seconds: 60),
            ])
        ))
    }

    func testActiveListMapFeatureFilteringUsesAnyActiveTrackVisitFilter() {
        let features: [(MapPlace, PinState)] = [
            (MapPlace(id: "kept", lat: 51.50, lon: -0.12, tier: 2, category: "history"), .init(saved: false, visit: .visited)),
            (MapPlace(id: "filtered", lat: 51.51, lon: -0.13, tier: 2, category: "history"), .init(saved: false, visit: .visited)),
        ]
        let context = TrackGeometryContext(visits: [
            trackVisit(id: 1, placeID: "kept", seconds: 0),
        ])

        XCTAssertEqual(
            ListMapFilteredFeatures.visibleFeatures(
                features,
                showVisited: true,
                visitFilter: TracksVisitFilter(listIDs: [77]),
                context: context
            ).map(\.0.id),
            ["kept"]
        )
        XCTAssertEqual(
            ListMapFilteredFeatures.visibleFeatures(
                features,
                showVisited: true,
                visitFilter: .all,
                context: context
            ).map(\.0.id),
            ["kept", "filtered"]
        )
        XCTAssertEqual(
            ListMapFilteredFeatures.visibleFeatures(
                features,
                showVisited: false,
                visitFilter: TracksVisitFilter(listIDs: [77]),
                context: context
            ).map(\.0.id),
            ["kept", "filtered"]
        )
    }

    func testListMapFilterChipsExposeActiveLovedListsAndCategories() {
        let chips = ListMapFilterChips.chips(
            for: TracksVisitFilter(
                lovedOnly: true,
                listIDs: [88, 77],
                categories: ["history", "architecture"]
            )
        )

        XCTAssertEqual(chips.map(\.title), ["Loved", "2 lists", "architecture", "history"])
        XCTAssertEqual(chips.map(\.accessibilityIdentifier), [
            "map.list-mode.filter.loved",
            "map.list-mode.filter.lists",
            "map.list-mode.filter.category.architecture",
            "map.list-mode.filter.category.history",
        ])
        XCTAssertEqual(chips.map(\.isToggle), [true, false, false, false])
    }

    func testTrackTimelineDateMarkersThinByAvailableWidth() {
        let visits = (0..<6).map { index in
            trackVisit(
                id: Int64(index + 1),
                seconds: TimeInterval(index) * 60 * 60 * 24
            )
        }
        let timeline = TrackTimelineModel(visits: visits)

        XCTAssertEqual(timeline.dateMarkers(availableWidth: 600).map(\.eventIndex), [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(timeline.dateMarkers(availableWidth: 150).map(\.eventIndex), [0, 5])
    }

    func testTrackReplayScrubPathWalksEveryEventBetweenCurrentAndTarget() {
        let timeline = TrackTimelineModel(visits: (0..<6).map {
            trackVisit(id: Int64($0 + 1), seconds: TimeInterval($0 * 60))
        })

        XCTAssertEqual(timeline.scrubEventPath(from: 1, to: 5), [2, 3, 4, 5])
        XCTAssertEqual(timeline.scrubEventPath(from: 5, to: 2), [4, 3, 2])
        XCTAssertEqual(timeline.scrubEventPath(from: nil, to: 2), [0, 1, 2])
        XCTAssertEqual(timeline.scrubEventPath(from: 2, to: 2), [2])
    }

    func testTrackReplaySnapshotCachePrecomputesEventPrefixes() {
        let context = TrackGeometryContext(
            visits: [
                trackVisit(id: 1, seconds: 0),
                trackVisit(id: 2, seconds: 60),
                trackVisit(id: 3, seconds: 120),
            ]
        )
        let cache = TrackReplaySnapshotCache(context: context)

        XCTAssertEqual(cache.snapshot(throughEventIndex: 0).segmentCount, 0)
        XCTAssertEqual(cache.snapshot(throughEventIndex: 1).segmentCount, 1)
        XCTAssertEqual(cache.snapshot(throughEventIndex: 2).segmentCount, 2)
        XCTAssertEqual(cache.snapshot(throughEventIndex: -1).segmentCount, 0)
    }

    func testTrackReplaySnapshotCacheMarksArrivingSegmentActive() throws {
        let context = TrackGeometryContext(
            visits: [
                trackVisit(id: 1, seconds: 0),
                trackVisit(id: 2, seconds: 60),
                trackVisit(id: 3, seconds: 120),
            ]
        )
        let cache = TrackReplaySnapshotCache(context: context)

        XCTAssertEqual(try trackSegmentPhases(in: cache.snapshot(throughEventIndex: 0)), [])
        XCTAssertEqual(try trackSegmentPhases(in: cache.snapshot(throughEventIndex: 1)), [TrackLayers.activeArcPhase])
        XCTAssertEqual(try trackSegmentPhases(in: cache.snapshot(throughEventIndex: 2)), ["visited", TrackLayers.activeArcPhase])
    }

    func testListMapViewportFitsAllMembersWithPadding() throws {
        let places = [
            MapPlace(id: "west", lat: 3.12, lon: 101.60, tier: 2, category: "museum"),
            MapPlace(id: "east", lat: 3.20, lon: 101.78, tier: 2, category: "museum"),
            MapPlace(id: "south", lat: 3.06, lon: 101.70, tier: 2, category: "museum"),
            MapPlace(id: "north", lat: 3.24, lon: 101.68, tier: 2, category: "museum"),
            MapPlace(id: "middle", lat: 3.16, lon: 101.69, tier: 2, category: "museum"),
        ]

        let viewport = try XCTUnwrap(ListMapViewport.viewport(for: places))

        XCTAssertLessThan(viewport.bbox.minLon, 101.60)
        XCTAssertGreaterThan(viewport.bbox.maxLon, 101.78)
        XCTAssertLessThan(viewport.bbox.minLat, 3.06)
        XCTAssertGreaterThan(viewport.bbox.maxLat, 3.24)
        for place in places {
            XCTAssertTrue(viewport.bbox.contains(lon: place.lon, lat: place.lat), place.id)
        }
    }

    func testListMapViewportFitsAntimeridianMembersWithoutWorldSpan() throws {
        let places = [
            MapPlace(id: "west", lat: 0.0, lon: 179.8, tier: 2, category: "museum"),
            MapPlace(id: "east", lat: 0.1, lon: -179.7, tier: 2, category: "museum"),
            MapPlace(id: "middle", lat: -0.1, lon: -179.9, tier: 2, category: "museum"),
        ]

        let viewport = try XCTUnwrap(ListMapViewport.viewport(for: places))

        XCTAssertLessThan(viewport.bbox.maxLon - viewport.bbox.minLon, 2.0)
        for place in places {
            XCTAssertTrue(viewport.bbox.contains(lon: place.lon, lat: place.lat), place.id)
        }
    }

    func testListMapPinPresentationTracksModeUsesFullStrengthPins() {
        XCTAssertEqual(ListMapPinPresentation.presentation(showVisited: true), .tracks)
        XCTAssertEqual(ListMapPinPresentation.presentation(showVisited: false), .discovery)
    }

    private func trackVisit(
        id: Int64,
        seconds: TimeInterval,
        verdict: Verdict? = nil,
        name: String? = nil
    ) -> TrackVisit {
        TrackVisit(
            id: id,
            placeID: "p\(id)",
            visitedAt: Date(timeIntervalSince1970: seconds),
            verdict: verdict,
            name: name ?? "Place \(id)",
            category: "history",
            tier: 2,
            lat: 51.5 + (Double(id) * 0.001),
            lon: -0.12
        )
    }

    private func trackVisit(
        id: Int64,
        placeID: String,
        seconds: TimeInterval,
        verdict: Verdict? = nil,
        name: String? = nil
    ) -> TrackVisit {
        TrackVisit(
            id: id,
            placeID: placeID,
            visitedAt: Date(timeIntervalSince1970: seconds),
            verdict: verdict,
            name: name ?? "Place \(id)",
            category: "history",
            tier: 2,
            lat: 51.5 + (Double(id) * 0.001),
            lon: -0.12
        )
    }

    private func trackSegmentPhases(in snapshot: TrackSourceSnapshot) throws -> [String] {
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: snapshot.data) as? [String: Any])
        let features = try XCTUnwrap(root["features"] as? [[String: Any]])
        return try features.map { feature in
            let properties = try XCTUnwrap(feature["properties"] as? [String: Any])
            return try XCTUnwrap(properties[TrackLayers.trackSegmentPhaseProperty] as? String)
        }
    }

    func testUpdateRequiredSurfaceBlocksOnlyFreshTooOldReaderState() throws {
        let surface = try XCTUnwrap(MapBlockingSurface.resolve(loadState: .updateRequired))

        XCTAssertEqual(surface.title, "Update required")
        XCTAssertTrue(surface.message.contains("too old to read the latest map"))
        XCTAssertEqual(surface.primaryActionTitle, "Open App Store")
        XCTAssertEqual(surface.appStoreURL.scheme, "https")
        XCTAssertEqual(surface.appStoreURL.host, "apps.apple.com")

        let nonBlockingStates: [TileLoadState] = [.ok, .stale, .updateAvailable, .offline, .manifestInvalid, .unavailable]
        for loadState in nonBlockingStates {
            XCTAssertNil(MapBlockingSurface.resolve(loadState: loadState), "\(loadState) must not block the app")
        }
    }

    func testEmptyRegionSurfaceDistinguishesUnsupportedUnavailableAndGenuineEmpty() {
        let ocean = ViewportSeed.ocean
        let london = ViewportSeed(
            bbox: BBox(minLon: -0.13, minLat: 51.48, maxLon: -0.11, maxLat: 51.50),
            zoom: 12
        )
        let wideSupported = ViewportSeed(
            bbox: BBox(minLon: -8.65, minLat: 0.85, maxLon: 119.27, maxLat: 60.86),
            zoom: 1
        )
        let place = MapPlace(id: "mt1_test", lat: 51.49, lon: -0.12, tier: 1, category: "history")

        XCTAssertEqual(
            MapEmptyRegionSurface.resolve(features: [], loadState: .ok, viewport: ocean, isFixtureMap: false),
            .unsupportedRegion
        )
        XCTAssertEqual(
            MapEmptyRegionSurface.resolve(features: [], loadState: .unavailable, viewport: ocean, isFixtureMap: false),
            .unsupportedRegion
        )
        XCTAssertEqual(
            MapEmptyRegionSurface.resolve(features: [], loadState: .unavailable, viewport: london, isFixtureMap: false),
            .mapDataUnavailable
        )
        XCTAssertEqual(
            MapEmptyRegionSurface.resolve(features: [], loadState: .ok, viewport: london, isFixtureMap: false),
            .noPlaces
        )
        XCTAssertEqual(
            MapEmptyRegionSurface.resolve(features: [], loadState: .ok, viewport: wideSupported, isFixtureMap: false),
            .noPlaces
        )
        XCTAssertNil(MapEmptyRegionSurface.resolve(
            features: [],
            loadState: .ok,
            viewport: london,
            isFixtureMap: false,
            isViewportLoading: true
        ))
        XCTAssertNil(MapEmptyRegionSurface.resolve(
            features: [],
            loadState: .manifestInvalid,
            viewport: london,
            isFixtureMap: false
        ))
        XCTAssertNil(MapEmptyRegionSurface.resolve(
            features: [(place, PinState(saved: false, visit: .none))],
            loadState: .unavailable,
            viewport: london,
            isFixtureMap: false
        ))
        XCTAssertNil(MapEmptyRegionSurface.resolve(features: [], loadState: .ok, viewport: london, isFixtureMap: true))
    }

    func testEmptyRegionSurfaceDistinguishesTrueEmptyFromThinnedEmpty() {
        let kl = ViewportSeed(
            bbox: BBox(minLon: 101.64, minLat: 3.09, maxLon: 101.74, maxLat: 3.19),
            zoom: 11
        )

        XCTAssertEqual(MapEmptyRegionSurface.resolve(
            features: [],
            sourceFeatureCount: 0,
            loadState: .ok,
            viewport: kl,
            isFixtureMap: false
        ), .noPlaces)
        XCTAssertNil(MapEmptyRegionSurface.resolve(
            features: [],
            sourceFeatureCount: 1,
            loadState: .ok,
            viewport: kl,
            isFixtureMap: false
        ))
    }

    func testEmptyRegionNoPlacesCopyUsesPublishedRegionNames() {
        XCTAssertEqual(
            MapEmptyRegionSurface.noPlaces.message,
            "Try another part of Malaysia, Singapore, and Brunei or United Kingdom."
        )
        XCTAssertFalse(MapEmptyRegionSurface.noPlaces.message.contains("UK or Malaysia"))
    }

    func testMapDataUnavailableSurfaceUsesNeutralCopyAndOfflineMapsAffordance() throws {
        let surface = MapEmptyRegionSurface.mapDataUnavailable

        XCTAssertEqual(surface.title, "Map data unavailable")
        XCTAssertTrue(surface.message.contains("Check your connection"))
        XCTAssertEqual(surface.primaryActionTitle, "Offline maps")
        XCTAssertNil(MapEmptyRegionSurface.unsupportedRegion.primaryActionTitle)
        XCTAssertNil(MapEmptyRegionSurface.noPlaces.primaryActionTitle)
    }

    func testDatabaseStartupFailurePreservesHistoryAndSurfacesRecoveryState() {
        let result = DatabaseStartupPolicy.open(
            fixture: false,
            resetFixtureStore: {},
            openFixtureStore: { throw AppDatabaseError.unreadableDatabase },
            openLiveStore: { throw AppDatabaseError.unreadableDatabase },
            seedFixtureUserList: nil
        )

        guard case .failed(let surface) = result else {
            return XCTFail("expected startup failure surface")
        }
        XCTAssertEqual(surface.title, "History recovery needed")
        XCTAssertEqual(surface.reasonLabel, "database-unavailable")
        XCTAssertTrue(surface.message.contains("saved places, lists, and visits have not been erased"))
        XCTAssertTrue(surface.recoveryHint.contains("Do not delete or reinstall"))
        XCTAssertFalse(surface.recoveryHint.contains("Update Making Tracks"))
    }

    func testDatabaseStartupFailureForNewerDatabaseTellsUserToUpdate() {
        let result = DatabaseStartupPolicy.open(
            fixture: false,
            resetFixtureStore: {},
            openFixtureStore: { throw AppDatabaseError.unreadableDatabase },
            openLiveStore: { throw AppDatabaseError.databaseFromNewerAppVersion(unknown: ["v99"]) },
            seedFixtureUserList: nil
        )

        guard case .failed(let surface) = result else {
            return XCTFail("expected startup failure surface")
        }
        XCTAssertEqual(surface.reasonLabel, "database-from-newer-app-version")
        XCTAssertTrue(surface.message.contains("newer app version"))
        XCTAssertTrue(surface.recoveryHint.contains("Update Making Tracks"))
    }

    func testListMapFeatureFilterKeepsHiddenMembersAndFiltersOnlyVisitedState() {
        let fresh = MapPlace(id: "fresh", lat: 51.49, lon: -0.12, tier: 1, category: "history")
        let visited = MapPlace(id: "visited", lat: 51.50, lon: -0.13, tier: 2, category: "museum")
        let hiddenFresh = MapPlace(id: "hidden-fresh", lat: 51.51, lon: -0.14, tier: 2, category: "artwork")
        let hiddenVisited = MapPlace(id: "hidden-visited", lat: 51.52, lon: -0.15, tier: 3, category: "viewpoint")
        let features = [
            (fresh, PinState(saved: false, visit: .none, hidden: false)),
            (visited, PinState(saved: false, visit: .visited, hidden: false)),
            (hiddenFresh, PinState(saved: false, visit: .none, hidden: true)),
            (hiddenVisited, PinState(saved: false, visit: .loved, hidden: true)),
        ]

        XCTAssertEqual(
            ListMapFeatureFilter.visibleFeatures(features, showVisited: false).map(\.0.id),
            ["fresh", "hidden-fresh"]
        )
        XCTAssertEqual(
            ListMapFeatureFilter.visibleFeatures(features, showVisited: true).map(\.0.id),
            ["fresh", "visited", "hidden-fresh", "hidden-visited"]
        )
    }

    func testListDetailRowsBlockStoredMembershipRemovalButAllowTrackVisitEditing() {
        let collection = PlaceList(id: 10, name: "Date night", isSystem: false, createdAt: Date(timeIntervalSince1970: 0))
        let wantToGo = PlaceList(id: 1, name: "Want to go", isSystem: true, createdAt: Date(timeIntervalSince1970: 0))
        let myTracks = PlaceList(
            id: 2,
            name: "My tracks",
            isSystem: true,
            kind: PlaceList.trackKind,
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let importedTrackKind = PlaceList(
            id: 42,
            name: "Imported",
            isSystem: false,
            kind: PlaceList.trackKind,
            createdAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertTrue(ListDetailItemActions.canRemoveStoredMembership(from: collection))
        XCTAssertTrue(ListDetailItemActions.canRemoveStoredMembership(from: wantToGo))
        XCTAssertFalse(ListDetailItemActions.canRemoveStoredMembership(from: myTracks))
        XCTAssertTrue(ListDetailItemActions.canRemoveStoredMembership(from: importedTrackKind))
        XCTAssertFalse(ListDetailVisitActions.canEditTrackVisits(from: collection))
        XCTAssertFalse(ListDetailVisitActions.canEditTrackVisits(from: wantToGo))
        XCTAssertTrue(ListDetailVisitActions.canEditTrackVisits(from: myTracks))
        XCTAssertFalse(ListDetailVisitActions.canEditTrackVisits(from: importedTrackKind))
    }

    func testListMapCategoryVisibilityIgnoresDiscoveryCategoryToggles() {
        XCTAssertNil(
            ListMapCategoryVisibility.visibleCategories(
                discoveryVisibleCategories: ["history"],
                isListMapActive: true
            )
        )
        XCTAssertEqual(
            ListMapCategoryVisibility.visibleCategories(
                discoveryVisibleCategories: ["history"],
                isListMapActive: false
            ),
            ["history"]
        )
    }

    func testViewportRefreshTrackerSuppressesEmptySurfaceUntilLatestRefreshCompletes() {
        var tracker = ViewportRefreshTracker()
        let london = ViewportSeed(
            bbox: BBox(minLon: -0.13, minLat: 51.48, maxLon: -0.11, maxLat: 51.50),
            zoom: 12
        )

        let firstRequestID = tracker.nextRequestID()
        let secondRequestID = tracker.nextRequestID()

        XCTAssertTrue(tracker.isLoading)
        XCTAssertNil(MapEmptyRegionSurface.resolve(
            features: [],
            loadState: .ok,
            viewport: london,
            isFixtureMap: false,
            isViewportLoading: tracker.isLoading
        ))

        tracker.complete(requestID: firstRequestID)
        XCTAssertTrue(tracker.isLoading)

        tracker.complete(requestID: secondRequestID)
        XCTAssertFalse(tracker.isLoading)
        XCTAssertEqual(MapEmptyRegionSurface.resolve(
            features: [],
            loadState: .ok,
            viewport: london,
            isFixtureMap: false,
            isViewportLoading: tracker.isLoading
        ), .noPlaces)
    }

    @MainActor
    func testThemeStorageUsesStableKeyAndDefinedPaperDefault() {
        XCTAssertEqual(MapScreen.themeStorageKey, "map.theme.id")
        XCTAssertEqual(MapScreen.pinSizeMultiplierStorageKey, "map.pinSize.multiplier")
        XCTAssertEqual(MapScreen.coverageShadingStorageKey, "map.coverageShading.visible")
        XCTAssertEqual(MapTheme.named(nil).id, MapTheme.definedPaper.id)
        XCTAssertEqual(MapTheme.named("defined-paper").displayName, "Defined Paper")
    }

    func testPinSizePreviewMetricsUseSharedPinSizeMath() {
        let pinSize = PinSize(multiplier: 1.4)
        let metrics = PinSizePreviewMetrics(pinSize: pinSize)

        XCTAssertEqual(metrics.circleDiameter, pinSize.circleRadius * 2)
        XCTAssertEqual(metrics.categoryIconScale, pinSize.categoryIconScale)
        XCTAssertEqual(metrics.badgeIconScale, pinSize.badgeIconScale)
    }

    func testSettingsStorageNavigationTargetsOfflineMaps() {
        XCTAssertEqual(SettingsStorageNavigation.destination, .offlineMaps)
    }

    func testOfflineDownloadProgressBoundsInvalidFractions() {
        XCTAssertEqual(OfflineDownloadProgress(fractionComplete: .nan).percentComplete, 0)
        XCTAssertEqual(OfflineDownloadProgress(fractionComplete: .infinity).percentComplete, 0)
        XCTAssertEqual(OfflineDownloadProgress(fractionComplete: -.infinity).percentComplete, 0)
        XCTAssertEqual(OfflineDownloadProgress(fractionComplete: -0.25).percentComplete, 0)
        XCTAssertEqual(OfflineDownloadProgress(fractionComplete: 1.25).percentComplete, 100)
    }

    func testOfflineDownloadProgressDoesNotRoundActiveDownloadsUpToComplete() {
        let progress = OfflineDownloadProgress(fractionComplete: 0.996)

        XCTAssertEqual(progress.percentComplete, 99)
    }

    func testOfflineDownloadProgressWithZeroTotalBytesIsNotComplete() {
        let progress = OfflineDownloadProgress(
            region: "malaysia-singapore-brunei",
            completedBytes: 0,
            totalBytes: 0,
            fractionComplete: 1
        )

        XCTAssertEqual(progress.percentComplete, 0)
        XCTAssertFalse(progress.isComplete)
    }

    func testOnboardingStorageUsesFoldedDesignKeys() {
        XCTAssertEqual(OnboardingStorage.hasCompletedOnboardingKey, "hasCompletedOnboarding")
        XCTAssertEqual(OnboardingStorage.chosenRegionKey, "chosenRegion")
        XCTAssertEqual(OfflineDownloadSettings.allowsCellularDownloadsKey, "offline.downloads.allow-cellular")
        XCTAssertFalse(OfflineDownloadSettings.defaultAllowsCellularDownloads)
    }

    func testChosenRegionDrivesStartupSeedUnlessUITestArgumentOverrides() {
        XCTAssertEqual(OnboardingRegionChoice.uk.startupViewport, .uk)
        XCTAssertEqual(OnboardingRegionChoice.malaysia.startupViewport, .kl)
        XCTAssertEqual(OnboardingRegionChoice.uk.publishRegionID, MapRegion.unitedKingdom.rawValue)
        XCTAssertEqual(OnboardingRegionChoice.malaysia.publishRegionID, MapRegion.malaysiaSingaporeBrunei.rawValue)
        XCTAssertEqual(
            OnboardingStorage.startupViewport(argumentSeed: nil, chosenRegionRawValue: "uk"),
            .uk
        )
        XCTAssertEqual(
            OnboardingStorage.startupViewport(argumentSeed: nil, chosenRegionRawValue: "malaysia"),
            .kl
        )
        XCTAssertEqual(
            OnboardingStorage.startupViewport(argumentSeed: "ocean", chosenRegionRawValue: "uk"),
            .ocean
        )
        XCTAssertEqual(
            OnboardingStorage.startupViewport(argumentSeed: "penang", chosenRegionRawValue: "uk"),
            .penang
        )
        XCTAssertEqual(
            OnboardingStorage.startupViewport(argumentSeed: "penang-wide", chosenRegionRawValue: "uk"),
            .penangWide
        )
        XCTAssertEqual(
            OnboardingStorage.startupViewport(argumentSeed: "penang-mid", chosenRegionRawValue: "uk"),
            .penangMid
        )
        XCTAssertEqual(
            OnboardingStorage.startupViewport(argumentSeed: "kl-mid", chosenRegionRawValue: "uk"),
            .klMid
        )
        XCTAssertEqual(ViewportSeed.klMid.bbox, ViewportSeed.kl.bbox)
        XCTAssertEqual(ViewportSeed.klMid.zoom, 13)
        XCTAssertEqual(ViewportSeed.penang.bbox, BBox(minLon: 100.282, minLat: 5.440, maxLon: 100.306, maxLat: 5.464))
        XCTAssertEqual(ViewportSeed.penang.zoom, 14)
        XCTAssertEqual(ViewportSeed.penangWide.bbox, BBox(minLon: 100.264, minLat: 5.422, maxLon: 100.324, maxLat: 5.482))
        XCTAssertEqual(ViewportSeed.penangWide.zoom, 12)
        XCTAssertEqual(ViewportSeed.penangMid.bbox, BBox(minLon: 100.276, minLat: 5.434, maxLon: 100.312, maxLat: 5.470))
        XCTAssertEqual(ViewportSeed.penangMid.zoom, 13)
    }

    func testOnboardingCopyMatchesPrivacyPolicyQualifierAndDoesNotExposeImageToggle() {
        XCTAssertEqual(
            OnboardingCopy.savedActivityPrivacy,
            "Nothing you save leaves unless you choose to share it."
        )
        XCTAssertFalse(OnboardingCopy.offlinePackOffer.contains("no one can see where you look"))
        XCTAssertFalse(OnboardingCopy.offlinePackOffer.localizedCaseInsensitiveContains("images"))
    }

    func testReplayPreselectsExistingRegionButTrueFirstRunDoesNot() {
        XCTAssertNil(OnboardingFlowState.initialSelectedRegion(isReplay: false, chosenRegionRawValue: "uk"))
        XCTAssertEqual(OnboardingFlowState.initialSelectedRegion(isReplay: true, chosenRegionRawValue: "uk"), .uk)
        XCTAssertEqual(OnboardingFlowState.initialSelectedRegion(isReplay: true, chosenRegionRawValue: "malaysia"), .malaysia)
        XCTAssertNil(OnboardingFlowState.initialSelectedRegion(isReplay: true, chosenRegionRawValue: "not-a-region"))
    }

    @MainActor
    func testLocationPermissionRequestIsOneShotAndExplicit() {
        let manager = AppLocationManager(simulatedAuthorizationStatus: .notDetermined)
        let permission = LocationPermission(manager: manager)

        XCTAssertEqual(manager.whenInUseAuthorizationRequestCount, 0)
        XCTAssertEqual(permission.authorizationRequestCount, 0)

        permission.requestWhenInUseIfNeeded()
        permission.requestWhenInUseIfNeeded()

        XCTAssertEqual(manager.whenInUseAuthorizationRequestCount, 1)
        XCTAssertEqual(permission.authorizationRequestCount, 1)
    }

    @MainActor
    func testMapCameraRequestIsConsumedOnce() {
        let coordinator = makeCoordinator()

        XCTAssertTrue(coordinator.consumeCameraRequest(1))
        XCTAssertFalse(coordinator.consumeCameraRequest(1))
        XCTAssertTrue(coordinator.consumeCameraRequest(2))
    }

    func testOfflineDownloadProgressCarriesDownloaderBytes() {
        let progress = OfflineDownloadProgress(OfflineRegionDownloadProgress(
            region: "uk",
            publishVersion: "20260717T000000Z",
            completedBytes: 25,
            totalBytes: 100,
            completedObjectCount: 1,
            totalObjectCount: 4
        ))

        XCTAssertEqual(progress.region, "uk")
        XCTAssertEqual(progress.completedBytes, 25)
        XCTAssertEqual(progress.totalBytes, 100)
        XCTAssertEqual(progress.percentComplete, 25)
    }

    @MainActor
    func testOfflineDownloadSessionKeepsProgressFloorAcrossRestart() {
        let session = OfflineRegionDownloadSession()

        session.begin(region: "uk", control: OfflineRegionDownloadControl(), downloadID: UUID())
        session.update(OfflineDownloadProgress(region: "uk", fractionComplete: 0.6))
        session.pause(region: "uk")
        session.begin(region: "uk", control: OfflineRegionDownloadControl(), downloadID: UUID())
        session.update(OfflineDownloadProgress(region: "uk", fractionComplete: 0.2))

        XCTAssertEqual(session.liveProgress?.fractionComplete, 0.6)

        session.update(OfflineDownloadProgress(region: "uk", fractionComplete: 0.8))
        XCTAssertEqual(session.liveProgress?.fractionComplete, 0.8)
    }

    @MainActor
    func testOfflineDownloadSessionDoesNotFloorByteProgressBehindZeroTotalMetadataProgress() {
        let session = OfflineRegionDownloadSession()

        session.begin(region: "malaysia-singapore-brunei", control: OfflineRegionDownloadControl(), downloadID: UUID())
        session.update(OfflineDownloadProgress(
            region: "malaysia-singapore-brunei",
            completedBytes: 0,
            totalBytes: 0,
            fractionComplete: 1
        ))
        session.update(OfflineDownloadProgress(
            region: "malaysia-singapore-brunei",
            completedBytes: 23_300_000,
            totalBytes: 233_000_000,
            fractionComplete: 0.1
        ))

        XCTAssertEqual(session.liveProgress?.percentComplete, 10)
        XCTAssertEqual(session.liveProgress?.completedBytes, 23_300_000)
        XCTAssertEqual(session.liveProgress?.totalBytes, 233_000_000)
    }

    func testOfflineInstall404UsesUnavailableAreaCopy() {
        XCTAssertEqual(
            offlineInstallFailureMessage(for: TileError.httpStatus(404)),
            "This area isn't available yet"
        )
        XCTAssertEqual(
            offlineInstallFailureDetail(for: TileError.httpStatus(404)),
            "http-404"
        )
    }

    func testOfflineDownloadProgressSurfacesConnectivityWaitingState() {
        let progress = OfflineDownloadProgress(
            region: "united-kingdom_london",
            publishVersion: "20260718T000000Z",
            completedBytes: 0,
            totalBytes: 100,
            fractionComplete: 0,
            isWaitingForConnectivity: true
        )
        let row = OfflineRegionCatalogRow(
            zone: OfflineRegionCatalog.debugFixture.zone(id: "united-kingdom_london")!,
            depth: 1,
            state: .downloading(progress)
        )

        XCTAssertEqual(progress.statusText, "Waiting for Wi-Fi")
        XCTAssertEqual(row.statusLabel, "Waiting for Wi-Fi")
    }

    func testOnboardingDownloadStateSurfacesWaitingForWiFi() {
        let plan = OnboardingDownloadPlan(
            region: .malaysia,
            bytesToFetch: 100,
            availableBytes: 10_000_000_000,
            hasHeadroom: true,
            fetchedBytes: 0
        )

        XCTAssertEqual(
            OnboardingDownloadState.downloading(plan, fetchedBytes: 0, isWaitingForConnectivity: true).statusText,
            "Waiting for Wi-Fi"
        )
    }

    func testOfflineDownloadCancelTreatsActiveLeaseAsCancellationSuccess() {
        XCTAssertEqual(
            offlineDownloadCancelMessage {
                throw TileError.downloadAlreadyInProgress
            },
            "Download cancelled"
        )
    }

    @MainActor
    func testDeferredReplaySessionRegistersActiveControlBeforeProgressAppears() {
        let session = OfflineRegionDownloadSession()
        let control = OfflineRegionDownloadControl()
        let downloadID = UUID()
        let progress = OfflineDownloadProgress(region: "uk", publishVersion: "20260717T000000Z", completedBytes: 25, totalBytes: 100, fractionComplete: 0.25)

        XCTAssertTrue(session.beginDeferredReplay(region: "uk", control: control, downloadID: downloadID))

        XCTAssertTrue(session.activeControl === control)
        XCTAssertEqual(session.activeDownloadID, downloadID)
        XCTAssertEqual(session.liveProgress?.region, "uk")
        XCTAssertEqual(session.liveProgress?.completedBytes, 0)
        XCTAssertNil(session.pausedProgress)

        session.updateDeferredReplay(progress: progress, downloadID: downloadID)

        XCTAssertEqual(session.liveProgress?.region, "uk")
        XCTAssertEqual(session.liveProgress?.completedBytes, 25)
        XCTAssertNil(session.pausedProgress)
    }

    @MainActor
    func testDeferredReplaySessionRefusesToStealActiveUserDownload() {
        let session = OfflineRegionDownloadSession()
        let userControl = OfflineRegionDownloadControl()
        let userDownloadID = UUID()
        session.begin(region: "uk", control: userControl, downloadID: userDownloadID)

        let replayControl = OfflineRegionDownloadControl()

        XCTAssertFalse(session.beginDeferredReplay(region: "uk", control: replayControl, downloadID: UUID()))
        XCTAssertTrue(session.activeControl === userControl)
        XCTAssertEqual(session.activeDownloadID, userDownloadID)
    }

    @MainActor
    func testDeferredReplayPausePreservesResumableProgress() {
        let session = OfflineRegionDownloadSession()
        let control = OfflineRegionDownloadControl()
        let downloadID = UUID()
        let progress = OfflineDownloadProgress(region: "uk", publishVersion: "20260717T000000Z", completedBytes: 25, totalBytes: 100, fractionComplete: 0.25)

        XCTAssertTrue(session.beginDeferredReplay(region: "uk", control: control, downloadID: downloadID))
        session.updateDeferredReplay(progress: progress, downloadID: downloadID)
        session.pauseDeferredReplay(region: "uk", downloadID: downloadID)

        XCTAssertNil(session.liveProgress)
        XCTAssertNil(session.chromeProgress)
        XCTAssertEqual(session.pausedProgress, progress)
        XCTAssertEqual(session.rowProgress, progress)
        XCTAssertNil(session.activeControl)
        XCTAssertNil(session.activeTask)
    }

    @MainActor
    func testDeferredReplayPauseIgnoresStaleReplayID() {
        let session = OfflineRegionDownloadSession()
        let userControl = OfflineRegionDownloadControl()
        let userDownloadID = UUID()
        let progress = OfflineDownloadProgress(region: "uk", fractionComplete: 0.42)
        session.begin(region: "uk", control: userControl, downloadID: userDownloadID)
        session.update(progress)

        session.pauseDeferredReplay(region: "uk", downloadID: UUID())

        XCTAssertEqual(session.liveProgress, progress)
        XCTAssertNil(session.pausedProgress)
        XCTAssertTrue(session.activeControl === userControl)
        XCTAssertEqual(session.activeDownloadID, userDownloadID)
    }

    @MainActor
    func testPausedDeferredReplayBlocksAnotherDeferredReplayRegion() {
        let session = OfflineRegionDownloadSession()
        let downloadID = UUID()
        XCTAssertTrue(session.beginDeferredReplay(region: "uk", control: OfflineRegionDownloadControl(), downloadID: downloadID))
        session.updateDeferredReplay(
            progress: OfflineDownloadProgress(region: "uk", fractionComplete: 0.42),
            downloadID: downloadID
        )
        session.pauseDeferredReplay(region: "uk", downloadID: downloadID)

        XCTAssertFalse(session.canBegin(region: "malaysia"))
    }

    func testStartupAndEarlyCameraIdleSuppressManifestRefreshUntilPostFirstRenderRefreshCompletes() {
        XCTAssertFalse(MapManifestRefreshPolicy.startupAllowsManifestRefresh)
        XCTAssertFalse(MapManifestRefreshPolicy.cameraIdleAllowsManifestRefresh(afterPostFirstRenderRefreshCompleted: false))
        XCTAssertTrue(MapManifestRefreshPolicy.cameraIdleAllowsManifestRefresh(afterPostFirstRenderRefreshCompleted: true))
        XCTAssertTrue(MapManifestRefreshPolicy.mapLoadFailureAllowsManifestRefresh(afterPostFirstRenderRefreshCompleted: false))
        XCTAssertFalse(MapManifestRefreshPolicy.mapLoadFailureAllowsManifestRefresh(afterPostFirstRenderRefreshCompleted: true))
    }

    func testDeferredOfflineMaintenanceCanRunAfterMapLoadFailureWhenProtectedDataIsAvailable() {
        XCTAssertTrue(MapDeferredOfflineMaintenancePolicy.allowsDeferredMaintenance(
            isMapReady: false,
            didMapLoadFail: true,
            didScheduleMaintenance: false,
            isProtectedDataAvailable: true,
            hasPausedDownload: false,
            hasActiveDownload: false
        ))
        XCTAssertTrue(MapDeferredOfflineMaintenancePolicy.allowsDeferredMaintenance(
            isMapReady: true,
            didMapLoadFail: false,
            didScheduleMaintenance: false,
            isProtectedDataAvailable: true,
            hasPausedDownload: false,
            hasActiveDownload: false
        ))
        XCTAssertFalse(MapDeferredOfflineMaintenancePolicy.allowsDeferredMaintenance(
            isMapReady: false,
            didMapLoadFail: false,
            didScheduleMaintenance: false,
            isProtectedDataAvailable: true,
            hasPausedDownload: false,
            hasActiveDownload: false
        ))
        XCTAssertFalse(MapDeferredOfflineMaintenancePolicy.allowsDeferredMaintenance(
            isMapReady: false,
            didMapLoadFail: true,
            didScheduleMaintenance: true,
            isProtectedDataAvailable: true,
            hasPausedDownload: false,
            hasActiveDownload: false
        ))
        XCTAssertFalse(MapDeferredOfflineMaintenancePolicy.allowsDeferredMaintenance(
            isMapReady: false,
            didMapLoadFail: true,
            didScheduleMaintenance: false,
            isProtectedDataAvailable: false,
            hasPausedDownload: false,
            hasActiveDownload: false
        ))
        XCTAssertFalse(MapDeferredOfflineMaintenancePolicy.allowsDeferredMaintenance(
            isMapReady: true,
            didMapLoadFail: false,
            didScheduleMaintenance: false,
            isProtectedDataAvailable: true,
            hasPausedDownload: true,
            hasActiveDownload: false
        ))
        XCTAssertFalse(MapDeferredOfflineMaintenancePolicy.allowsDeferredMaintenance(
            isMapReady: true,
            didMapLoadFail: false,
            didScheduleMaintenance: false,
            isProtectedDataAvailable: true,
            hasPausedDownload: false,
            hasActiveDownload: true
        ))
    }

    func testMapLoadingPlaceholderUsesOpaqueDefinedPaperBackground() {
        let color = MapThemeColor.uiColor(hex: MapTheme.definedPaper.background)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        XCTAssertEqual(Int(round(red * 255)), 0xF3)
        XCTAssertEqual(Int(round(green * 255)), 0xEF)
        XCTAssertEqual(Int(round(blue * 255)), 0xE5)
        XCTAssertEqual(alpha, 1)

        let fallback = MapThemeColor.uiColor(hex: "not-a-color")
        XCTAssertTrue(fallback.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        XCTAssertEqual(Int(round(red * 255)), 0xF3)
        XCTAssertEqual(Int(round(green * 255)), 0xEF)
        XCTAssertEqual(Int(round(blue * 255)), 0xE5)
        XCTAssertEqual(alpha, 1)
    }

    func testStorageMenuStatusUsesStableRowsAndByteFormatting() {
        let status = StorageMenuStatus.ready(
            totalBytes: 2_097_152,
            regions: [
                StorageMenuRegion(region: "uk_london", publishVersion: "20260716T155409Z", bytes: 1_572_864, tileCount: 12),
                StorageMenuRegion(region: "uk", publishVersion: "20260716T155409Z", bytes: 524_288, tileCount: 4),
            ]
        )

        XCTAssertEqual(status.totalBytesText, "2.1 MB")
        XCTAssertEqual(status.regions.map(\.region), ["uk", "uk_london"])
        XCTAssertEqual(status.regions.map(\.title), ["uk", "uk_london"])
        XCTAssertEqual(status.regions.map(\.detail), [
            "20260716T155409Z · 4 tiles",
            "20260716T155409Z · 12 tiles",
        ])
        XCTAssertEqual(status.regions.map(\.bytesText), ["524 KB", "1.6 MB"])
        XCTAssertEqual(status.failedRegions, [])
    }

    func testStorageMenuStatusTreatsEmptyStoreAsReady() {
        let status = StorageMenuStatus.ready(from: OfflinePackStorageSummary(packs: [], failedRegions: [], totalBytes: 0))

        XCTAssertEqual(status.kind, .ready)
        XCTAssertEqual(status.totalBytesText, "Zero KB")
        XCTAssertEqual(status.regions, [])
        XCTAssertEqual(status.failedRegions, [])
    }

    func testOfflineRegionCatalogDerivesRowsFromDecodedRegionIndex() throws {
        let catalog = OfflineRegionCatalog(regionIndex: try RegionIndex.decode(appJSONData(appRegionIndexV3Object())))

        XCTAssertEqual(catalog.rootZones.map(\.id), ["malaysia-singapore-brunei"])
        XCTAssertEqual(catalog.children(of: "malaysia-singapore-brunei").map(\.id), ["malaysia-singapore-brunei_kl"])
        XCTAssertEqual(catalog.zone(id: "malaysia-singapore-brunei")?.sizeLabel(includeThumbnails: false), "229 MB")
        XCTAssertEqual(catalog.zone(id: "malaysia-singapore-brunei_kl")?.sizeLabel(includeThumbnails: true), "41 MB")
        XCTAssertNil(catalog.zone(id: "not-a-zone"))

        let rows = catalog.rows(
            installed: [:],
            availablePublishVersions: [
                "malaysia-singapore-brunei": "20260719T125813Z",
                "malaysia-singapore-brunei_kl": "20260719T125813Z",
            ],
            activeProgress: nil,
            quarantines: []
        )
        XCTAssertEqual(rows.map(\.zone.id), ["malaysia-singapore-brunei", "malaysia-singapore-brunei_kl"])
        XCTAssertEqual(rows.map(\.state), [.notInstalled, .notInstalled])
    }

    func testOfflineRegionRowsSurfaceProgressUpdatesAndQuarantines() {
        let catalog = OfflineRegionCatalog.debugFixture
        let progress = OfflineDownloadProgress(
            region: "united-kingdom",
            publishVersion: "20260718T000000Z",
            completedBytes: 50,
            totalBytes: 100,
            fractionComplete: 0.5
        )
        let quarantine = OfflinePackQuarantine(
            region: "malaysia-singapore-brunei",
            publishVersion: "20260717T000000Z",
            coordinates: [TileCoordinate(z: 10, x: 806, y: 503)]
        )

        let rows = catalog.rows(
            installed: [
                "united-kingdom": "20260718T000000Z",
                "united-kingdom_london": "20260717T000000Z",
                "united-kingdom_south_east": "20260717T000000Z",
                "malaysia-singapore-brunei_kl": "20260717T000000Z",
            ],
            activeProgress: progress,
            quarantines: [quarantine]
        )
        let uk = rows.first { $0.zone.id == "united-kingdom" }
        let london = rows.first { $0.zone.id == "united-kingdom_london" }
        let southEast = rows.first { $0.zone.id == "united-kingdom_south_east" }
        let malaysia = rows.first { $0.zone.id == "malaysia-singapore-brunei" }
        let kl = rows.first { $0.zone.id == "malaysia-singapore-brunei_kl" }

        XCTAssertEqual(uk?.state, .downloading(progress))
        XCTAssertEqual(london?.state, .installed(publishVersion: "20260717T000000Z"))
        XCTAssertEqual(southEast?.state, .installed(publishVersion: "20260717T000000Z"))
        XCTAssertEqual(malaysia?.state, .quarantined(quarantine))
        XCTAssertEqual(kl?.state, .installed(publishVersion: "20260717T000000Z"))
        XCTAssertEqual(london?.depth, 1)
        XCTAssertEqual(southEast?.statusLabel, "Downloaded")
        XCTAssertEqual(malaysia?.statusLabel, "Quarantined pack")
        XCTAssertEqual(kl?.statusLabel, "Downloaded")
        XCTAssertFalse(kl?.hasUnavailableLocalData == true)
    }

    func testOfflineRegionRowsLabelCompleteActiveProgressAsInstalling() {
        let catalog = OfflineRegionCatalog.debugFixture
        let progress = OfflineDownloadProgress(
            region: "malaysia-singapore-brunei",
            publishVersion: "20260719T125813Z",
            completedBytes: 223_400_000,
            totalBytes: 223_400_000,
            fractionComplete: 1
        )

        let rows = catalog.rows(installed: [:], activeProgress: progress, quarantines: [])
        let malaysia = rows.first { $0.zone.id == "malaysia-singapore-brunei" }

        XCTAssertEqual(malaysia?.statusLabel, "Installing")
        XCTAssertEqual(malaysia?.sizeLabel(includeThumbnails: false), "223.4 MB")
    }

    func testOfflineRegionRowsDoNotRoundDisplayedActiveProgressUpToComplete() {
        let catalog = OfflineRegionCatalog.debugFixture
        let progress = OfflineDownloadProgress(
            region: "malaysia-singapore-brunei",
            fractionComplete: 0.996
        )

        let rows = catalog.rows(installed: [:], activeProgress: progress, quarantines: [])
        let malaysia = rows.first { $0.zone.id == "malaysia-singapore-brunei" }

        XCTAssertEqual(malaysia?.statusLabel, "Downloading 99%")
    }

    func testOfflineRegionRowsDoNotTreatZeroByteActiveProgressAsInstalling() {
        let catalog = OfflineRegionCatalog.debugFixture
        let progress = OfflineDownloadProgress(
            region: "malaysia-singapore-brunei",
            completedBytes: 0,
            totalBytes: 0,
            fractionComplete: 1
        )

        let rows = catalog.rows(installed: [:], activeProgress: progress, quarantines: [])
        let malaysia = rows.first { $0.zone.id == "malaysia-singapore-brunei" }

        XCTAssertEqual(malaysia?.statusLabel, "Downloading 0%")
        XCTAssertEqual(malaysia?.sizeLabel(includeThumbnails: false), "1.4 GB")
    }

    func testOfflineRegionRowsUseAvailableCatalogBytesBeforeDownloadStarts() {
        let catalog = OfflineRegionCatalog.debugFixture

        let rows = catalog.rows(
            installed: [:],
            availablePublishVersions: ["malaysia-singapore-brunei": "20260718T000000Z"],
            availableStorageBytes: ["malaysia-singapore-brunei": 233_000_000],
            activeProgress: nil,
            quarantines: []
        )
        let malaysia = rows.first { $0.zone.id == "malaysia-singapore-brunei" }

        XCTAssertEqual(malaysia?.state, .notInstalled)
        XCTAssertEqual(malaysia?.sizeLabel(includeThumbnails: false), "233 MB")
    }

    func testOfflineRegionRowsOfferCatalogSubregionDownloads() {
        let catalog = OfflineRegionCatalog.debugFixture
        let quarantine = OfflinePackQuarantine(
            region: "malaysia-singapore-brunei_kl",
            publishVersion: "20260717T000000Z",
            coordinates: [TileCoordinate(z: 10, x: 806, y: 503)]
        )

        let rows = catalog.rows(
            installed: [
                "united-kingdom_london": "20260717T000000Z",
                "malaysia-singapore-brunei_kl": "20260717T000000Z",
            ],
            availablePublishVersions: [
                "united-kingdom": "20260718T000000Z",
                "united-kingdom_london": "20260718T000000Z",
                "malaysia-singapore-brunei": "20260718T000000Z",
                "malaysia-singapore-brunei_kl": "20260718T000000Z",
            ],
            activeProgress: OfflineDownloadProgress(region: "united-kingdom_london", fractionComplete: 0.25),
            pausedProgress: OfflineDownloadProgress(region: "malaysia-singapore-brunei_kl", fractionComplete: 0.5),
            quarantines: [quarantine]
        )

        XCTAssertEqual(rows.first { $0.zone.id == "united-kingdom" }?.state, .notInstalled)
        XCTAssertEqual(rows.first { $0.zone.id == "malaysia-singapore-brunei" }?.state, .notInstalled)
        XCTAssertEqual(rows.first { $0.zone.id == "united-kingdom_london" }?.state, .downloading(OfflineDownloadProgress(region: "united-kingdom_london", fractionComplete: 0.25)))
        XCTAssertEqual(rows.first { $0.zone.id == "malaysia-singapore-brunei_kl" }?.statusLabel, "Quarantined pack")
        XCTAssertFalse(rows.first { $0.zone.id == "united-kingdom_london" }?.hasUnavailableLocalData == true)
        XCTAssertFalse(rows.first { $0.zone.id == "malaysia-singapore-brunei_kl" }?.hasUnavailableLocalData == true)
    }

    func testOfflineRegionRowsSurfaceUnknownLocalRegionsForCleanup() {
        let catalog = OfflineRegionCatalog.debugFixture
        let rows = catalog.rows(
            installed: [
                "uk": "20260716T155409Z",
            ],
            activeProgress: nil,
            pausedRegions: ["uk_london"],
            quarantines: [
                OfflinePackQuarantine(
                    region: "malaysia",
                    publishVersion: "20260716T155035Z",
                    coordinates: [TileCoordinate(z: 10, x: 806, y: 503)]
                ),
            ]
        )

        let installed = rows.first { $0.zone.id == "uk" }
        let paused = rows.first { $0.zone.id == "uk_london" }
        let quarantined = rows.first { $0.zone.id == "malaysia" }

        XCTAssertEqual(installed?.state, .unavailable)
        XCTAssertTrue(installed?.allowsDelete == true)
        XCTAssertEqual(paused?.state, .unavailable)
        XCTAssertEqual(paused?.cancelRegion, "uk_london")
        XCTAssertEqual(quarantined?.state, .unavailable)
        XCTAssertTrue(quarantined?.allowsDelete == true)
    }

    func testOfflineRegionRowsOfferCleanupForUnavailablePausedUnknownRegion() {
        let catalog = OfflineRegionCatalog.debugFixture

        let rows = catalog.rows(
            installed: [:],
            activeProgress: nil,
            pausedRegions: ["united-kingdom_unknown"],
            quarantines: []
        )
        let london = rows.first { $0.zone.id == "united-kingdom_unknown" }

        XCTAssertEqual(london?.state, .unavailable)
        XCTAssertEqual(london?.statusLabel, "Not available")
        XCTAssertEqual(london?.cancelRegion, "united-kingdom_unknown")
        XCTAssertFalse(london?.hasUnavailableLocalData == true)
        XCTAssertTrue(london?.hasUnavailablePausedDownload == true)
    }

    func testOfflineRegionRowsDoNotInventUpdatesFromFixtureVersions() {
        let catalog = OfflineRegionCatalog.debugFixture

        let rows = catalog.rows(
            installed: [
                "malaysia-singapore-brunei": "20260716T155035Z",
            ],
            installedStorageBytes: [
                "malaysia-singapore-brunei": 223_400_000,
            ],
            activeProgress: nil,
            quarantines: []
        )
        let malaysia = rows.first { $0.zone.id == "malaysia-singapore-brunei" }

        XCTAssertEqual(malaysia?.state, .installed(publishVersion: "20260716T155035Z"))
        XCTAssertEqual(malaysia?.statusLabel, "Downloaded")
        XCTAssertEqual(malaysia?.sizeLabel(includeThumbnails: false), "223.4 MB")
    }

    func testOfflineRegionRowsUseFetchedCurrentForUpdateComparison() {
        let catalog = OfflineRegionCatalog.debugFixture

        let currentRows = catalog.rows(
            installed: [
                "malaysia-singapore-brunei": "20260716T155035Z",
            ],
            availablePublishVersions: [
                "malaysia-singapore-brunei": "20260716T155035Z",
            ],
            activeProgress: nil,
            quarantines: []
        )
        let updatedRows = catalog.rows(
            installed: [
                "malaysia-singapore-brunei": "20260716T155035Z",
            ],
            availablePublishVersions: [
                "malaysia-singapore-brunei": "20260718T000000Z",
            ],
            activeProgress: nil,
            quarantines: []
        )

        XCTAssertEqual(currentRows.first { $0.zone.id == "malaysia-singapore-brunei" }?.state, .installed(publishVersion: "20260716T155035Z"))
        XCTAssertEqual(updatedRows.first { $0.zone.id == "malaysia-singapore-brunei" }?.state, .updateAvailable(
            installedPublishVersion: "20260716T155035Z",
            availablePublishVersion: "20260718T000000Z"
        ))
        XCTAssertTrue(updatedRows.first { $0.zone.id == "malaysia-singapore-brunei" }?.allowsDelete == true)
    }

    @MainActor
    func testOfflineMapsRefreshPublishesLocalRowsBeforeAvailabilityCompletes() async {
        let catalog = OfflineRegionCatalog.debugFixture
        let localApplied = expectation(description: "local offline map rows applied")
        var observedRows: [OfflineRegionCatalogRow] = []

        let availabilityTask = await OfflineMapsRefreshCoordinator.refresh(
            loadLocalState: {
                OfflineMapsLocalState(
                    installed: [
                        "united-kingdom": "20260718T000000Z",
                        "united-kingdom_london": "20260717T000000Z",
                    ],
                    pausedRegions: ["malaysia-singapore-brunei"],
                    quarantines: [
                        OfflinePackQuarantine(
                            region: "united-kingdom_london",
                            publishVersion: "20260717T000000Z",
                            coordinates: [TileCoordinate(z: 10, x: 511, y: 340)]
                        ),
                    ],
                    storageStatus: .ready(
                        totalBytes: 223_400_000,
                        regions: [
                            StorageMenuRegion(
                                region: "united-kingdom",
                                publishVersion: "20260718T000000Z",
                                bytes: 223_400_000,
                                tileCount: 42
                            ),
                        ],
                        failedRegions: []
                    )
                )
            },
            loadAvailability: { _ in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(10))
                }
                return .empty
            },
            applyLocalState: { localState in
                observedRows = catalog.rows(
                    installed: localState.installed,
                    installedStorageBytes: localState.storageStatus.installedStorageBytes,
                    availablePublishVersions: [:],
                    activeProgress: nil,
                    pausedRegions: localState.pausedRegions,
                    quarantines: localState.quarantines
                )
                localApplied.fulfill()
            },
            applyAvailability: { _, _ in
                XCTFail("availability fetch must not finish in this test")
            }
        )
        defer { availabilityTask.cancel() }

        await fulfillment(of: [localApplied], timeout: 1)

        XCTAssertEqual(observedRows.first { $0.zone.id == "united-kingdom" }?.state, .installed(publishVersion: "20260718T000000Z"))
        XCTAssertEqual(observedRows.first { $0.zone.id == "united-kingdom" }?.sizeLabel(includeThumbnails: false), "223.4 MB")
        XCTAssertEqual(observedRows.first { $0.zone.id == "united-kingdom_london" }?.state, .quarantined(OfflinePackQuarantine(
            region: "united-kingdom_london",
            publishVersion: "20260717T000000Z",
            coordinates: [TileCoordinate(z: 10, x: 511, y: 340)]
        )))
        XCTAssertEqual(observedRows.first { $0.zone.id == "malaysia-singapore-brunei" }?.state, .paused(OfflineDownloadProgress(region: "malaysia-singapore-brunei", fractionComplete: 0)))
    }

    func testOfflineAvailabilityUsesSharedCatalogPointerWithoutInstalledRegionFanout() async throws {
        let fetcher = AppStubFetcher(routes: [
            "https://tiles.making-tracks.app/catalog/current.json": try appJSONData([
                "schema_version": 1,
                "publish_versions": [
                    "united-kingdom": "20260718T000000Z",
                    "united-kingdom_london": "20260717T000000Z",
                    "malaysia-singapore-brunei": "20260716T155035Z",
                ],
            ]),
        ])

        let versions = try await OfflinePublishAvailability.currentPublishVersions(
            for: .debugFixture,
            installedRegions: ["united-kingdom", "united-kingdom_london", "malaysia-singapore-brunei"],
            fetcher: fetcher
        )

        XCTAssertEqual(versions, [
            "united-kingdom": "20260718T000000Z",
            "united-kingdom_london": "20260717T000000Z",
            "malaysia-singapore-brunei": "20260716T155035Z",
        ])
        XCTAssertEqual(fetcher.requestedURLs, [
            "https://tiles.making-tracks.app/catalog/current.json",
        ])
        XCTAssertFalse(fetcher.requestedURLs.contains("https://tiles.making-tracks.app/united-kingdom/current.json"))
        XCTAssertFalse(fetcher.requestedURLs.contains("https://tiles.making-tracks.app/malaysia-singapore-brunei/current.json"))
    }

    @MainActor
    func testMapScreenModelOfflineAvailabilityUsesSharedCatalogPointerWithoutInstalledRegionFanout() async throws {
        let fetcher = AppStubFetcher(routes: [
            "https://tiles.making-tracks.app/catalog/current.json": try appJSONData([
                "schema_version": 1,
                "publish_versions": [
                    "united-kingdom": "20260718T000000Z",
                    "united-kingdom_london": "20260717T000000Z",
                    "malaysia-singapore-brunei": "20260716T155035Z",
                ],
            ]),
        ])
        let model = try MapScreenModel(database: try AppDatabase.inMemory())

        let versions = await model.availableOfflinePublishVersions(
            for: .debugFixture,
            installedRegions: ["united-kingdom", "united-kingdom_london", "malaysia-singapore-brunei"],
            allowsCellularDownloads: false,
            availabilityFetcher: fetcher
        )

        XCTAssertEqual(versions, [
            "united-kingdom": "20260718T000000Z",
            "united-kingdom_london": "20260717T000000Z",
            "malaysia-singapore-brunei": "20260716T155035Z",
        ])
        XCTAssertEqual(fetcher.requestedURLs, [
            "https://tiles.making-tracks.app/catalog/current.json",
        ])
        XCTAssertFalse(fetcher.requestedURLs.contains("https://tiles.making-tracks.app/united-kingdom/current.json"))
        XCTAssertFalse(fetcher.requestedURLs.contains("https://tiles.making-tracks.app/malaysia-singapore-brunei/current.json"))
    }

    @MainActor
    func testMapScreenModelOfflineAvailabilityLoadsRegionIndexBytes() async throws {
        let catalog = OfflineRegionCatalog(regionIndex: try RegionIndex.decode(appJSONData(appRegionIndexV3Object())))
        let fetcher = AppStubFetcher(routes: [
            "https://tiles.making-tracks.app/catalog/current.json": try appJSONData([
                "schema_version": 1,
                "publish_versions": [
                    "malaysia-singapore-brunei": "20260719T125813Z",
                    "malaysia-singapore-brunei_kl": "20260719T125813Z",
                ],
            ]),
        ])
        let model = try MapScreenModel(database: try AppDatabase.inMemory())

        let availability = await model.availableOfflineAvailability(
            for: catalog,
            installedRegions: ["malaysia-singapore-brunei"],
            allowsCellularDownloads: false,
            availabilityFetcher: fetcher
        )

        XCTAssertEqual(availability.publishVersions, [
            "malaysia-singapore-brunei": "20260719T125813Z",
            "malaysia-singapore-brunei_kl": "20260719T125813Z",
        ])
        XCTAssertEqual(availability.storageBytes, [
            "malaysia-singapore-brunei": 228_849_472,
            "malaysia-singapore-brunei_kl": 33_000_000,
        ])
        XCTAssertEqual(fetcher.requestedURLs, [
            "https://tiles.making-tracks.app/catalog/current.json",
        ])
    }

    @MainActor
    func testMapScreenModelOfflineAvailabilityDropsStaleRegionIndexBytes() async throws {
        let catalog = OfflineRegionCatalog(regionIndex: try RegionIndex.decode(appJSONData(appRegionIndexV3Object())))
        let fetcher = AppStubFetcher(routes: [
            "https://tiles.making-tracks.app/catalog/current.json": try appJSONData([
                "schema_version": 1,
                "publish_versions": [
                    "malaysia-singapore-brunei": "20260720T000000Z",
                    "malaysia-singapore-brunei_kl": "20260719T125813Z",
                ],
            ]),
        ])
        let model = try MapScreenModel(database: try AppDatabase.inMemory())

        let availability = await model.availableOfflineAvailability(
            for: catalog,
            installedRegions: ["malaysia-singapore-brunei"],
            allowsCellularDownloads: false,
            availabilityFetcher: fetcher
        )

        XCTAssertEqual(availability.publishVersions, [
            "malaysia-singapore-brunei": "20260720T000000Z",
            "malaysia-singapore-brunei_kl": "20260719T125813Z",
        ])
        XCTAssertEqual(availability.storageBytes, [
            "malaysia-singapore-brunei_kl": 33_000_000,
        ])

        let rows = catalog.rows(
            installed: [:],
            availablePublishVersions: availability.publishVersions,
            availableStorageBytes: availability.storageBytes,
            activeProgress: nil,
            quarantines: []
        )
        XCTAssertEqual(rows.first { $0.zone.id == "malaysia-singapore-brunei" }?.state, .unavailable)
        XCTAssertEqual(rows.first { $0.zone.id == "malaysia-singapore-brunei" }?.knownByteSize, nil)
        XCTAssertFalse(rows.first { $0.zone.id == "malaysia-singapore-brunei" }?.hasUnavailableLocalData == true)
        XCTAssertNil(rows.first { $0.zone.id == "malaysia-singapore-brunei" }?.cancelRegion)
        XCTAssertFalse(rows.first { $0.zone.id == "malaysia-singapore-brunei" }?.allowsDelete == true)
        XCTAssertEqual(rows.first { $0.zone.id == "malaysia-singapore-brunei_kl" }?.knownByteSize, 33_000_000)
    }

    @MainActor
    func testMapScreenModelOfflineAvailabilityFailsClosedForUninstalledStaleCatalogZones() async throws {
        let catalog = OfflineRegionCatalog(regionIndex: try RegionIndex.decode(appJSONData(appRegionIndexV3Object())))
        let fetcher = AppStubFetcher(routes: [
            "https://tiles.making-tracks.app/catalog/current.json": try appJSONData([
                "schema_version": 1,
                "publish_versions": [
                    "malaysia-singapore-brunei": "20260720T000000Z",
                    "malaysia-singapore-brunei_kl": "20260719T125813Z",
                ],
            ]),
        ])
        let model = try MapScreenModel(database: try AppDatabase.inMemory())

        let availability = await model.availableOfflineAvailability(
            for: catalog,
            installedRegions: [],
            allowsCellularDownloads: false,
            availabilityFetcher: fetcher
        )
        let rows = catalog.rows(
            installed: [:],
            availablePublishVersions: availability.publishVersions,
            availableStorageBytes: availability.storageBytes,
            activeProgress: nil,
            quarantines: []
        )

        XCTAssertEqual(availability.publishVersions, [
            "malaysia-singapore-brunei": "20260720T000000Z",
            "malaysia-singapore-brunei_kl": "20260719T125813Z",
        ])
        XCTAssertEqual(rows.first { $0.zone.id == "malaysia-singapore-brunei" }?.state, .unavailable)
        XCTAssertFalse(rows.first { $0.zone.id == "malaysia-singapore-brunei" }?.allowsDelete == true)
        XCTAssertEqual(rows.first { $0.zone.id == "malaysia-singapore-brunei_kl" }?.state, .notInstalled)
    }

    func testOfflineRegionRowsFailClosedWhenCurrentPublishVersionIsUnknown() {
        let catalog = OfflineRegionCatalog.debugFixture

        let rows = catalog.rows(
            installed: [:],
            availablePublishVersions: [:],
            activeProgress: nil,
            quarantines: []
        )

        XCTAssertEqual(rows.first { $0.zone.id == "malaysia-singapore-brunei" }?.state, .unavailable)
        XCTAssertFalse(rows.first { $0.zone.id == "malaysia-singapore-brunei" }?.allowsDelete == true)
    }

    @MainActor
    func testMapScreenModelOfflineAvailabilityGracefullyDegradesToNoUpdates() async throws {
        let model = try MapScreenModel(database: try AppDatabase.inMemory())
        let malformedFetcher = AppStubFetcher(routes: [
            "https://tiles.making-tracks.app/catalog/current.json": try appJSONData([
                "schema_version": 2,
                "publish_versions": ["malaysia-singapore-brunei": "20260718T000000Z"],
            ]),
        ])
        let offlineFetcher = AppStubFetcher(routes: [:])

        let malformedVersions = await model.availableOfflinePublishVersions(
            for: .debugFixture,
            installedRegions: ["malaysia-singapore-brunei"],
            allowsCellularDownloads: false,
            availabilityFetcher: malformedFetcher
        )
        let offlineVersions = await model.availableOfflinePublishVersions(
            for: .debugFixture,
            installedRegions: ["malaysia-singapore-brunei"],
            allowsCellularDownloads: false,
            availabilityFetcher: offlineFetcher
        )
        let rows = OfflineRegionCatalog.debugFixture.rows(
            installed: ["malaysia-singapore-brunei": "20260716T155035Z"],
            availablePublishVersions: malformedVersions,
            activeProgress: nil,
            quarantines: []
        )

        XCTAssertEqual(malformedVersions, [:])
        XCTAssertEqual(offlineVersions, [:])
        XCTAssertEqual(rows.first { $0.zone.id == "malaysia-singapore-brunei" }?.state, .installed(publishVersion: "20260716T155035Z"))
    }

    @MainActor
    func testMapScreenModelForceOfflineDisablesOfflineCatalogProbes() async throws {
        let model = try MapScreenModel(
            database: try AppDatabase.inMemory(),
            forceTileNetworkOffline: true
        )

        let catalog = await model.offlineRegionCatalog(allowsCellularDownloads: false)
        let versions = await model.availableOfflinePublishVersions(
            for: .debugFixture,
            installedRegions: ["united-kingdom"],
            allowsCellularDownloads: false
        )
        let availability = await model.availableOfflineAvailability(
            for: .debugFixture,
            installedRegions: ["united-kingdom"],
            allowsCellularDownloads: false
        )

        XCTAssertEqual(catalog, .empty)
        XCTAssertEqual(versions, [:])
        XCTAssertEqual(availability, .empty)
    }

    func testOfflineRegionRowsSurfacePausedProgressSeparatelyFromActiveProgress() {
        let catalog = OfflineRegionCatalog.debugFixture
        let paused = OfflineDownloadProgress(
            region: "united-kingdom",
            publishVersion: "20260718T000000Z",
            completedBytes: 50,
            totalBytes: 100,
            fractionComplete: 0.5
        )

        let rows = catalog.rows(
            installed: [
                "united-kingdom": "20260718T000000Z",
            ],
            activeProgress: nil,
            pausedProgress: paused,
            quarantines: []
        )
        let uk = rows.first { $0.zone.id == "united-kingdom" }

        XCTAssertEqual(uk?.state, .paused(paused))
        XCTAssertEqual(uk?.statusLabel, "Paused at 50%")
    }

    @MainActor
    func testOfflineDownloadSessionDeletePreservesUnrelatedActiveDownload() {
        let session = OfflineRegionDownloadSession()
        let progress = OfflineDownloadProgress(region: "uk", fractionComplete: 0.42)
        let downloadID = UUID()
        let task = Task<Void, Never> {}
        defer { task.cancel() }

        session.begin(region: "uk", control: OfflineRegionDownloadControl(), downloadID: downloadID)
        session.attach(task: task)
        session.update(progress)
        session.noteDeleted(region: "malaysia")

        XCTAssertEqual(session.liveProgress, progress)
        XCTAssertNil(session.pausedProgress)
        XCTAssertNotNil(session.activeControl)
        XCTAssertNotNil(session.activeTask)
        XCTAssertEqual(session.activeDownloadID, downloadID)
    }

    @MainActor
    func testOfflineDownloadSessionPauseClearsChipProgressButKeepsResumableProgress() {
        let session = OfflineRegionDownloadSession()
        let progress = OfflineDownloadProgress(region: "uk", fractionComplete: 0.42)

        session.begin(region: "uk", control: OfflineRegionDownloadControl(), downloadID: UUID())
        session.update(progress)
        session.pause(region: "uk")

        XCTAssertNil(session.liveProgress)
        XCTAssertNil(session.chromeProgress)
        XCTAssertEqual(session.pausedProgress, progress)
        XCTAssertEqual(session.rowProgress, progress)
        XCTAssertNil(session.activeControl)
        XCTAssertNil(session.activeTask)
    }

    @MainActor
    func testOfflineDownloadSessionRequiresPausedRegionToResumeOrCancelBeforeStartingAnotherRegion() {
        let session = OfflineRegionDownloadSession()

        session.begin(region: "uk", control: OfflineRegionDownloadControl(), downloadID: UUID())
        session.update(OfflineDownloadProgress(region: "uk", fractionComplete: 0.42))
        session.pause(region: "uk")

        XCTAssertTrue(session.canBegin(region: "uk"))
        XCTAssertFalse(session.canBegin(region: "malaysia"))
    }

    @MainActor
    func testOfflineDownloadSessionUsesPersistedPausedRowRegionForCancelAfterRelaunch() {
        let session = OfflineRegionDownloadSession()

        XCTAssertEqual(session.regionForCancel(fallbackRegion: "uk_london"), "uk_london")
    }

    @MainActor
    func testOfflineDownloadSessionUsesTappedPausedRowRegionBeforeLiveSessionForCancel() {
        let session = OfflineRegionDownloadSession()
        session.begin(region: "uk", control: OfflineRegionDownloadControl(), downloadID: UUID())
        session.update(OfflineDownloadProgress(region: "uk", fractionComplete: 0.42))

        XCTAssertFalse(session.canBegin(region: "uk_london"))
        XCTAssertEqual(session.regionForCancel(fallbackRegion: "uk_london"), "uk_london")
        XCTAssertFalse(session.shouldClearSessionForCancel(fallbackRegion: "uk_london"))
        XCTAssertTrue(session.shouldClearSessionForCancel(fallbackRegion: "uk"))
        XCTAssertFalse(session.isSessionRegion("uk_london"))
        XCTAssertTrue(session.isSessionRegion("uk"))
    }

    func testDeferredOfflineMaintenanceRouteCarriesCellularPolicyIntoReplayFetchers() {
        let route = DeferredOfflineMaintenanceDownloadRoute(
            region: "uk",
            allowsCellularDownloads: true
        )
        defer {
            OfflineDownloadSession.invalidateBackgroundSessionForTesting(identifier: route.backgroundIdentifier)
        }

        XCTAssertEqual(route.backgroundIdentifier, OfflineDownloadSession.backgroundIdentifier(region: "uk"))
        XCTAssertTrue(route.metadataAllowsCellularDownloadsForTesting)
        XCTAssertTrue(route.objectAllowsCellularDownloadsForTesting)
    }

    func testOfflineCoverageBBoxUsesManifestLonLatOrder() {
        XCTAssertEqual(
            OfflineCoverageBBox.coverage(
                fromManifestBasemapBBox: [99.60, 0.80, 119.30, 7.60]
            ),
            CoverageBBox(minLon: 99.60, minLat: 0.80, maxLon: 119.30, maxLat: 7.60)
        )
        XCTAssertNil(OfflineCoverageBBox.coverage(
            fromManifestBasemapBBox: [0.80, 99.60, 7.60, 119.30]
        ))
    }

    func testPausedOfflineRegionCatalogRowCarriesRowRegionForCancelAction() {
        let zone = OfflineRegionCatalogZone(
            id: "uk_london",
            displayName: "London",
            parentID: "uk",
            publishVersion: "20260718T000000Z",
            bytesWithoutThumbnails: 842_000_000,
            bytesWithThumbnails: 1_160_000_000
        )

        XCTAssertEqual(
            OfflineRegionCatalogRow(
                zone: zone,
                depth: 1,
                state: .paused(OfflineDownloadProgress(region: "uk_london", fractionComplete: 0))
            ).cancelRegion,
            "uk_london"
        )
        XCTAssertNil(OfflineRegionCatalogRow(
            zone: zone,
            depth: 1,
            state: .downloading(OfflineDownloadProgress(region: "uk_london", fractionComplete: 0.42))
        ).cancelRegion)
    }

    @MainActor
    func testCoordinatorGeneratesThemeSpecificStyleJSON() throws {
        let coordinator = makeCoordinator()

        let definedPaperURL = try XCTUnwrap(coordinator.styleURL(
            worldPMTilesURL: "pmtiles://world.pmtiles",
            regionPMTilesURL: nil,
            coverageBBoxes: [],
            theme: .definedPaper
        ))
        let snowURL = try XCTUnwrap(coordinator.styleURL(
            worldPMTilesURL: "pmtiles://world.pmtiles",
            regionPMTilesURL: nil,
            coverageBBoxes: [],
            theme: .snow
        ))

        let definedPaperJSON = try String(contentsOf: definedPaperURL, encoding: .utf8)
        let snowJSON = try String(contentsOf: snowURL, encoding: .utf8)
        XCTAssertNotEqual(definedPaperJSON, snowJSON)
        XCTAssertTrue(definedPaperJSON.contains(MapTheme.definedPaper.background))
        XCTAssertTrue(snowJSON.contains(MapTheme.snow.background))
    }

    @MainActor
    func testCoordinatorReloadPlanIncludesThemeAndCommitsOnlyAfterURLExists() throws {
        let coordinator = makeCoordinator()
        coordinator.currentWorldPMTilesURL = "pmtiles://world.pmtiles"
        coordinator.currentRegionPMTilesURL = nil
        coordinator.currentCoverageBBoxes = []
        coordinator.currentThemeID = MapTheme.definedPaper.id

        let failedReload = coordinator.prepareStyleReload(
            worldPMTilesURL: "pmtiles://world.pmtiles",
            regionPMTilesURL: nil,
            coverageBBoxes: [],
            theme: .snow,
            makeStyleURL: { _, _, _, _ in nil }
        )
        XCTAssertNil(failedReload)
        XCTAssertEqual(coordinator.currentThemeID, MapTheme.definedPaper.id)

        let url = URL(fileURLWithPath: "/tmp/making-tracks-style-test.json")
        let reload = try XCTUnwrap(coordinator.prepareStyleReload(
            worldPMTilesURL: "pmtiles://world.pmtiles",
            regionPMTilesURL: nil,
            coverageBBoxes: [],
            theme: .snow,
            makeStyleURL: { _, _, _, _ in url }
        ))
        XCTAssertEqual(reload.themeID, MapTheme.snow.id)
        coordinator.commitStyleReload(reload)
        XCTAssertEqual(coordinator.currentThemeID, MapTheme.snow.id)
        XCTAssertNil(coordinator.prepareStyleReload(
            worldPMTilesURL: "pmtiles://world.pmtiles",
            regionPMTilesURL: nil,
            coverageBBoxes: [],
            theme: .snow,
            makeStyleURL: { _, _, _, _ in url }
        ))
    }

    @MainActor
    func testCoordinatorReloadPlanIncludesCoverageBBoxes() throws {
        let coordinator = makeCoordinator()
        coordinator.currentWorldPMTilesURL = "pmtiles://world.pmtiles"
        coordinator.currentRegionPMTilesURL = "pmtiles://region.pmtiles"
        coordinator.currentCoverageBBoxes = [
            CoverageBBox(minLon: -8.65, minLat: 49.84, maxLon: 1.77, maxLat: 60.86),
        ]
        coordinator.currentThemeID = MapTheme.definedPaper.id

        var capturedCoverage: [CoverageBBox] = []
        let reload = try XCTUnwrap(coordinator.prepareStyleReload(
            worldPMTilesURL: "pmtiles://world.pmtiles",
            regionPMTilesURL: "pmtiles://region.pmtiles",
            coverageBBoxes: [
                CoverageBBox(minLon: -8.65, minLat: 49.84, maxLon: 1.77, maxLat: 60.86),
                CoverageBBox(minLon: 99.60, minLat: 0.80, maxLon: 119.30, maxLat: 7.60),
            ],
            theme: .definedPaper,
            makeStyleURL: { _, _, coverage, _ in
                capturedCoverage = coverage
                return URL(fileURLWithPath: "/tmp/making-tracks-style-coverage-test.json")
            }
        ))

        XCTAssertEqual(capturedCoverage, [
            CoverageBBox(minLon: -8.65, minLat: 49.84, maxLon: 1.77, maxLat: 60.86),
            CoverageBBox(minLon: 99.60, minLat: 0.80, maxLon: 119.30, maxLat: 7.60),
        ])
        coordinator.commitStyleReload(reload)
        XCTAssertEqual(coordinator.currentCoverageBBoxes, capturedCoverage)
        XCTAssertNil(coordinator.prepareStyleReload(
            worldPMTilesURL: "pmtiles://world.pmtiles",
            regionPMTilesURL: "pmtiles://region.pmtiles",
            coverageBBoxes: capturedCoverage,
            theme: .definedPaper,
            makeStyleURL: { _, _, _, _ in URL(fileURLWithPath: "/tmp/unused.json") }
        ))
    }

    @MainActor
    func testCoordinatorCoverageToggleRemovesMaskBBoxes() throws {
        let coordinator = makeCoordinator()
        coordinator.currentWorldPMTilesURL = "pmtiles://world.pmtiles"
        coordinator.currentRegionPMTilesURL = "pmtiles://region.pmtiles"
        coordinator.currentCoverageBBoxes = [
            CoverageBBox(minLon: 99.60, minLat: 0.80, maxLon: 119.30, maxLat: 7.60),
        ]
        coordinator.currentShowsCoverageShading = true
        coordinator.currentThemeID = MapTheme.definedPaper.id

        var capturedCoverage: [CoverageBBox] = [
            CoverageBBox(minLon: 99.60, minLat: 0.80, maxLon: 119.30, maxLat: 7.60),
        ]
        let reload = try XCTUnwrap(coordinator.prepareStyleReload(
            worldPMTilesURL: "pmtiles://world.pmtiles",
            regionPMTilesURL: "pmtiles://region.pmtiles",
            coverageBBoxes: capturedCoverage,
            showsCoverageShading: false,
            theme: .definedPaper,
            makeStyleURL: { _, _, coverage, _ in
                capturedCoverage = coverage
                return URL(fileURLWithPath: "/tmp/making-tracks-style-no-coverage.json")
            }
        ))

        XCTAssertEqual(capturedCoverage, [])
        coordinator.commitStyleReload(reload)
        XCTAssertEqual(coordinator.currentCoverageBBoxes, [])
        XCTAssertFalse(coordinator.currentShowsCoverageShading)
    }

    func testMapPinAccessibilityContentUsesStableIdentifierAndReadableLabel() {
        let place = MapPlace(id: "mt1_test", lat: 51.49, lon: -0.12, tier: 1, category: "historic_building")

        let content = MapPinAccessibilityContent(
            place: place,
            state: PinState(saved: true, visit: .visited, hidden: false),
            name: "Art Deco Cinema"
        )

        XCTAssertEqual(content.identifier, "map.pin.mt1_test")
        XCTAssertEqual(content.label, "Art Deco Cinema, Historic Building, visited, saved")
        XCTAssertEqual(content.hint, "Opens the place card")
    }

    func testMapPinAccessibilityContentIncludesHiddenAndLovedStateWhenRendered() {
        let place = MapPlace(id: "hidden-loved", lat: 51.52, lon: -0.14, tier: 2, category: "artwork")

        let content = MapPinAccessibilityContent(
            place: place,
            state: PinState(saved: false, visit: .loved, hidden: true),
            name: "Laneway Mural"
        )

        XCTAssertEqual(content.label, "Laneway Mural, Artwork, loved, hidden")
    }

    func testMapPinAccessibilityContentDoesNotExposePlaceIDWhenNameIsMissing() {
        let place = MapPlace(id: "mt1_internal_identifier", lat: 51.52, lon: -0.14, tier: 2, category: "future_category")

        let content = MapPinAccessibilityContent(
            place: place,
            state: PinState(saved: false, visit: .none, hidden: false),
            name: nil
        )

        XCTAssertEqual(content.label, "Unnamed place, Future Category, not visited")
        XCTAssertFalse(content.label.contains(place.id))
    }

    func testListMapPinAccessibilityNamesUsesVisibleSnapshotNamesOnly() {
        let visible = ListPlace(
            placeID: "visible",
            name: "Saved Ghost Sign",
            category: "attraction",
            pinState: PinState(saved: true, visit: .none)
        )
        let filtered = ListPlace(
            placeID: "filtered",
            name: "Already Seen",
            category: "museum",
            pinState: PinState(saved: false, visit: .visited)
        )

        XCTAssertEqual(
            ListMapPinAccessibilityNames.names(from: [visible, filtered], visiblePlaceIDs: ["visible"]),
            ["visible": "Saved Ghost Sign"]
        )
    }

    @MainActor
    private func makeCoordinator() -> MLNMapViewRepresentable.Coordinator {
        MLNMapViewRepresentable.Coordinator(
            onCameraIdle: { _, _ in },
            onUserPanned: {},
            onTapPlace: { _ in },
            onTapEmpty: {},
            onMapReady: { _ in },
            onFeaturesApplied: {},
            onStyleWillReload: {},
            onMapLoadFailed: {}
        )
    }
}

private final class AppStubFetcher: TileFetching, @unchecked Sendable {
    let routes: [String: Data]
    private let lock = NSLock()
    private var requestedURLStorage: [String] = []
    var requestedURLs: [String] {
        lock.lock()
        defer { lock.unlock() }
        return requestedURLStorage
    }

    init(routes: [String: Data]) {
        self.routes = routes
    }

    func fetch(_ url: URL) async throws -> Data {
        lock.withLock {
            requestedURLStorage.append(url.absoluteString)
        }
        guard let data = routes[url.absoluteString] else { throw URLError(.notConnectedToInternet) }
        return data
    }
}

private func appJSONData(_ object: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

private func appRegionIndexV3Object() -> [String: Any] {
    [
        "schema_version": 3,
        "min_reader_version": 1,
        "generated_at": "2026-07-20T12:00:00Z",
        "regions": [
            appRegionIndexV3Entry([
                "id": "malaysia-singapore-brunei",
                "display_name": "Malaysia, Singapore, and Brunei",
                "bbox": [99.0, -1.5, 120.0, 7.5],
                "basemap_bytes": 4_000_000,
                "tile_count": 12,
                "bytes_without_thumbs": 228_849_472,
                "bytes_with_thumbs": 240_582_030,
                "search_compact": [
                    "path": "malaysia-singapore-brunei/20260719T125813Z/search/compact.json",
                    "sha256": String(repeating: "a", count: 64),
                    "bytes": 208,
                    "schema_version": 1,
                ],
            ]),
            appRegionIndexV3Entry([
                "id": "malaysia-singapore-brunei_kl",
                "display_name": "Kuala Lumpur",
                "parent": "malaysia-singapore-brunei",
                "bbox": [101.4, 2.8, 101.9, 3.4],
                "basemap_bytes": 1_000_000,
                "tile_count": 4,
                "bytes_without_thumbs": 33_000_000,
                "bytes_with_thumbs": 41_000_000,
                "search_compact": [
                    "path": "malaysia-singapore-brunei_kl/20260719T125813Z/search/compact.json",
                    "sha256": String(repeating: "b", count: 64),
                    "bytes": 197,
                    "schema_version": 1,
                ],
            ]),
        ],
    ]
}

private func appRegionIndexV3Entry(_ overrides: [String: Any] = [:]) -> [String: Any] {
    var entry: [String: Any] = [
        "id": "malaysia-singapore-brunei",
        "display_name": "Malaysia, Singapore, and Brunei",
        "parent": NSNull(),
        "bbox": [99.0, -1.5, 120.0, 7.5],
        "publish_version": "20260719T125813Z",
        "basemap_bytes": 4_000_000,
        "tile_count": 12,
        "bytes_without_thumbs": 228_849_472,
        "bytes_with_thumbs": 240_582_030,
        "search_compact": [
            "path": "malaysia-singapore-brunei/20260719T125813Z/search/compact.json",
            "sha256": String(repeating: "a", count: 64),
            "bytes": 208,
            "schema_version": 1,
        ],
    ]
    for (key, value) in overrides {
        entry[key] = value
    }
    return entry
}

private func assertColor(
    _ color: Color,
    red expectedRed: CGFloat,
    green expectedGreen: CGFloat,
    blue expectedBlue: CGFloat,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let uiColor = UIColor(color)
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0

    XCTAssertTrue(uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha), file: file, line: line)
    XCTAssertEqual(red, expectedRed, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(green, expectedGreen, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(blue, expectedBlue, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(alpha, 1, accuracy: 0.001, file: file, line: line)
}
