import Foundation
import MakingTracksTiles

enum SourceNames {
    static func names(from refs: [String]?) -> [String] {
        guard let refs else { return [] }
        let names = refs.compactMap { ref -> String? in
            guard PlaceContentGuards.isValidSourceRef(ref),
                  let prefix = ref.split(separator: ":", maxSplits: 1).first.map(String.init)
            else { return nil }
            return nameByPrefix[prefix]
        }
        return Array(Set(names)).sorted()
    }

    private static let nameByPrefix: [String: String] = [
        "historic_england": "Historic England",
        "open_plaques": "Open Plaques",
        "osm": "OpenStreetMap",
        "wd": "Wikidata",
        "wp": "Wikipedia",
    ]
}
