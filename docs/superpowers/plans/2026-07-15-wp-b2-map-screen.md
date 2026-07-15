# WP-B2 (iOS Map Screen) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The map screen — a `@MainActor`-contained `MLNMapView` wrapper over a PMTiles paper-style basemap, rendering place pins as the mandated GeoJSON `MLNShapeSource` + style-layer substrate (§5.1) with the full 6-cell pin matrix as a **data-driven fade opacity expression + badge symbol layers**, tap via feature hit-testing.

**Architecture:** The valuable seam is a **pure, host-testable** SwiftPM library `MakingTracksMapStyle` that owns the pin-matrix truth (`pinAppearance`) **and generates the MapLibre style/expressions from it** — so the *generated expression* is proven to reproduce the matrix host-side (a tiny evaluator asserts `expression == pinAppearance` per cell, **no simulator**). **Honest scope:** this proves *generation*, not *rendering* — the JSON→MLN *application* (via `NSExpression`/`NSPredicate`) is `[XCODE/SIM]` and gets its own read-back check (Task 5 Step 2). So §7's *full-pin-matrix* enumeration is host-proven at the generation layer and simulator-verified at the render layer; neither half is oversold. All MapLibre-touching code is simulator-gated; nothing about it is claimed host-verified.

**Tech Stack:** Swift 6 (language mode, strict concurrency `complete`), SwiftUI, MapLibre Native iOS (`ios-v6.27.0`, PMTiles native since `v6.10.0`), XcodeGen, GRDB (via `MakingTracksData`). iOS 18. Dev basemap: public Protomaps demo tiles.

## Global Constraints

