@testable import DesignSystem
import Foundation
import GRDB
import SwiftUI
import UIKit
import XCTest
import MakingTracksCore
@testable import MakingTracksData
import MakingTracksMapStyle
@testable import MakingTracksTiles
@testable import MakingTracks

final class AppShellTests: XCTestCase {
    func testAboutLicenceInventoryPreservesEverySoftwareEntry() throws {
        let manifest = try XCTUnwrap(OSSCreditsManifest.load())
        let inventory = AboutLicenceInventory(
            softwareCredits: manifest.credits,
            attribution: []
        )

        XCTAssertEqual(inventory.software.count, 4)
        XCTAssertEqual(
            inventory.software.map(\.name),
            [
                "GRDB.swift",
                "MapLibre Native iOS / maplibre-gl-native-distribution",
                "Newsreader",
                "Noto Sans glyph PBF mirror",
            ]
        )
        XCTAssertEqual(inventory.software.count, manifest.credits.count)

        for (rendered, loaded) in zip(inventory.software, manifest.credits) {
            XCTAssertEqual(rendered.name, loaded.name)
            XCTAssertEqual(rendered.acknowledgement, loaded.acknowledgement)
            XCTAssertEqual(rendered.category, loaded.category)
            XCTAssertEqual(rendered.versionOrPin, loaded.versionOrPin)
            XCTAssertEqual(rendered.licenseURL, loaded.licenseURL)
            XCTAssertEqual(rendered.noticeText, loaded.noticeText)
        }
    }

    func testAboutLicenceInventoryPreservesOSMAndEveryDataEntry() {
        let attribution = [
            Attribution(
                source: "Wikipedia",
                license: "CC BY-SA 4.0",
                text: "Wikipedia sentinel attribution."
            ),
            Attribution(
                source: "Regional heritage register",
                license: "Open Government Licence",
                text: "Regional sentinel attribution."
            ),
        ]
        let inventory = AboutLicenceInventory(
            softwareCredits: [],
            attribution: attribution
        )

        XCTAssertEqual(inventory.data.count, attribution.count + 1)
        XCTAssertEqual(
            inventory.data.map(\.name),
            ["OpenStreetMap", "Wikipedia", "Regional heritage register"]
        )
        XCTAssertEqual(inventory.data[0].license, "Open Database License")
        XCTAssertEqual(
            inventory.data[0].text,
            "Map data © OpenStreetMap contributors."
        )
        XCTAssertEqual(
            inventory.data[0].licenseURL?.absoluteString,
            "https://www.openstreetmap.org/copyright"
        )

        for (rendered, loaded) in zip(inventory.data.dropFirst(), attribution) {
            XCTAssertEqual(rendered.name, loaded.source)
            XCTAssertEqual(rendered.license, loaded.license)
            XCTAssertEqual(rendered.text, loaded.text)
            XCTAssertNil(rendered.licenseURL)
        }
    }

