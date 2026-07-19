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
        "hehle": "Historic England",
        "plaque": "Open Plaques",
        "historic_england": "Historic England",
        "open_plaques": "Open Plaques",
        "osm": "OpenStreetMap",
        "wd": "Wikidata",
        "wp": "Wikipedia",
    ]
}

enum SourceArticleLinks {
    static func link(wikipediaTitle: String?, sourceRefs: [String]?) -> SourceArticleLink? {
        if let sourceRefs {
            for ref in sourceRefs where PlaceContentGuards.isValidSourceRef(ref) && ref.hasPrefix("wp:") {
                guard let link = link(sourceRef: ref) else { continue }
                return link
            }
        }

        if let wikipediaTitle,
           let title = safeWikipediaTitle(wikipediaTitle),
           let url = wikipediaURL(title: title)
        {
            return SourceArticleLink(label: "Source article", sourceName: "Wikipedia", url: url)
        }

        guard let sourceRefs else { return nil }
        for ref in sourceRefs where PlaceContentGuards.isValidSourceRef(ref) {
            guard let link = link(sourceRef: ref) else { continue }
            return link
        }
        return nil
    }

    private static func link(sourceRef ref: String) -> SourceArticleLink? {
        let parts = ref.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let prefix = parts[0]
        let value = parts[1]
        switch prefix {
        case "wp":
            guard matches(value, pattern: "^[1-9][0-9]*$"),
                  let url = wikipediaPageIDURL(value)
            else { return nil }
            return SourceArticleLink(label: "Source article", sourceName: "Wikipedia", url: url)
        case "wd":
            guard matches(value, pattern: "^Q[1-9][0-9]*$"),
                  let url = validatedURL(host: "www.wikidata.org", path: "/wiki/\(value)")
            else { return nil }
            return SourceArticleLink(label: "Source article", sourceName: "Wikidata", url: url)
        case "osm":
            return osmLink(value)
        case "open_plaques":
            return openPlaquesLink(value)
        case "plaque":
            guard let id = openPlaquesID(value) else { return nil }
            return openPlaquesLink(id)
        case "historic_england", "hehle":
            guard matches(value, pattern: "^[0-9]+$"),
                  let url = validatedURL(host: "historicengland.org.uk", path: "/listing/the-list/list-entry/\(value)")
            else { return nil }
            return SourceArticleLink(label: "Source article", sourceName: "Historic England", url: url)
        default:
            return nil
        }
    }

    private static func osmLink(_ value: String) -> SourceArticleLink? {
        let parts = value.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              ["node", "way", "relation"].contains(parts[0]),
              matches(parts[1], pattern: "^[0-9]+$"),
              let url = validatedURL(host: "www.openstreetmap.org", path: "/\(parts[0])/\(parts[1])")
        else { return nil }
        return SourceArticleLink(label: "Source article", sourceName: "OpenStreetMap", url: url)
    }

    private static func openPlaquesID(_ value: String) -> String? {
        let prefix = "openplaques/"
        guard value.hasPrefix(prefix) else { return nil }
        let id = String(value.dropFirst(prefix.count))
        return matches(id, pattern: "^[0-9]+$") ? id : nil
    }

    private static func openPlaquesLink(_ value: String) -> SourceArticleLink? {
        guard matches(value, pattern: "^[0-9]+$"),
              let url = validatedURL(host: "openplaques.org", path: "/plaques/\(value)")
        else { return nil }
        return SourceArticleLink(label: "Source article", sourceName: "Open Plaques", url: url)
    }

    private static func wikipediaURL(title: String) -> URL? {
        let normalized = title.replacingOccurrences(of: " ", with: "_")
        guard let encoded = encodedPathSegment(normalized) else { return nil }
        return validatedURL(host: "en.wikipedia.org", percentEncodedPath: "/wiki/\(encoded)")
    }

    private static func wikipediaPageIDURL(_ pageID: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "en.wikipedia.org"
        components.path = "/"
        components.queryItems = [URLQueryItem(name: "curid", value: pageID)]
        guard let url = components.url else { return nil }
        return isAllowedSourceURL(url) ? url : nil
    }

    private static func safeWikipediaTitle(_ title: String) -> String? {
        guard (1...300).contains(title.unicodeScalars.count),
              PlaceContentGuards.isSafeText(title),
              !title.contains("#"),
              !title.contains("?")
        else { return nil }
        return title
    }

    private static func encodedPathSegment(_ segment: String) -> String? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return segment.addingPercentEncoding(withAllowedCharacters: allowed)
    }

    private static func validatedURL(host: String, path: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        guard let url = components.url else { return nil }
        return isAllowedSourceURL(url) ? url : nil
    }

    private static func validatedURL(host: String, percentEncodedPath: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.percentEncodedPath = percentEncodedPath
        guard let url = components.url else { return nil }
        return isAllowedSourceURL(url) ? url : nil
    }

    private static func isAllowedSourceURL(_ url: URL) -> Bool {
        url.scheme == "https"
            && url.port == nil
            && allowedHosts.contains(url.host ?? "")
    }

    private static func matches(_ value: String, pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) == value.startIndex..<value.endIndex
    }

    private static let allowedHosts: Set<String> = [
        "en.wikipedia.org",
        "www.wikidata.org",
        "www.openstreetmap.org",
        "openplaques.org",
        "historicengland.org.uk",
    ]
}
