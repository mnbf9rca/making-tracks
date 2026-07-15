// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MakingTracksData",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "MakingTracksData", targets: ["MakingTracksData"]),
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
        .testTarget(
            name: "MakingTracksDataTests",
            dependencies: ["MakingTracksData"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
