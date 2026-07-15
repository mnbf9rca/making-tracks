# WP-B1 (App Skeleton + User DB) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the iOS app skeleton and the on-device user-data layer — a host-testable SwiftPM package (`MakingTracksData`) holding the GRDB schema, numbered migrations, and indexes exactly per §5.4, the derivations (seen, list progress, batched viewport-state resolve, pin-state matrix), and the `place_snapshots` writes on first user interaction — plus a thin SwiftUI app shell that depends on it.

**Architecture:** A **SwiftPM package split** answers the simulator constraint. `MakingTracksData` is pure Swift + GRDB with **no SwiftUI/UIKit**, so every invariant runs on the macOS host via `swift test` — **no simulator**. A thin iOS app target, generated from a text `project.yml` via **XcodeGen**, depends on that package and is the *only* Xcode/simulator-dependent piece. Swift 6 strict concurrency from day one: the store is a `Sendable` type over a GRDB `DatabaseQueue`; all records are `Sendable` value structs.

**Tech Stack:** Swift 6 (strict concurrency), iOS 18+, GRDB 7.x via SPM, XcodeGen, XCTest (host-side via `swift test`).

## Build-phase testability (fable's constraint — read first)

Every task is tagged **[HOST]** or **[XCODE/SIM]**:
- **[HOST]** — pure SwiftPM; runs via `swift test` on macOS with **no simulator**. Tasks 1–6 (the entire data layer + every invariant test). A builder can start these tonight while the simulator is occupied.
- **[XCODE/SIM]** — needs Xcode/simulator. Task 7 only (XcodeGen project generation + app-shell compile/launch smoke). Do not start until a simulator is free.

## Global Constraints