- **§5.1 pin substrate is MANDATED, not a choice.** Pins are runtime features via **GeoJSON `MLNShapeSource` + symbol/circle style layers** — never `MLNAnnotation`/`MLNAnnotationView` (rejected for density collapse). Fade is a **data-driven opacity expression**; loved/bookmark badges are **additional symbol layers**; tap is **feature hit-testing (`visibleFeatures(at:)`)**; clustering (`MLNShapeSourceOptionClustered`, B8) shares this substrate. Basemap = PMTiles via native `pmtiles://` URLs. Basemap style = **muted/paper-like style JSON; the pins are the only saturated colour** (the snow metaphor lives in the basemap look). Wrap `MLNMapView` ourselves (the official SwiftUI wrapper is pre-1.0).
- **§3.2 pin matrix — two orthogonal axes, fade keys on VISIT.** `saved ∈ {no,yes} × visit ∈ {none,visited,loved}`. **Precedence, pinned exactly (fable-confirmed):** the **visit axis drives fade** (`visit != .none` ⇒ faded); the **saved axis contributes an independent bookmark badge that persists through fading**; **loved additionally keeps a heart badge**. B2 renders pins from `PinState(saved, visit)` — **`AppDatabase.seen(among:)` is NOT the pin-matrix axis** (it serves progress counts and the B8 "Fresh snow" toggle). "B1 owns the state; B2 renders it." The six cells: (no,none)=full,no-badge · (yes,none)=full,bookmark · (no,visited)=faded,no-badge · (yes,visited)=faded,bookmark [the guaranteed core-loop end state] · (no,loved)=faded,heart · (yes,loved)=faded,bookmark+heart.
- **§5.3 concurrency containment.** Swift 6 strict concurrency `complete`. The MapLibre wrapper is a **`@MainActor`-isolated boundary using `@preconcurrency import`** (MLN types are un-Sendable ObjC). **All map mutations happen on the main actor.** The wrapper exchanges only **plain `Sendable` value types** (`MapPlace`, `PinState`, generated JSON strings) — **never MLN objects across the boundary**. The concurrency cost stays inside the wrapper; it must not leak across B2/B3/B4. `MakingTracksData.AppDatabase` is already `Sendable` (a `final class` over a `Sendable` `DatabaseQueue`) — read/write user state off any task, mutate the map on the main actor.
- **§5.5 untrusted tiles — B2's slice.** **B3 (the tile client) owns the PRIMARY §5.5 decode-time validation** and hands B2 already-validated `Sendable` value types — B2 does **not** re-decode. B2's obligations: **never crash the map on malformed data** (skip, never crash); render place text as **plain text only** (no HTML/attributed rendering of source content); fetch image URLs **https-only from the expected host** (place-card imagery is B4 — B2 renders no source imagery on the map itself).
- **Host-testable seam vs `[XCODE/SIM]` (fable's mandated design move).** Everything pure — the pin-matrix truth, the paper-style JSON generation, the pin-layer + expression generation, the feature-property encoding, the `foundationObject` JSON→Foundation bridge, and the evaluator that proves the *generated* `expression == matrix` — lives in **`MakingTracksMapStyle`** and is verified by **`swift test` on the host (macOS), no simulator**. Everything MapLibre-touching (the `MLNMapView` wrapper, the JSON→MLN `NSExpression`/`NSPredicate` application, PMTiles registration, tap hit-testing, the app shell) is **`[XCODE/SIM]`** — described with named APIs but **not host-verifiable**; the plan makes **no host-verification claim** for it, and Task 5's `[XCODE/SIM]` read-back gives the JSON→MLN application its own (simulator) teeth.
- **`MapPlace` is a shared value type, provisional-until-B3.** B3 will *produce* `MapPlace` (the tile client), so it lives in **`MakingTracksData`** (the `Sendable` value-type home) — **not** in the rendering module, so B3 imports data, not rendering. Keep it **minimal** (`id, lat, lon, tier` — nothing speculative). **Provisional: B3's designer may EXTEND it, never break it.**
- **B2's shell SUPERSEDES B1 Task 7 (fable-ratified).** B1's Task 7 (app shell) never landed (only `MakingTracksData` is on develop). B2 introduces the XcodeGen project + `@main` shell — **one shell, one owner.** **Issue #12 closes when B2's shell lands**, referencing this WP.
- **Buildable before B3/A7 (§8 order note).** B2 builds against **public Protomaps demo tiles** for the basemap and an **injected set of dev `MapPlace`s** for the pin substrate, so the full pin matrix is exercisable before the real tile client (B3) and real tiles (A7) exist.

**Ratified (fable, thread `wp/b2`)** — `MakingTracksMapStyle` as the pure host-tested seam (matrix truth + generated expressions + per-cell evaluator = §7 without a simulator); fade axis is `visit != .none` (not `seen()`); B2 shell supersedes B1 Task 7 (issue #12); `MapPlace` minimal in `MakingTracksData`, provisional-until-B3 (extend-never-break); `[XCODE/SIM]` honesty (no host-verification claims for MapLibre parts).

---

## File Structure

```
ios/
  Package.swift                                 # MODIFY: add MakingTracksMapStyle library target (+ its test target)
  Sources/
    MakingTracksData/
      MapPlace.swift                            # NEW: Sendable value type (id, lat, lon, tier) — provisional-until-B3
    MakingTracksMapStyle/                       # NEW host-testable library (pure; no MapLibre/UIKit)
      JSONValue.swift                           # Codable style-JSON tree
      PinAppearance.swift                       # PinAppearance + pinAppearance(PinState) — the matrix truth
      PaperStyle.swift                          # muted paper basemap style JSON generator (PMTiles source)
      PinLayers.swift                           # shape-source + circle/badge layers + expressions FROM pinAppearance
      FeatureEncoding.swift                     # featureProperties(PinState) + MapPlace -> GeoJSON feature
      Expression.swift                          # tiny evaluator (get/match/==/literals) — proves expression==matrix
  Tests/
    MakingTracksMapStyleTests/
      PinMatrixTests.swift                      # THE §7 surface: full 6-cell matrix, host-side
      PaperStyleTests.swift
      PinLayersTests.swift
  App/                                          # [XCODE/SIM] — the app shell (supersedes B1 Task 7)
    project.yml                                 # XcodeGen: MakingTracks app, iOS 18, Swift 6 strict=complete
    Sources/
      MakingTracksApp.swift                     # @main; root = MapScreen (replaces B1's reserved placeholder)
      AppDatabase+Live.swift                    # AppDatabase.live() (Application Support store)
      Map/
        MapScreen.swift                         # SwiftUI screen: viewport -> viewportState -> feature feed
        MLNMapViewRepresentable.swift           # @MainActor UIViewRepresentable wrapper (@preconcurrency import)
        DevPlaces.swift                         # injected dev MapPlaces + Protomaps demo basemap URL
```

---

### Task 1: `MapPlace` value type + `MakingTracksMapStyle` scaffold + the pin-matrix truth  `[HOST]`

**Files:**
- Create: `ios/Sources/MakingTracksData/MapPlace.swift`
- Modify: `ios/Package.swift` (add the library + test targets)
- Create: `ios/Sources/MakingTracksMapStyle/JSONValue.swift`, `.../PinAppearance.swift`
- Test: `ios/Tests/MakingTracksMapStyleTests/PinMatrixTests.swift`

**Interfaces:**
- Produces:
  - `MakingTracksData.MapPlace` — `public struct MapPlace: Sendable, Equatable { public let id: String; public let lat: Double; public let lon: Double; public let tier: Int }` (provisional-until-B3).
  - `MakingTracksMapStyle.JSONValue` — `public indirect enum JSONValue: Equatable, Codable` (`.string/.double/.bool/.array/.object/.null`) — the host-serializable style-JSON tree.
  - `MakingTracksMapStyle.PinAppearance` — `public struct PinAppearance: Equatable, Sendable { public var opacity: Double; public var showBookmarkBadge: Bool; public var showHeartBadge: Bool }`.
  - `MakingTracksMapStyle.pinAppearance(_ state: PinState) -> PinAppearance` — the **single source of truth** for the matrix.
  - Constants `FULL_OPACITY = 1.0`, `FADED_OPACITY = 0.35`.

- [ ] **Step 1: Write the failing matrix test**

`ios/Tests/MakingTracksMapStyleTests/PinMatrixTests.swift`:
```swift
import XCTest
import MakingTracksData
@testable import MakingTracksMapStyle

final class PinMatrixTests: XCTestCase {
    // §7: the FULL pin matrix — saved{0,1} × visit{none,visited,loved}. Precedence (§3.2):
    // visit drives fade; saved is an independent persistent bookmark; loved keeps a heart.
    func testPinAppearanceCoversAllSixCells() {
        let cases: [(PinState, PinAppearance)] = [
            (PinState(saved: false, visit: .none),    PinAppearance(opacity: 1.0,  showBookmarkBadge: false, showHeartBadge: false)),
            (PinState(saved: true,  visit: .none),    PinAppearance(opacity: 1.0,  showBookmarkBadge: true,  showHeartBadge: false)),
            (PinState(saved: false, visit: .visited), PinAppearance(opacity: 0.35, showBookmarkBadge: false, showHeartBadge: false)),
            (PinState(saved: true,  visit: .visited), PinAppearance(opacity: 0.35, showBookmarkBadge: true,  showHeartBadge: false)),
            (PinState(saved: false, visit: .loved),   PinAppearance(opacity: 0.35, showBookmarkBadge: false, showHeartBadge: true)),
            (PinState(saved: true,  visit: .loved),   PinAppearance(opacity: 0.35, showBookmarkBadge: true,  showHeartBadge: true)),
        ]
        for (state, expected) in cases {
            XCTAssertEqual(pinAppearance(state), expected, "cell saved=\(state.saved) visit=\(state.visit)")
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd ios && swift test --filter PinMatrixTests`
Expected: FAIL — no such module `MakingTracksMapStyle`.

- [ ] **Step 3: Add the target + `MapPlace` + `JSONValue` + the matrix**

In `ios/Package.swift`, add to `products` a `.library(name: "MakingTracksMapStyle", targets: ["MakingTracksMapStyle"])`, and to `targets`:
```swift
.target(name: "MakingTracksMapStyle", dependencies: ["MakingTracksData"],
        swiftSettings: [.swiftLanguageMode(.v6)]),                          // parity with existing targets
.testTarget(name: "MakingTracksMapStyleTests", dependencies: ["MakingTracksMapStyle", "MakingTracksData"],
            swiftSettings: [.swiftLanguageMode(.v6)]),
```

`ios/Sources/MakingTracksData/MapPlace.swift`:
```swift
/// A place feature for the map. PROVISIONAL: WP-B3 (the tile client) will PRODUCE MapPlace from
/// decoded tiles and may EXTEND this (add fields) but must not BREAK it. Lives in MakingTracksData
/// (not the rendering module) so B3 produces it without importing rendering code. Minimal by design.
public struct MapPlace: Sendable, Equatable {
    public let id: String        // place_id
    public let lat: Double
    public let lon: Double
    public let tier: Int         // §4 tier — reserved for B8 tier/zoom gating; carried on the feature now
    public init(id: String, lat: Double, lon: Double, tier: Int) {
        self.id = id; self.lat = lat; self.lon = lon; self.tier = tier
    }
}
```

`ios/Sources/MakingTracksMapStyle/JSONValue.swift`:
```swift
import Foundation

/// A minimal, host-serializable JSON tree for authoring MapLibre style JSON + expressions.
public indirect enum JSONValue: Equatable, Codable {
    case string(String), double(Double), bool(Bool), array([JSONValue]), object([String: JSONValue]), null

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .double(let d): try c.encode(d)
        case .bool(let b): try c.encode(b)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        case .null: try c.encodeNil()
        }
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let d = try? c.decode(Double.self) { self = .double(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    /// Serialize to a compact JSON string (sorted keys → deterministic, testable).
    public func jsonString() throws -> String {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        return String(decoding: try enc.encode(self), as: UTF8.self)
    }

    /// A Foundation JSON object (String / NSNumber / [Any] / [String: Any] / NSNull) — the shape
    /// `NSExpression(mglJSONObject:)` / `NSPredicate(mglJSONObject:)` require in the [XCODE/SIM] wrapper.
    /// `.bool` MUST become a BOOLEAN NSNumber (not 0/1) so a `["==",["get","saved"],true]` predicate
    /// compares correctly — this is host-testable even though NSExpression is not.
    public var foundationObject: Any {
        switch self {
        case .string(let s): return s
        case .double(let d): return NSNumber(value: d)
        case .bool(let b): return NSNumber(value: b)
        case .array(let a): return a.map(\.foundationObject)
        case .object(let o): return o.mapValues(\.foundationObject)
        case .null: return NSNull()
        }
    }
}
```

`ios/Sources/MakingTracksMapStyle/PinAppearance.swift`:
```swift
import MakingTracksData

public let FULL_OPACITY = 1.0
public let FADED_OPACITY = 0.35        // the "seen treatment" (§3.3): visited & loved pins fade

public struct PinAppearance: Equatable, Sendable {
    public var opacity: Double
    public var showBookmarkBadge: Bool
    public var showHeartBadge: Bool
    public init(opacity: Double, showBookmarkBadge: Bool, showHeartBadge: Bool) {
        self.opacity = opacity; self.showBookmarkBadge = showBookmarkBadge; self.showHeartBadge = showHeartBadge
    }
}

/// The SINGLE SOURCE OF TRUTH for the §3.2 pin matrix. The style expressions (PinLayers) are
/// generated FROM this, and a host test proves they agree per cell.
public func pinAppearance(_ state: PinState) -> PinAppearance {
    PinAppearance(
        opacity: state.visit == .none ? FULL_OPACITY : FADED_OPACITY,   // visit drives fade
        showBookmarkBadge: state.saved,                                 // saved: independent, persists through fade
        showHeartBadge: state.visit == .loved                           // loved keeps a heart
    )
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd ios && swift test --filter PinMatrixTests`
Expected: PASS (1 test, 6 cells).

- [ ] **Step 5: Commit**

```bash
git add ios/Package.swift ios/Sources/MakingTracksData/MapPlace.swift \
        ios/Sources/MakingTracksMapStyle/JSONValue.swift ios/Sources/MakingTracksMapStyle/PinAppearance.swift \
        ios/Tests/MakingTracksMapStyleTests/PinMatrixTests.swift
git commit -m "Add MapPlace + MakingTracksMapStyle scaffold + pin-matrix truth (pinAppearance, host-tested)"
```

---

### Task 2: Paper-style basemap style JSON generator  `[HOST]`

**Files:**
- Create: `ios/Sources/MakingTracksMapStyle/PaperStyle.swift`
- Test: `ios/Tests/MakingTracksMapStyleTests/PaperStyleTests.swift`

**Interfaces:**
- Produces:
  - `PaperPalette` — `public struct PaperPalette: Sendable { public var background, land, water, roads, boundaries, labels: String }` with a `.default` muted/paper palette (hex strings; B2's authored deliverable — the spec mandates "muted/paper-like … pins the only saturated colour" but no exact hexes).
  - `paperBasemapStyle(pmtilesURL: String, palette: PaperPalette = .default) -> JSONValue` — a MapLibre **style-spec v8** object: a `vector` source of type `pmtiles://<url>` and muted background/land/water/road/boundary/label layers against the **Protomaps basemap vector schema** (the demo tiles' layer names: `earth`, `water`, `roads`, `boundaries`, `places`). The pins source/layers are added by `PinLayers` (Task 3).

- [ ] **Step 1: Write the failing test**

`PaperStyleTests.swift`:
```swift
import XCTest
@testable import MakingTracksMapStyle

final class PaperStyleTests: XCTestCase {
    func testStyleIsV8WithPmtilesVectorSource() throws {
        let style = paperBasemapStyle(pmtilesURL: "pmtiles://https://demo.protomaps.com/…/example.pmtiles")
        guard case let .object(root) = style else { return XCTFail("root not object") }
        XCTAssertEqual(root["version"], .double(8))
        guard case let .object(sources) = root["sources"], case let .object(base) = sources["basemap"]
        else { return XCTFail("no basemap source") }
        XCTAssertEqual(base["type"], .string("vector"))
        if case let .string(url) = base["url"] { XCTAssertTrue(url.hasPrefix("pmtiles://")) } else { XCTFail("url") }
        // muted paper background present; JSON round-trips
        guard case let .array(layers) = root["layers"] else { return XCTFail("no layers") }
        XCTAssertTrue(layers.contains { if case let .object(l) = $0 { return l["type"] == .string("background") } else { return false } })
        XCTAssertNoThrow(try style.jsonString())
    }

    func testEveryPaletteColourIsMutedAndPinIsSaturated() {
        // §5.1: "muted/paper-like … the pins are the ONLY saturated colour." Assert HSV saturation:
        // every basemap colour < MUTED_MAX; the pin colour >= MUTED_MAX. (Verified on host: the
        // default palette is 0.04–0.10; #E4572E pin is 0.80. Teeth: a neon basemap colour reds.)
        let p = PaperPalette.default
        for hex in [p.background, p.land, p.water, p.roads, p.boundaries] {
            XCTAssertLessThan(saturation(hex: hex), MUTED_MAX, "basemap colour \(hex) is not muted")
        }
        XCTAssertGreaterThanOrEqual(saturation(hex: PinLayers.pinColor), MUTED_MAX, "pin colour must be saturated")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd ios && swift test --filter PaperStyleTests`
Expected: FAIL — `paperBasemapStyle` / `PaperPalette` not defined.

- [ ] **Step 3: Implement**

`ios/Sources/MakingTracksMapStyle/PaperStyle.swift`:
```swift
public let MUTED_MAX = 0.25    // HSV-saturation ceiling for a "muted/paper" colour (§5.1)

/// HSV saturation of a #RRGGBB hex (0…1). Pure — lets the palette-muted mandate be host-tested.
public func saturation(hex: String) -> Double {
    var s = hex; if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6, let v = UInt32(s, radix: 16) else { return 0 }
    let r = Double((v >> 16) & 0xFF) / 255, g = Double((v >> 8) & 0xFF) / 255, b = Double(v & 0xFF) / 255
    let mx = max(r, g, b), mn = min(r, g, b)
    return mx == 0 ? 0 : (mx - mn) / mx
}

public struct PaperPalette: Sendable {
    public var background, land, water, roads, boundaries: String   // labels dropped: no label layer in v1 (deferred)
    public init(background: String, land: String, water: String, roads: String, boundaries: String) {
        self.background = background; self.land = land; self.water = water
        self.roads = roads; self.boundaries = boundaries
    }
    /// Muted, paper-like. Low-saturation greys/creams so the saturated pins carry all the colour.
    public static let `default` = PaperPalette(
        background: "#F4F1EA", land: "#ECE8DD", water: "#DCE3E5",
        roads: "#E3DED2", boundaries: "#CDC7B8")
}

private func layer(_ id: String, _ type: String, source: String? = nil, sourceLayer: String? = nil,
                   paint: [String: JSONValue]) -> JSONValue {
    var o: [String: JSONValue] = ["id": .string(id), "type": .string(type), "paint": .object(paint)]
    if let source { o["source"] = .string(source) }
    if let sourceLayer { o["source-layer"] = .string(sourceLayer) }
    return .object(o)
}

/// MapLibre style-spec v8. Basemap only — PinLayers (Task 3) appends the pins source + layers.
/// Layer names target the Protomaps basemap vector schema used by the public demo tiles.
public func paperBasemapStyle(pmtilesURL: String, palette: PaperPalette = .default) -> JSONValue {
    .object([
        "version": .double(8),
        "sources": .object([
            "basemap": .object(["type": .string("vector"), "url": .string(pmtilesURL)]),
        ]),
        "layers": .array([
            layer("background", "background", paint: ["background-color": .string(palette.background)]),
            layer("earth", "fill", source: "basemap", sourceLayer: "earth",
                  paint: ["fill-color": .string(palette.land)]),
            layer("water", "fill", source: "basemap", sourceLayer: "water",
                  paint: ["fill-color": .string(palette.water)]),
            layer("roads", "line", source: "basemap", sourceLayer: "roads",
                  paint: ["line-color": .string(palette.roads), "line-width": .double(0.6)]),
            layer("boundaries", "line", source: "basemap", sourceLayer: "boundaries",
                  paint: ["line-color": .string(palette.boundaries), "line-width": .double(0.5)]),
        ]),
    ])
}
```

- [ ] **Step 4: Run + commit**

Run: `cd ios && swift test --filter PaperStyleTests`
Expected: PASS.

```bash
git add ios/Sources/MakingTracksMapStyle/PaperStyle.swift ios/Tests/MakingTracksMapStyleTests/PaperStyleTests.swift
git commit -m "Add paper-style basemap style JSON generator (muted palette, pmtiles vector source)"
```

---

### Task 3: Pin substrate — layers + expressions generated from the matrix + the evaluator  `[HOST]`

**Files:**
- Create: `ios/Sources/MakingTracksMapStyle/PinLayers.swift`, `.../FeatureEncoding.swift`, `.../Expression.swift`
- Test: `ios/Tests/MakingTracksMapStyleTests/PinLayersTests.swift`

**Interfaces:**
- Produces:
  - `FeatureEncoding.featureProperties(_ state: PinState) -> [String: JSONValue]` → `["visit": .string("none|visited|loved"), "saved": .bool]` (what the expressions read).
  - `FeatureEncoding.feature(_ place: MapPlace, _ state: PinState) -> JSONValue` → a GeoJSON Feature (Point `[lon,lat]`, properties = id/tier + featureProperties). `featureCollection([...]) -> JSONValue`.
  - `PinLayers.pinColor` — the single saturated pin colour.
  - `PinLayers.fadeOpacityExpression() -> JSONValue` — a `match` on `["get","visit"]` whose per-visit opacity is taken **from `pinAppearance`** (single source of truth).
  - `PinLayers.bookmarkFilter() -> JSONValue` (`["==", ["get","saved"], true]`), `PinLayers.heartFilter() -> JSONValue` (`["==", ["get","visit"], "loved"]`).
  - `PinLayers.pinLayers() -> [JSONValue]` — the GeoJSON `MLNShapeSource`-backed circle pin layer (`circle-opacity` = fade expression, `circle-color` = pinColor) + bookmark symbol layer (filtered) + heart symbol layer (filtered). Source id `"pins"`, `type: "geojson"`.
  - `Expression.evaluate(_ expr: JSONValue, _ props: [String: JSONValue]) -> JSONValue` — a tiny evaluator for the subset we generate (`get`, `match`, `==`, literals) so tests can prove `expression == matrix` per cell.

- [ ] **Step 1: Write the failing tests — THE §7 pin-matrix surface, host-side**

`PinLayersTests.swift`:
```swift
import XCTest
import MakingTracksData
@testable import MakingTracksMapStyle

final class PinLayersTests: XCTestCase {
    private let matrix: [PinState] = [
        PinState(saved: false, visit: .none), PinState(saved: true, visit: .none),
        PinState(saved: false, visit: .visited), PinState(saved: true, visit: .visited),
        PinState(saved: false, visit: .loved), PinState(saved: true, visit: .loved),
    ]

    // The star: the GENERATED style expression, evaluated per cell, must equal pinAppearance —
    // so §7's full-pin-matrix mandate is satisfied on the host, no simulator.
    func testGeneratedExpressionsMatchPinAppearanceForEveryCell() {
        for state in matrix {
            let want = pinAppearance(state)
            let props = FeatureEncoding.featureProperties(state)
            guard case let .double(op) = Expression.evaluate(PinLayers.fadeOpacityExpression(), props)
            else { return XCTFail("opacity not a number for \(state)") }
            XCTAssertEqual(op, want.opacity, accuracy: 1e-9, "opacity \(state)")
            XCTAssertEqual(Expression.evaluate(PinLayers.bookmarkFilter(), props), .bool(want.showBookmarkBadge), "bookmark \(state)")
            XCTAssertEqual(Expression.evaluate(PinLayers.heartFilter(), props), .bool(want.showHeartBadge), "heart \(state)")
        }
    }

    func testPinSubstrateIsShapeSourcePlusStyleLayersNotAnnotations() {
        let layers = PinLayers.pinLayers()
        // a geojson-sourced circle pin layer + two symbol badge layers (the mandated substrate)
        func layerOfType(_ t: String) -> [String: JSONValue]? {
            for case let .object(l) in layers where l["type"] == .string(t) { return l }; return nil
        }
        XCTAssertNotNil(layerOfType("circle"), "circle pin layer")
        let symbols = layers.filter { if case let .object(l) = $0 { return l["type"] == .string("symbol") } else { return false } }
        XCTAssertEqual(symbols.count, 2, "bookmark + heart badge symbol layers")
        // co-present badges (the saved+loved cell) must NOT stack — distinct icon-offset anchors.
        XCTAssertNotEqual(PinLayers.bookmarkOffset, PinLayers.heartOffset, "badges would collide at one anchor")
        // the pin colour is saturated and used ONLY by the pin circle
        if case let .object(circle)? = layers.first(where: { if case let .object(l) = $0 { return l["type"] == .string("circle") } else { return false } }),
           case let .object(paint)? = circle["paint"] {
            XCTAssertEqual(paint["circle-color"], .string(PinLayers.pinColor))
        } else { XCTFail("pin circle paint") }
    }

    func testFoundationObjectBridgeKeepsBoolAsBooleanNSNumber() {
        // The [XCODE/SIM] wrapper passes .foundationObject to NSPredicate(mglJSONObject:). A `true`
        // must become a BOOLEAN NSNumber (not 1), or a ["==",["get","saved"],true] filter mis-compares.
        let n = JSONValue.bool(true).foundationObject as? NSNumber
        XCTAssertNotNil(n)
        XCTAssertEqual(CFGetTypeID(n!), CFBooleanGetTypeID(), "bool must bridge to a boolean NSNumber, not 0/1")
        XCTAssertTrue(PinLayers.fadeOpacityExpression().foundationObject is [Any])   // expression bridges to NSArray
    }

    func testFeatureIsGeoJSONPointWithLonLatOrder() {
        let f = FeatureEncoding.feature(MapPlace(id: "mt1_x", lat: 51.5, lon: -0.12, tier: 2),
                                        PinState(saved: true, visit: .loved))
        guard case let .object(feat) = f, case let .object(geom) = feat["geometry"],
              case let .array(coords) = geom["coordinates"] else { return XCTFail("geometry") }
        XCTAssertEqual(coords, [.double(-0.12), .double(51.5)])   // GeoJSON is [lon, lat]
        guard case let .object(props) = feat["properties"] else { return XCTFail("props") }
        XCTAssertEqual(props["visit"], .string("loved"))
        XCTAssertEqual(props["saved"], .bool(true))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd ios && swift test --filter PinLayersTests`
Expected: FAIL — `PinLayers`/`FeatureEncoding`/`Expression` not defined.

- [ ] **Step 3: Implement**

`ios/Sources/MakingTracksMapStyle/Expression.swift`:
```swift
/// A tiny evaluator for exactly the MapLibre style-spec expression subset PinLayers generates:
/// ["get", k], ["match", input, l1, v1, …, fallback], ["==", a, b], and literals. Enough to PROVE
/// (host-side) that the generated expressions reproduce pinAppearance per cell — not a full engine.
public enum Expression {
    public static func evaluate(_ expr: JSONValue, _ props: [String: JSONValue]) -> JSONValue {
        guard case let .array(items) = expr, case let .string(op)? = items.first else { return expr }
        switch op {
        case "get":
            if case let .string(key) = items[1] { return props[key] ?? .null }
            return .null
        case "==":
            return .bool(evaluate(items[1], props) == evaluate(items[2], props))
        case "match":
            let input = evaluate(items[1], props)
            var i = 2
            while i + 1 < items.count {
                if evaluate(items[i], props) == input { return items[i + 1] }   // labels are literals
                i += 2
            }
            return items[items.count - 1]                                       // fallback
        default:
            return expr
        }
    }
}
```

`ios/Sources/MakingTracksMapStyle/FeatureEncoding.swift`:
```swift
import MakingTracksData

public enum FeatureEncoding {
    static func visitTag(_ v: VisitState) -> String {
        switch v { case .none: "none"; case .visited: "visited"; case .loved: "loved" }
    }
    /// The properties the style expressions read. Only what the matrix needs (visit, saved).
    public static func featureProperties(_ state: PinState) -> [String: JSONValue] {
        ["visit": .string(visitTag(state.visit)), "saved": .bool(state.saved)]
    }
    public static func feature(_ place: MapPlace, _ state: PinState) -> JSONValue {
        var props = featureProperties(state)
        props["place_id"] = .string(place.id)     // for tap → B4 lookup
        props["tier"] = .double(Double(place.tier))
        return .object([
            "type": .string("Feature"),
            "geometry": .object(["type": .string("Point"),
                                 "coordinates": .array([.double(place.lon), .double(place.lat)])]),  // [lon,lat]
            "properties": .object(props),
        ])
    }
    public static func featureCollection(_ features: [JSONValue]) -> JSONValue {
        .object(["type": .string("FeatureCollection"), "features": .array(features)])
    }
}
```

`ios/Sources/MakingTracksMapStyle/PinLayers.swift`:
```swift
import MakingTracksData

public enum PinLayers {
    public static let pinColor = "#E4572E"     // the ONLY saturated colour on the map (§5.1)
    public static let sourceID = "pins"

    /// match(["get","visit"], "none"->full, "visited"->faded, "loved"->faded, fallback full) —
    /// the per-visit opacity is taken FROM pinAppearance so it CANNOT diverge from the matrix.
    public static func fadeOpacityExpression() -> JSONValue {
        var match: [JSONValue] = [.string("match"), .array([.string("get"), .string("visit")])]
        for v in [VisitState.none, .visited, .loved] {
            match.append(.string(FeatureEncoding.visitTag(v)))
            match.append(.double(pinAppearance(PinState(saved: false, visit: v)).opacity))
        }
        match.append(.double(FULL_OPACITY))     // fallback for an unknown value
        return .array(match)
    }
    public static func bookmarkFilter() -> JSONValue {
        .array([.string("=="), .array([.string("get"), .string("saved")]), .bool(true)])
    }
    public static func heartFilter() -> JSONValue {
        .array([.string("=="), .array([.string("get"), .string("visit")]), .string("loved")])
    }

    /// The mandated substrate: a geojson MLNShapeSource-backed CIRCLE pin layer (opacity = fade
    /// expression, colour = the saturated pinColor) + a bookmark SYMBOL layer + a heart SYMBOL layer
    /// (filtered; badges persist at full opacity through the fade). NOT MLNAnnotation.
    public static func pinLayers() -> [JSONValue] {
        [
            .object(["id": .string("pins-circle"), "type": .string("circle"), "source": .string(sourceID),
                     "paint": .object(["circle-color": .string(pinColor),
                                       "circle-opacity": fadeOpacityExpression(),
                                       "circle-radius": .double(6)])]),
            .object(["id": .string("pins-bookmark"), "type": .string("symbol"), "source": .string(sourceID),
                     "filter": bookmarkFilter(),
                     "layout": .object(["icon-image": .string("badge-bookmark"), "icon-allow-overlap": .bool(true),
                                        "icon-offset": bookmarkOffset])]),   // distinct corner so co-present
            .object(["id": .string("pins-heart"), "type": .string("symbol"), "source": .string(sourceID),
                     "filter": heartFilter(),
                     "layout": .object(["icon-image": .string("badge-heart"), "icon-allow-overlap": .bool(true),
                                        "icon-offset": heartOffset])]),      // badges (saved+loved) don't collide
        ]
    }
    // Distinct anchors so the (saved, loved) cell renders BOTH badges legibly (§3.2): bookmark top-right,
    // heart top-left. (A cartographic decision — the spec mandates both badges co-present, not their layout.)
    public static let bookmarkOffset: JSONValue = .array([.double(8), .double(-8)])
    public static let heartOffset: JSONValue = .array([.double(-8), .double(-8)])
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd ios && swift test`
Expected: PASS (all `MakingTracksMapStyle` tests — the full-matrix expression==appearance proof, substrate shape, `[lon,lat]` order). **Teeth:** change any `fadeOpacityExpression` opacity or a badge filter and `testGeneratedExpressionsMatchPinAppearanceForEveryCell` reds for the affected cell(s).

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/MakingTracksMapStyle/Expression.swift ios/Sources/MakingTracksMapStyle/FeatureEncoding.swift \
        ios/Sources/MakingTracksMapStyle/PinLayers.swift ios/Tests/MakingTracksMapStyleTests/PinLayersTests.swift
git commit -m "Add pin substrate: shape-source+style layers, fade/badge expressions generated from the matrix, host-side evaluator proving expression==pinAppearance"
```

---

### Task 4: XcodeGen app shell + MapLibre dependency (supersedes B1 Task 7)  `[XCODE/SIM]`

> **`[XCODE/SIM]`** — this task builds the app target and cannot be verified on the host (no simulator/Xcode here). Steps give exact code + the simulator build/run commands; the plan makes **no host-verification claim** for them.

**Files:**
- Create: `ios/App/project.yml`, `ios/App/Sources/MakingTracksApp.swift`
- Create: `ios/Sources/MakingTracksData/AppDatabase+Live.swift` (in the **package**, not the app — see below)

**Interfaces:**
- Consumes: `MakingTracksData`, `MakingTracksMapStyle`, MapLibre Native.
- Produces: a launchable iOS 18 app whose root is `MapScreen` (Task 6); `AppDatabase.live()`. **Supersedes B1 Task 7 — closes issue #12** (reference this WP in the closing note).
- **`live()` lives in `MakingTracksData`, not the app target.** It uses GRDB (`DatabaseQueue`), and the app target does **not** depend on GRDB — putting `live()` in the app would fail with `No such module 'GRDB'`. `MakingTracksData` already depends on GRDB, so `live()` belongs there (and stays host-buildable). The app just calls `AppDatabase.live()`.

- [ ] **Step 1: XcodeGen project**

`ios/App/project.yml`:
```yaml
name: MakingTracks
options:
  deploymentTarget: { iOS: "18.0" }
settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete
packages:
  MakingTracksData: { path: .. }                 # the ios/ SwiftPM package (MakingTracksData + MakingTracksMapStyle)
  MapLibre:
    url: https://github.com/maplibre/maplibre-gl-native-distribution
    from: "6.27.0"                                  # XcodeGen: `from` (up-to-next-major), not lone `minVersion`
targets:
  MakingTracks:
    type: application
    platform: iOS
    sources: [Sources]
    dependencies:
      - package: MakingTracksData
        product: MakingTracksData
      - package: MakingTracksData
        product: MakingTracksMapStyle
      - package: MapLibre
        product: MapLibre
    info:
      path: Sources/Info.plist
      properties:
        UILaunchScreen: {}
```

- [ ] **Step 2: `@main` shell (replaces B1's reserved placeholder) + live DB**

`ios/App/Sources/MakingTracksApp.swift`:
```swift
import SwiftUI
import MakingTracksData

@main
struct MakingTracksApp: App {
    // B2 supersedes B1's reserved Task-7 placeholder root: the map screen IS the root now.
    let database = try! AppDatabase.live()
    var body: some Scene {
        WindowGroup { MapScreen(database: database) }
    }
}
```

`ios/Sources/MakingTracksData/AppDatabase+Live.swift` (in the **package** — it uses GRDB, which the app target does not depend on; this is the Application Support store B1's Task 7 would have provided):
```swift
import Foundation
import GRDB

public extension AppDatabase {
    static func live() throws -> AppDatabase {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true).appendingPathComponent("MakingTracks", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let dbQueue = try DatabaseQueue(path: support.appendingPathComponent("user.sqlite").path)
        return try AppDatabase(dbQueue, now: { Date() })
    }
}
```

- [ ] **Step 3: Generate + build (simulator)**

```bash
cd ios/App && xcodegen generate
xcodebuild -project MakingTracks.xcodeproj -scheme MakingTracks \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```
Expected: builds (after Tasks 5–6 provide `MapScreen`). **Not host-runnable — requires Xcode + a simulator.**

- [ ] **Step 4: Commit**

```bash
git add ios/App/project.yml ios/App/Sources/MakingTracksApp.swift ios/Sources/MakingTracksData/AppDatabase+Live.swift
git commit -m "Add XcodeGen app shell + MapLibre dep + AppDatabase.live in MakingTracksData (supersedes B1 Task 7; closes issue #12)"
```

---

### Task 5: `MLNMapView` `@MainActor` wrapper — basemap + pin substrate + tap  `[XCODE/SIM]`

> **`[XCODE/SIM]`** — MapLibre-touching; not host-verifiable. Exact code below; simulator is the only test surface.

**Files:**
- Create: `ios/App/Sources/Map/MLNMapViewRepresentable.swift`

**Interfaces:**
- Consumes: `MakingTracksMapStyle` (generated JSON), `MapPlace`/`PinState` (Sendable values). Produces: a `UIViewRepresentable` map that renders the paper basemap + the pin substrate and reports taps as `place_id`s.

- [ ] **Step 1: The wrapper**

`ios/App/Sources/Map/MLNMapViewRepresentable.swift`:
```swift
import SwiftUI
@preconcurrency import MapLibre          // MLN types are un-Sendable ObjC — contained here (§5.3)
import MakingTracksData
import MakingTracksMapStyle

/// @MainActor-isolated boundary. ALL map mutation is on the main actor; the ONLY things that cross
/// this boundary are Sendable values (features + generated JSON strings) — never MLN objects.
@MainActor
struct MLNMapViewRepresentable: UIViewRepresentable {
    let pmtilesURL: String                 // Protomaps demo (dev) or a local region .pmtiles path
    var features: [(MapPlace, PinState)]   // Sendable inputs; the wrapper builds GeoJSON from them
    var onTapPlace: (String) -> Void       // reports place_id from feature hit-testing

    func makeCoordinator() -> Coordinator { Coordinator(onTapPlace: onTapPlace) }

    func makeUIView(context: Context) -> MLNMapView {
        // Write the generated paper style to a temp file and point MapLibre at it (styleURL).
        let json = (try? paperBasemapStyle(pmtilesURL: pmtilesURL).jsonString()) ?? "{\"version\":8,\"sources\":{},\"layers\":[]}"
        let map = context.coordinator.writeStyle(json).map { MLNMapView(frame: .zero, styleURL: $0) }
            ?? MLNMapView(frame: .zero)     // style-write failure → empty map, never a crash
        map.delegate = context.coordinator
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        map.addGestureRecognizer(tap)
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        context.coordinator.update(map: map, features: features)      // main-actor mutation
    }

    @MainActor
    final class Coordinator: NSObject, MLNMapViewDelegate {
        let onTapPlace: (String) -> Void
        weak var map: MLNMapView?
        init(onTapPlace: @escaping (String) -> Void) { self.onTapPlace = onTapPlace }

        func writeStyle(_ json: String) -> URL? {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("mt-style.json")
            do { try Data(json.utf8).write(to: url); return url }
            catch { return nil }                                   // real error path (un-observable on host)
        }

        // Correct delegate selector is `mapView:didFinishLoadingStyle:` → `didFinishLoading style:`.
        // (The earlier `didFinish style:` matched NO protocol requirement, so it compiled but was
        // NEVER called — the entire pin substrate would silently never render. Verified against docs.)
        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            self.map = mapView
            // Badge icons MUST be registered or a symbol layer's icon-image renders NOTHING (silently).
            if let bookmark = UIImage(named: "badge-bookmark") { style.setImage(bookmark, forName: "badge-bookmark") }
            if let heart = UIImage(named: "badge-heart") { style.setImage(heart, forName: "badge-heart") }

            let source = MLNShapeSource(identifier: PinLayers.sourceID, shape: nil, options: nil)  // B8: …Clustered
            style.addSource(source)

            // Circle pin layer — opacity from the HOST-PROVEN fade expression via NSExpression(mglJSONObject:);
            // constants MUST be wrapped in NSExpression(forConstantValue:) (all MLN layer props are NSExpression).
            let circle = MLNCircleStyleLayer(identifier: "pins-circle", source: source)
            circle.circleOpacity = NSExpression(mglJSONObject: PinLayers.fadeOpacityExpression().foundationObject)
            circle.circleColor = NSExpression(forConstantValue: UIColor(hex: PinLayers.pinColor))
            circle.circleRadius = NSExpression(forConstantValue: 6)
            style.addLayer(circle)

            // Badge SYMBOL layers — filter is an NSPredicate (NOT NSExpression): MLNVectorStyleLayer.predicate
            // is NSPredicate?, built via NSPredicate(mglJSONObject:). [XCODE/SIM] caveat: verify the modern
            // ["==",["get","saved"],true] form is accepted; if the predicate needs the legacy bare-property
            // form, emit it from PinLayers and add a host test for that form too.
            addBadge(id: "pins-bookmark", icon: "badge-bookmark", filter: PinLayers.bookmarkFilter(),
                     offset: PinLayers.bookmarkOffset, source: source, style: style)
            addBadge(id: "pins-heart", icon: "badge-heart", filter: PinLayers.heartFilter(),
                     offset: PinLayers.heartOffset, source: source, style: style)
        }

        private func addBadge(id: String, icon: String, filter: JSONValue, offset: JSONValue,
                              source: MLNShapeSource, style: MLNStyle) {
            let layer = MLNSymbolStyleLayer(identifier: id, source: source)
            layer.iconImageName = NSExpression(forConstantValue: icon)
            layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
            if case let .array(o) = offset, case let .double(x) = o[0], case let .double(y) = o[1] {
                layer.iconOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: x, dy: y)))
            }
            layer.predicate = NSPredicate(mglJSONObject: filter.foundationObject)
            style.addLayer(layer)
        }

        func update(map: MLNMapView, features: [(MapPlace, PinState)]) {
            let fc = FeatureEncoding.featureCollection(features.map { FeatureEncoding.feature($0.0, $0.1) })
            guard let src = map.style?.source(withIdentifier: PinLayers.sourceID) as? MLNShapeSource,
                  let shape = try? MLNShape(data: Data(try fc.jsonString().utf8),
                                            encoding: String.Encoding.utf8.rawValue)
            else { return }                                        // malformed → skip, never crash (§5.5)
            src.shape = shape
        }

        @objc func handleTap(_ gr: UITapGestureRecognizer) {
            guard let map = self.map else { return }
            let point = gr.location(in: map)
            // MANDATED hit-testing (§5.1): query ALL pin layers (badges too) so a tap on an offset
            // badge still resolves its place_id.
            let hits = map.visibleFeatures(at: point,
                                           styleLayerIdentifiers: ["pins-circle", "pins-bookmark", "pins-heart"])
            if let id = hits.first?.attribute(forKey: "place_id") as? String { onTapPlace(id) }
        }
    }
}

