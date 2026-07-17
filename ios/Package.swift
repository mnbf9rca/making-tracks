// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MakingTracksData",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "MakingTracksData", targets: ["MakingTracksData"]),
        .library(name: "MakingTracksTiles", targets: ["MakingTracksTiles"]),
        .library(name: "MakingTracksMapStyle", targets: ["MakingTracksMapStyle"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "MakingTracksData",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "MakingTracksTiles",
            dependencies: ["MakingTracksData"],
            swiftSettings: [.swiftLanguageMode(.v6)],
            linkerSettings: [.linkedLibrary("z")]
        ),
        .target(
            name: "MakingTracksMapStyle",
            dependencies: ["MakingTracksData"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "MakingTracksDataTests",
            dependencies: ["MakingTracksData"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "MakingTracksTilesTests",
            dependencies: ["MakingTracksTiles"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "MakingTracksMapStyleTests",
            dependencies: ["MakingTracksMapStyle", "MakingTracksData"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