- **Swift 6 language mode + strict concurrency, day one (§5.3).** All shared types are `Sendable`; DB access goes through a `Sendable` store; no cross-actor shared mutable state. GRDB's `DatabaseQueue` is `Sendable` and serializes access.
- **iOS 18 minimum** (app target); the `MakingTracksData` package targets macOS (for host tests) **and** iOS 18.
- **GRDB, not SwiftData (§5.3 rationale, pinned):** predictable, testable migrations + raw-SQL control under a schema user history depends on. Migrations are monotonic, numbered, via `DatabaseMigrator`.
- **Schema is EXACTLY §5.4** — tables `visits`, `lists`, `list_items`, `place_snapshots`; the composite **PRIMARY KEY (list_id, place_id)** on `list_items`; and **both** indexes `idx_visits_place` and `idx_list_items_place`. One deliberate integrity refinement beyond the literal §5.4 DDL: `list_items.list_id` gets a `REFERENCES lists ON DELETE CASCADE` (orphaned list items are never desirable; deleting a list removes its items). This is flagged to fable as a conscious addition, not a silent migration default, and confirms the cascade-on-list-delete semantic B5 will rely on.
- **Seen is a fact about the world (Principle 4).** Global per user, stored as a **visit-event log** — not a boolean. `seen` = derived (≥1 visit). Un-marking = deleting an event. Re-visits are representable.
- **Snapshot on first interaction (Principle 8 / §5.4).** The first time a user visits or saves a place, its read-only fields are snapshotted into `place_snapshots` so Tracks and lists render **forever**, independent of upstream churn or tile eviction.
- **Versioned stored artifacts (Principle 11 / §5.6).** (a) User-DB migrations are numbered; the app **refuses to open a DB written by a newer app version** (backup-restore safety) rather than corrupt it, via a defined error. (b) `place_snapshots` records the place `schema_version` it was written under (`snapshot_schema_version`), so a snapshot read years later is understood, never misread.
- **No R-tree in v1 (§5.4).** The viewport-state resolve is a **batched keyed membership lookup** over the two `place_id` indexes (or an in-memory `Set` cache), never a spatial query.
- **Backup posture (§5.3).** The DB lives in **Application Support** and rides the iCloud **device** backup by default — nothing sets `isExcludedFromBackup`, and no file-protection level is applied that would block a later background read (B8 nearby prompts are foreground-only in v1, but do not paint that corner). GRDB runs in WAL mode by default; `DatabaseQueue` checkpoints on close, so the `-wal`/`-shm` sidecars need no special handling — they are transient and the on-disk `.sqlite` is consistent for backup after close.
- **Consumes A0 (cite by name, not JSON literals — wp-a0-impl is still settling).** The read-only place fields, per A0 `CONTRACTS.md`: `place_id`, `name`, `lat`, `lon`, `category`, `tier` (1–4), `score`, optional `alt_names`, `blurb`, `image_url`, `wikipedia_title`, `source_refs`.
- **Untrusted tile data → validated storage boundary (§5.5, Principle 10).** Tile content is untrusted even though we published it. **B3 (the tile client) owns the primary §5.5 decode-time validation** — strict typed decoding, length/size caps, `https://`-only `image_url` with host allowlist, control-char stripping — and hands B1 a `PlaceRef`. B1's `PlaceRef` is **constructible only through a throwing initializer** that re-checks the storage-critical caps (coordinate bounds + finiteness, `tier ∈ 1…4`, field-length caps, `snapshot_json` byte cap), so B1 can never persist unvalidated data (defense in depth). `PlaceRef` is deliberately **not `Codable`** — it cannot be decoded straight from a tile blob.
- **Snapshot content is verbatim + self-describing (Principle 8 / 11).** `snapshot_json` stores the **verbatim** A0 place-object bytes (never a re-encode of the typed subset, which would drop any field the struct doesn't model — fatal to "renders forever" as A0 evolves). `snapshot_schema_version` and `fetched_at` are **data-derived** — the version the data was actually decoded under and its manifest provenance time — supplied by B3, never a compile-time constant (a constant would let a snapshot lie about its own shape).
- **Test-first.** Every type lands with a failing host test first.

**Ratified (fable, thread `wp/b1`):** SwiftPM data package + host `swift test`; XcodeGen for the app; full place JSON in `snapshot_json` with typed projection; minimal shell (pin-state matrix is B1 derivation logic, visual snapshots are B2); GRDB 7.x behind a `Sendable` boundary, iOS 18, no R-tree. Plus three riders folded in: `snapshot_schema_version` column, refuse-newer-DB guard (host-tested), backup posture asserted.

---

## File Structure

```
ios/
  Package.swift                              # SwiftPM: MakingTracksData library + tests (GRDB 7.x) [HOST]
  Sources/MakingTracksData/
    AppDatabase.swift                        # Sendable store over DatabaseQueue; open + migrate + refuse-newer
    Migrations.swift                         # DatabaseMigrator v1: §5.4 schema, PK, indexes, seed 'Want to go'
    Errors.swift                             # AppDatabaseError (incl. databaseFromNewerAppVersion)
    Models/Visit.swift                       # Visit record + Verdict enum
    Models/PlaceList.swift                   # PlaceList record ('Want to go' is is_system)
    Models/ListItem.swift                    # ListItem record (PK list_id+place_id)
    Models/PlaceSnapshot.swift               # PlaceSnapshot record (+ snapshot_schema_version)
    Models/PlaceRef.swift                    # Sendable value type: the A0 place fields used to seed a snapshot
    PinState.swift                           # SavedState / VisitState / PinState (saved × visit matrix)
    Derivations.swift                        # seen (batched), list progress, viewport-state resolve
    Interactions.swift                       # recordVisit / addToList / snapshotIfNeeded (first-interaction writes)
  Tests/MakingTracksDataTests/
    MigrationsTests.swift                    # schema/PK/index/seed + refuse-newer [HOST]
    ModelsTests.swift                        # record round-trips [HOST]
    DerivationsTests.swift                   # seen, progress, viewport resolve [HOST]
    PinStateTests.swift                      # full 6-cell pin matrix [HOST]
    InteractionsTests.swift                  # snapshot-on-first-interaction + schema_version + idempotence [HOST]
    ConcurrencyTests.swift                   # Sendable store used from concurrent tasks [HOST]
  App/                                       # [XCODE/SIM] — the only simulator-dependent piece
    project.yml                              # XcodeGen: iOS 18 app target depending on MakingTracksData
    Sources/MakingTracksApp.swift            # @main App + placeholder root view
    Sources/AppDatabase+Live.swift           # opens the DB in Application Support (backup-included)
    Resources/Info.plist                     # minimal; iOS 18 deployment target
```

`MakingTracksData` never imports SwiftUI/UIKit — that is what keeps it host-testable. `App/` is a thin consumer.

---

### Task 1 [HOST]: SwiftPM package scaffold + GRDB dependency

**Files:**
- Create: `ios/Package.swift`, `ios/Sources/MakingTracksData/AppDatabase.swift` (stub), `ios/Tests/MakingTracksDataTests/SmokeTests.swift`

**Interfaces:**
- Consumes: GRDB 7.x (SPM).
- Produces: `MakingTracksData.AppDatabase` with `AppDatabase.inMemory(now:) throws -> AppDatabase` (the host-test entry point — no file, no simulator).

- [ ] **Step 1: Write the failing smoke test**

`ios/Tests/MakingTracksDataTests/SmokeTests.swift`:
```swift
import XCTest
import GRDB
@testable import MakingTracksData

final class SmokeTests: XCTestCase {
    func testInMemoryDatabaseOpens() throws {
        let db = try AppDatabase.inMemory()
        XCTAssertNotNil(db)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd ios && swift test --filter SmokeTests`
Expected: FAIL — no `Package.swift` / `AppDatabase` yet (compile error).

- [ ] **Step 3: Write `Package.swift`**

`ios/Package.swift`:
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MakingTracksData",
    platforms: [.iOS(.v18), .macOS(.v14)],   // macOS enables host `swift test`
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
            swiftSettings: [.swiftLanguageMode(.v6)]     // strict concurrency, day one
        ),
        .testTarget(
            name: "MakingTracksDataTests",
            dependencies: ["MakingTracksData"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
```

- [ ] **Step 4: Write the `AppDatabase` stub**

`ios/Sources/MakingTracksData/AppDatabase.swift`:
```swift
import Foundation
import GRDB

/// The on-device user-data store. `Sendable`: a `DatabaseQueue` is Sendable and
/// serializes all access, and `now` is a Sendable clock injected for deterministic
/// tests. No SwiftUI/UIKit here — the package is host-testable via `swift test`.
public final class AppDatabase: Sendable {
    let dbQueue: DatabaseQueue
    let now: @Sendable () -> Date

    // public: the app target (Task 7) constructs this via a plain `import` (not @testable).
    public init(_ dbQueue: DatabaseQueue, now: @escaping @Sendable () -> Date) throws {
        self.dbQueue = dbQueue
        self.now = now
        try open()
    }

    /// Host-test entry point: an in-memory DB, no file, no simulator.
    public static func inMemory(now: @escaping @Sendable () -> Date = { Date() }) throws -> AppDatabase {
        try AppDatabase(try DatabaseQueue(), now: now)
    }

    private func open() throws {
        try migrate()   // fleshed out in Task 2
    }

    func migrate() throws { /* Task 2 */ }
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `cd ios && swift test --filter SmokeTests`
Expected: PASS (GRDB resolves via SPM; 1 test passes). *(First run fetches GRDB — network required once.)*

- [ ] **Step 6: Commit**

```bash
git add ios/Package.swift ios/Sources/MakingTracksData/AppDatabase.swift ios/Tests/MakingTracksDataTests/SmokeTests.swift
git commit -m "Scaffold MakingTracksData SwiftPM package (GRDB, Swift 6, host-testable) with Sendable store"
```

---

### Task 2 [HOST]: Migrations — §5.4 schema, PK, indexes, system list + refuse-newer guard

**Files:**
- Create: `ios/Sources/MakingTracksData/Migrations.swift`, `ios/Sources/MakingTracksData/Errors.swift`
- Modify: `ios/Sources/MakingTracksData/AppDatabase.swift` (`migrate()`)
- Test: `ios/Tests/MakingTracksDataTests/MigrationsTests.swift`

**Interfaces:**
- Produces:
  - `AppDatabase.makeMigrator() -> (migrator, identifiers)` — registers migrations and returns their identifiers from ONE place (allow-list can't drift from what's registered); `AppDatabase.appliedMigrations: Set<String>`.
  - `AppDatabaseError.databaseFromNewerAppVersion(unknown:)` and `AppDatabaseError.unreadableDatabase`.
  - v1 schema exactly per §5.4, with the `'Want to go'` system list seeded (deterministic `created_at` via the injected clock) and a `snapshot_schema_version` column on `place_snapshots`.

- [ ] **Step 1: Write the failing test**

`ios/Tests/MakingTracksDataTests/MigrationsTests.swift`:
```swift
import XCTest
import GRDB
@testable import MakingTracksData

final class MigrationsTests: XCTestCase {
    func testSchemaMatchesSection54Exactly() throws {
        let db = try AppDatabase.inMemory()
        try db.dbQueue.read { d in
            // EXACT column sets (equality, not superset) for all four tables (§5.4)
            func cols(_ t: String) throws -> Set<String> { Set(try d.columns(in: t).map(\.name)) }
            XCTAssertEqual(try cols("visits"), ["id", "place_id", "visited_at", "verdict", "created_at"])
            XCTAssertEqual(try cols("lists"), ["id", "name", "is_system", "created_at"])
            XCTAssertEqual(try cols("list_items"), ["list_id", "place_id", "added_at"])
            XCTAssertEqual(try cols("place_snapshots"), ["place_id", "name", "lat", "lon", "category",
                "tier", "snapshot_json", "snapshot_schema_version", "fetched_at"])
            // list_items composite primary key (§5.4)
            XCTAssertEqual(try d.primaryKey("list_items").columns, ["list_id", "place_id"])
            // both indexes exist AND are on the place_id column (not just named right)
            let vIdx = try d.indexes(on: "visits").first { $0.name == "idx_visits_place" }
            let liIdx = try d.indexes(on: "list_items").first { $0.name == "idx_list_items_place" }
            XCTAssertEqual(vIdx?.columns, ["place_id"])
            XCTAssertEqual(liIdx?.columns, ["place_id"])
        }
    }

    func testNoSpatialRTreeTableExists() throws {
        // §5.4: viewport-state resolve is a batched keyed lookup, NOT a spatial query.
        let db = try AppDatabase.inMemory()
        let rtree = try db.dbQueue.read { try Int.fetchOne($0,
            sql: "SELECT COUNT(*) FROM sqlite_master WHERE lower(sql) LIKE '%rtree%'") } ?? 0
        XCTAssertEqual(rtree, 0)
    }

    func testSystemListNotDoubleSeededAcrossReopen() throws {
        // in-memory DBs vanish on close, so use a file to exercise the real reopen path.
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("mt-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        for _ in 0..<2 {
            let db = try AppDatabase(try DatabaseQueue(path: path), now: { Date(timeIntervalSince1970: 0) })
            _ = db
        }
        let db = try AppDatabase(try DatabaseQueue(path: path), now: { Date(timeIntervalSince1970: 0) })
        let n = try db.dbQueue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM lists WHERE is_system = 1") }
        XCTAssertEqual(n, 1)   // migration ran once; not re-seeded on reopen
    }

    func testSeedsWantToGoSystemListExactlyOnce() throws {
        let db = try AppDatabase.inMemory()
        let rows = try db.dbQueue.read { try Row.fetchAll($0, sql: "SELECT name, is_system FROM lists") }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["name"], "Want to go")
        XCTAssertEqual(rows[0]["is_system"], true)
    }

    func testRefusesDatabaseFromNewerAppVersion() throws {
        // Simulate a DB written by a FUTURE app: an applied migration this app doesn't know.
        let queue = try DatabaseQueue()
        try queue.write { d in
            try d.execute(sql: "CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)")
            try d.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('v1'), ('v2_future')")
        }
        XCTAssertThrowsError(try AppDatabase(queue, now: { Date() })) { err in
            guard case AppDatabaseError.databaseFromNewerAppVersion(let unknown) = err else {
                return XCTFail("expected databaseFromNewerAppVersion, got \(err)")
            }
            XCTAssertTrue(unknown.contains("v2_future"))
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd ios && swift test --filter MigrationsTests`
Expected: FAIL — `migrate()` is empty; tables/guard missing.

- [ ] **Step 3: Write `Errors.swift`**

`ios/Sources/MakingTracksData/Errors.swift`:
```swift
import Foundation

public enum AppDatabaseError: Error, Equatable {
    /// The DB on disk was written by a newer app version (has migrations this app
    /// does not know). Refuse rather than corrupt (§5.6). The shell renders this
    /// as an "update required" state (B10).
    case databaseFromNewerAppVersion(unknown: Set<String>)
    /// The file has a grdb_migrations table we cannot read (foreign/corrupt DB).
    /// Refuse cleanly with a typed error rather than surfacing a raw SQLite error.
    case unreadableDatabase
}
```

- [ ] **Step 4: Write `Migrations.swift` and wire `migrate()`**

`ios/Sources/MakingTracksData/Migrations.swift`:
```swift
import Foundation
import GRDB

extension AppDatabase {
    /// Build the migrator AND collect the identifiers it registers in ONE place, so
    /// the refuse-newer allow-list can never drift from what's actually registered.
    /// (A drift would either miss a newer DB or lock users out of their own DB.)
    private func makeMigrator() -> (migrator: DatabaseMigrator, identifiers: [String]) {
        var migrator = DatabaseMigrator()
        var identifiers: [String] = []
        func register(_ id: String, _ body: @escaping @Sendable (Database) throws -> Void) {
            identifiers.append(id)
            migrator.registerMigration(id, migrate: body)
        }

        register("v1") { [now] db in
            try db.create(table: "visits") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("place_id", .text).notNull()
                t.column("visited_at", .datetime).notNull()
                t.column("verdict", .text)                 // nullable; v1: 'loved' or null (§3.3)
                t.column("created_at", .datetime).notNull()
            }
            try db.create(index: "idx_visits_place", on: "visits", columns: ["place_id"])

            try db.create(table: "lists") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("is_system", .boolean).notNull().defaults(to: false)
                t.column("created_at", .datetime).notNull()
            }

            try db.create(table: "list_items") { t in
                t.column("list_id", .integer).notNull()
                    .references("lists", onDelete: .cascade)
                t.column("place_id", .text).notNull()
                t.column("added_at", .datetime).notNull()
                t.primaryKey(["list_id", "place_id"])       // §5.4 composite PK
            }
            try db.create(index: "idx_list_items_place", on: "list_items", columns: ["place_id"])

            try db.create(table: "place_snapshots") { t in
                t.column("place_id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("lat", .double).notNull()
                t.column("lon", .double).notNull()
                t.column("category", .text).notNull()
                t.column("tier", .integer).notNull()
                t.column("snapshot_json", .text).notNull()
                t.column("snapshot_schema_version", .integer).notNull()  // Principle 11 (rider 1)
                t.column("fetched_at", .datetime).notNull()
            }

            // Ship the 'Want to go' system list (deterministic clock for tests).
            try db.execute(sql: "INSERT INTO lists (name, is_system, created_at) VALUES (?, ?, ?)",
                           arguments: ["Want to go", true, now()])
        }
        return (migrator, identifiers)
    }

    /// Migration identifiers already applied to the DB on disk (empty for a fresh DB).
    var appliedMigrations: Set<String> {
        get throws {
            try dbQueue.read { db in
                guard try db.tableExists("grdb_migrations") else { return [] }
                do {
                    return try Set(String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations"))
                } catch {
                    // A grdb_migrations table we can't read = a foreign/corrupt DB.
                    throw AppDatabaseError.unreadableDatabase
                }
            }
        }
    }

    func migrate() throws {
        let (migrator, identifiers) = makeMigrator()
        // §5.6 refuse-newer guard: a DB carrying a migration this app version does not
        // know was written by a NEWER app. Refuse before touching it.
        let unknown = try appliedMigrations.subtracting(identifiers)
        if !unknown.isEmpty {
            throw AppDatabaseError.databaseFromNewerAppVersion(unknown: unknown)
        }
        try migrator.migrate(dbQueue)
    }
}
```

**Delete the entire `func migrate() throws { /* Task 2 */ }` stub from `AppDatabase.swift`** (remove the whole method, not just its body). The `Migrations.swift` extension above now supplies the *sole* `migrate()`, which `open()` already calls (an extension method on the same type is directly callable).

- [ ] **Step 5: Run to verify it passes**

Run: `cd ios && swift test --filter MigrationsTests`
Expected: PASS (5 tests).

- [ ] **Step 6: Commit**

```bash
git add ios/Sources/MakingTracksData/Migrations.swift ios/Sources/MakingTracksData/Errors.swift \
        ios/Sources/MakingTracksData/AppDatabase.swift ios/Tests/MakingTracksDataTests/MigrationsTests.swift
git commit -m "Add v1 GRDB migrations (§5.4 schema, PK, indexes, system list) + refuse-newer-DB guard"
```

---

### Task 3 [HOST]: Record models (Sendable value types)

**Files:**
- Create: `ios/Sources/MakingTracksData/Models/{Visit,PlaceList,ListItem,PlaceSnapshot,PlaceRef}.swift`
- Test: `ios/Tests/MakingTracksDataTests/ModelsTests.swift`

**Interfaces:**
- Produces:
  - `Visit` (`id: Int64?`, `placeID: String`, `visitedAt: Date`, `verdict: Verdict?`, `createdAt: Date`); `enum Verdict: String, Codable, Sendable { case loved }`.
  - `PlaceList` (`id: Int64?`, `name: String`, `isSystem: Bool`, `createdAt: Date`).
  - `ListItem` (`listID: Int64`, `placeID: String`, `addedAt: Date`).
  - `PlaceSnapshot` (typed columns + `snapshotJSON: String`, `snapshotSchemaVersion: Int`, `fetchedAt: Date`).
  - `PlaceRef` — a `Sendable` value seeded from tile data, with a **throwing validating initializer** (§5.5 storage-boundary caps) and instance fields `schemaVersion: Int`, `fetchedAt: Date`, `rawJSON: String` (verbatim A0 payload), all supplied by B3. **Not `Codable`** (cannot be decoded straight from a tile blob).
  - The four GRDB records conform to `Codable, Sendable, FetchableRecord`, and `MutablePersistableRecord`/`PersistableRecord`, with snake_case column mapping.

- [ ] **Step 1: Write the failing test**

`ios/Tests/MakingTracksDataTests/ModelsTests.swift`:
```swift
import XCTest
import GRDB
@testable import MakingTracksData

final class ModelsTests: XCTestCase {
    func testVisitRoundTripsWithSnakeCaseColumns() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 0) })
        try db.dbQueue.write { d in
            var v = Visit(id: nil, placeID: "mt1_" + String(repeating: "0", count: 26),
                          visitedAt: Date(timeIntervalSince1970: 10), verdict: .loved,
                          createdAt: Date(timeIntervalSince1970: 10))
            try v.insert(d)
        }
        let got = try db.dbQueue.read { try Visit.fetchOne($0) }
        XCTAssertEqual(got?.placeID, "mt1_" + String(repeating: "0", count: 26))
        XCTAssertEqual(got?.verdict, .loved)
        // column is literally place_id (§5.4), not placeID
        let col = try db.dbQueue.read { try Row.fetchOne($0, sql: "SELECT place_id FROM visits") }
        XCTAssertNotNil(col)
    }

    func testPlaceRefCarriesProvenanceAndVerbatimPayload() throws {
        let raw = "{\"place_id\":\"p1\",\"name\":\"Big Ben\",\"lat\":51.5,\"lon\":-0.12,\"category\":\"architecture\",\"tier\":1,\"score\":0.8,\"source_refs\":[\"wd:Q42\"]}"
        let ref = try PlaceRef(placeID: "p1", name: "Big Ben", lat: 51.5, lon: -0.12,
                               category: "architecture", tier: 1, schemaVersion: 3,
                               fetchedAt: Date(timeIntervalSince1970: 7), rawJSON: raw)
        XCTAssertEqual(ref.schemaVersion, 3)                         // data-derived, carried as-is
        XCTAssertEqual(ref.fetchedAt, Date(timeIntervalSince1970: 7))
        XCTAssertEqual(ref.rawJSON, raw)                            // verbatim
    }

    func testListAndListItemRoundTripSnakeCaseColumns() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 0) })
        try db.dbQueue.write { d in
            var list = PlaceList(id: nil, name: "KL trip", isSystem: false,
                                 createdAt: Date(timeIntervalSince1970: 1))
            try list.insert(d)
            var item = ListItem(listID: list.id!, placeID: "p1", addedAt: Date(timeIntervalSince1970: 2))
            try item.insert(d)
        }
        let (l, i) = try db.dbQueue.read { d in
            (try PlaceList.filter(Column("is_system") == false).fetchOne(d),
             try ListItem.fetchOne(d))
        }
        XCTAssertEqual(l?.name, "KL trip")
        XCTAssertEqual(l?.isSystem, false)                          // is_system column mapped
        XCTAssertEqual(i?.placeID, "p1")                            // place_id / list_id columns mapped
        // literal snake_case columns exist as written (§5.4)
        let cols = try db.dbQueue.read { try Row.fetchOne($0, sql: "SELECT list_id, added_at FROM list_items") }
        XCTAssertNotNil(cols)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd ios && swift test --filter ModelsTests`
Expected: FAIL — model types don't exist.

- [ ] **Step 3: Write the model files**

`ios/Sources/MakingTracksData/Models/Visit.swift`:
```swift
import Foundation
import GRDB

public enum Verdict: String, Codable, Sendable {
    case loved   // v1's only non-null verdict (§3.3)
}

public struct Visit: Codable, Sendable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var placeID: String
    public var visitedAt: Date
    public var verdict: Verdict?
    public var createdAt: Date

    public static let databaseTableName = "visits"
    enum CodingKeys: String, CodingKey {
        case id
        case placeID = "place_id"
        case visitedAt = "visited_at"
        case verdict
        case createdAt = "created_at"
    }
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
```

`ios/Sources/MakingTracksData/Models/PlaceList.swift`:
```swift
import Foundation
import GRDB

public struct PlaceList: Codable, Sendable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var name: String
    public var isSystem: Bool
    public var createdAt: Date

    public static let databaseTableName = "lists"
    enum CodingKeys: String, CodingKey {
        case id, name
        case isSystem = "is_system"
        case createdAt = "created_at"
    }
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
```

`ios/Sources/MakingTracksData/Models/ListItem.swift`:
```swift
import Foundation
import GRDB

public struct ListItem: Codable, Sendable, FetchableRecord, PersistableRecord {
    public var listID: Int64
    public var placeID: String
    public var addedAt: Date

    public static let databaseTableName = "list_items"
    enum CodingKeys: String, CodingKey {
        case listID = "list_id"
        case placeID = "place_id"
        case addedAt = "added_at"
    }
}
```

`ios/Sources/MakingTracksData/Models/PlaceSnapshot.swift`:
```swift
import Foundation
import GRDB

public struct PlaceSnapshot: Codable, Sendable, FetchableRecord, PersistableRecord {
    public var placeID: String
    public var name: String
    public var lat: Double
    public var lon: Double
    public var category: String
    public var tier: Int
    public var snapshotJSON: String
    public var snapshotSchemaVersion: Int
    public var fetchedAt: Date

    public static let databaseTableName = "place_snapshots"
    enum CodingKeys: String, CodingKey {
        case placeID = "place_id"
        case name, lat, lon, category, tier
        case snapshotJSON = "snapshot_json"
        case snapshotSchemaVersion = "snapshot_schema_version"
        case fetchedAt = "fetched_at"
    }
}
```

`ios/Sources/MakingTracksData/Models/PlaceRef.swift`:
```swift
import Foundation

/// A tile-derived place, VALIDATED at the storage boundary before it can seed a
/// snapshot. Tile data is untrusted (§5.5) even though we published it (the bucket
/// could be compromised or the pipeline fooled). B3 (the tile client) owns the
/// primary decode-time §5.5 validation — full typed decoding, image_url host
/// allowlist, control-char stripping — and hands B1 this value carrying the
/// VERBATIM place JSON plus its data-derived version and provenance time. This
/// throwing initializer is the enforced storage-boundary guard (defense in depth):
/// a `PlaceRef` cannot exist without passing the caps that protect the stored
/// columns and payload, so B1 can never be handed unvalidated data. It is NOT
/// `Codable` — you cannot decode one straight from a tile blob; you must go through
/// B3's validation and this initializer.
public struct PlaceRef: Sendable, Equatable {
    // Validated typed projection (the queryable snapshot columns).
    public let placeID: String
    public let name: String
    public let lat: Double
    public let lon: Double
    public let category: String
    public let tier: Int
    // Data-derived provenance, supplied by B3 from the tile envelope / manifest —
    // NEVER a compile-time constant (§5.6: a snapshot records the version of the data
    // ACTUALLY written and its valid-as-of time, so a future reader interprets old
    // bytes correctly rather than trusting the reading app's own version).
    public let schemaVersion: Int
    public let fetchedAt: Date
    // The VERBATIM A0 place-object bytes → `snapshot_json`, so Tracks/lists render
    // forever even as the place schema evolves (Principle 8). Storing a re-encode of
    // this typed subset would silently drop any A0 field the struct doesn't model.
    public let rawJSON: String

    public enum ValidationError: Error, Equatable {
        case coordinateOutOfRange, tierOutOfRange, fieldTooLong, payloadTooLarge
    }

    // Storage-boundary caps (align with A0 place caps). The deep §5.5 semantic checks
    // — image_url host allowlist, control-char stripping — are B3's job at decode.
    public static let maxNameLength = 200
    public static let maxCategoryLength = 64
    public static let maxPlaceIDLength = 64
    public static let maxRawJSONBytes = 65536

    public init(placeID: String, name: String, lat: Double, lon: Double,
                category: String, tier: Int, schemaVersion: Int, fetchedAt: Date,
                rawJSON: String) throws {
        guard lat.isFinite, lon.isFinite,
              (-90.0...90.0).contains(lat), (-180.0...180.0).contains(lon)
        else { throw ValidationError.coordinateOutOfRange }
        guard (1...4).contains(tier) else { throw ValidationError.tierOutOfRange }
        guard placeID.count <= Self.maxPlaceIDLength,
              name.count <= Self.maxNameLength,
              category.count <= Self.maxCategoryLength
        else { throw ValidationError.fieldTooLong }
        guard rawJSON.utf8.count <= Self.maxRawJSONBytes else { throw ValidationError.payloadTooLarge }
        self.placeID = placeID; self.name = name; self.lat = lat; self.lon = lon
        self.category = category; self.tier = tier
        self.schemaVersion = schemaVersion; self.fetchedAt = fetchedAt; self.rawJSON = rawJSON
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd ios && swift test --filter ModelsTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/MakingTracksData/Models ios/Tests/MakingTracksDataTests/ModelsTests.swift
git commit -m "Add Sendable GRDB record models + PlaceRef (A0 place fields → snapshot payload)"
```

---

### Task 4 [HOST]: Pin-state matrix + derivations (seen, list progress, viewport resolve)

**Files:**
- Create: `ios/Sources/MakingTracksData/PinState.swift`, `ios/Sources/MakingTracksData/Derivations.swift`
- Test: `ios/Tests/MakingTracksDataTests/PinStateTests.swift`, `ios/Tests/MakingTracksDataTests/DerivationsTests.swift`

**Interfaces:**
- Produces:
  - `enum VisitState: Sendable, Equatable { case none, visited, loved }`; `struct PinState: Sendable, Equatable { var saved: Bool; var visit: VisitState }`.
  - `AppDatabase.isSeen(_ placeID: String) throws -> Bool`.
  - `AppDatabase.seen(among placeIDs: [String]) throws -> Set<String>` (batched).
  - `AppDatabase.listProgress(listID: Int64) throws -> (visited: Int, total: Int)`.
  - `AppDatabase.viewportState(_ placeIDs: [String]) throws -> [String: PinState]` — the hot query: batched keyed lookup, **no spatial query** (§5.4). Places absent from any list and any visit resolve to `PinState(saved: false, visit: .none)`.

- [ ] **Step 1: Write the failing pin-matrix test (all six cells)**

`ios/Tests/MakingTracksDataTests/PinStateTests.swift`:
```swift
import XCTest
@testable import MakingTracksData

final class PinStateTests: XCTestCase {
    // The full matrix: saved ∈ {false,true} × visit ∈ {none,visited,loved} (§3.2).
    func testViewportResolvesEveryCellOfThePinMatrix() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 0) })
        func pid(_ n: Int) -> String { "mt1_" + String(repeating: String(n % 10), count: 26) }
        // arrange: 6 places, one per matrix cell
        try db.dbQueue.write { d in
            // saved axis
            for n in [1, 3, 5] { // saved=true for these
                try d.execute(sql: "INSERT INTO list_items (list_id, place_id, added_at) VALUES (1, ?, ?)",
                              arguments: [pid(n), Date(timeIntervalSince1970: 0)])
            }
            // visit axis: visited (2,3), loved (4,5)
            for n in [2, 3] {
                try d.execute(sql: "INSERT INTO visits (place_id, visited_at, created_at) VALUES (?, ?, ?)",
                              arguments: [pid(n), Date(timeIntervalSince1970: 1), Date(timeIntervalSince1970: 1)])
            }
            for n in [4, 5] {
                try d.execute(sql: "INSERT INTO visits (place_id, visited_at, verdict, created_at) VALUES (?, ?, 'loved', ?)",
                              arguments: [pid(n), Date(timeIntervalSince1970: 1), Date(timeIntervalSince1970: 1)])
            }
        }
        let all = (0...5).map(pid)
        let state = try db.viewportState(all)
        XCTAssertEqual(state[pid(0)], PinState(saved: false, visit: .none))     // neither
        XCTAssertEqual(state[pid(1)], PinState(saved: true,  visit: .none))     // saved only
        XCTAssertEqual(state[pid(2)], PinState(saved: false, visit: .visited))  // visited only
        XCTAssertEqual(state[pid(3)], PinState(saved: true,  visit: .visited))  // saved + visited (core loop end state)
        XCTAssertEqual(state[pid(4)], PinState(saved: false, visit: .loved))    // loved only
        XCTAssertEqual(state[pid(5)], PinState(saved: true,  visit: .loved))    // saved + loved
    }

    func testLovedWinsOverACoexistingPlainVisitInEitherOrder() throws {
        // A place with BOTH a plain visit and a loved visit must resolve to .loved,
        // regardless of insertion order. Pins the MAX(loved) verdict resolution — a
        // last-write-wins or MIN-based bug would fail here (the 6-cell test can't
        // catch it because no place there has mixed rows).
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 0) })
        try db.dbQueue.write { d in
            // pA: plain THEN loved
            try d.execute(sql: "INSERT INTO visits (place_id, visited_at, created_at) VALUES ('pA', 1, 1)")
            try d.execute(sql: "INSERT INTO visits (place_id, visited_at, verdict, created_at) VALUES ('pA', 2, 'loved', 2)")
            // pB: loved THEN plain
            try d.execute(sql: "INSERT INTO visits (place_id, visited_at, verdict, created_at) VALUES ('pB', 1, 'loved', 1)")
            try d.execute(sql: "INSERT INTO visits (place_id, visited_at, created_at) VALUES ('pB', 2, 2)")
        }
        let state = try db.viewportState(["pA", "pB"])
        XCTAssertEqual(state["pA"], PinState(saved: false, visit: .loved))
        XCTAssertEqual(state["pB"], PinState(saved: false, visit: .loved))
    }
}
```

- [ ] **Step 2: Write the failing derivations test**

`ios/Tests/MakingTracksDataTests/DerivationsTests.swift`:
```swift
import XCTest
@testable import MakingTracksData

final class DerivationsTests: XCTestCase {
    private func seededDB() throws -> AppDatabase {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 0) })
        try db.dbQueue.write { d in
            try d.execute(sql: "INSERT INTO visits (place_id, visited_at, created_at) VALUES ('p_seen', 1, 1)")
        }
        return db
    }
    func testIsSeenIsDerivedFromVisitEvents() throws {
        let db = try seededDB()
        XCTAssertTrue(try db.isSeen("p_seen"))
        XCTAssertFalse(try db.isSeen("p_unseen"))
    }
    func testUnmarkingDeletesTheEventAndSeenBecomesFalse() throws {
        let db = try seededDB()
        try db.dbQueue.write { try $0.execute(sql: "DELETE FROM visits WHERE place_id='p_seen'") }
        XCTAssertFalse(try db.isSeen("p_seen"))   // seen is derived, not a stored boolean
    }

    func testRevisitsAreRepresentableAndDeletingOneKeepsSeen() throws {
        // Principle 4: the log holds multiple visits per place (no UNIQUE on place_id);
        // deleting ONE leaves the place seen.
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 0) })
        try db.dbQueue.write { d in
            try d.execute(sql: "INSERT INTO visits (place_id, visited_at, created_at) VALUES ('p', 1, 1)")
            try d.execute(sql: "INSERT INTO visits (place_id, visited_at, created_at) VALUES ('p', 2, 2)")
        }
        let n = try db.dbQueue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM visits WHERE place_id='p'") }
        XCTAssertEqual(n, 2)                                     // two visits coexist
        try db.dbQueue.write { try $0.execute(sql: "DELETE FROM visits WHERE id = (SELECT MIN(id) FROM visits)") }
        XCTAssertTrue(try db.isSeen("p"))                       // still seen after removing one
    }
    func testSeenAmongIsBatched() throws {
        let db = try seededDB()
        XCTAssertEqual(try db.seen(among: ["p_seen", "p_unseen"]), ["p_seen"])
    }
    func testListProgressCountsVisitedOfTotal() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 0) })
        try db.dbQueue.write { d in
            for p in ["a", "b", "c"] {
                try d.execute(sql: "INSERT INTO list_items (list_id, place_id, added_at) VALUES (1, ?, 0)", arguments: [p])
            }
            try d.execute(sql: "INSERT INTO visits (place_id, visited_at, created_at) VALUES ('a', 1, 1)")
        }
        let p = try db.listProgress(listID: 1)
        XCTAssertEqual(p.total, 3)
        XCTAssertEqual(p.visited, 1)   // "you've been to 1 of these · 2 to go"
    }
    func testEmptyViewportReturnsEmpty() throws {
        XCTAssertEqual(try AppDatabase.inMemory().viewportState([]), [:])
    }
}
```

- [ ] **Step 3: Run to verify both fail**

Run: `cd ios && swift test --filter PinStateTests --filter DerivationsTests`
Expected: FAIL — `PinState`/derivations don't exist.

- [ ] **Step 4: Write `PinState.swift`**

`ios/Sources/MakingTracksData/PinState.swift`:
```swift
public enum VisitState: Sendable, Equatable {
    case none, visited, loved
}

/// Two orthogonal axes (§3.2): the visit axis drives fade (visited & loved fade;
/// loved additionally keeps a heart badge); the saved axis contributes an
/// independent bookmark badge that persists through fading. B1 owns the STATE;
/// B2 renders it.
public struct PinState: Sendable, Equatable {
    public var saved: Bool
    public var visit: VisitState
    public init(saved: Bool, visit: VisitState) { self.saved = saved; self.visit = visit }
}
```

- [ ] **Step 5: Write `Derivations.swift`**

`ios/Sources/MakingTracksData/Derivations.swift`:
```swift
import Foundation
import GRDB

extension AppDatabase {
    public func isSeen(_ placeID: String) throws -> Bool {
        try dbQueue.read { db in
            try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM visits WHERE place_id = ?)",
                              arguments: [placeID]) ?? false
        }
    }

    /// The subset of `placeIDs` with ≥1 visit. Batched keyed lookup over idx_visits_place.
    public func seen(among placeIDs: [String]) throws -> Set<String> {
        guard !placeIDs.isEmpty else { return [] }
        return try dbQueue.read { db in
            let sql = "SELECT DISTINCT place_id FROM visits WHERE place_id IN (\(databaseQuestionMarks(count: placeIDs.count)))"
            return try Set(String.fetchAll(db, sql: sql, arguments: StatementArguments(placeIDs)))
        }
    }

    public func listProgress(listID: Int64) throws -> (visited: Int, total: Int) {
        try dbQueue.read { db in
            let total = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM list_items WHERE list_id = ?",
                                         arguments: [listID]) ?? 0
            let visited = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM list_items li
                WHERE li.list_id = ? AND EXISTS(SELECT 1 FROM visits v WHERE v.place_id = li.place_id)
                """, arguments: [listID]) ?? 0
            return (visited, total)
        }
    }

    /// The hot per-render query (§5.4): resolve saved?/visited?/loved? for the visible
    /// place_ids via TWO batched keyed lookups. Not a spatial query; no R-tree.
    public func viewportState(_ placeIDs: [String]) throws -> [String: PinState] {
        guard !placeIDs.isEmpty else { return [:] }
        return try dbQueue.read { db in
            let qmarks = databaseQuestionMarks(count: placeIDs.count)
            let saved = try Set(String.fetchAll(db,
                sql: "SELECT DISTINCT place_id FROM list_items WHERE place_id IN (\(qmarks))",
                arguments: StatementArguments(placeIDs)))
            // strongest verdict per place: 'loved' wins over a plain visit
            let visitRows = try Row.fetchAll(db, sql: """
                SELECT place_id, MAX(CASE WHEN verdict = 'loved' THEN 1 ELSE 0 END) AS loved
                FROM visits WHERE place_id IN (\(qmarks)) GROUP BY place_id
                """, arguments: StatementArguments(placeIDs))
            var visit: [String: VisitState] = [:]
            for r in visitRows {
                let pid: String = r["place_id"]
                visit[pid] = (r["loved"] as Int == 1) ? .loved : .visited
            }
            var out: [String: PinState] = [:]
            for pid in placeIDs {
                out[pid] = PinState(saved: saved.contains(pid), visit: visit[pid] ?? .none)
            }
            return out
        }
    }
}
```

- [ ] **Step 6: Run to verify they pass**

Run: `cd ios && swift test --filter PinStateTests --filter DerivationsTests`
Expected: PASS (8 tests — 2 pin-matrix incl. loved-precedence + 6 derivations).

- [ ] **Step 7: Commit**

```bash
git add ios/Sources/MakingTracksData/PinState.swift ios/Sources/MakingTracksData/Derivations.swift \
        ios/Tests/MakingTracksDataTests/PinStateTests.swift ios/Tests/MakingTracksDataTests/DerivationsTests.swift
git commit -m "Add pin-state matrix + derivations (seen, list progress, batched viewport resolve, no R-tree)"
```

---

### Task 5 [HOST]: First-interaction snapshot writes (mark seen / save)

**Files:**
- Create: `ios/Sources/MakingTracksData/Interactions.swift`
- Test: `ios/Tests/MakingTracksDataTests/InteractionsTests.swift`

**Interfaces:**
- Produces:
  - `AppDatabase.recordVisit(_ place: PlaceRef, verdict: Verdict? = nil) throws -> Int64` — snapshots on first interaction, then appends a visit event; returns the visit id (so it can be undone). Reversible: `deleteVisit(id:)`.
  - `AppDatabase.addToList(_ place: PlaceRef, listID: Int64) throws` — snapshots on first interaction, then `INSERT OR IGNORE` into `list_items` (idempotent; saving never mutates visits).
  - `AppDatabase.deleteVisit(id: Int64) throws`.
  - `AppDatabase.snapshotIfNeeded(_ place: PlaceRef, _ db: Database) throws` (internal helper): `INSERT`s a `place_snapshots` row only when absent (first interaction), storing the **verbatim** `place.rawJSON`, and stamping `snapshot_schema_version = place.schemaVersion` and `fetched_at = place.fetchedAt` (both data-derived).

- [ ] **Step 1: Write the failing test**

`ios/Tests/MakingTracksDataTests/InteractionsTests.swift`:
```swift
import XCTest
import GRDB
@testable import MakingTracksData

final class InteractionsTests: XCTestCase {
    // Builds a validated PlaceRef with a VERBATIM rawJSON payload + data-derived
    // provenance, exactly as B3 would hand B1.
    private func ref(_ id: String, name: String = "Big Ben", schemaVersion: Int = 1,
                     fetchedAt: Date = Date(timeIntervalSince1970: 50)) throws -> PlaceRef {
        let raw = "{\"place_id\":\"\(id)\",\"name\":\"\(name)\",\"lat\":51.5,\"lon\":-0.12," +
                  "\"category\":\"architecture\",\"tier\":1,\"score\":0.82,\"source_refs\":[\"wd:Q42\"]}"
        return try PlaceRef(placeID: id, name: name, lat: 51.5, lon: -0.12, category: "architecture",
                            tier: 1, schemaVersion: schemaVersion, fetchedAt: fetchedAt, rawJSON: raw)
    }

    func testMarkingSeenSnapshotsOnFirstInteractionWithProvenance() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        _ = try db.recordVisit(ref("p1", fetchedAt: Date(timeIntervalSince1970: 77)))
        let snap = try db.dbQueue.read { try PlaceSnapshot.fetchOne($0) }
        XCTAssertEqual(snap?.placeID, "p1")
        XCTAssertEqual(snap?.snapshotSchemaVersion, 1)                         // stamped from data
        XCTAssertEqual(snap?.fetchedAt, Date(timeIntervalSince1970: 77))       // provenance, not now()
        XCTAssertTrue(try db.isSeen("p1"))
    }

    func testSnapshotSchemaVersionIsDataDerivedNotAConstant() throws {
        // A place delivered at schema_version 2 must stamp 2 — proving the value comes
        // from the data, not a hardcoded app constant that could lie (§5.6).
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        _ = try db.recordVisit(ref("p2", schemaVersion: 2))
        let snap = try db.dbQueue.read { try PlaceSnapshot.fetchOne($0) }
        XCTAssertEqual(snap?.snapshotSchemaVersion, 2)
    }

    func testSnapshotJSONIsTheVerbatimPayload() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        let r = try ref("p1")
        _ = try db.recordVisit(r)
        let snap = try db.dbQueue.read { try PlaceSnapshot.fetchOne($0) }
        XCTAssertEqual(snap?.snapshotJSON, r.rawJSON)                          // byte-for-byte, not a re-encode
    }

    func testSnapshotIsWrittenOnceAndNotOverwrittenBySecondInteraction() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        _ = try db.recordVisit(ref("p1", name: "First Name"))
        try db.addToList(ref("p1", name: "Later Name"), listID: 1)   // second interaction
        let snaps = try db.dbQueue.read { try PlaceSnapshot.fetchAll($0) }
        XCTAssertEqual(snaps.count, 1)
        XCTAssertEqual(snaps[0].name, "First Name")   // first snapshot wins; not overwritten
    }

    func testVerdictLovedIsRecordedAndReversible() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        let vid = try db.recordVisit(ref("p1"), verdict: .loved)
        XCTAssertEqual(try db.viewportState(["p1"])["p1"], PinState(saved: false, visit: .loved))
        try db.deleteVisit(id: vid)                                  // un-mark (nothing destroyed)
        XCTAssertFalse(try db.isSeen("p1"))
    }

    func testSaveIsIdempotentAndDoesNotMarkSeen() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        try db.addToList(ref("p1"), listID: 1)
        try db.addToList(ref("p1"), listID: 1)                       // INSERT OR IGNORE
        let count = try db.dbQueue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM list_items") }
        XCTAssertEqual(count, 1)
        XCTAssertFalse(try db.isSeen("p1"))                          // saving ≠ seen (§3.2)
    }

    func testValidatingInitRejectsOutOfRangeAndOversize() throws {
        // The storage-boundary guard cannot be bypassed (defense in depth, §5.5).
        XCTAssertThrowsError(try PlaceRef(placeID: "p", name: "n", lat: 91, lon: 0, category: "c",
                                          tier: 1, schemaVersion: 1, fetchedAt: Date(), rawJSON: "{}"))
        XCTAssertThrowsError(try PlaceRef(placeID: "p", name: "n", lat: 0, lon: 0, category: "c",
                                          tier: 9, schemaVersion: 1, fetchedAt: Date(), rawJSON: "{}"))
        XCTAssertThrowsError(try PlaceRef(placeID: "p", name: "n", lat: 0, lon: 0, category: "c",
                                          tier: 1, schemaVersion: 1, fetchedAt: Date(),
                                          rawJSON: String(repeating: "x", count: PlaceRef.maxRawJSONBytes + 1)))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd ios && swift test --filter InteractionsTests`
Expected: FAIL — interaction methods don't exist.

- [ ] **Step 3: Write `Interactions.swift`**

`ios/Sources/MakingTracksData/Interactions.swift`:
```swift
import Foundation
import GRDB

extension AppDatabase {
    /// Snapshot the place iff it has no snapshot yet (first interaction, Principle 8).
    /// INSERT-only; a later interaction never overwrites the first snapshot.
    func snapshotIfNeeded(_ place: PlaceRef, _ db: Database) throws {
        let exists = try Bool.fetchOne(db,
            sql: "SELECT EXISTS(SELECT 1 FROM place_snapshots WHERE place_id = ?)",
            arguments: [place.placeID]) ?? false
        guard !exists else { return }
        let snap = PlaceSnapshot(placeID: place.placeID, name: place.name, lat: place.lat,
                                 lon: place.lon, category: place.category, tier: place.tier,
                                 snapshotJSON: place.rawJSON,                // VERBATIM A0 payload (renders forever)
                                 snapshotSchemaVersion: place.schemaVersion, // data-derived (§5.6), not a constant
                                 fetchedAt: place.fetchedAt)                 // data provenance, not write time
        try snap.insert(db)
    }

    @discardableResult
    public func recordVisit(_ place: PlaceRef, verdict: Verdict? = nil) throws -> Int64 {
        try dbQueue.write { db in
            try snapshotIfNeeded(place, db)
            var v = Visit(id: nil, placeID: place.placeID, visitedAt: now(),
                          verdict: verdict, createdAt: now())
            try v.insert(db)
            return v.id!
        }
    }

    public func deleteVisit(id: Int64) throws {
        try dbQueue.write { db in
            _ = try Visit.deleteOne(db, key: id)
        }
    }

    public func addToList(_ place: PlaceRef, listID: Int64) throws {
        try dbQueue.write { db in
            try snapshotIfNeeded(place, db)
            // INSERT OR IGNORE: composite PK makes re-adding a no-op (idempotent).
            try db.execute(sql: """
                INSERT OR IGNORE INTO list_items (list_id, place_id, added_at) VALUES (?, ?, ?)
                """, arguments: [listID, place.placeID, now()])
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd ios && swift test --filter InteractionsTests`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/MakingTracksData/Interactions.swift ios/Tests/MakingTracksDataTests/InteractionsTests.swift
git commit -m "Add first-interaction snapshot writes (mark seen/save), reversible, schema-versioned"
```

---

### Task 6 [HOST]: Concurrency safety + full host-suite green

**Files:**
- Create: `ios/Tests/MakingTracksDataTests/ConcurrencyTests.swift`

**Interfaces:**
- Consumes: everything above. Proves the `Sendable` store is safe under concurrent access (Swift 6 strict concurrency).

- [ ] **Step 1: Write the concurrency test**

`ios/Tests/MakingTracksDataTests/ConcurrencyTests.swift`:
```swift
import XCTest
@testable import MakingTracksData

final class ConcurrencyTests: XCTestCase {
    // The store is Sendable and captured by concurrent tasks; GRDB serializes writes.
    func testConcurrentWritesAreSerializedAndConsistent() async throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 0) })
        func ref(_ i: Int) throws -> PlaceRef {
            try PlaceRef(placeID: "p\(i)", name: "n", lat: 0, lon: 0, category: "c", tier: 1,
                         schemaVersion: 1, fetchedAt: Date(timeIntervalSince1970: 0), rawJSON: "{}")
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask { _ = try db.recordVisit(try ref(i)) }   // db is Sendable → captured safely
            }
            for try await _ in group {}   // drain: any per-task throw propagates (not swallowed)
        }
        // async context → the async read overload, which must be awaited
        let count = try await db.dbQueue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM visits") } ?? 0
        XCTAssertEqual(count, 50)   // no lost writes, no corruption
    }
}
```

- [ ] **Step 2: Run the whole host suite**

Run: `cd ios && swift test`
Expected: PASS (25 tests — all `MakingTracksDataTests` green: migrations, models, pin matrix, derivations, interactions, concurrency). **This entire suite runs with no simulator.**

- [ ] **Step 3: Commit**

```bash
git add ios/Tests/MakingTracksDataTests/ConcurrencyTests.swift
git commit -m "Add concurrency test proving the Sendable store is safe under concurrent access"
```

---

### Task 7 [XCODE/SIM]: XcodeGen app shell + backup-posture live DB (simulator-dependent)

> **Do not start until a simulator is free.** Everything above (Tasks 1–6) is done and green host-side without this.

**Files:**
- Create: `ios/App/project.yml`, `ios/App/Sources/MakingTracksApp.swift`, `ios/App/Sources/AppDatabase+Live.swift`
- Generated by XcodeGen (do not hand-author): `ios/App/Resources/Info.plist` (from the `info:` block in `project.yml`)

**Interfaces:**
- Consumes: `MakingTracksData` (the finished package).
- Produces: a launchable iOS 18 app shell whose live DB lives in Application Support with default backup inclusion.

- [ ] **Step 1: Write `App/project.yml` (XcodeGen)**

`ios/App/project.yml`:
```yaml
name: MakingTracks
options:
  deploymentTarget:
    iOS: "18.0"
  createIntermediateGroups: true
