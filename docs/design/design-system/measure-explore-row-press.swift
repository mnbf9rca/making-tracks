#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO

private struct RGB: Equatable {
    let red: Int
    let green: Int
    let blue: Int

    func distance(to other: RGB) -> Int {
        abs(red - other.red) + abs(green - other.green) + abs(blue - other.blue)
    }
}

private struct Raster {
    let width: Int
    let height: Int
    let rgba: [UInt8]

    init(url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw EvidenceError("cannot decode PNG: \(url.path)")
        }
        guard (300...2_000).contains(image.width),
              (600...4_000).contains(image.height)
        else {
            throw EvidenceError("out-of-bounds PNG dimensions: \(image.width)x\(image.height)")
        }

        width = image.width
        height = image.height
        var storage = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &storage,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo:
                CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            throw EvidenceError("cannot allocate RGBA context")
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        rgba = storage
    }

    init(width: Int, height: Int, fill: RGB) {
        self.width = width
        self.height = height
        var storage: [UInt8] = []
        storage.reserveCapacity(width * height * 4)
        for _ in 0..<(width * height) {
            storage += [UInt8(fill.red), UInt8(fill.green), UInt8(fill.blue), 255]
        }
        rgba = storage
    }

    func count(color: RGB, tolerance: Int = 24) -> Int {
        stride(from: 0, to: rgba.count, by: 4).reduce(into: 0) { total, offset in
            let sample = RGB(
                red: Int(rgba[offset]),
                green: Int(rgba[offset + 1]),
                blue: Int(rgba[offset + 2])
            )
            if sample.distance(to: color) <= tolerance {
                total += 1
            }
        }
    }

    func crop(frame: CGRect, appFrame: CGRect) throws -> RasterCrop {
        guard appFrame.width > 0, appFrame.height > 0,
              frame.width > 0, frame.height > 0,
              appFrame.contains(frame)
        else {
            throw EvidenceError("invalid measured crop frame \(frame) in app frame \(appFrame)")
        }
        let scaleX = CGFloat(width) / appFrame.width
        let scaleY = CGFloat(height) / appFrame.height
        guard abs(scaleX - scaleY) < 0.05, (1...4).contains(scaleX) else {
            throw EvidenceError("invalid screenshot scale x=\(scaleX) y=\(scaleY)")
        }

        let insetFrame = frame.insetBy(dx: -4, dy: -4).intersection(appFrame)
        let minX = max(0, Int(((insetFrame.minX - appFrame.minX) * scaleX).rounded(.down)))
        let maxX = min(width - 1, Int(((insetFrame.maxX - appFrame.minX) * scaleX).rounded(.up)))
        // Match MakingTracksCoreLoopUITests.RenderedPixelRaster: decoded
        // screenshot rows and XCTest frames both use the screen's top origin.
        let minY = max(
            0,
            Int(((insetFrame.minY - appFrame.minY) * scaleY).rounded(.down))
        )
        let maxY = min(
            height - 1,
            Int(((insetFrame.maxY - appFrame.minY) * scaleY).rounded(.up))
        )
        guard minX <= maxX, minY <= maxY else {
            throw EvidenceError("empty measured crop")
        }

        var bytes: [UInt8] = []
        bytes.reserveCapacity((maxX - minX + 1) * (maxY - minY + 1) * 4)
        for y in minY...maxY {
            let start = (y * width + minX) * 4
            let end = (y * width + maxX + 1) * 4
            bytes.append(contentsOf: rgba[start..<end])
        }
        return RasterCrop(width: maxX - minX + 1, height: maxY - minY + 1, rgba: bytes)
    }
}

private struct RasterCrop: Equatable {
    let width: Int
    let height: Int
    let rgba: [UInt8]

    func count(color: RGB, tolerance: Int = 24) -> Int {
        stride(from: 0, to: rgba.count, by: 4).reduce(into: 0) { total, offset in
            let sample = RGB(
                red: Int(rgba[offset]),
                green: Int(rgba[offset + 1]),
                blue: Int(rgba[offset + 2])
            )
            if sample.distance(to: color) <= tolerance {
                total += 1
            }
        }
    }

    func ink(background: RGB = RGB(red: 255, green: 252, blue: 245)) -> InkMeasurement {
        var count = 0
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let sample = RGB(
                    red: Int(rgba[offset]),
                    green: Int(rgba[offset + 1]),
                    blue: Int(rgba[offset + 2])
                )
                guard sample.distance(to: background) > 60 else { continue }
                count += 1
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        return InkMeasurement(
            count: count,
            bounds: count == 0
                ? nil
                : CGRect(
                    x: minX,
                    y: minY,
                    width: maxX - minX + 1,
                    height: maxY - minY + 1
                )
        )
    }
}

