import Foundation

enum WorldBasemap {
    static let resourceName = "protomaps-20260714-z0-6"
    static let expectedSHA256 = "31dc1dd37b93ba6a05f64a21b967989ac40f6740bc845a06e9ab0fb83773c19c"
    static let expectedBytes = 44_720_722

    static func pmtilesURL(in bundle: Bundle = .main) -> String? {
        guard let url = resourceURL(in: bundle) else { return nil }
        return "pmtiles://\(url.absoluteString)"
    }

    static func resourceURL(in bundle: Bundle = .main) -> URL? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "pmtiles") else {
            return nil
        }
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              values.fileSize == expectedBytes
        else {
            return nil
        }
        return url
    }
}