packages:
  MakingTracksData:
    path: ..
settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete
targets:
  MakingTracks:
    type: application
    platform: iOS
    sources: [Sources]
    info:
      path: Resources/Info.plist
      properties:
        UILaunchScreen: {}
    dependencies:
      - package: MakingTracksData
```

- [ ] **Step 2: Write the app shell**

`ios/App/Sources/MakingTracksApp.swift`:
```swift
import SwiftUI
import MakingTracksData

@main
struct MakingTracksApp: App {
    var body: some Scene {
        WindowGroup {
            // Placeholder root — map/pins/place card arrive in B2/B4.
            Text("Making Tracks")
        }
    }
}
```

`ios/App/Sources/AppDatabase+Live.swift`:
```swift
import Foundation
import GRDB
import MakingTracksData

extension AppDatabase {
    /// The on-device store path: Application Support/MakingTracks/user.sqlite.
    /// Rides the iCloud DEVICE backup by default (§5.3) — we deliberately DO NOT set
    /// isExcludedFromBackup, and apply NO file-protection level that would block a
    /// later background read (B8 foreground-only in v1, but don't paint the corner).
    public static func live() throws -> AppDatabase {
        let base = try FileManager.default.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("MakingTracks", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // NOTE: no resourceValues(isExcludedFromBackup) set → included in device backup.
        var config = Configuration()   // no .fileProtection override → default, background-read safe
        let queue = try DatabaseQueue(path: dir.appendingPathComponent("user.sqlite").path, configuration: config)
        return try AppDatabase(queue, now: { Date() })
    }
}
```

`ios/App/Resources/Info.plist`: minimal (iOS 18 target, launch screen). Generated/filled by XcodeGen defaults where possible.

- [ ] **Step 3: Generate the project and build (needs Xcode + simulator)**

Run: `cd ios/App && xcodegen generate`
Then: `xcodebuild -project MakingTracks.xcodeproj -scheme MakingTracks -destination 'generic/platform=iOS Simulator' build`
Expected: the shell compiles and links against `MakingTracksData` under Swift 6 strict concurrency. (A launch smoke in the simulator is optional; the data layer is already fully tested host-side.)

- [ ] **Step 4: Commit**

```bash
git add ios/App
git commit -m "Add XcodeGen app shell (iOS 18) + live DB in Application Support (backup-included)"
```

---

## Review Record

**Author self-review** — every WP-B1 deliverable maps to a task: Xcode project scaffold (T7, XcodeGen); GRDB schema + numbered migrations + indexes exactly per §5.4 incl. `list_items` composite PK and both `place_id` indexes (T2); derivations — seen, list progress, batched viewport-state resolve, full pin-state matrix (T4); `place_snapshots` writes on first interaction (T5). Consumes A0 place fields by CONTRACTS.md name (T3, `PlaceRef`). GRDB-over-SwiftData rationale, Swift 6 strict concurrency, iOS 18, no R-tree — all pinned. **Tasks 1–6 are host-side `swift test` (no simulator); Task 7 is the single marked Xcode/simulator task** — the build-phase split fable required.

**Ratifications + riders (fable, thread `wp/b1`)** — SwiftPM data package + host tests; XcodeGen; full place JSON in `snapshot_json` + typed projection; minimal shell; GRDB 7.x behind a Sendable boundary. Riders folded in: (1) `snapshot_schema_version` column (Principle 11, T2/T3/T5); (2) refuse-newer-DB guard with a host test + typed `AppDatabaseError.databaseFromNewerAppVersion` (T2); (3) backup posture — Application Support, nothing excluded from backup, no blocking file-protection (T7, asserted in code + comments).

**Adversarial review (5 subagent critics + cross-examination, per AGENTS.md gate)** — the feasibility critic **actually built the Tasks 1–6 package against real GRDB 7.11.1 under Swift 6.3.3 and ran `swift test` (18 tests pass** after one `await` fix), confirming every GRDB API, the `Sendable`/Swift 6 boundary, and the refuse-newer guard are real and correct. Material fixes folded in after cross-examination:
- *Security + spec-fidelity (HIGH, convergent):* `snapshot_json` was a **lossy re-encode** of the typed `PlaceRef` (drops any A0 field the struct doesn't model — fatal to "renders forever" as A0 evolves) and `snapshot_schema_version` was a **hardcoded constant that can lie**. Redesigned: `PlaceRef` now carries the **verbatim** `rawJSON`, a **data-derived** `schemaVersion`, and a data-provenance `fetchedAt`, all supplied by B3; the snapshot stores those directly. `PlaceRef` is now constructible only via a **throwing validating initializer** (coord/finiteness, tier 1–4, field-length, `snapshot_json` byte caps) and is **not `Codable`** — B1 can't be handed unvalidated tile data; the plan states B3 owns the primary §5.5 decode-validation.
- *Security (MEDIUM):* the refuse-newer allow-list was a drift-prone duplicate constant that could **lock users out of their own DB** after a future migration — now the migrator registration and the allow-list derive from one place (`makeMigrator`); a foreign/corrupt `grdb_migrations` table now yields a typed `unreadableDatabase` error, not a raw SQLite error.
- *Coherence (HIGH):* `AppDatabase.init` is now `public` (Task 7's app-target `live()` uses a plain `import` and would not have compiled); the "replace `migrate()`" instruction now says to **delete** the stub (avoids a duplicate-method error).
- *Test-quality (HIGH/MED):* added the loved-vs-visited **precedence** test (a place with both a plain and a loved visit, both orders — the 6-cell matrix couldn't catch a MIN/last-wins bug); a **no-R-tree** schema assertion; **exact** column-set + index-column assertions for all four tables; `ListItem`/`PlaceList` round-trip coverage; a **revisits-representable** test; a file-backed **reopen** test (no double-seed); a **data-derived-version** test (a v2 place stamps 2); and the concurrency test now drains the task group so throws surface.
- *Feasibility:* the missing `await` on GRDB's async `read` overload (concurrency test) and a `var`→`let` warning are fixed.

**Cross-package note** — B1 consumes only A0's place *field shapes* (read-only), by CONTRACTS.md name. The snapshot version is now stamped from data (`place.schemaVersion` supplied by B3 from the tile envelope), not an app constant — so a snapshot never lies about its own shape. Also surfaced to fable: the `list_items` FK+cascade is a deliberate integrity refinement beyond the literal §5.4 DDL.