private struct InkMeasurement {
    let count: Int
    let bounds: CGRect?
}

private struct EvidenceError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private struct CaseSpec {
    let kind: String
    let size: String

    var name: String { "\(kind)-\(size)" }
    var kindColor: RGB {
        kind == "settings"
            ? RGB(red: 26, green: 204, blue: 51)
            : RGB(red: 242, green: 204, blue: 13)
    }
    var sizeColor: RGB {
        size == "default"
            ? RGB(red: 26, green: 51, blue: 242)
            : RGB(red: 242, green: 89, blue: 13)
    }
}

private let restColor = RGB(red: 13, green: 217, blue: 242)
private let pressedColor = RGB(red: 242, green: 13, blue: 204)
private let markerMinimum = 300

private func parseFrame(label: String, from text: String) throws -> CGRect {
    let escaped = NSRegularExpression.escapedPattern(for: label)
    let pattern = "(?m)^\(escaped): x=([0-9.]+) y=([0-9.]+) width=([0-9.]+) height=([0-9.]+)$"
    let regex = try NSRegularExpression(pattern: pattern)
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges == 5 else {
        throw EvidenceError("missing or malformed \(label) measurement")
    }
    let values = (1...4).map { index -> Double? in
        guard let valueRange = Range(match.range(at: index), in: text) else { return nil }
        return Double(text[valueRange])
    }
    guard values.allSatisfy({ $0 != nil }),
          let x = values[0], let y = values[1],
          let width = values[2], let height = values[3],
          [x, y, width, height].allSatisfy({ $0.isFinite })
    else {
        throw EvidenceError("non-finite \(label) measurement")
    }
    return CGRect(x: x, y: y, width: width, height: height)
}

private func format(_ rect: CGRect?) -> String {
    guard let rect else { return "none" }
    return String(
        format: "x=%.0f y=%.0f width=%.0f height=%.0f",
        rect.minX,
        rect.minY,
        rect.width,
        rect.height
    )
}