private extension UIColor {
    convenience init(hex: String) {                // #RRGGBB → UIColor (the saturated pin colour)
        var s = hex; if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt64(s, radix: 16) ?? 0
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
```
*(Applying the generated JSON to live MLN layers is the **single riskiest MLN surface** and no host test reaches it: opacity via `NSExpression(mglJSONObject:)` (the `mgl` prefix is retained despite the `MLN` class rename — verified); constants via `NSExpression(forConstantValue:)`; **filters via `NSPredicate(mglJSONObject:)`, NOT `NSExpression`** (`MLNVectorStyleLayer.predicate` is `NSPredicate?`); badge icons via `style.setImage(_:forName:)`. The `.foundationObject` bridge (Task 1) turns the host-proven `JSONValue` into the `NSArray`/`NSNumber` these initializers expect. All of this is `[XCODE/SIM]`-verified only — see Step 2's read-back check.)*

- [ ] **Step 2: Build + read-back check (simulator) + commit**

Build via the Task 4 `xcodebuild` command. **Not host-runnable.** Then — because the host proof covers only *generation*, not the JSON→MLN *application* — add a `[XCODE/SIM]` read-back test that closes the loop: after the style loads, for each of the 6 matrix cells, set the shape source to a single synthetic feature with that cell's `featureProperties`, then assert `MLNCircleStyleLayer.circleOpacity` evaluated for the feature equals `pinAppearance(cell).opacity`, and evaluate each badge layer's `predicate` against the feature and assert it matches `showBookmarkBadge`/`showHeartBadge`. This gives the JSON→MLN bridge teeth (in the simulator) that the host tests cannot.
```bash
git add ios/App/Sources/Map/MLNMapViewRepresentable.swift
git commit -m "Add MLNMapView @MainActor wrapper: didFinishLoading, circle+badge layers via NSExpression/NSPredicate, badge icon registration, visibleFeatures(at:) tap"
```

---

### Task 6: `MapScreen` — viewport → viewportState → feature feed + dev harness  `[XCODE/SIM]`

> **`[XCODE/SIM]`** — SwiftUI screen wiring the Sendable data layer to the wrapper. Not host-verifiable.

**Files:**
- Create: `ios/App/Sources/Map/MapScreen.swift`, `ios/App/Sources/Map/DevPlaces.swift`

- [ ] **Step 1: The screen + dev harness**

`ios/App/Sources/Map/MapScreen.swift`:
```swift
import SwiftUI
import MakingTracksData

struct MapScreen: View {
    let database: AppDatabase
    @State private var features: [(MapPlace, PinState)] = []

    var body: some View {
        MLNMapViewRepresentable(
            pmtilesURL: DevPlaces.demoBasemapURL,       // public Protomaps demo tiles (dev)
            features: features,
            onTapPlace: { placeID in /* B4 opens the place card via this id */ _ = placeID }
        )
        .ignoresSafeArea()
        .task { await refresh(places: DevPlaces.all) }  // dev features until B3 supplies real ones
    }

    // Viewport → visible place_ids → viewportState → features. THE HOT QUERY (§5.4, hundreds of ids at
    // street zoom) is a SYNCHRONOUS GRDB read, so it must run OFF the main actor (§5.3: "read user state
    // off any task, mutate the map on the main actor"). `.task` inherits the View's @MainActor, so we hop
    // off via Task.detached, then assign `features` back on the main actor. B3/B4 inherit THIS pattern —
    // it must be correct here. (`database` is Sendable, so capturing it in a detached task is safe.)
    private func refresh(places: [MapPlace]) async {
        let ids = places.map(\.id)
        let db = database
        let states = await Task.detached { (try? db.viewportState(ids)) ?? [:] }.value
        // viewportState returns an entry for every id on success; the fallback covers a READ FAILURE
        // (states == [:]), keeping this crash-free (§5.5) rather than force-unwrapping.
        features = places.map { ($0, states[$0.id] ?? PinState(saved: false, visit: .none)) }
    }
}
```

`ios/App/Sources/Map/DevPlaces.swift`:
```swift
import MakingTracksData

// Dev-only harness so the pin substrate is exercisable before B3/A7. Replaced by the tile client.
enum DevPlaces {
    static let demoBasemapURL = "pmtiles://https://demo.protomaps.com/…/example.pmtiles"  // set to a current demo build
    static let all: [MapPlace] = [
        MapPlace(id: "mt1_dev0000000000000000000001", lat: 51.507, lon: -0.128, tier: 1),
        MapPlace(id: "mt1_dev0000000000000000000002", lat: 51.501, lon: -0.142, tier: 2),
        MapPlace(id: "mt1_dev0000000000000000000003", lat: 51.513, lon: -0.098, tier: 3),
    ]
}
```

- [ ] **Step 2: Generate, build, run (simulator)**

```bash
cd ios/App && xcodegen generate
xcodebuild -project MakingTracks.xcodeproj -scheme MakingTracks \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```
Manual simulator check: paper basemap renders; dev pins appear in saturated colour; a saved/visited/loved dev place shows the right fade + badges; tapping a pin logs its `place_id`. **Not host-runnable.**

- [ ] **Step 3: Commit**

```bash
git add ios/App/Sources/Map/MapScreen.swift ios/App/Sources/Map/DevPlaces.swift
git commit -m "Add MapScreen: viewportState-driven feature feed + dev harness (Protomaps demo basemap)"
```

---

## Review Record

**Author self-review** — deliverables map to tasks: the pure host-tested `MakingTracksMapStyle` — pin-matrix truth (T1), paper basemap style JSON (T2), pin substrate with expressions **generated from the matrix** + the evaluator proving `expression == pinAppearance` per cell (T3, the §7 surface host-side); the `[XCODE/SIM]` app shell superseding B1 Task 7 (T4), the `MLNMapView` `@MainActor` wrapper with the mandated shape-source+style-layer substrate and `visibleFeatures(at:)` tap (T5), and the `viewportState`-driven `MapScreen` + dev harness (T6). Renders pins from `PinState` (`visit` drives fade — not `seen()`); exchanges only `Sendable` values across the `@MainActor` boundary; never crashes on malformed features (skip); plain-text only. `MapPlace` is minimal and lives in `MakingTracksData` (provisional-until-B3).

**Ratifications (fable, thread `wp/b2`)** — the host-tested `MakingTracksMapStyle` seam (matrix + generated expressions + per-cell evaluator = §7 without a simulator); fade axis = `visit != .none`; B2 shell supersedes B1 Task 7 (issue #12); `MapPlace` minimal in `MakingTracksData`, provisional-until-B3; `[XCODE/SIM]` honesty.

**Feasibility pre-verified (author, Swift 6.3.3 on host).** The pure core was prototyped and run: `JSONValue` (incl. Codable round-trip with bool≠double and the `foundationObject` bool→boolean-NSNumber bridge), `pinAppearance` + the generated `match` fade expression + badge filters + the evaluator over the **full 6-cell matrix** (every cell's evaluated expression equals `pinAppearance`), and the HSV `saturation` palette check (default palette 0.04–0.21 muted, pin 0.80). This is what Tasks 1–3's `swift test` re-runs; the MapLibre/`UIViewRepresentable` tasks are `[XCODE/SIM]` and **not** claimed host-verified.

**Cross-package flags surfaced:**
- **B1 Task 7 absorbed** — B2's XcodeGen shell is the one app shell; **issue #12 closes when it lands** (referencing this WP).
- **`MapPlace` provisional** — in `MakingTracksData`, minimal (`id/lat/lon/tier`); **B3's designer may extend, never break** it. B3 produces it from decoded tiles; B2 consumes it. Flag on B3's design.
- **B4 consumes B2's tap** — `onTapPlace(place_id)` is the hit-testing seam B4 turns into the place card.
- **B8 shares the substrate** — clustering (`MLNShapeSourceOptionClustered` on the `pins` source), tier/zoom gating (`tier` rides on the feature), and the "Fresh snow" toggle build on the same `MLNShapeSource` + layers.
- **Off-main hot-query pattern** — `MapScreen.refresh` runs `viewportState` via `Task.detached` (the synchronous GRDB read must not block the main actor, §5.3/§5.4); **B3/B4 inherit this pattern**.
- **Protomaps demo basemap URL / badge icon assets** — dev placeholders; set to a current demo `.pmtiles` and provide `badge-bookmark`/`badge-heart` `UIImage`s at implementation (registered via `style.setImage`).

**Adversarial review (per AGENTS.md gate) — COMPLETED. 3 independent critics (spec/§5.1-boundary fidelity; MapLibre-iOS-API correctness for the un-host-testable wrapper; coherence+test-quality that BUILT `MakingTracksMapStyle` on Swift 6.3.3). The build critic confirmed Tasks 1–3 compile clean under strict-concurrency `complete`, all tests pass, and the star matrix test reds under both neuters. All findings fixed and, for the pure parts, re-verified on the host.**
- **Fixed — CRITICAL:** the style-loaded delegate was `didFinish style:` (matched no protocol requirement → compiled but **never called** → a pin-less map that "looks done") → corrected to `didFinishLoading style:`. This is exactly the class of bug no host test catches, caught by the API critic verifying against real MapLibre docs.
- **Fixed — HIGH:** (a) badge filters were applied as `NSExpression` — but a layer filter is `MLNVectorStyleLayer.predicate` (`NSPredicate`, via `NSPredicate(mglJSONObject:)`) → corrected, with a `[XCODE/SIM]` note to confirm the modern `["==",["get",...]]` form vs legacy. (b) `AppDatabase+Live` used GRDB but the app target doesn't depend on it → moved `live()` into `MakingTracksData`. (c) **Overclaim** ("expression can never diverge from the matrix") — the evaluator is a same-module re-implementation, so it proves *generation*, not *rendering* → softened everywhere, and Task 5 gained a `[XCODE/SIM]` per-cell read-back so the JSON→MLN bridge has its own teeth; `addLayer` is fleshed out with named APIs (`NSExpression(mglJSONObject:)`/`forConstantValue:`, `NSPredicate(mglJSONObject:)`, `style.setImage`), not a stub.
- **Fixed — MEDIUM:** badge icons were never registered (`icon-image` → nothing renders) → explicit `style.setImage` step; the (saved,loved) cell stacked both badges at one anchor → distinct `icon-offset` (host-tested different); `viewportState` ran synchronously on the main actor → `Task.detached`; XcodeGen `minVersion:` alone → `from: "6.27.0"`; tap hit-tested only the circle → all three pin layers.
- **Fixed — LOW:** the palette-muted test was vacuous (a neon basemap passed) → HSV `saturation` assertion over all colours (host-verified); `Derivations.seen()` → `AppDatabase.seen(among:)`; new targets given `.swiftLanguageMode(.v6)`; `writeStyle` got a real error path; dead `PaperPalette.labels` dropped.
- **Affirmed by the critics (not changed):** `NSExpression(mglJSONObject:)` for `circle-opacity`, the `pmtiles://` vector source, `MLNShape(data:encoding:)`, the `@preconcurrency`+`@MainActor` Sendable-only containment, the mandated `MLNShapeSource`+circle/symbol substrate (not `MLNAnnotation`), the 6-cell matrix precedence, the seen-vs-visit reading, and the host/`[XCODE/SIM]` seam cut — all verified correct.