    @MainActor
    func testAccentColorAssetIsTheGlobalAppAccent() {
        let accent = MaterialTheme.snow.tokens.accent

        guard let asset = UIColor(named: "AccentColor", in: .main, compatibleWith: nil) else {
            XCTFail("AccentColor asset must be compiled into the app")
            return
        }

        assertColor(Color(uiColor: asset), red: accent.red, green: accent.green, blue: accent.blue)
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "NSAccentColorName") as? String, "AccentColor")
    }

    func testPlaceCardAppearanceResolvesApprovedMaterialTokens() {
        XCTAssertEqual(PlaceCardAppearance.cardBackgroundToken, .surface)
        XCTAssertEqual(PlaceCardAppearance.mediaBackgroundToken, .road)
        XCTAssertEqual(PlaceCardAppearance.primaryTextToken, .ink)
        XCTAssertEqual(PlaceCardAppearance.secondaryTextToken, .muted)
        XCTAssertEqual(PlaceCardAppearance.linkTextToken, .accent)

        let appearance = PlaceCardAppearance(theme: .snow)
        let tokens = MaterialTheme.snow.tokens
        assertColor(
            appearance.cardBackground,
            red: tokens.surface.red,
            green: tokens.surface.green,
            blue: tokens.surface.blue
        )
        assertColor(
            appearance.primaryText,
            red: tokens.ink.red,
            green: tokens.ink.green,
            blue: tokens.ink.blue
        )
        assertColor(
            appearance.secondaryText,
            red: tokens.muted.red,
            green: tokens.muted.green,
            blue: tokens.muted.blue
        )
        assertColor(
            appearance.linkText,
            red: tokens.accent.red,
            green: tokens.accent.green,
            blue: tokens.accent.blue
        )
    }

    func testPlaceCardActionsUseStateMorphology() {
        let cases: [(PlaceCardAction, Bool, PlaceCardActionPresentation)] = [
            (.save, false, .init(title: "Save", systemImage: "bookmark", style: .tonal)),
            (
                .save,
                true,
                .init(
                    title: "Saved",
                    systemImage: "bookmark.fill",
                    style: .state(
                        foreground: .accentContrast,
                        background: .accentDeepContainer
                    )
                )
            ),
            (.seen, false, .init(title: "Seen", systemImage: "eye", style: .tonal)),
            (
                .unsee(isEnabled: true),
                false,
                .init(
                    title: "Seen",
                    systemImage: "eye.fill",
                    style: .state(
                        foreground: .accentContrast,
                        background: .accent
                    )
                )
            ),
            (
                .unsee(isEnabled: false),
                false,
                .init(
                    title: "Seen",
                    systemImage: "eye.fill",
                    style: .state(
                        foreground: .accentContrast,
                        background: .accent
                    )
                )
            ),
            (
                .love,
                false,
                .init(
                    title: "Love",
                    systemImage: "heart",
                    style: .state(
                        foreground: .love,
                        background: .loveContainer
                    )
                )
            ),
            (
                .unlove,
                false,
                .init(
                    title: "Loved",
                    systemImage: "heart.fill",
                    style: .state(
                        foreground: .accentContrast,
                        background: .love
                    )
                )
            ),
            (.hide, false, .init(title: "Hide", systemImage: nil, style: .quiet)),
            (.unhide, false, .init(title: "Unhide", systemImage: nil, style: .quiet)),
        ]

        for (action, isSaved, expected) in cases {
            XCTAssertEqual(
                PlaceCardActionAppearance.presentation(
                    for: action,
                    isSaved: isSaved
                ),
                expected,
                "\(action), isSaved: \(isSaved)"
            )
        }

        let onPresentations = [
            PlaceCardActionAppearance.presentation(for: .save, isSaved: true),
            PlaceCardActionAppearance.presentation(
                for: .unsee(isEnabled: true),
                isSaved: false
            ),
            PlaceCardActionAppearance.presentation(for: .unlove, isSaved: false),
        ]
        let offPresentations = [
            PlaceCardActionAppearance.presentation(for: .save, isSaved: false),
            PlaceCardActionAppearance.presentation(for: .seen, isSaved: false),
            PlaceCardActionAppearance.presentation(for: .love, isSaved: false),
        ]
        let momentaryPresentations = [
            PlaceCardActionAppearance.presentation(for: .hide, isSaved: false),
            PlaceCardActionAppearance.presentation(for: .unhide, isSaved: false),
        ]

        XCTAssertTrue(onPresentations.allSatisfy { $0.systemImage?.hasSuffix(".fill") == true })
        XCTAssertTrue(offPresentations.allSatisfy {
            guard let systemImage = $0.systemImage else { return false }
            return !systemImage.hasSuffix(".fill")
        })
        XCTAssertTrue(momentaryPresentations.allSatisfy { $0.systemImage == nil })
        XCTAssertTrue(
            PlaceCardActionAppearance.usesQuietTextPressInset(for: .hide)
        )
        XCTAssertTrue(
            PlaceCardActionAppearance.usesQuietTextPressInset(for: .unhide)
        )
        XCTAssertFalse(
            PlaceCardActionAppearance.usesQuietTextPressInset(
                for: .unsee(isEnabled: false)
            )
        )
    }

    @MainActor
    func testPlaceCardActionStyleMountsQuietTextInsetOnlyWhereRuled() {
        let cases: [
            (
                action: PlaceCardAction,
                expected: MaterialControlPressFeedback
            )
        ] = [
            (.hide, .textInset(points: 1)),
            (.unhide, .textInset(points: 1)),
        ]

        for testCase in cases {
            let body = PlaceCardActionStyledContent(
                content: Text(verbatim: testCase.action.title),
                action: testCase.action,
                isSaved: false,
                theme: .snow
            ).body
            let mountedStyles = descendants(
                of: MaterialQuietButtonStyle.self,
                in: body
            )

            XCTAssertEqual(mountedStyles.count, 1)
            XCTAssertEqual(
                mountedStyles.first?.pressFeedback,
                testCase.expected,
                "\(testCase.action) must mount the ruled quiet feedback strategy"
            )
        }
    }

    func testPlaceCardPhotoHeightFollowsAspectRatioWithinTasteClamp() {
        XCTAssertEqual(PlaceCardPhotoLayout.preferredMinimumHeight, 112)
        XCTAssertEqual(PlaceCardPhotoLayout.maximumHeight, 260)
        XCTAssertEqual(
            PlaceCardPhotoLayout.height(containerWidth: 320, imageWidth: 640, imageHeight: 480),
            240
        )
        let panoramicFrame = PlaceCardPhotoLayout.size(
            containerWidth: 320,
            imageWidth: 1_600,
            imageHeight: 400
        )
        XCTAssertEqual(panoramicFrame.height, 80)
        XCTAssertEqual(panoramicFrame.width, 320)
        XCTAssertEqual(
            panoramicFrame.width / panoramicFrame.height,
            4,
            accuracy: 0.001,
            "An extreme panorama must preserve its aspect ratio rather than add letterbox bars."
        )
        XCTAssertEqual(
            PlaceCardPhotoLayout.height(containerWidth: 320, imageWidth: 400, imageHeight: 1_200),
            260
        )
        let portraitFrame = PlaceCardPhotoLayout.size(
            containerWidth: 320,
            imageWidth: 400,
            imageHeight: 1_200
        )
        XCTAssertEqual(portraitFrame.height, 260)
        XCTAssertEqual(portraitFrame.width, 260 / 3, accuracy: 0.001)
        XCTAssertEqual(
            portraitFrame.width / portraitFrame.height,
            1 / 3,
            accuracy: 0.001,
            "A max-clamped portrait frame must still match the image, with no letterbox bars."
        )
        XCTAssertEqual(
            PlaceCardPhotoLayout.height(containerWidth: 320, imageWidth: nil, imageHeight: nil),
            240
        )
        XCTAssertEqual(
            PlaceCardPhotoLayout.height(containerWidth: 320, imageWidth: 0, imageHeight: 480),
            240
        )
    }

    func testPlaceCardSurfaceIsExtractedFromMapScreen() throws {
        let appRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let mapSource = try String(
            contentsOf: appRoot.appendingPathComponent("Sources/Map/MapScreen.swift"),
            encoding: .utf8
        )
        let cardSource = try String(
            contentsOf: appRoot.appendingPathComponent(
                "Sources/PlaceCard/PlaceCardSheet.swift"
            ),
            encoding: .utf8
        )

        XCTAssertFalse(mapSource.contains("struct PlaceCardSheet: View"))
        XCTAssertTrue(cardSource.contains("struct PlaceCardSheet: View"))
    }

    func testPersistentDoorChromeReservesStandardAndAccessibilityClearance() {
        XCTAssertEqual(MapDoorChromeSpec.doorBarClearance(isAccessibilitySize: false), 68)
        XCTAssertEqual(MapDoorChromeSpec.doorBarClearance(isAccessibilitySize: true), 124)
        XCTAssertGreaterThan(
            MapDoorChromeSpec.accessibilityDoorBarClearance,
            MapDoorChromeSpec.standardDoorBarClearance
        )
    }

    func testDoorsMoveAboveAnOpenMediumPlaceCard() {
        XCTAssertEqual(
            MapDoorChromeSpec.effectiveDoorBarBottomPadding(
                containerHeight: 844,
                isPlaceCardPresented: false
            ),
            12
        )
        XCTAssertGreaterThan(
            MapDoorChromeSpec.effectiveDoorBarBottomPadding(
                containerHeight: 844,
                isPlaceCardPresented: true
            ),
            844 / 2
        )
    }

    func testExploreRootDestinationsAndAccessibilitySizesRequireLargeDetent() {
        XCTAssertFalse(
            MapDoorDetentPolicy.requiresLarge(
                door: .journal,
                isAccessibilitySize: false,
                hasDestination: false
            )
        )
        XCTAssertTrue(
            MapDoorDetentPolicy.requiresLarge(
                door: .explore,
                isAccessibilitySize: false,
                hasDestination: false
            )
        )
        XCTAssertTrue(
            MapDoorDetentPolicy.requiresLarge(
                door: .journal,
                isAccessibilitySize: true,
                hasDestination: false
            )
        )
        XCTAssertTrue(
            MapDoorDetentPolicy.requiresLarge(
                door: .journal,
                isAccessibilitySize: false,
                hasDestination: true
            )
        )
    }

    func testMapDoorsExposeDistinctRuledPresentation() {
        XCTAssertEqual(
            MapDoor.explore.presentation,
            MapDoorPresentation(
                title: "Explore",
                systemImage: "globe.europe.africa",
                accessibilityIdentifier: "map.door.explore"
            )
        )
        XCTAssertEqual(
            MapDoor.journal.presentation,
            MapDoorPresentation(
                title: "Journal",
                systemImage: "shoeprints.fill",
                accessibilityIdentifier: "map.door.journal"
            )
        )
    }

    func testDoorRootsExposeOnlyRuledRows() {
        XCTAssertEqual(ExploreDoorRow.allCases, [.settings, .about])
        XCTAssertEqual(
            JournalDoorRow.allCases,
            [.myTracks, .newList, .lovedPlaces, .hiddenPlaces]
        )
        XCTAssertFalse(ExploreDoorRow.allCases.map(\.title).contains("Offline maps"))
        XCTAssertFalse(ExploreDoorRow.allCases.map(\.title).contains("Coverage"))
        XCTAssertEqual(JournalDoorRow.lovedPlaces.presentation.title, "Loved places")
        XCTAssertEqual(JournalDoorRow.lovedPlaces.presentation.systemImage, "heart")
        XCTAssertEqual(
            JournalDoorRow.lovedPlaces.presentation.accessibilityIdentifier,
            "journal.row.loved"
        )
        XCTAssertEqual(JournalDoorRow.hiddenPlaces.presentation.title, "Hidden places")
        XCTAssertEqual(JournalDoorRow.hiddenPlaces.presentation.systemImage, "eye.slash")
        XCTAssertEqual(
            JournalDoorRow.hiddenPlaces.presentation.accessibilityIdentifier,
            "journal.row.hidden"
        )
        XCTAssertEqual(
            ExploreDoorRow.settings.presentation.accessibilityIdentifier,
            "explore.row.settings"
        )
        XCTAssertEqual(
            ExploreDoorRow.about.presentation.accessibilityIdentifier,
            "explore.row.about"
        )
    }

    func testExploreRootExposesCompleteScopeControlsInRuledOrder() {
        XCTAssertEqual(
            ExploreScopeControl.allCases,
            [.includeHidden, .showSaved, .coverageShading]
        )
        XCTAssertEqual(
            ExploreScopeControl.includeHidden.presentation,
            ExploreScopeControlPresentation(
                title: "Include hidden places",
                icon: .system("eye.slash"),
                accessibilityIdentifier: "map.layers.show-hidden"
            )
        )
        XCTAssertEqual(
            ExploreScopeControl.showSaved.presentation,
            ExploreScopeControlPresentation(
                title: "Show saved places",
                icon: .system("bookmark"),
                accessibilityIdentifier: "map.layers.show-saved"
            )
        )
        XCTAssertEqual(
            ExploreScopeControl.coverageShading.presentation,
            ExploreScopeControlPresentation(
                title: "Show coverage shading",
                icon: .coverageShading,
                accessibilityIdentifier: "map.layers.coverage-shading"
            )
        )
    }

    func testExploreCategoryChipRowsExposeOnlyActualNeighbours() {
        let visibility = MapLayerVisibility()
        XCTAssertEqual(
            ExploreCategoryChipTopology.rows(
                visibility.categories,
                isAccessibilitySize: false
            ).map(\.count),
            [3, 3, 2]
        )
        XCTAssertEqual(
            ExploreCategoryChipTopology.rows(
                visibility.categories,
                isAccessibilitySize: true
            ).map(\.count),
            [2, 2, 2, 2]
        )

        let topLeading = ExploreCategoryChipTopology.neighborGaps(
            rowIndex: 0,
            rowItemCounts: [3, 3, 2],
            itemIndex: 0
        )
        XCTAssertNil(topLeading.top)
        XCTAssertNil(topLeading.leading)
        XCTAssertEqual(topLeading.bottom, 6)
        XCTAssertEqual(topLeading.trailing, 6)

        let raggedMiddleTrailing = ExploreCategoryChipTopology.neighborGaps(
            rowIndex: 1,
            rowItemCounts: [3, 3, 2],
            itemIndex: 2
        )
        XCTAssertEqual(raggedMiddleTrailing.top, 6)
        XCTAssertEqual(raggedMiddleTrailing.leading, 6)
        XCTAssertNil(raggedMiddleTrailing.bottom)
        XCTAssertNil(raggedMiddleTrailing.trailing)

        let bottomTrailing = ExploreCategoryChipTopology.neighborGaps(
            rowIndex: 2,
            rowItemCounts: [3, 3, 2],
            itemIndex: 1
        )
        XCTAssertEqual(bottomTrailing.top, 6)
        XCTAssertEqual(bottomTrailing.leading, 6)
        XCTAssertNil(bottomTrailing.bottom)
        XCTAssertNil(bottomTrailing.trailing)
    }

    func testJournalDoorContentProjectsHeroAndEveryNonTrackListInDatabaseOrder() {
        let content = JournalDoorContent.make(
            lists: [
                PlaceList(
                    id: 1,
                    name: "My tracks",
                    isSystem: true,
                    kind: PlaceList.trackKind,
                    createdAt: .distantPast
                ),
                PlaceList(
                    id: 2,
                    name: "Want to go",
                    isSystem: true,
                    createdAt: .distantPast
                ),
                PlaceList(
                    id: 3,
                    name: "Ghost signs",
                    isSystem: false,
                    createdAt: .distantPast
                ),
                PlaceList(
                    id: 4,
                    name: "KL follies",
                    isSystem: false,
                    createdAt: .distantPast
                ),
            ],
            progress: [
                2: ListProgress(visited: 1, total: 3),
                3: ListProgress(visited: 4, total: 11),
                4: ListProgress(visited: 7, total: 9),
            ],
            visits: [
                TrackVisit(
                    id: 10,
                    placeID: "p1",
                    visitedAt: Date(timeIntervalSince1970: 100),
                    verdict: nil,
                    name: "First",
                    category: "memorial",
                    tier: 1,
                    lat: 0,
                    lon: 0
                ),
                TrackVisit(
                    id: 11,
                    placeID: "p2",
                    visitedAt: Date(timeIntervalSince1970: 200),
                    verdict: nil,
                    name: "Thean Hou Temple",
                    category: "building",
                    tier: 1,
                    lat: 0,
                    lon: 0
                ),
            ],
            lovedPlaces: [
                ListPlace(
                    placeID: "loved",
                    name: "Loved Place",
                    category: "history",
                    pinState: PinState(saved: false, visit: .loved)
                ),
                ListPlace(
                    placeID: "both",
                    name: "Loved and Hidden",
                    category: "memorial",
                    pinState: PinState(saved: false, visit: .loved, hidden: true)
                ),
            ],
            hiddenPlaces: [
                ListPlace(
                    placeID: "both",
                    name: "Loved and Hidden",
                    category: "memorial",
                    pinState: PinState(saved: false, visit: .loved, hidden: true)
                ),
            ]
        )

        XCTAssertEqual(
            content.hero,
            JournalDoorHeroContent(
                listID: 1,
                metadata: "2 visits · last: Thean Hou Temple"
            )
        )
        XCTAssertEqual(
            content.lists,
            [
                JournalDoorListContent(
                    id: 2,
                    name: "Want to go",
                    isSystem: true,
                    progress: ListProgress(visited: 1, total: 3)
                ),
                JournalDoorListContent(
                    id: 3,
                    name: "Ghost signs",
                    isSystem: false,
                    progress: ListProgress(visited: 4, total: 11)
                ),
                JournalDoorListContent(
                    id: 4,
                    name: "KL follies",
                    isSystem: false,
                    progress: ListProgress(visited: 7, total: 9)
                ),
            ]
        )
        XCTAssertEqual(content.lovedCount, 2)
        XCTAssertEqual(content.hiddenCount, 1)
    }

    func testJournalDoorContentHandlesEmptyHistoryAndMissingProgressWithoutInventingRows() {
        let content = JournalDoorContent.make(
            lists: [
                PlaceList(
                    id: 1,
                    name: "My tracks",
                    isSystem: true,
                    kind: PlaceList.trackKind,
                    createdAt: .distantPast
                ),
                PlaceList(
                    id: nil,
                    name: "Unsaved",
                    isSystem: false,
                    createdAt: .distantPast
                ),
                PlaceList(
                    id: 2,
                    name: "Empty list",
                    isSystem: false,
                    createdAt: .distantPast
                ),
            ],
            progress: [:],
            visits: [],
            lovedPlaces: [],
            hiddenPlaces: []
        )

        XCTAssertEqual(
            content.hero,
            JournalDoorHeroContent(listID: 1, metadata: "No visits yet")
        )
        XCTAssertEqual(
            content.lists,
            [
                JournalDoorListContent(
                    id: 2,
                    name: "Empty list",
                    isSystem: false,
                    progress: ListProgress(visited: 0, total: 0)
                ),
            ]
        )
        XCTAssertEqual(content.lovedCount, 0)
        XCTAssertEqual(content.hiddenCount, 0)
    }

    func testManagedPlacesModesExposeRuledPresentationAndAccessibleActions() {
        let loved = ManagedPlacesMode.loved.presentation
        XCTAssertEqual(loved.title, "Loved places")
        XCTAssertEqual(loved.systemImage, "heart")
        XCTAssertEqual(loved.emptyTitle, "No loved places yet")
        XCTAssertEqual(
            loved.emptyGuidance,
            "Love a place you’ve seen and it’ll wait here."
        )
        XCTAssertEqual(loved.surfaceIdentifier, "tracks.loved.surface")
        XCTAssertEqual(loved.rowIdentifierPrefix, "tracks.loved.row")
        XCTAssertEqual(loved.primaryActionIdentifierPrefix, "tracks.loved.remove")
        XCTAssertNil(loved.secondaryActionIdentifierPrefix)
        XCTAssertEqual(loved.failureMessage, "Could not update that loved place.")
        XCTAssertEqual(
            ManagedPlacesMode.loved.actionAccessibilityLabel(placeName: "Alpha Arch"),
            "Remove loved from Alpha Arch"
        )

        let hidden = ManagedPlacesMode.hidden.presentation
        XCTAssertEqual(hidden.title, "Hidden places")
        XCTAssertEqual(hidden.systemImage, "eye.slash")
        XCTAssertEqual(hidden.emptyTitle, "No hidden places")
        XCTAssertEqual(
            hidden.emptyGuidance,
            "Places you hide will wait here until you bring them back."
        )
        XCTAssertEqual(hidden.surfaceIdentifier, "tracks.hidden.surface")
        XCTAssertEqual(hidden.rowIdentifierPrefix, "tracks.hidden.row")
        XCTAssertEqual(hidden.primaryActionIdentifierPrefix, "tracks.hidden.unhide")
        XCTAssertEqual(hidden.secondaryActionIdentifierPrefix, "tracks.hidden.save")
        XCTAssertEqual(
            hidden.primaryActionIdentifier(placeID: "hidden"),
            "tracks.hidden.unhide.hidden"
        )
        XCTAssertEqual(
            hidden.secondaryActionIdentifier(placeID: "hidden"),
            "tracks.hidden.save.hidden"
        )
        XCTAssertEqual(hidden.failureMessage, "Could not unhide that place.")
        XCTAssertEqual(
            ManagedPlacesMode.hidden.actionAccessibilityLabel(placeName: "Beta Plaque"),
            "Unhide Beta Plaque"
        )
    }

    func testManagedPlacesStateRemovesOnlySuccessfulMembershipAndRetainsFailures() {
        let loved = ListPlace(
            placeID: "loved",
            name: "Loved Place",
            category: "history",
            pinState: PinState(saved: false, visit: .loved)
        )
        let both = ListPlace(
            placeID: "both",
            name: "Loved and Hidden",
            category: "memorial",
            pinState: PinState(saved: false, visit: .loved, hidden: true)
        )
        var state = ManagedPlacesState(places: [loved, both])

        state.beginAction(placeID: loved.placeID)
        state.beginAction(placeID: both.placeID)
        XCTAssertTrue(state.isPending(placeID: loved.placeID))
        XCTAssertTrue(state.isPending(placeID: both.placeID))

        state.finishAction(
            placeID: loved.placeID,
            succeeded: true,
            failureMessage: "unused"
        )
        XCTAssertEqual(state.places, [both])
        XCTAssertFalse(state.isPending(placeID: loved.placeID))
        XCTAssertTrue(state.isPending(placeID: both.placeID))
        XCTAssertNil(state.errorMessage)

        state.finishAction(
            placeID: both.placeID,
            succeeded: false,
            failureMessage: "Could not update that loved place."
        )
        XCTAssertEqual(state.places, [both])
        XCTAssertTrue(state.pendingPlaceIDs.isEmpty)
        XCTAssertEqual(state.errorMessage, "Could not update that loved place.")

        var concurrentState = ManagedPlacesState(places: [loved, both])
        concurrentState.beginAction(placeID: loved.placeID)
        concurrentState.beginAction(placeID: both.placeID)
        concurrentState.finishAction(
            placeID: both.placeID,
            succeeded: false,
            failureMessage: "Could not update that loved place."
        )
        concurrentState.finishAction(
            placeID: loved.placeID,
            succeeded: true,
            failureMessage: "unused"
        )
        XCTAssertEqual(concurrentState.places, [both])
        XCTAssertTrue(concurrentState.pendingPlaceIDs.isEmpty)
        XCTAssertEqual(
            concurrentState.errorMessage,
            "Could not update that loved place.",
            "A later concurrent success must not erase another row's real failure."
        )
    }

    func testManagedPlacesStateRemovesHiddenRowAfterSaveAddition() {
        let hidden = ListPlace(
            placeID: "hidden",
            name: "Hidden",
            category: "memorial",
            pinState: PinState(saved: false, visit: .none, hidden: true)
        )
        var state = ManagedPlacesState(places: [hidden])

        state.removePlace(placeID: hidden.placeID)

        XCTAssertTrue(state.places.isEmpty)
    }

    func testListPickerMembershipChangeMapsPriorMembershipToCompletedDirection() {
        XCTAssertEqual(
            ListPickerMembershipChange.completed(wasMember: false, listID: 7),
            .added(listID: 7)
        )
        XCTAssertEqual(
            ListPickerMembershipChange.completed(wasMember: true, listID: 7),
            .removed(listID: 7)
        )
    }

    func testListPickerMembershipStateSerializesTogglesUntilReloadCompletes() {
        var state = ListPickerMembershipState(memberships: [7])

        XCTAssertEqual(state.beginToggle(listID: 7), .removed(listID: 7))
        XCTAssertTrue(state.isUpdating)
        XCTAssertNil(state.beginToggle(listID: 8))

        state.replaceMemberships([])
        state.finishMutation()

        XCTAssertFalse(state.isUpdating)
        XCTAssertEqual(state.beginToggle(listID: 7), .added(listID: 7))
    }

    @MainActor
    func testListPickerInitialReloadBlocksTogglesUntilCompleteSnapshotPublishes() async {
        var state = ListPickerMembershipState()
        var publishedSnapshot: ListPickerSnapshot?
        let (releaseLoad, releaseLoadContinuation) = AsyncStream<Void>.makeStream()

        let reload = Task { @MainActor in
            await ListPickerReloadCoordinator.perform {
                state.beginMutation()
            } finish: {
                state.finishMutation()
            } load: {
                for await _ in releaseLoad {
                    break
                }
                return ListPickerSnapshot(
                    lists: [
                        PlaceList(
                            id: 7,
                            name: "Trip",
                            isSystem: false,
                            createdAt: Date(timeIntervalSince1970: 0)
                        )
                    ],
                    memberships: [7]
                )
            } apply: { snapshot in
                publishedSnapshot = snapshot
                state.replaceMemberships(snapshot.memberships)
            }
        }

        var attempts = 0
        while !state.isUpdating, attempts < 100 {
            attempts += 1
            await Task.yield()
        }
        XCTAssertTrue(state.isUpdating)
        XCTAssertNil(publishedSnapshot)
        XCTAssertNil(state.beginToggle(listID: 7))

        releaseLoadContinuation.yield()
        releaseLoadContinuation.finish()
        await reload.value

        XCTAssertEqual(publishedSnapshot?.lists.map(\.id), [7])
        XCTAssertEqual(publishedSnapshot?.memberships, [7])
        XCTAssertFalse(state.isUpdating)
        XCTAssertEqual(state.beginToggle(listID: 7), .removed(listID: 7))
    }

    func testLovedManagedPlaceMetadataNamesHiddenOverlapWithoutFilteringIt() {
        let both = ListPlace(
            placeID: "both",
            name: "Loved and Hidden",
            category: "historic_building",
            pinState: PinState(saved: false, visit: .loved, hidden: true)
        )

        XCTAssertEqual(
            ManagedPlacesMode.loved.metadata(for: both),
            "Historic Building · Hidden"
        )
        XCTAssertEqual(
            ManagedPlacesMode.hidden.metadata(for: both),
            "Historic Building"
        )
    }

    @MainActor
    func testManagedPlacesAndVirtualRowIconsOwnRatifiedRolesAtPointOfUse() throws {
        let place = ListPlace(
            placeID: "both",
            name: "Loved and Hidden",
            category: "historic_building",
            pinState: PinState(saved: false, visit: .loved, hidden: true)
        )
        let lovedView = ManagedPlacesView(model: nil, mode: .loved)
        let hiddenView = ManagedPlacesView(model: nil, mode: .hidden)
        let tracksView = JournalDoorRootView(
            path: .constant([]),
            model: nil,
            prepareTracksHistory: {},
            onListDeleted: { _ in }
        )

        XCTAssertEqual(
            descendants(
                of: ManagedPlacesInlineIconGlyph.self,
                in: lovedView.titleRow
            ).count,
            1
        )
        XCTAssertEqual(
            descendants(
                of: ManagedPlacesEmptyIconGlyph.self,
                in: lovedView.emptyRow
            ).count,
            1
        )
        XCTAssertEqual(
            descendants(
                of: ManagedPlacesInlineIconGlyph.self,
                in: lovedView.placeRow(place)
            ).count,
            2,
            "A loved row must ratify both its row symbol and remove action."
        )
        XCTAssertEqual(
            descendants(
                of: ManagedPlacesInlineIconGlyph.self,
                in: hiddenView.placeRow(place)
            ).count,
            1,
            "A hidden row has one symbol; Unhide remains a text action."
        )
        XCTAssertEqual(
            descendants(
                of: JournalDoorVirtualRowIconGlyph.self,
                in: tracksView.virtualPlacesRow(
                    .lovedPlaces,
                    count: 2,
                    destination: .lovedPlaces
                )
            ).count,
            1
        )

        XCTAssertEqual(
            try XCTUnwrap(
                firstDescendant(
                    of: IconRole.self,
                    in: ManagedPlacesInlineIconGlyph(systemName: "heart").body
                )
            ),
            .inline
        )
        XCTAssertEqual(
            try XCTUnwrap(
                firstDescendant(
                    of: IconRole.self,
                    in: ManagedPlacesEmptyIconGlyph(systemName: "heart").body
                )
            ),
            .hero
        )
        XCTAssertEqual(
            try XCTUnwrap(
                firstDescendant(
                    of: IconRole.self,
                    in: JournalDoorVirtualRowIconGlyph(systemName: "heart").body
                )
            ),
            .inline
        )
    }

    @MainActor
    func testManagedPlacesActionCoordinatorRetainsRowAndShowsErrorWhenModelThrows() async throws {
        let database = try AppDatabase.inMemory()
        let unrelatedFixture = try PlaceRef(
            placeID: "fixture",
            name: "Fixture",
            lat: 51.5,
            lon: -0.1,
            category: "memorial",
            tier: 2,
            schemaVersion: 1,
            fetchedAt: Date(timeIntervalSince1970: 1),
            rawJSON: "{}"
        )
        let model = try MapScreenModel(
            database: database,
            fixturePlaces: [unrelatedFixture]
        )
        let missing = ListPlace(
            placeID: "missing",
            name: "Missing snapshot",
            category: "memorial",
            pinState: PinState(saved: false, visit: .none, hidden: true)
        )
        var state = ManagedPlacesState(places: [missing])

        await ManagedPlacesActionCoordinator.perform {
            state.beginAction(placeID: missing.placeID)
        } finish: { succeeded in
            state.finishAction(
                placeID: missing.placeID,
                succeeded: succeeded,
                failureMessage: "Could not unhide that place."
            )
        } operation: {
            try await model.setHidden(placeID: missing.placeID, hidden: false)
        }

        XCTAssertEqual(state.places, [missing])
        XCTAssertTrue(state.pendingPlaceIDs.isEmpty)
        XCTAssertEqual(state.errorMessage, "Could not unhide that place.")
    }

    @MainActor
    func testAddingHiddenPlaceToListMirrorsAutoUnhideAndMarksOneRefresh() async throws {
        let database = try AppDatabase.inMemory()
        let place = try PlaceRef(
            placeID: "hidden-save",
            name: "Hidden save",
            lat: 51.5,
            lon: -0.1,
            category: "memorial",
            tier: 2,
            schemaVersion: 1,
            fetchedAt: Date(timeIntervalSince1970: 1),
            rawJSON: "{}"
        )
        try database.setHidden(place, true)
        let model = try MapScreenModel(database: database, fixturePlaces: [place])

        try await model.addToList(placeID: place.placeID, listID: database.wantToGoListID())

        XCTAssertFalse(model.hiddenIDs.contains(place.placeID))
        XCTAssertTrue(model.consumeHiddenMembershipChange(overlapping: [place.placeID]))
        XCTAssertFalse(model.consumeHiddenMembershipChange(overlapping: [place.placeID]))
    }

    @MainActor
    func testAddingOversizedSnapshotOnlyHiddenPlaceToListUsesActionSafeSource() async throws {
        let database = try AppDatabase.inMemory()
        let snapshotOnlyPlace = try PlaceRef(
            placeID: "snapshot-only-hidden-save",
            name: "Snapshot-only hidden save",
            lat: 51.5,
            lon: -0.1,
            category: "memorial",
            tier: 2,
            schemaVersion: 1,
            fetchedAt: Date(timeIntervalSince1970: 1),
            rawJSON: "{}"
        )
        let unrelatedFixture = try PlaceRef(
            placeID: "fixture",
            name: "Fixture",
            lat: 51.6,
            lon: -0.2,
            category: "museum",
            tier: 2,
            schemaVersion: 1,
            fetchedAt: Date(timeIntervalSince1970: 1),
            rawJSON: "{}"
        )
        try database.setHidden(snapshotOnlyPlace, true)
        let originalSnapshot = try XCTUnwrap(
            database.snapshot(for: snapshotOnlyPlace.placeID)
        )
        let oversizedSnapshot = PlaceSnapshot(
            placeID: originalSnapshot.placeID,
            name: originalSnapshot.name,
            lat: originalSnapshot.lat,
            lon: originalSnapshot.lon,
            category: originalSnapshot.category,
            tier: originalSnapshot.tier,
            snapshotJSON: String(repeating: "x", count: PlaceRef.maxRawJSONBytes + 1),
            snapshotSchemaVersion: originalSnapshot.snapshotSchemaVersion,
            fetchedAt: originalSnapshot.fetchedAt
        )
        try await database.dbQueue.write { database in
            try oversizedSnapshot.update(database)
        }
        let model = try MapScreenModel(
            database: database,
            fixturePlaces: [unrelatedFixture]
        )
        let wantToGoListID = try database.wantToGoListID()

        try await model.addToList(
            placeID: snapshotOnlyPlace.placeID,
            listID: wantToGoListID
        )

        XCTAssertEqual(
            try database.listMemberships(containing: snapshotOnlyPlace.placeID),
            [wantToGoListID]
        )
        XCTAssertFalse(try database.hiddenPlaceIDs().contains(snapshotOnlyPlace.placeID))
        XCTAssertFalse(model.hiddenIDs.contains(snapshotOnlyPlace.placeID))
    }

    @MainActor
    func testFailedSaveRollsBackOptimisticAutoUnhide() async throws {
        let database = try AppDatabase.inMemory()
        let place = try PlaceRef(
            placeID: "hidden-save-failure",
            name: "Hidden save failure",
            lat: 51.5,
            lon: -0.1,
            category: "memorial",
            tier: 2,
            schemaVersion: 1,
            fetchedAt: Date(timeIntervalSince1970: 1),
            rawJSON: "{}"
        )
        try database.setHidden(place, true)
        let model = try MapScreenModel(database: database, fixturePlaces: [place])
        let lists = await model.lists()
        let trackListID = try XCTUnwrap(
            lists.first { $0.isSystem && $0.kind == PlaceList.trackKind }?.id
        )

        do {
            try await model.addToList(placeID: place.placeID, listID: trackListID)
            XCTFail("Expected protected track-list write to fail")
        } catch {
            XCTAssertEqual(error as? AppDatabaseError, .systemListIsProtected)
        }

        XCTAssertTrue(model.hiddenIDs.contains(place.placeID))
        XCTAssertFalse(model.consumeHiddenMembershipChange(overlapping: [place.placeID]))
    }

    func testQuietChromeUsesTokenSurfacesAndBareAttribution() {
        XCTAssertEqual(MapDoorChromeSpec.attributionTypographyRole, .label)
        XCTAssertFalse(MapDoorChromeSpec.attributionHasBackground)
        XCTAssertEqual(MapDoorChromeSpec.locateMinimumHitTarget, 44)
        XCTAssertTrue(MapDoorChromeSpec.usesBuiltInCompass)
    }

    @MainActor
    func testLocationSettingsGearOwnsInlineIconRole() throws {
        XCTAssertEqual(
            try XCTUnwrap(
                firstDescendant(
                    of: IconRole.self,
                    in: MapLocationOffToast(onOpenSettings: {}).body
                )
            ),
            .inline
        )
    }

    @MainActor
    func testAdoptedSurfaceIconsOwnFontRenderingAndTintAgainstHostileAmbientStyle() throws {
        let glyphs: [(name: String, glyph: AnyView)] = [
            (
                "destination close",
                AnyView(MapDoorDestinationCloseIconGlyph())
            ),
            (
                "door row",
                AnyView(MapDoorRowIconGlyph(systemName: "cloud.sun.rain.fill"))
            ),
            (
                "door button",
                AnyView(MapDoorButtonIconGlyph(systemName: "globe"))
            ),
            (
                "place-card More",
                AnyView(PlaceCardMoreIconGlyph())
            ),
            (
                "missing-photo fallback",
                AnyView(PlaceCardMissingPhotoIconGlyph())
            ),
        ]

        for dynamicTypeSize in [DynamicTypeSize.large, .accessibility5] {
            for glyph in glyphs {
                let expected = try renderedAppGlyph(
                    glyph.glyph,
                    dynamicTypeSize: dynamicTypeSize
                )
                let actual = try renderedAppGlyph(
                    glyph.glyph
                        .font(.largeTitle.bold())
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.red, Color.blue),
                    dynamicTypeSize: dynamicTypeSize
                )

                XCTAssertEqual(
                    actual,
                    expected,
                    "\(glyph.name) must override hostile ambient font, palette rendering, and tint"
                )
            }
        }
    }

    @MainActor
    func testAdoptedSurfaceConsumersWireOwnedGlyphsAtPointOfUse() {
        let destinationSheet = MapDoorSheet(
            door: .explore,
            deepLinkDestination: nil,
            model: nil,
            visibility: .constant(MapLayerVisibility()),
            prepareTracksHistory: {},
            onListDeleted: { _ in }
        ) { _ in
            EmptyView()
        }
        let rowPresentation = MapDoorRowPresentation(
            title: "Settings",
            subtitle: "preferences",
            systemImage: "gearshape",
            accessibilityIdentifier: "explore.row.settings"
        )
        let placeCard = PlaceCardSheet(
            placeID: "mt1_00000000000000000000000000",
            model: nil,
            onHide: { _, _ in },
            onManageVisits: { _ in },
            setNearbyPromptSuppressed: { _, _ in false },
            showHiddenMode: false
        )
        let photoSlot = PlaceCardPhotoSlot(
            photo: PlaceCardPhoto(
                accessibilityLabel: "Photo unavailable",
                attribution: "Fixture"
            ),
            model: nil,
            appearance: PlaceCardAppearance(theme: .snow)
        )

        XCTAssertEqual(
            descendants(
                of: MapDoorDestinationCloseIconGlyph.self,
                in: destinationSheet.destinationView(.settings)
            ).count,
            1
        )
        XCTAssertEqual(
            descendants(
                of: MapDoorRowIconGlyph.self,
                in: MapDoorRowLabel(presentation: rowPresentation).body
            ).count,
            1
        )
        XCTAssertEqual(
            descendants(
                of: MapDoorButtonIconGlyph.self,
                in: MapDoorButton(door: .explore, action: {}).body
            ).count,
            1
        )
        XCTAssertEqual(
            descendants(
                of: PlaceCardMoreIconGlyph.self,
                in: placeCard.header
            ).count,
            1
        )
        XCTAssertEqual(
            descendants(
                of: PlaceCardMissingPhotoIconGlyph.self,
                in: photoSlot.body
            ).count,
            1
        )
    }

    @MainActor
    func testAdoptedSurfaceIconsWireOwnedRolesAtPointOfUse() throws {
        XCTAssertEqual(
            try XCTUnwrap(
                firstDescendant(
                    of: IconRole.self,
                    in: MapDoorDestinationCloseIconGlyph().body
                )
            ),
            .inline
        )
        XCTAssertEqual(
            try XCTUnwrap(
                firstDescendant(
                    of: IconRole.self,
                    in: MapDoorButtonIconGlyph(systemName: "globe").body
                )
            ),
            .inline
        )
        XCTAssertEqual(
            try XCTUnwrap(
                firstDescendant(
                    of: IconRole.self,
                    in: PlaceCardMoreIconGlyph().body
                )
            ),
            .hero
        )
        XCTAssertEqual(
            try XCTUnwrap(
                firstDescendant(
                    of: IconRole.self,
                    in: PlaceCardMissingPhotoIconGlyph().body
                )
            ),
            .hero
        )
    }

    @MainActor
    func testAdoptedSurfaceLiteralIconsMatchFrozenRenderTypography() throws {
        let rowRenderingMode = try XCTUnwrap(
            firstDescendant(
                of: SymbolRenderingMode.self,
                in: MapDoorRowIconGlyph(systemName: "gearshape").body
            )
        )
        XCTAssertEqual(
            String(reflecting: rowRenderingMode),
            String(reflecting: SymbolRenderingMode.monochrome),
            "The cited row literal must explicitly own its symbol rendering mode."
        )

        let glyphs: [
            (
                name: String,
                actual: AnyView,
                expected: AnyView
            )
        ] = [
            (
                "door row",
                AnyView(MapDoorRowIconGlyph(systemName: "gearshape")),
                AnyView(RatifiedMapDoorRowIcon(systemName: "gearshape"))
            ),
        ]

        for dynamicTypeSize in [DynamicTypeSize.large, .accessibility5] {
            for glyph in glyphs {
                XCTAssertEqual(
                    try renderedAppGlyph(
                        glyph.actual,
                        dynamicTypeSize: dynamicTypeSize
                    ),
                    try renderedAppGlyph(
                        glyph.expected,
                        dynamicTypeSize: dynamicTypeSize
                    ),
                    "\(glyph.name) must match the frozen render's size and medium weight"
                )
            }
        }
    }

    @MainActor
    func testMapDoorBarRendersAtStandardAndAX5DynamicType() {
        for dynamicTypeSize in [DynamicTypeSize.large, .accessibility5] {
            let renderer = ImageRenderer(
                content: MapDoorBar(openExplore: {}, openJournal: {})
                    .environment(\.dynamicTypeSize, dynamicTypeSize)
                    .frame(width: 390)
            )

            XCTAssertNotNil(renderer.uiImage)
        }
    }

    @MainActor
    func testJournalDoorHeroIconUsesHeroRole() throws {
        for dynamicTypeSize in [DynamicTypeSize.large, .accessibility5] {
            let actual = try journalDoorRenderedSize(
                JournalDoorHeroIconGlyph(systemName: "figure.walk")
                    .font(.largeTitle),
                dynamicTypeSize: dynamicTypeSize
            )
            let expected = try journalDoorRenderedSize(
                RatifiedJournalDoorHeroIcon(systemName: "figure.walk"),
                dynamicTypeSize: dynamicTypeSize
            )

            XCTAssertEqual(actual.width, expected.width, accuracy: 1)
            XCTAssertEqual(actual.height, expected.height, accuracy: 1)
        }
    }

    @MainActor
    func testJournalDoorNewListIconUsesInlineRole() throws {
        for dynamicTypeSize in [DynamicTypeSize.large, .accessibility5] {
            let actual = try journalDoorRenderedSize(
                JournalDoorNewListIcon(systemName: "plus"),
                dynamicTypeSize: dynamicTypeSize
            )
            let expected = try journalDoorRenderedSize(
                RatifiedJournalDoorInlineIcon(systemName: "plus"),
                dynamicTypeSize: dynamicTypeSize
            )

            XCTAssertEqual(actual.width, expected.width, accuracy: 1)
            XCTAssertEqual(actual.height, expected.height, accuracy: 1)
        }
    }

    @MainActor
    func testJournalDoorIconsWireRatifiedRolesAtPointOfUse() throws {
        XCTAssertEqual(
            try XCTUnwrap(
                firstDescendant(
                    of: IconRole.self,
                    in: JournalDoorHeroIconGlyph(
                        systemName: "figure.walk"
                    ).body
                )
            ),
            .hero
        )
        XCTAssertEqual(
            try XCTUnwrap(
                firstDescendant(
                    of: IconRole.self,
                    in: JournalDoorNewListIcon(
                        systemName: "plus"
                    ).body
                )
            ),
            .inline
        )
        XCTAssertEqual(
            try XCTUnwrap(
                firstDescendant(
                    of: IconRole.self,
                    in: JournalDoorRetraceCue().body
                )
            ),
            .accessory
        )
    }

    @MainActor
    func testJournalDoorRetraceCueUsesRatifiedActionRoleGapAndChevronScale() throws {
        for dynamicTypeSize in [DynamicTypeSize.large, .accessibility5] {
            let actual = try journalDoorRenderedSize(
                JournalDoorRetraceCue(),
                dynamicTypeSize: dynamicTypeSize
            )
            let expected = try journalDoorRenderedSize(
                RatifiedJournalDoorRetraceCue(),
                dynamicTypeSize: dynamicTypeSize
            )

            XCTAssertEqual(actual.width, expected.width, accuracy: 1)
            XCTAssertEqual(actual.height, expected.height, accuracy: 1)
        }
    }

    @MainActor
    func testJournalDoorHeroTitleKeepsRatifiedEighteenPointHierarchy() throws {
        let shortTitle = "My"
        let longTitle = "My tracks"

        for dynamicTypeSize in [DynamicTypeSize.large, .accessibility5] {
            let actualDelta = try journalDoorRenderedSize(
                JournalDoorHeroTitle(title: shortTitle),
                dynamicTypeSize: dynamicTypeSize
            ).width - journalDoorRenderedSize(
                JournalDoorHeroTitle(title: longTitle),
                dynamicTypeSize: dynamicTypeSize
            ).width
            let expectedDelta = try journalDoorRenderedSize(
                RatifiedJournalDoorHeroTitle(title: shortTitle),
                dynamicTypeSize: dynamicTypeSize
            ).width - journalDoorRenderedSize(
                RatifiedJournalDoorHeroTitle(title: longTitle),
                dynamicTypeSize: dynamicTypeSize
            ).width

            XCTAssertEqual(actualDelta, expectedDelta, accuracy: 1)
        }
    }

    func testAppShellModelOpensJournalAndExploreAtTheirRoots() {
        let shell = AppShellModel()

        XCTAssertNil(shell.presentedDoor)
        XCTAssertNil(shell.deepLinkDestination)

        shell.openExploreDoor()
        XCTAssertEqual(shell.presentedDoor, .explore)
        XCTAssertNil(shell.deepLinkDestination)

        shell.openJournalDoor()
        XCTAssertEqual(shell.presentedDoor, .journal)
        XCTAssertNil(shell.deepLinkDestination)
    }

    func testAppShellModelRoutesOfflineMapsDeepLinkThroughExploreDoor() {
        let shell = AppShellModel()

        shell.openOfflineMapsDeepLink()

        XCTAssertEqual(shell.presentedDoor, .explore)
        XCTAssertEqual(shell.deepLinkDestination, .offlineMaps)
    }

    func testAppShellModelRoutesListsDeepLinkThroughJournalDoor() {
        let shell = AppShellModel()

        shell.openListsDeepLink()

        XCTAssertEqual(shell.presentedDoor, .journal)
        XCTAssertNil(shell.deepLinkDestination)
    }

    func testAppShellModelRoutesListDetailDeepLinkThroughListsPath() {
        let shell = AppShellModel()

        shell.openListDetailDeepLink(listID: 42, visitFilter: .loved)

        XCTAssertEqual(shell.presentedDoor, .journal)
        XCTAssertEqual(shell.deepLinkDestination, .listDetail(42))
        XCTAssertEqual(shell.listDetailVisitFilter, .loved)
    }

    func testAppShellModelRoutesTracksDeepLinkThroughJournalDoor() {
        let shell = AppShellModel()

        shell.openTracksDeepLink()

        XCTAssertEqual(shell.presentedDoor, .journal)
        XCTAssertEqual(shell.deepLinkDestination, .tracks)
        XCTAssertNil(shell.tracksFocusPlaceID)
    }

    func testAppShellModelCanRouteTracksDeepLinkWithFocusedPlace() {
        let shell = AppShellModel()

        shell.openTracksDeepLink(focusingPlaceID: "p_repeat")

        XCTAssertEqual(shell.presentedDoor, .journal)
        XCTAssertEqual(shell.deepLinkDestination, .tracks)
        XCTAssertEqual(shell.tracksFocusPlaceID, "p_repeat")
    }

    func testAppShellModelClearsOnlyTheFocusedTrackStateForRootHero() {
        let shell = AppShellModel()
        shell.openTracksDeepLink(focusingPlaceID: "p_repeat")

        shell.prepareTracksHistory()

        XCTAssertNil(shell.tracksFocusPlaceID)
        XCTAssertEqual(shell.listDetailVisitFilter, .all)
        XCTAssertEqual(shell.presentedDoor, .journal)
        XCTAssertEqual(shell.deepLinkDestination, .tracks)
    }

    func testAppShellModelClearsTrackFocusForJournalAndExploreRootsAndOtherDeepLinks() {
        let shell = AppShellModel()
        shell.openTracksDeepLink(focusingPlaceID: "p_repeat")

        shell.openExploreDoor()

        XCTAssertEqual(shell.presentedDoor, .explore)
        XCTAssertNil(shell.deepLinkDestination)
        XCTAssertNil(shell.tracksFocusPlaceID)

        shell.openTracksDeepLink(focusingPlaceID: "p_repeat")
        shell.openOfflineMapsDeepLink()

        XCTAssertEqual(shell.presentedDoor, .explore)
        XCTAssertEqual(shell.deepLinkDestination, .offlineMaps)
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

    func testListCreateFailureCopyDistinguishesEmptyNamesFromLengthFailures() {
        XCTAssertEqual(
            ListsCopy.listNameCreateFailureMessage(for: AppDatabaseError.emptyListName, draftName: "   "),
            "Enter a list name."
        )
        XCTAssertEqual(
            ListsCopy.listNameCreateFailureMessage(for: AppDatabaseError.emptyListName, draftName: "\u{0007}\u{200B}"),
            "Enter a list name."
        )
        XCTAssertEqual(
            ListsCopy.listNameCreateFailureMessage(
                for: AppDatabaseError.listNameTooLong,
                draftName: String(repeating: "x", count: 81)
            ),
            "Use a shorter list name."
        )
        XCTAssertEqual(
            ListsCopy.listNameCreateFailureMessage(for: AppDatabaseError.unreadableDatabase, draftName: "KL walk"),
            "Could not create that list."
        )
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
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_GB")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let timeline = TrackTimelineModel(visits: [
            trackVisit(id: 1, seconds: 0),
            trackVisit(id: 2, seconds: 60),
            trackVisit(id: 3, seconds: 60 * 60 * 24 * 12),
        ], calendar: calendar)

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

    func testTrackTimelineAutoplayBeatKeepsPlacePingUnderASecond() {
        XCTAssertEqual(TrackTimelineModel.autoplayBeatDuration, 0.5)
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

    func testTrackReplayPinPresentationScopesDisplayToReplayContext() {
        let features = [
            (MapPlace(id: "attraction", lat: 51.501, lon: -0.101, tier: 2, category: "attraction"), PinState(saved: false, visit: .visited)),
            (MapPlace(id: "historic", lat: 51.502, lon: -0.102, tier: 2, category: "historic_building"), PinState(saved: false, visit: .visited)),
        ]
        let context = TrackGeometryContext(visits: [
            trackVisit(id: 1, placeID: "attraction", seconds: 0),
        ])

        let replayed = TrackReplayPinPresentation.features(
            features,
            context: context,
            throughEventIndex: 0
        )

        XCTAssertEqual(replayed.map(\.0.id), ["attraction"])
        XCTAssertEqual(
            TrackReplayPinPresentation.features(features, context: .empty, throughEventIndex: nil).map(\.0.id),
            []
        )
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
        XCTAssertEqual(chips.map(\.isToggle), [false, false, false, false])
    }

    func testTrackFilterPickerDraftComposesLovedListsAndTypesIntoVisitFilter() {
        var draft = TrackFilterPickerDraft(
            filter: TracksVisitFilter(lovedOnly: false, listIDs: [77], categories: ["history"])
        )

        draft.toggleLoved()
        draft.toggleList(id: 88)
        draft.toggleCategory("architecture")
        draft.toggleCategory("history")

        XCTAssertEqual(
            draft.filter,
            TracksVisitFilter(lovedOnly: true, listIDs: [77, 88], categories: ["architecture"])
        )
    }

    func testTrackFilterPickerTreatsNoSelectedCategoryButtonsAsAllCategories() {
        var draft = TrackFilterPickerDraft()

        XCTAssertTrue(draft.includesAllCategories)
        draft.toggleCategory("history")
        XCTAssertEqual(draft.categories, ["history"])
        XCTAssertFalse(draft.includesAllCategories)

        draft.toggleCategory("history")
        XCTAssertNil(draft.categories)
        XCTAssertTrue(draft.includesAllCategories)
        XCTAssertEqual(draft.filter, .all)
    }

    func testTrackFilterPickerCanExplicitlyReturnFromNoCategoriesToAll() {
        var draft = TrackFilterPickerDraft(
            filter: TracksVisitFilter(categories: Set<String>())
        )

        XCTAssertFalse(draft.includesAllCategories)
        draft.selectAllCategories()

        XCTAssertTrue(draft.includesAllCategories)
        XCTAssertEqual(draft.filter, .all)
    }

    func testTrackFilterPickerActionLabelReportsOnlyScopedVisitCount() {
        XCTAssertEqual(TrackFilterPickerCopy.applyLabel(scopedVisitCount: 27), "Show 27 visits")
        XCTAssertEqual(TrackFilterPickerCopy.applyLabel(scopedVisitCount: 1), "Show 1 visit")
    }

    func testTrackFilterPickerActiveChipsKeepLovedInOneFilterFamily() {
        let chips = ListMapFilterChips.chips(
            for: TracksVisitFilter(lovedOnly: true, listIDs: [77], categories: ["history"])
        )

        XCTAssertEqual(chips.map(\.title), ["Loved", "1 list", "history"])
        XCTAssertEqual(chips.first?.isToggle, false)
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

    func testTrackReplaySnapshotCacheReturnsEventPrefixes() {
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

    func testTrackReplaySnapshotCachePrecomputedMatchesLazySnapshots() throws {
        let context = TrackGeometryContext(
            visits: [
                trackVisit(id: 1, seconds: 0),
                trackVisit(id: 2, seconds: 60),
                trackVisit(id: 3, seconds: 120),
                trackVisit(id: 4, seconds: 180),
            ]
        )
        let lazyCache = TrackReplaySnapshotCache(context: context)
        let precomputedCache = try XCTUnwrap(TrackReplaySnapshotCache.precomputed(context: context))

        for index in [-1, 0, 1, 2, 3, 4] {
            XCTAssertEqual(
                precomputedCache.snapshot(throughEventIndex: index).signature,
                lazyCache.snapshot(throughEventIndex: index).signature,
                "Precomputed replay snapshot differed from lazy snapshot at index \(index)"
            )
        }
        XCTAssertEqual(
            precomputedCache.snapshot(throughEventIndex: nil).signature,
            lazyCache.snapshot(throughEventIndex: nil).signature
        )
    }

    func testTrackReplaySnapshotCachePrecomputeStopsWhenCancelled() {
        let context = TrackGeometryContext(
            visits: [
                trackVisit(id: 1, seconds: 0),
                trackVisit(id: 2, seconds: 60),
                trackVisit(id: 3, seconds: 120),
            ]
        )

        let cache = TrackReplaySnapshotCache.precomputed(
            context: context,
            isCancelled: { true }
        )

        XCTAssertNil(cache)
    }

    func testTrackReplaySnapshotCacheConstructionStaysInsideLargeReplayListOpenBudget() {
        let context = TrackGeometryContext(
            visits: (0..<500).map { index in
                trackVisit(id: Int64(index + 1), seconds: TimeInterval(index * 60))
            }
        )

        let start = Date()
        _ = TrackReplaySnapshotCache(context: context)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 0.025, "500-visit replay cache construction took \(elapsed)s")
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

    func testTrackReplaySnapshotCacheCanPartiallyDrawArrivingArc() throws {
        let context = TrackGeometryContext(
            visits: [
                trackVisit(id: 1, seconds: 0),
                trackVisit(id: 2, seconds: 60),
            ]
        )
        let cache = TrackReplaySnapshotCache(context: context)

        let partialCoordinates = try trackSegmentCoordinateCount(in: cache.snapshot(throughEventIndex: 1, activeArcProgress: 0.35))
        let completeCoordinates = try trackSegmentCoordinateCount(in: cache.snapshot(throughEventIndex: 1, activeArcProgress: 1.0))

        XCTAssertGreaterThan(partialCoordinates, 1)
        XCTAssertLessThan(partialCoordinates, completeCoordinates)
    }

    func testTrackTimelineDateMarkerLabelsUseCalendarLocale() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "fr_FR")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let timeline = TrackTimelineModel(
            visits: [
                trackVisit(id: 1, seconds: 1_721_433_600),
            ],
            calendar: calendar
        )

        XCTAssertEqual(timeline.dateMarkers.map(\.label), ["20 juil."])
    }

    func testTrackReplayTimelineVelocityZoomThresholds() {
        XCTAssertEqual(TrackReplayTimelineZoomLevel.level(forDragVelocity: 900), .coarse)
        XCTAssertEqual(TrackReplayTimelineZoomLevel.level(forDragVelocity: 120), .detail)
    }

    func testTrackReplayTimelineLayoutUsesEqualEventSpacingAndDecimatedLabels() {
        let timeline = TrackTimelineModel(visits: [
            trackVisit(id: 1, seconds: 0),
            trackVisit(id: 2, seconds: 60),
            trackVisit(id: 3, seconds: 120),
            trackVisit(id: 4, seconds: 180),
        ])

        let marks = TrackReplayTimelineLayout.marks(
            timeline: timeline,
            selectedIndex: 2,
            availableWidth: 180,
            zoomLevel: .coarse
        )

        XCTAssertEqual(marks.map(\.eventIndex), [0, 1, 2, 3])
        XCTAssertEqual(marks.map(\.position), [0, 1.0 / 3.0, 2.0 / 3.0, 1])
        XCTAssertEqual(marks.filter(\.isLabeled).map(\.eventIndex), [0, 3])
        XCTAssertEqual(marks.first { $0.eventIndex == 2 }?.isSelected, true)
    }

    func testTrackReplayTimelineLayoutShowsLocalTimeLabelsInDetailZoom() {
        let timeline = TrackTimelineModel(visits: (0..<5).map {
            trackVisit(id: Int64($0 + 1), seconds: TimeInterval($0 * 60 * 60))
        })

        let marks = TrackReplayTimelineLayout.marks(
            timeline: timeline,
            selectedIndex: 2,
            availableWidth: 180,
            zoomLevel: .detail
        )

        XCTAssertEqual(marks.filter(\.isLabeled).map(\.eventIndex), [1, 2, 3])
        XCTAssertTrue(marks.first { $0.eventIndex == 2 }?.label.contains(":") == true)
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

    func testListMapViewportUsesFilteredTrackContextWhenVisitFilterIsActive() {
        let places = [
            MapPlace(id: "kept", lat: 3.12, lon: 101.60, tier: 2, category: "museum"),
            MapPlace(id: "nearby", lat: 3.13, lon: 101.61, tier: 2, category: "museum"),
            MapPlace(id: "far", lat: 4.20, lon: 102.80, tier: 2, category: "museum"),
        ]
        let features = places.map { ($0, PinState(saved: false, visit: .visited)) }
        let context = TrackGeometryContext(visits: [
            trackVisit(id: 1, placeID: "kept", seconds: 0),
        ])

        let viewportPlaces = ListMapViewport.places(
            for: features,
            showVisited: true,
            visitFilter: TracksVisitFilter(lovedOnly: true),
            context: context
        )

        XCTAssertEqual(viewportPlaces.map(\.id), ["kept"])
    }

    func testListMapViewportKeepsDenseReplayMembersTightlyFramed() throws {
        let places = [
            MapPlace(id: "west", lat: 3.132, lon: 101.682, tier: 1, category: "attraction"),
            MapPlace(id: "east", lat: 3.136, lon: 101.686, tier: 1, category: "historic_building"),
            MapPlace(id: "middle", lat: 3.134, lon: 101.684, tier: 1, category: "museum"),
        ]

        let viewport = try XCTUnwrap(ListMapViewport.viewport(for: places))

        XCTAssertLessThan(viewport.bbox.maxLon - viewport.bbox.minLon, 0.008)
        XCTAssertLessThan(viewport.bbox.maxLat - viewport.bbox.minLat, 0.008)
        for place in places {
            XCTAssertTrue(viewport.bbox.contains(lon: place.lon, lat: place.lat), place.id)
        }
    }

    func testTrackVisitRowsUseMockupCardControls() {
        XCTAssertFalse(TrackVisitRowDensitySpec.usesInlineEditControls)
        XCTAssertTrue(TrackVisitRowDensitySpec.showsStandaloneDateLabel)
        XCTAssertGreaterThanOrEqual(TrackVisitRowDensitySpec.verticalSpacing, 8)
        XCTAssertGreaterThanOrEqual(TrackVisitRowDensitySpec.minimumHeight, 96)
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

    private func trackSegmentCoordinateCount(in snapshot: TrackSourceSnapshot) throws -> Int {
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: snapshot.data) as? [String: Any])
        let features = try XCTUnwrap(root["features"] as? [[String: Any]])
        let feature = try XCTUnwrap(features.first)
        let geometry = try XCTUnwrap(feature["geometry"] as? [String: Any])
        let coordinates = try XCTUnwrap(geometry["coordinates"] as? [[Double]])
        return coordinates.count
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

    func testListPickerTargetsIncludeWantToGoAndCustomListsButExcludeMyTracks() {
        let collection = PlaceList(id: 10, name: "Date night", isSystem: false, createdAt: Date(timeIntervalSince1970: 0))
        let wantToGo = PlaceList(id: 1, name: "Want to go", isSystem: true, createdAt: Date(timeIntervalSince1970: 0))
        let myTracks = PlaceList(
            id: 2,
            name: "My tracks",
            isSystem: true,
            kind: PlaceList.trackKind,
            createdAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(
            ListPickerTargetLists.options(from: [myTracks, collection, wantToGo]).map(\.name),
            ["Date night", "Want to go"]
        )
    }

    func testTrackVisitReorderingGroupsFullChronologicalRowsByLocalDay() {
        let calendar = Calendar(identifier: .gregorian)
        let visits = [
            trackVisit(id: 1, seconds: 100),
            trackVisit(id: 2, seconds: 200),
            trackVisit(id: 3, seconds: 90_000),
        ]

        let sections = TrackVisitReordering.daySections(for: visits, calendar: calendar)

        XCTAssertEqual(sections.map { $0.visits.map(\.id) }, [[1, 2], [3]])
    }

    func testTrackVisitReorderingBuildsOneMovableRowPerVisitWithInlineDayHeaders() {
        let calendar = Calendar(identifier: .gregorian)
        let dayOne = Date(timeIntervalSince1970: 60 * 60 * 24 * 10)
        let dayTwo = dayOne.addingTimeInterval(60 * 60 * 24)
        let visits = [
            trackVisit(id: 1, seconds: dayOne.timeIntervalSince1970 + 60),
            trackVisit(id: 2, seconds: dayOne.timeIntervalSince1970 + 120),
            trackVisit(id: 3, seconds: dayTwo.timeIntervalSince1970 + 60),
        ]

        let rows = TrackVisitReordering.rows(for: visits, calendar: calendar)

        XCTAssertEqual(rows.map { $0.visit.id }, [1, 2, 3])
        XCTAssertEqual(rows.compactMap(\.dayHeader), [
            calendar.startOfDay(for: dayOne),
            calendar.startOfDay(for: dayTwo),
        ])
        XCTAssertEqual(rows.map { $0.dayHeader != nil }, [true, false, true])
    }

    func testTrackVisitReorderingMovesRowsWithinDayByVisitID() {
        let visits = [
            trackVisit(id: 1, seconds: 100),
            trackVisit(id: 2, seconds: 200),
            trackVisit(id: 3, seconds: 300),
        ]

        XCTAssertEqual(
            TrackVisitReordering.reorderedIDs(in: visits, fromOffsets: IndexSet(integer: 0), toOffset: 3),
            [2, 3, 1]
        )
        XCTAssertNil(
            TrackVisitReordering.reorderedIDs(in: visits, fromOffsets: IndexSet(integer: 1), toOffset: 2)
        )
    }

    func testTrackVisitReorderingPlansCrossDayMoveIntoTargetSlot() {
        let calendar = Calendar(identifier: .gregorian)
        let dayOne = Date(timeIntervalSince1970: 60 * 60 * 24 * 10)
        let dayTwo = dayOne.addingTimeInterval(60 * 60 * 24)
        let visits = [
            trackVisit(id: 1, seconds: dayOne.timeIntervalSince1970 + 60),
            trackVisit(id: 2, seconds: dayOne.timeIntervalSince1970 + 120),
            trackVisit(id: 3, seconds: dayTwo.timeIntervalSince1970 + 60),
            trackVisit(id: 4, seconds: dayTwo.timeIntervalSince1970 + 120),
        ]

        let plan = TrackVisitReordering.movePlan(
            in: visits,
            fromOffsets: IndexSet(integer: 1),
            toOffset: 3,
            calendar: calendar
        )

        XCTAssertEqual(
            plan,
            .moveVisit(id: 2, targetDay: calendar.startOfDay(for: dayTwo), targetDayOrderedIDs: [3, 2, 4])
        )
    }

    func testTrackVisitReorderingPlansSameDayMoveAsDayReorder() {
        let calendar = Calendar(identifier: .gregorian)
        let day = Date(timeIntervalSince1970: 60 * 60 * 24 * 10)
        let visits = [
            trackVisit(id: 1, seconds: day.timeIntervalSince1970 + 60),
            trackVisit(id: 2, seconds: day.timeIntervalSince1970 + 120),
            trackVisit(id: 3, seconds: day.timeIntervalSince1970 + 180),
        ]

        let plan = TrackVisitReordering.movePlan(
            in: visits,
            fromOffsets: IndexSet(integer: 0),
            toOffset: 3,
            calendar: calendar
        )

        XCTAssertEqual(
            plan,
            .reorderDay(day: calendar.startOfDay(for: day), orderedIDs: [2, 3, 1])
        )
    }

    func testTrackVisitReorderingKeepsSameDayMoveAtBoundaryOnOriginalDay() {
        let calendar = Calendar(identifier: .gregorian)
        let dayOne = Date(timeIntervalSince1970: 60 * 60 * 24 * 10)
        let dayTwo = dayOne.addingTimeInterval(60 * 60 * 24)
        let visits = [
            trackVisit(id: 1, seconds: dayOne.timeIntervalSince1970 + 60),
            trackVisit(id: 2, seconds: dayOne.timeIntervalSince1970 + 120),
            trackVisit(id: 3, seconds: dayTwo.timeIntervalSince1970 + 60),
        ]

        let plan = TrackVisitReordering.movePlan(
            in: visits,
            fromOffsets: IndexSet(integer: 0),
            toOffset: 2,
            calendar: calendar
        )

        XCTAssertEqual(
            plan,
            .reorderDay(day: calendar.startOfDay(for: dayOne), orderedIDs: [2, 1])
        )
    }

    func testTrackVisitReorderingRefusesCrossDayBlockMove() {
        let calendar = Calendar(identifier: .gregorian)
        let dayOne = Date(timeIntervalSince1970: 60 * 60 * 24 * 10)
        let dayTwo = dayOne.addingTimeInterval(60 * 60 * 24)
        let visits = [
            trackVisit(id: 1, seconds: dayOne.timeIntervalSince1970 + 60),
            trackVisit(id: 2, seconds: dayOne.timeIntervalSince1970 + 120),
            trackVisit(id: 3, seconds: dayTwo.timeIntervalSince1970 + 60),
        ]

        XCTAssertNil(
            TrackVisitReordering.movePlan(
                in: visits,
                fromOffsets: IndexSet([0, 1]),
                toOffset: 3,
                calendar: calendar
            )
        )
    }

    func testTrackVisitDragTriggerMapsDropPositionToExistingMoveOffset() {
        let orderedVisitIDs: [Int64] = [1, 2, 3]
        let rowFrames: [Int64: CGRect] = [
            1: CGRect(x: 0, y: 0, width: 300, height: 80),
            2: CGRect(x: 0, y: 90, width: 300, height: 80),
            3: CGRect(x: 0, y: 180, width: 300, height: 80),
        ]

        XCTAssertEqual(
            TrackVisitDragTrigger.destinationOffset(
                for: 1,
                dropY: 230,
                orderedVisitIDs: orderedVisitIDs,
                rowFrames: rowFrames
            ),
            3
        )
        XCTAssertEqual(
            TrackVisitDragTrigger.destinationOffset(
                for: 3,
                dropY: 10,
                orderedVisitIDs: orderedVisitIDs,
                rowFrames: rowFrames
            ),
            0
        )
    }

    func testTrackVisitDragTriggerMapsPositiveTranslationFromKnownSourceFrame() {
        let orderedVisitIDs: [Int64] = [1, 2, 3]
        let rowFrames: [Int64: CGRect] = [
            1: CGRect(x: 0, y: 0, width: 300, height: 80),
            2: CGRect(x: 0, y: 90, width: 300, height: 80),
            3: CGRect(x: 0, y: 180, width: 300, height: 80),
        ]

        XCTAssertEqual(
            TrackVisitDragTrigger.destinationOffset(
                for: 2,
                translationY: 90,
                orderedVisitIDs: orderedVisitIDs,
                rowFrames: rowFrames
            ),
            3,
            "Dragging the middle row down by one row must move it after the next row, not to index 0"
        )
    }

    func testTrackVisitDragTriggerUsesCapturedSourceAfterAutoScrollUnmountsRow() {
        let orderedVisitIDs: [Int64] = [1, 2, 3]
        let remainingRowFrames: [Int64: CGRect] = [
            1: CGRect(x: 0, y: 0, width: 300, height: 80),
            3: CGRect(x: 0, y: 180, width: 300, height: 80),
        ]

        XCTAssertEqual(
            TrackVisitDragTrigger.destinationOffset(
                for: 2,
                translationY: 90,
                sourceMidY: 130,
                orderedVisitIDs: orderedVisitIDs,
                rowFrames: remainingRowFrames
            ),
            3,
            "A lazy List unmounting the source row during edge auto-scroll must not cancel the drop"
        )
    }

    func testTrackVisitDragVisualSpecLiftsOnlyTheActiveRow() {
        let startFrame = CGRect(x: 16, y: 120, width: 370, height: 64)

        XCTAssertEqual(TrackVisitDragVisualSpec.scale(isActive: false), 1)
        XCTAssertGreaterThan(TrackVisitDragVisualSpec.scale(isActive: true), 1)
        XCTAssertEqual(
            TrackVisitDragVisualSpec.overlayFrame(
                startFrame: startFrame,
                translationY: 90
            ),
            CGRect(x: 16, y: 207, width: 370, height: 64)
        )
        XCTAssertEqual(
            TrackVisitDragVisualSpec.overlayFrame(
                startFrame: startFrame,
                translationY: -90
            ),
            CGRect(x: 16, y: 27, width: 370, height: 64)
        )
        XCTAssertEqual(TrackVisitDragVisualSpec.shadowOpacity(isActive: false), 0)
        XCTAssertGreaterThan(TrackVisitDragVisualSpec.shadowOpacity(isActive: true), 0)
    }

    func testTrackVisitDragTriggerRejectsUnknownOrUnmeasuredSource() {
        let orderedVisitIDs: [Int64] = [1, 2]
        let rowFrames: [Int64: CGRect] = [1: CGRect(x: 0, y: 0, width: 300, height: 80)]

        XCTAssertNil(
            TrackVisitDragTrigger.destinationOffset(
                for: 3,
                dropY: 10,
                orderedVisitIDs: orderedVisitIDs,
                rowFrames: rowFrames
            )
        )
        XCTAssertNil(
            TrackVisitDragTrigger.destinationOffset(
                for: 2,
                dropY: 10,
                orderedVisitIDs: orderedVisitIDs,
                rowFrames: rowFrames
            )
        )
    }

    func testTrackVisitDragTriggerFindsAdjacentOffscreenRowAtViewportEdge() {
        let orderedVisitIDs: [Int64] = [1, 2, 3, 4, 5, 6]
        let rowFrames: [Int64: CGRect] = [
            3: CGRect(x: 0, y: 100, width: 300, height: 80),
            4: CGRect(x: 0, y: 190, width: 300, height: 80),
        ]

        XCTAssertEqual(
            TrackVisitDragTrigger.autoScrollTargetID(
                dropY: 265,
                orderedVisitIDs: orderedVisitIDs,
                rowFrames: rowFrames,
                viewportBounds: CGRect(x: 0, y: 90, width: 300, height: 190)
            ),
            5
        )
        XCTAssertEqual(
            TrackVisitDragTrigger.autoScrollTargetID(
                dropY: 105,
                orderedVisitIDs: orderedVisitIDs,
                rowFrames: rowFrames,
                viewportBounds: CGRect(x: 0, y: 90, width: 300, height: 190)
            ),
            2
        )
        XCTAssertNil(
            TrackVisitDragTrigger.autoScrollTargetID(
                dropY: 180,
                orderedVisitIDs: orderedVisitIDs,
                rowFrames: rowFrames,
                viewportBounds: CGRect(x: 0, y: 90, width: 300, height: 190)
            )
        )
    }

    func testTrackVisitDragTriggerUsesViewportInsteadOfClippedOrPrefetchedRowEdges() {
        let orderedVisitIDs: [Int64] = [1, 2, 3, 4, 5, 6]
        let rowFrames: [Int64: CGRect] = [
            2: CGRect(x: 0, y: -120, width: 300, height: 70),
            3: CGRect(x: 0, y: -20, width: 300, height: 100),
            4: CGRect(x: 0, y: 90, width: 300, height: 290),
            5: CGRect(x: 0, y: 400, width: 300, height: 80),
        ]
        let viewport = CGRect(x: 0, y: 0, width: 300, height: 300)

        XCTAssertEqual(
            TrackVisitDragTrigger.autoScrollTargetID(
                dropY: 295,
                orderedVisitIDs: orderedVisitIDs,
                rowFrames: rowFrames,
                viewportBounds: viewport
            ),
            5
        )
        XCTAssertEqual(
            TrackVisitDragTrigger.autoScrollTargetID(
                dropY: 5,
                orderedVisitIDs: orderedVisitIDs,
                rowFrames: rowFrames,
                viewportBounds: viewport
            ),
            2
        )
        XCTAssertNil(
            TrackVisitDragTrigger.autoScrollTargetID(
                dropY: 150,
                orderedVisitIDs: orderedVisitIDs,
                rowFrames: rowFrames,
                viewportBounds: viewport
            )
        )
    }

    func testTrackVisitDragTriggerMapsAccessibilityStepsToMoveOffsets() {
        XCTAssertEqual(
            TrackVisitDragTrigger.accessibilityDestinationOffset(
                sourceIndex: 0,
                movingTowardEnd: true,
                visitCount: 3
            ),
            2
        )
        XCTAssertEqual(
            TrackVisitDragTrigger.accessibilityDestinationOffset(
                sourceIndex: 2,
                movingTowardEnd: false,
                visitCount: 3
            ),
            1
        )
        XCTAssertNil(
            TrackVisitDragTrigger.accessibilityDestinationOffset(
                sourceIndex: 0,
                movingTowardEnd: false,
                visitCount: 3
            )
        )
        XCTAssertNil(
            TrackVisitDragTrigger.accessibilityDestinationOffset(
                sourceIndex: 2,
                movingTowardEnd: true,
                visitCount: 3
            )
        )
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

    func testOnboardingRegionChoicesComeFromRegionCatalogRoots() throws {
        var regionIndex = appRegionIndexV3Object()
        regionIndex["regions"] = [
            appRegionIndexV3Entry([
                "id": "west-midlands",
                "display_name": "West Midlands",
                "bbox": [-3.0, 51.8, -1.1, 53.8],
                "search_compact": [
                    "path": "west-midlands/20260720T000000Z/search/compact.json",
                    "sha256": String(repeating: "c", count: 64),
                    "bytes": 201,
                    "schema_version": 1,
                ],
            ]),
            appRegionIndexV3Entry([
                "id": "west-midlands_birmingham",
                "display_name": "Birmingham",
                "parent": "west-midlands",
                "bbox": [-2.1, 52.3, -1.6, 52.7],
                "search_compact": [
                    "path": "west-midlands_birmingham/20260720T000000Z/search/compact.json",
                    "sha256": String(repeating: "d", count: 64),
                    "bytes": 199,
                    "schema_version": 1,
                ],
            ]),
        ]
        let catalog = OfflineRegionCatalog(regionIndex: try RegionIndex.decode(appJSONData(regionIndex)))

        let choices = OnboardingRegionChoice.catalogChoices(from: catalog)

        XCTAssertEqual(choices.map(\.publishRegionID), ["west-midlands"])
        XCTAssertEqual(choices.map(\.title), ["West Midlands"])
        XCTAssertEqual(choices.first?.startupViewport.bbox, BBox(minLon: -3.0, minLat: 51.8, maxLon: -1.1, maxLat: 53.8))
    }

    func testOnboardingRegionChoicesFailClosedWhenCatalogIsUnavailable() {
        XCTAssertEqual(OnboardingRegionChoice.catalogChoices(from: .empty), [])
    }

    func testCatalogSelectsPublishedRootRegionForViewportWithoutMapRegionAllowlist() throws {
        var regionIndex = appRegionIndexV3Object()
        regionIndex["regions"] = [
            appRegionIndexV3Entry([
                "id": "west-midlands",
                "display_name": "West Midlands",
                "bbox": [-3.0, 51.8, -1.1, 53.8],
                "search_compact": [
                    "path": "west-midlands/20260720T000000Z/search/compact.json",
                    "sha256": String(repeating: "c", count: 64),
                    "bytes": 201,
                    "schema_version": 1,
                ],
            ]),
            appRegionIndexV3Entry([
                "id": "north-west",
                "display_name": "North West",
                "bbox": [-3.7, 53.1, -1.5, 55.0],
                "search_compact": [
                    "path": "north-west/20260720T000000Z/search/compact.json",
                    "sha256": String(repeating: "e", count: 64),
                    "bytes": 203,
                    "schema_version": 1,
                ],
            ]),
        ]
        let catalog = OfflineRegionCatalog(regionIndex: try RegionIndex.decode(appJSONData(regionIndex)))

        let selected = catalog.selectedRootZoneID(
            for: BBox(minLon: -2.2, minLat: 52.3, maxLon: -1.6, maxLat: 52.8),
            current: nil
        )

        XCTAssertEqual(selected, "west-midlands")
        XCTAssertNil(MapRegion(rawValue: "west-midlands"))
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

    func testMapThemeColorParsesOpaqueHexAndSnowBoundaryToken() throws {
        let color = try XCTUnwrap(MapThemeColor.uiColor(css: MapTheme.definedPaper.background))
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        XCTAssertEqual(Int(round(red * 255)), 0xF3)
        XCTAssertEqual(Int(round(green * 255)), 0xEF)
        XCTAssertEqual(Int(round(blue * 255)), 0xE5)
        XCTAssertEqual(alpha, 1)

        let translucent = try XCTUnwrap(MapThemeColor.uiColor(css: MapTheme.snow.boundaries))
        XCTAssertTrue(translucent.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        XCTAssertEqual(Int(round(red * 255)), 43)
        XCTAssertEqual(Int(round(green * 255)), 40)
        XCTAssertEqual(Int(round(blue * 255)), 35)
        XCTAssertEqual(alpha, 0.14, accuracy: 0.001)
    }

    func testMapThemeColorRejectsMalformedCSSInsteadOfSubstitutingBeige() {
        XCTAssertNil(MapThemeColor.uiColor(css: "not-a-color"))
        XCTAssertNil(MapThemeColor.components(css: "not-a-color"))
        XCTAssertNil(MapThemeColor.components(css: "-12345"))
        XCTAssertNil(MapThemeColor.components(css: "+12345"))
        XCTAssertNil(MapThemeColor.components(css: "rgba(256, 40, 35, 0.14)"))
        XCTAssertNil(MapThemeColor.components(css: "rgba(43, 40, 35, 1.4)"))
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

    func testStorageMenuStatusUsesCatalogDisplayNamesForInstalledPacks() throws {
        let catalog = OfflineRegionCatalog(regionIndex: try RegionIndex.decode(appJSONData(appRegionIndexV3Object())))
        let status = StorageMenuStatus.ready(
            from: OfflinePackStorageSummary(
                packs: [
                    InstalledOfflinePackStorage(
                        region: "malaysia-singapore-brunei",
                        publishVersion: "20260719T125813Z",
                        tileCount: 12,
                        tileBytes: 2_000_000,
                        basemapBytes: 1_000_000,
                        referencedBytes: 3_000_000
                    ),
                ],
                totalBytes: 3_000_000
            ),
            catalog: catalog
        )

        XCTAssertEqual(status.regions.map(\.region), ["malaysia-singapore-brunei"])
        XCTAssertEqual(status.regions.map(\.title), ["Malaysia, Singapore, and Brunei"])
    }

    func testOfflineRegionCatalogUsesCachedCatalogWhenCurrentFetchIsOffline() async throws {
        let cache = try OfflineRegionCatalogCache(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let onlineFetcher = AppStubFetcher(routes: [
            "https://tiles.making-tracks.app/regions.json": try appJSONData(appRegionIndexV3Object()),
        ])
        let offlineFetcher = AppStubFetcher(routes: [:])

        _ = try await OfflineRegionCatalog.current(fetcher: onlineFetcher, cache: cache)
        let offlineCatalog = try await OfflineRegionCatalog.current(fetcher: offlineFetcher, cache: cache)

        XCTAssertEqual(offlineCatalog.rootZones.map(\.displayName), ["Malaysia, Singapore, and Brunei"])
        XCTAssertEqual(offlineFetcher.requestedURLs, ["https://tiles.making-tracks.app/regions.json"])
    }

    func testOfflineRegionCatalogUsesCachedCatalogWhenCurrentFetchReturnsTruncatedBytes() async throws {
        let cache = try OfflineRegionCatalogCache(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let validCatalogData = try appJSONData(appRegionIndexV3Object())
        let onlineFetcher = AppStubFetcher(routes: [
            "https://tiles.making-tracks.app/regions.json": validCatalogData,
        ])
        let truncatedFetcher = AppStubFetcher(routes: [
            "https://tiles.making-tracks.app/regions.json": Data(validCatalogData.prefix(48)),
        ])

        _ = try await OfflineRegionCatalog.current(fetcher: onlineFetcher, cache: cache)
        let recoveredCatalog = try await OfflineRegionCatalog.current(fetcher: truncatedFetcher, cache: cache)

        XCTAssertEqual(recoveredCatalog.rootZones.map(\.displayName), ["Malaysia, Singapore, and Brunei"])
        XCTAssertEqual(truncatedFetcher.requestedURLs, ["https://tiles.making-tracks.app/regions.json"])
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

    func testOfflineRegionCatalogDropsConstructedZoneWithMalformedSearchCompactPath() {
        let catalog = OfflineRegionCatalog(
            regionIndex: appConstructedRegionIndexWithMalformedSearchCompactPath()
        )

        XCTAssertEqual(catalog.zones.map(\.id), ["malaysia-singapore-brunei"])
        XCTAssertEqual(catalog.zone(id: "malaysia-singapore-brunei")?.searchCompactPublishVersion, "20260719T125813Z")
        XCTAssertNil(catalog.zone(id: "malaysia-singapore-brunei_kl"))
        XCTAssertNil(catalog.zone(id: "malaysia-singapore-brunei_wrong-path-id"))
        XCTAssertNil(catalog.zone(id: "malaysia-singapore-brunei_invalid-version"))
        XCTAssertNil(catalog.zone(id: "malaysia-singapore-brunei_trailing-extra"))
        XCTAssertNil(catalog.zone(id: "malaysia-singapore-brunei_nondigit-version"))
        let rows = catalog.rows(
            installed: [:],
            availablePublishVersions: [
                "malaysia-singapore-brunei": "20260719T125813Z",
                "malaysia-singapore-brunei_kl": "20260719T125813Z",
                "malaysia-singapore-brunei_wrong-path-id": "20260719T125813Z",
                "malaysia-singapore-brunei_invalid-version": "not-a-publish-version",
                "malaysia-singapore-brunei_trailing-extra": "20260719T125813Z",
                "malaysia-singapore-brunei_nondigit-version": "2026071XT125813Z",
            ],
            activeProgress: nil,
            quarantines: []
        )
        XCTAssertEqual(rows.map(\.zone.id), ["malaysia-singapore-brunei"])
        XCTAssertEqual(rows.map(\.state), [.notInstalled])
    }

    func testOfflineRegionCatalogRecordsDroppedMalformedZoneInDiagnostics() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OfflineRegionCatalogDropLogs-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DiagnosticLogStore(root: root)
        MakingTracksLog.configureDiagnosticLogStore(store)
        defer { MakingTracksLog.configureDiagnosticLogStore(nil) }

        _ = OfflineRegionCatalog(
            regionIndex: appConstructedRegionIndexWithMalformedSearchCompactPath()
        )

        let droppedLines = try store.snapshotLines(window: .everything).filter {
            $0.contains("downloads error region catalog entry dropped")
        }
        XCTAssertEqual(droppedLines.count, 5)
        for region in [
            "malaysia-singapore-brunei_kl",
            "malaysia-singapore-brunei_wrong-path-id",
            "malaysia-singapore-brunei_invalid-version",
            "malaysia-singapore-brunei_trailing-extra",
            "malaysia-singapore-brunei_nondigit-version",
        ] {
            let line = try XCTUnwrap(droppedLines.first { $0.contains("region=\(region)") })
            XCTAssertTrue(line.contains("reason=invalid-search-compact-publish-version"), line)
        }
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

    func testOfflineRegionRowsSurfaceInstalledValidChildOfDroppedParentForCleanup() {
        let catalog = OfflineRegionCatalog(
            regionIndex: appConstructedRegionIndexWithMalformedParentAndValidChild()
        )

        XCTAssertNil(catalog.zone(id: "orphan-parent"))
        XCTAssertNotNil(catalog.zone(id: "orphan-parent_child"))
        XCTAssertTrue(catalog.rootZones.isEmpty)

        let rows = catalog.rows(
            installed: ["orphan-parent_child": "20260719T125813Z"],
            activeProgress: nil,
            quarantines: []
        )
        let child = rows.first { $0.zone.id == "orphan-parent_child" }

        XCTAssertEqual(rows.map(\.zone.id), ["orphan-parent_child"])
        XCTAssertEqual(child?.state, .unavailable)
        XCTAssertTrue(child?.hasUnavailableLocalData == true)
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

private func appConstructedRegionIndexWithMalformedSearchCompactPath() -> RegionIndex {
    let validSearchCompact = RegionIndex.SearchCompact(
        path: "malaysia-singapore-brunei/20260719T125813Z/search/compact.json",
        sha256: String(repeating: "a", count: 64),
        bytes: 208,
        schemaVersion: 1
    )
    let malformedSearchCompact = RegionIndex.SearchCompact(
        path: "malaysia-singapore-brunei_kl/search/compact.json",
        sha256: String(repeating: "b", count: 64),
        bytes: 197,
        schemaVersion: 1
    )
    let wrongPathIDSearchCompact = RegionIndex.SearchCompact(
        path: "wrong-region/20260719T125813Z/search/compact.json",
        sha256: String(repeating: "c", count: 64),
        bytes: 196,
        schemaVersion: 1
    )
    let invalidVersionSearchCompact = RegionIndex.SearchCompact(
        path: "malaysia-singapore-brunei_invalid-version/not-a-publish-version/search/compact.json",
        sha256: String(repeating: "d", count: 64),
        bytes: 195,
        schemaVersion: 1
    )
    let trailingExtraSearchCompact = RegionIndex.SearchCompact(
        path: "malaysia-singapore-brunei_trailing-extra/20260719T125813Z/search/compact.json/extra",
        sha256: String(repeating: "e", count: 64),
        bytes: 194,
        schemaVersion: 1
    )
    let nondigitVersionSearchCompact = RegionIndex.SearchCompact(
        path: "malaysia-singapore-brunei_nondigit-version/2026071XT125813Z/search/compact.json",
        sha256: String(repeating: "f", count: 64),
        bytes: 193,
        schemaVersion: 1
    )
    return RegionIndex(
        schemaVersion: 3,
        minReaderVersion: 1,
        generatedAt: "2026-07-20T12:00:00Z",
        regions: [
            RegionIndex.Entry(
                id: "malaysia-singapore-brunei",
                displayName: "Malaysia, Singapore, and Brunei",
                parent: nil,
                bbox: BBox(minLon: 99.0, minLat: -1.5, maxLon: 120.0, maxLat: 7.5),
                publishVersion: "20260719T125813Z",
                searchCompact: validSearchCompact,
                basemapBytes: 4_000_000,
                tileCount: 12,
                bytesWithoutThumbnails: 228_849_472,
                bytesWithThumbnails: 240_582_030
            ),
            RegionIndex.Entry(
                id: "malaysia-singapore-brunei_kl",
                displayName: "Kuala Lumpur",
                parent: "malaysia-singapore-brunei",
                bbox: BBox(minLon: 101.4, minLat: 2.8, maxLon: 101.9, maxLat: 3.4),
                publishVersion: "20260719T125813Z",
                searchCompact: malformedSearchCompact,
                basemapBytes: 1_000_000,
                tileCount: 4,
                bytesWithoutThumbnails: 33_000_000,
                bytesWithThumbnails: 41_000_000
            ),
            RegionIndex.Entry(
                id: "malaysia-singapore-brunei_wrong-path-id",
                displayName: "Wrong Path ID",
                parent: "malaysia-singapore-brunei",
                bbox: BBox(minLon: 101.0, minLat: 2.0, maxLon: 102.0, maxLat: 3.0),
                publishVersion: "20260719T125813Z",
                searchCompact: wrongPathIDSearchCompact,
                basemapBytes: 900_000,
                tileCount: 3,
                bytesWithoutThumbnails: 32_000_000,
                bytesWithThumbnails: 40_000_000
            ),
            RegionIndex.Entry(
                id: "malaysia-singapore-brunei_invalid-version",
                displayName: "Invalid Version",
                parent: "malaysia-singapore-brunei",
                bbox: BBox(minLon: 102.0, minLat: 3.0, maxLon: 103.0, maxLat: 4.0),
                publishVersion: "20260719T125813Z",
                searchCompact: invalidVersionSearchCompact,
                basemapBytes: 800_000,
                tileCount: 2,
                bytesWithoutThumbnails: 31_000_000,
                bytesWithThumbnails: 39_000_000
            ),
            RegionIndex.Entry(
                id: "malaysia-singapore-brunei_trailing-extra",
                displayName: "Trailing Extra",
                parent: "malaysia-singapore-brunei",
                bbox: BBox(minLon: 103.0, minLat: 4.0, maxLon: 104.0, maxLat: 5.0),
                publishVersion: "20260719T125813Z",
                searchCompact: trailingExtraSearchCompact,
                basemapBytes: 700_000,
                tileCount: 2,
                bytesWithoutThumbnails: 30_000_000,
                bytesWithThumbnails: 38_000_000
            ),
            RegionIndex.Entry(
                id: "malaysia-singapore-brunei_nondigit-version",
                displayName: "Nondigit Version",
                parent: "malaysia-singapore-brunei",
                bbox: BBox(minLon: 104.0, minLat: 5.0, maxLon: 105.0, maxLat: 6.0),
                publishVersion: "20260719T125813Z",
                searchCompact: nondigitVersionSearchCompact,
                basemapBytes: 600_000,
                tileCount: 1,
                bytesWithoutThumbnails: 29_000_000,
                bytesWithThumbnails: 37_000_000
            ),
        ]
    )
}

private func firstDescendant<Descendant>(
    of type: Descendant.Type,
    in value: Any
) -> Descendant? {
    if let value = value as? Descendant {
        return value
    }
    for child in Mirror(reflecting: value).children {
        if let descendant = firstDescendant(
            of: type,
            in: child.value
        ) {
            return descendant
        }
    }
    return nil
}

private func descendants<Descendant>(
    of type: Descendant.Type,
    in value: Any
) -> [Descendant] {
    var matches: [Descendant] = []
    if let value = value as? Descendant {
        matches.append(value)
    }
    for child in Mirror(reflecting: value).children {
        matches.append(contentsOf: descendants(of: type, in: child.value))
    }
    return matches
}

private struct RatifiedJournalDoorHeroIcon: View {
    let systemName: String

    @ScaledMetric(relativeTo: .headline) private var pointSize = 22.0

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: pointSize, weight: .medium))
            .symbolRenderingMode(.monochrome)
    }
}

private struct RatifiedMapDoorRowIcon: View {
    let systemName: String

    private let tokens = MaterialTheme.snow.tokens

    var body: some View {
        Image(systemName: systemName)
            .font(.headline.weight(.medium))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(tokens.accent.swiftUIColor)
    }
}

private struct RatifiedJournalDoorInlineIcon: View {
    let systemName: String

    @ScaledMetric(relativeTo: .subheadline) private var pointSize = 15.0

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: pointSize, weight: .medium))
            .symbolRenderingMode(.monochrome)
    }
}

private struct RatifiedJournalDoorAccessoryIcon: View {
    let systemName: String

    @ScaledMetric(relativeTo: .caption2) private var pointSize = 11.0

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: pointSize, weight: .medium))
            .symbolRenderingMode(.monochrome)
    }
}

private struct RatifiedJournalDoorRetraceCue: View {
    /// R12 / ia-doors.html:428-431 and :753 ratify SF 13/600 type and a 3pt gap.
    var body: some View {
        HStack(spacing: 3) {
            Text("Retrace")
            RatifiedJournalDoorAccessoryIcon(systemName: "chevron.right")
                .accessibilityHidden(true)
        }
        .font(.system(.footnote, design: .default, weight: .semibold))
        .fixedSize(horizontal: true, vertical: true)
    }
}

private struct RatifiedJournalDoorHeroTitle: View {
    let title: String

    var body: some View {
        Text(verbatim: title)
            .font(
                .custom(
                    "Newsreader16pt-SemiBold",
                    size: 18,
                    relativeTo: .headline
                )
            )
    }
}

private struct RenderedAppGlyph: Equatable {
    let width: Int
    let height: Int
    let rgba: Data
}

@MainActor
private func renderedAppGlyph<Content: View>(
    _ content: Content,
    dynamicTypeSize: DynamicTypeSize
) throws -> RenderedAppGlyph {
    let renderer = ImageRenderer(
        content: content
            .environment(\.dynamicTypeSize, dynamicTypeSize)
            .frame(width: 96, height: 96)
    )
    renderer.scale = 1
    let image = try XCTUnwrap(renderer.uiImage)
    let cgImage = try XCTUnwrap(image.cgImage)
    let data = try XCTUnwrap(cgImage.dataProvider?.data)

    return RenderedAppGlyph(
        width: cgImage.width,
        height: cgImage.height,
        rgba: data as Data
    )
}

@MainActor
private func journalDoorRenderedSize<Content: View>(
    _ content: Content,
    dynamicTypeSize: DynamicTypeSize
) throws -> CGSize {
    let renderer = ImageRenderer(
        content: content.environment(\.dynamicTypeSize, dynamicTypeSize)
    )
    return try XCTUnwrap(renderer.uiImage).size
}

private func appConstructedRegionIndexWithMalformedParentAndValidChild() -> RegionIndex {
    RegionIndex(
        schemaVersion: 3,
        minReaderVersion: 1,
        generatedAt: "2026-07-20T12:00:00Z",
        regions: [
            RegionIndex.Entry(
                id: "orphan-parent",
                displayName: "Orphan Parent",
                parent: nil,
                bbox: BBox(minLon: 99.0, minLat: -1.5, maxLon: 120.0, maxLat: 7.5),
                publishVersion: "20260719T125813Z",
                searchCompact: RegionIndex.SearchCompact(
                    path: "orphan-parent/search/compact.json",
                    sha256: String(repeating: "a", count: 64),
                    bytes: 208,
                    schemaVersion: 1
                ),
                basemapBytes: 4_000_000,
                tileCount: 12,
                bytesWithoutThumbnails: 228_849_472,
                bytesWithThumbnails: 240_582_030
            ),
            RegionIndex.Entry(
                id: "orphan-parent_child",
                displayName: "Orphan Child",
                parent: "orphan-parent",
                bbox: BBox(minLon: 101.4, minLat: 2.8, maxLon: 101.9, maxLat: 3.4),
                publishVersion: "20260719T125813Z",
                searchCompact: RegionIndex.SearchCompact(
                    path: "orphan-parent_child/20260719T125813Z/search/compact.json",
                    sha256: String(repeating: "b", count: 64),
                    bytes: 197,
                    schemaVersion: 1
                ),
                basemapBytes: 1_000_000,
                tileCount: 4,
                bytesWithoutThumbnails: 33_000_000,
                bytesWithThumbnails: 41_000_000
            ),
        ]
    )
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
