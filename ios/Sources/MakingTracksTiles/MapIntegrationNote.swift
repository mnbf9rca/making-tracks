/// [XCODE/SIM] B2 integration seam.
///
/// B2 owns MapLibre wiring. On camera idle, B2 should derive a `BBox` from the
/// visible coordinate bounds and call `places(inViewport:zoom:)`. The returned
/// `MapPlace` values are already decoded and validated by `MakingTracksTiles`;
/// B2 must not re-decode tile JSON. B2 also reads `basemapURL` for its
/// `pmtiles://` source and `basemapIntegrity` before trusting a streamed
/// basemap. This package makes no host-verification claim for MapLibre's own
/// network path; B3's host, redirect, checksum, cache, and decode gates are
/// covered by host `swift test`.
public enum MapIntegrationNote {}
