A2_PLACES_DDL = """
CREATE TABLE IF NOT EXISTS places (
    place_id         TEXT PRIMARY KEY,
    region           TEXT NOT NULL,
    name             TEXT NOT NULL,
    lat              REAL NOT NULL,
    lon              REAL NOT NULL,
    refs_json        TEXT NOT NULL,
    member_refs_json TEXT NOT NULL,
    status           TEXT NOT NULL
)
"""