private func analyzeCase(_ spec: CaseSpec, input: URL, output: URL) throws {
    let caseDirectory = input.appendingPathComponent(spec.name, isDirectory: true)
    let measurementURL = caseDirectory.appendingPathComponent("measurement.txt")
    let measurementText = try String(contentsOf: measurementURL, encoding: .utf8)
    let appFrame = try parseFrame(label: "app-frame", from: measurementText)
    let rowFrame = try parseFrame(label: "row-derived", from: measurementText)
    let iconFrame = try parseFrame(label: "icon", from: measurementText)
    let kindMarkerFrame = try parseFrame(label: "kind-marker", from: measurementText)
    let sizeMarkerFrame = try parseFrame(label: "size-marker", from: measurementText)
    let stateMarkerFrame = try parseFrame(label: "state-marker", from: measurementText)
    guard rowFrame.contains(iconFrame), iconFrame.width >= 8, iconFrame.height >= 8 else {
        throw EvidenceError("\(spec.name): icon frame is not contained in row frame")
    }

    let candidates = try FileManager.default.contentsOfDirectory(
        at: caseDirectory,
        includingPropertiesForKeys: nil
    ).filter { $0.pathExtension.lowercased() == "png" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    guard (2...100).contains(candidates.count) else {
        throw EvidenceError("\(spec.name): expected 2...100 PNG candidates, found \(candidates.count)")
    }

    var rest: (URL, Raster, Int)?
    var pressed: (URL, Raster, Int)?
    var expectedDimensions: (Int, Int)?
    for candidate in candidates {
        let raster = try Raster(url: candidate)
        if let expectedDimensions,
           (raster.width, raster.height) != expectedDimensions {
            throw EvidenceError("\(spec.name): mixed candidate dimensions")
        }
        expectedDimensions = (raster.width, raster.height)

        let kindCount = try raster.crop(
            frame: kindMarkerFrame,
            appFrame: appFrame
        ).count(color: spec.kindColor)
        let sizeCount = try raster.crop(
            frame: sizeMarkerFrame,
            appFrame: appFrame
        ).count(color: spec.sizeColor)
        guard kindCount >= markerMinimum, sizeCount >= markerMinimum
        else { continue }
        let stateCrop = try raster.crop(frame: stateMarkerFrame, appFrame: appFrame)
        let restCount = stateCrop.count(color: restColor)
        let pressedCount = stateCrop.count(color: pressedColor)
        if restCount >= markerMinimum, pressedCount < markerMinimum {
            if rest == nil || restCount > rest!.2 { rest = (candidate, raster, restCount) }
        } else if pressedCount >= markerMinimum, restCount < markerMinimum {
            if pressed == nil || pressedCount > pressed!.2 {
                pressed = (candidate, raster, pressedCount)
            }
        }
    }

    guard let rest, let pressed else {
        throw EvidenceError("\(spec.name): missing exact rest or live-pressed marker candidate")
    }
    let restCrop = try rest.1.crop(frame: iconFrame, appFrame: appFrame)
    let pressedCrop = try pressed.1.crop(frame: iconFrame, appFrame: appFrame)
    guard restCrop != pressedCrop else {
        throw EvidenceError("\(spec.name): rest and pressed glyph crops are identical")
    }
    let restInk = restCrop.ink()
    let pressedInk = pressedCrop.ink()
    guard restInk.count > 0, pressedInk.count > restInk.count else {
        throw EvidenceError(
            "\(spec.name): expected pressed glyph ink > rest (\(pressedInk.count) <= \(restInk.count))"
        )
    }

    for state in ["rest", "pressed"] {
        let source = state == "rest" ? rest.0 : pressed.0
        let target = output.appendingPathComponent(
            "explore-row-press-\(spec.name)-\(state).png"
        )
        try FileManager.default.copyItem(at: source, to: target)
    }
    let report = """
    case: \(spec.name)
    evidence-class: live ButtonStyle.Configuration.isPressed marker
    app-frame: \(format(appFrame))
    row-frame: \(format(rowFrame))
    icon-frame: \(format(iconFrame))
    rest-candidate: \(rest.0.lastPathComponent)
    rest-marker-pixels: \(rest.2)
    rest-ink-pixels: \(restInk.count)
    rest-ink-bounds: \(format(restInk.bounds))
    pressed-candidate: \(pressed.0.lastPathComponent)
    pressed-marker-pixels: \(pressed.2)
    pressed-ink-pixels: \(pressedInk.count)
    pressed-ink-bounds: \(format(pressedInk.bounds))
    pressed-minus-rest-ink: \(pressedInk.count - restInk.count)
    identical-glyph-crop: false
    """ + "\n"
    try report.write(
        to: output.appendingPathComponent("explore-row-press-\(spec.name).txt"),
        atomically: true,
        encoding: .utf8
    )
}

private func runSelfTests() throws {
    let settings = CaseSpec(kind: "settings", size: "default")
    guard settings.kindColor == RGB(red: 26, green: 204, blue: 51),
          settings.sizeColor == RGB(red: 26, green: 51, blue: 242)
    else { throw EvidenceError("self-test marker palette mismatch") }

    let synthetic = Raster(width: 20, height: 20, fill: restColor)
    guard synthetic.count(color: restColor) == 400,
          synthetic.count(color: pressedColor) == 0
    else { throw EvidenceError("self-test exact marker classification failed") }

    let frameText = "app-frame: x=0.00 y=0.00 width=402.00 height=874.00\n"
    guard try parseFrame(label: "app-frame", from: frameText)
        == CGRect(x: 0, y: 0, width: 402, height: 874)
    else { throw EvidenceError("self-test bounded frame parse failed") }

    let background = RGB(red: 255, green: 252, blue: 245)
    var pixels = Raster(width: 2, height: 2, fill: background).rgba
    pixels[0] = 10
    pixels[1] = 20
    pixels[2] = 30
    let crop = RasterCrop(width: 2, height: 2, rgba: pixels)
    guard crop.ink().count == 1,
          crop != RasterCrop(width: 2, height: 2, rgba: Array(repeating: 255, count: 16))
    else { throw EvidenceError("self-test ink or identical-crop rejection failed") }
    print("measure-explore-row-press: 4 self-tests passed")
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["--self-test"] {
        try runSelfTests()
        exit(EXIT_SUCCESS)
    }
    guard arguments.count == 4,
          arguments[0] == "--input",
          arguments[2] == "--output"
    else {
        throw EvidenceError("usage: measure-explore-row-press.swift --self-test | --input DIR --output DIR")
    }
    let input = URL(fileURLWithPath: arguments[1], isDirectory: true)
    let output = URL(fileURLWithPath: arguments[3], isDirectory: true)
    guard FileManager.default.fileExists(atPath: input.path) else {
        throw EvidenceError("input directory does not exist: \(input.path)")
    }
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let cases = [
        CaseSpec(kind: "settings", size: "default"),
        CaseSpec(kind: "about", size: "default"),
        CaseSpec(kind: "settings", size: "ax"),
        CaseSpec(kind: "about", size: "ax"),
    ]
    for spec in cases {
        try analyzeCase(spec, input: input, output: output)
    }
    print("measure-explore-row-press: analyzed 4 cases / selected 8 frames")
} catch {
    fputs("measure-explore-row-press: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}
