import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

private let restMarker = RGB(red: 0, green: 255, blue: 255)
private let pressedMarker = RGB(red: 255, green: 0, blue: 255)
private let luminanceThreshold: UInt8 = 96
private let fixtureMarkerCrop = CGRect(x: 18, y: 0, width: 12, height: 12)
private let fixtureInkCrop = CGRect(x: 5, y: 5, width: 12, height: 16)

struct RGB: Equatable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
}

struct InkBounds: Equatable {
    let darkPixelCount: Int
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

enum LivePressState: String {
    case rest
    case pressed
}

private enum AnalyzerError: LocalizedError {
    case invalid(String)
    case markerMismatch

    var errorDescription: String? {
        switch self {
        case .invalid(let message):
            return message
        case .markerMismatch:
            return "marker crop is not one exact live state"
        }
    }
}

struct Raster {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init(width: Int, height: Int, pixels: [UInt8]) throws {
        guard width > 0, height > 0, width <= 10_000, height <= 10_000,
              width <= Int.max / height,
              width * height <= Int.max / 4,
              pixels.count == width * height * 4
        else {
            throw AnalyzerError.invalid("invalid 8-bit RGBA raster")
        }
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    init(pngAt url: URL) throws {
        let values = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (values[.size] as? NSNumber)?.intValue ?? -1
        guard size > 0, size <= 64 * 1024 * 1024 else {
            throw AnalyzerError.invalid("PNG is empty or exceeds the 64 MiB input limit: \(url.path)")
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) == 1,
              let sourceType = CGImageSourceGetType(source) as String?,
              sourceType == "public.png",
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw AnalyzerError.invalid("not a single-image PNG: \(url.path)")
        }

        let imageWidth = image.width
        let imageHeight = image.height
        guard imageWidth > 0, imageHeight > 0,
              imageWidth <= 10_000, imageHeight <= 10_000,
              imageWidth <= Int.max / imageHeight,
              imageWidth * imageHeight <= Int.max / 4
        else {
            throw AnalyzerError.invalid("PNG dimensions are invalid: \(url.path)")
        }

        var normalized = [UInt8](repeating: 0, count: imageWidth * imageHeight * 4)
        guard let context = CGContext(
            data: &normalized,
            width: imageWidth,
            height: imageHeight,
            bitsPerComponent: 8,
            bytesPerRow: imageWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            throw AnalyzerError.invalid("could not normalize PNG to 8-bit RGBA: \(url.path)")
        }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
        try self.init(width: imageWidth, height: imageHeight, pixels: normalized)
    }

    func rgb(x: Int, y: Int) -> RGB {
        let offset = ((y * width) + x) * 4
        return RGB(red: pixels[offset], green: pixels[offset + 1], blue: pixels[offset + 2])
    }
}

private struct FixtureRaster {
    let width = 30
    let height = 30
    var pixels = [UInt8](repeating: 255, count: 30 * 30 * 4)

    init(inkY: Int, marker: (UInt8, UInt8, UInt8)) {
        for y in inkY..<(inkY + 2) {
            for x in 7..<13 {
                let offset = ((y * width) + x) * 4
                pixels[offset] = 0
                pixels[offset + 1] = 0
                pixels[offset + 2] = 0
                pixels[offset + 3] = 255
            }
        }
        for y in 0..<12 {
            for x in 18..<30 {
                let markerOffset = ((y * width) + x) * 4
                pixels[markerOffset] = marker.0
                pixels[markerOffset + 1] = marker.1
                pixels[markerOffset + 2] = marker.2
                pixels[markerOffset + 3] = 255
            }
        }
    }
}

private func checkedPixelRect(_ crop: CGRect, in raster: Raster) throws -> (minX: Int, minY: Int, maxX: Int, maxY: Int) {
    guard crop.origin.x.isFinite,
          crop.origin.y.isFinite,
          crop.width.isFinite,
          crop.height.isFinite,
          crop.width > 0,
          crop.height > 0,
          crop.minX >= 0,
          crop.minY >= 0,
          crop.maxX <= CGFloat(raster.width),
          crop.maxY <= CGFloat(raster.height)
    else {
        throw AnalyzerError.invalid("crop is non-finite, empty, or outside the PNG frame")
    }
    let minX = Int(floor(crop.minX))
    let minY = Int(floor(crop.minY))
    let maxX = Int(ceil(crop.maxX))
    let maxY = Int(ceil(crop.maxY))
    guard minX >= 0, minY >= 0, maxX > minX, maxY > minY,
          maxX <= raster.width, maxY <= raster.height
    else {
        throw AnalyzerError.invalid("crop does not contain a valid pixel region")
    }
    return (minX, minY, maxX, maxY)
}

func classify(_ raster: Raster, marker: CGRect) throws -> LivePressState {
    let rect = try checkedPixelRect(marker, in: raster)
    var restSamples = 0
    var pressedSamples = 0
    var sampleCount = 0

    for y in rect.minY..<rect.maxY {
        for x in rect.minX..<rect.maxX {
            sampleCount += 1
            let sample = raster.rgb(x: x, y: y)
            if sample == restMarker {
                restSamples += 1
            } else if sample == pressedMarker {
                pressedSamples += 1
            } else {
                throw AnalyzerError.markerMismatch
            }
        }
    }
    guard sampleCount > 0 else {
        throw AnalyzerError.invalid("marker crop has no samples")
    }
    if restSamples == sampleCount { return .rest }
    if pressedSamples == sampleCount { return .pressed }
    throw AnalyzerError.markerMismatch
}

// A single BT.709 integer luminance threshold (96/255) classifies dark ink in every frame.
func measureInk(_ raster: Raster, crop: CGRect, luminanceThreshold: UInt8) throws -> InkBounds {
    let rect = try checkedPixelRect(crop, in: raster)
    var darkPixelCount = 0
    var minimumX = Int.max
    var minimumY = Int.max
    var maximumX = Int.min
    var maximumY = Int.min

    for y in rect.minY..<rect.maxY {
        for x in rect.minX..<rect.maxX {
            let pixel = raster.rgb(x: x, y: y)
            let luminance = (54 * Int(pixel.red) + 183 * Int(pixel.green) + 19 * Int(pixel.blue)) >> 8
            if luminance <= Int(luminanceThreshold) {
                darkPixelCount += 1
                minimumX = min(minimumX, x)
                minimumY = min(minimumY, y)
                maximumX = max(maximumX, x)
                maximumY = max(maximumY, y)
            }
        }
    }

    guard darkPixelCount > 0 else {
        throw AnalyzerError.invalid("ink crop has no dark samples")
    }
    return InkBounds(
        darkPixelCount: darkPixelCount,
        x: minimumX,
        y: minimumY,
        width: maximumX - minimumX + 1,
        height: maximumY - minimumY + 1
    )
}

func displacement(rest: InkBounds, pressed: InkBounds) -> Int {
    pressed.y - rest.y
}

private func runSelfTest() throws {
    let restPixels = try Raster(width: 30, height: 30, pixels: FixtureRaster(inkY: 8, marker: (0, 255, 255)).pixels)
    let defaultPressedPixels = try Raster(width: 30, height: 30, pixels: FixtureRaster(inkY: 11, marker: (255, 0, 255)).pixels)
    let axPressedPixels = try Raster(width: 30, height: 30, pixels: FixtureRaster(inkY: 14, marker: (255, 0, 255)).pixels)

    var mixedMarkerFixture = FixtureRaster(inkY: 8, marker: (0, 255, 255)).pixels
    mixedMarkerFixture[((6 * 30) + 24) * 4] = 255
    mixedMarkerFixture[((6 * 30) + 24) * 4 + 1] = 0
    mixedMarkerFixture[((6 * 30) + 24) * 4 + 2] = 255
    let mixedMarker = try Raster(width: 30, height: 30, pixels: mixedMarkerFixture)

    let restState = try classify(restPixels, marker: fixtureMarkerCrop)
    let pressedState = try classify(defaultPressedPixels, marker: fixtureMarkerCrop)
    precondition(restState == .rest)
    precondition(pressedState == .pressed)
    do {
        _ = try classify(mixedMarker, marker: fixtureMarkerCrop)
        preconditionFailure("mixed marker must be rejected")
    } catch AnalyzerError.markerMismatch {
        // Expected: an exact state marker may not mix the fixture RGB values.
    }
    do {
        _ = try measureInk(restPixels, crop: CGRect(x: -1, y: 5, width: 12, height: 16), luminanceThreshold: luminanceThreshold)
        preconditionFailure("out-of-frame crop must be rejected")
    } catch AnalyzerError.invalid {
        // Expected: evidence crops never clip silently.
    }
    let orientationURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("measure-place-card-orientation-\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: orientationURL) }
    try writeOrientationFixturePNG(to: orientationURL)
    let decodedOrientation = try Raster(pngAt: orientationURL)
    precondition(decodedOrientation.rgb(x: 0, y: 0) == RGB(red: 255, green: 0, blue: 0), "decoded PNG top row must stay row 0")
    precondition(decodedOrientation.rgb(x: 0, y: 1) == RGB(red: 0, green: 0, blue: 255), "decoded PNG bottom row must stay row 1")

    let frameDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("measure-place-card-frame-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: frameDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: frameDirectory) }
    let realisticFrameURL = frameDirectory.appendingPathComponent("realistic.txt")
    try """
    capture: realistic
    screen-scale: 3.00
    hide: x=152.33 y=413.00 width=81.33 height=60.00
    state: x=152.33 y=413.00 width=12.00 height=12.00

    """.write(to: realisticFrameURL, atomically: true, encoding: .utf8)
    let realisticFrame = try ExportedFrame(file: realisticFrameURL)
    let realisticMarkerCrop = try realisticFrame.markerCrop()
    precondition(
        realisticMarkerCrop == CGRect(x: 457, y: 1239, width: 36, height: 36),
        "marker crop must use the exported state frame with rounded device-pixel edges"
    )

    let missingStateURL = frameDirectory.appendingPathComponent("missing-state.txt")
    try """
    screen-scale: 3.00
    hide: x=152.33 y=413.00 width=81.33 height=60.00

    """.write(to: missingStateURL, atomically: true, encoding: .utf8)
    do {
        _ = try ExportedFrame(file: missingStateURL)
        preconditionFailure("missing state frame must be rejected")
    } catch AnalyzerError.invalid {
        // Expected: marker geometry is mandatory evidence input.
    }

    let fractionalStateURL = frameDirectory.appendingPathComponent("fractional-state.txt")
    try """
    screen-scale: 3.00
    hide: x=152.33 y=413.00 width=81.33 height=60.00
    state: x=152.20 y=413.00 width=12.00 height=12.00

    """.write(to: fractionalStateURL, atomically: true, encoding: .utf8)
    do {
        _ = try ExportedFrame(file: fractionalStateURL).markerCrop()
        preconditionFailure("state edges far from device pixels must be rejected")
    } catch AnalyzerError.invalid {
        // Expected: two-decimal serialization may round to a pixel, not widen a fractional crop.
    }
    let rest = try measureInk(restPixels, crop: fixtureInkCrop, luminanceThreshold: luminanceThreshold)
    let defaultDelta = displacement(rest: rest, pressed: try measureInk(defaultPressedPixels, crop: fixtureInkCrop, luminanceThreshold: luminanceThreshold))
    let axDelta = displacement(rest: rest, pressed: try measureInk(axPressedPixels, crop: fixtureInkCrop, luminanceThreshold: luminanceThreshold))
    precondition(defaultDelta == 3, "default displacement must be 3")
    precondition(axDelta > defaultDelta, "AX displacement must exceed default")
    precondition(axDelta == 6, "AX displacement must be 6")
    print("PASS default=\(defaultDelta) ax=\(axDelta)")
}

private func writeOrientationFixturePNG(to url: URL) throws {
    // PNG scanlines are top-to-bottom: red/green first, blue/black second.
    let pixels: [UInt8] = [
        255, 0, 0, 255, 0, 255, 0, 255,
        0, 0, 255, 255, 0, 0, 0, 255,
    ]
    guard let provider = CGDataProvider(data: Data(pixels) as CFData),
          let image = CGImage(
              width: 2,
              height: 2,
              bitsPerComponent: 8,
              bitsPerPixel: 32,
              bytesPerRow: 8,
              space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              provider: provider,
              decode: nil,
              shouldInterpolate: false,
              intent: .defaultIntent
          ),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
    else {
        throw AnalyzerError.invalid("could not create PNG orientation fixture")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw AnalyzerError.invalid("could not write PNG orientation fixture")
    }
}

private struct ExportedFrame {
    let button: CGRect
    let state: CGRect
    let screenScale: CGFloat

    init(file: URL) throws {
        let text = try String(contentsOf: file, encoding: .utf8)
        var scale: Double?
        var buttonValues: [String: Double] = [:]
        var stateValues: [String: Double] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            if line.hasPrefix("screen-scale:") {
                scale = Double(line.dropFirst("screen-scale:".count).trimmingCharacters(in: .whitespaces))
            } else if line.hasPrefix("hide:") || line.hasPrefix("state:") {
                let isState = line.hasPrefix("state:")
                for field in line.split(separator: " ").dropFirst() {
                    let pair = field.split(separator: "=", maxSplits: 1)
                    guard pair.count == 2, let number = Double(pair[1]) else {
                        throw AnalyzerError.invalid("malformed frame record: \(file.path)")
                    }
                    if isState {
                        stateValues[String(pair[0])] = number
                    } else {
                        buttonValues[String(pair[0])] = number
                    }
                }
            }
        }
        guard let buttonX = buttonValues["x"], let buttonY = buttonValues["y"],
              let buttonWidth = buttonValues["width"], let buttonHeight = buttonValues["height"],
              let stateX = stateValues["x"], let stateY = stateValues["y"],
              let stateWidth = stateValues["width"], let stateHeight = stateValues["height"],
              let scale,
              buttonX.isFinite, buttonY.isFinite, buttonWidth.isFinite, buttonHeight.isFinite,
              stateX.isFinite, stateY.isFinite, stateWidth.isFinite, stateHeight.isFinite,
              scale.isFinite, buttonWidth > 0, buttonHeight > 0,
              stateWidth > 0, stateHeight > 0, scale > 0
        else {
            throw AnalyzerError.invalid("missing or invalid Hide/state frame record: \(file.path)")
        }
        button = CGRect(x: buttonX, y: buttonY, width: buttonWidth, height: buttonHeight)
        state = CGRect(x: stateX, y: stateY, width: stateWidth, height: stateHeight)
        screenScale = CGFloat(scale)
    }

    var inkCrop: CGRect {
        CGRect(
            x: button.minX * screenScale,
            y: button.minY * screenScale,
            width: button.width * screenScale,
            height: button.height * screenScale
        )
    }

    func markerCrop() throws -> CGRect {
        func roundedPixelEdge(_ pointEdge: CGFloat) throws -> CGFloat {
            let scaled = pointEdge * screenScale
            let rounded = scaled.rounded()
            guard abs(scaled - rounded) <= 0.02 else {
                throw AnalyzerError.invalid("state frame edge does not resolve to a device pixel")
            }
            return rounded
        }
        let minX = try roundedPixelEdge(state.minX)
        let minY = try roundedPixelEdge(state.minY)
        let maxX = try roundedPixelEdge(state.maxX)
        let maxY = try roundedPixelEdge(state.maxY)
        guard maxX > minX, maxY > minY else {
            throw AnalyzerError.invalid("state frame has no device-pixel area")
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

private struct Candidate {
    let url: URL
    let state: LivePressState
    let ink: InkBounds
    let sha256: String
    let dimensions: String
}

private func digest(of url: URL) throws -> String {
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func selectedCandidate(
    in directory: URL,
    frame: ExportedFrame
) throws -> (rest: Candidate, pressed: Candidate) {
    let markerCrop = try frame.markerCrop()
    let files = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    )
    .filter { $0.pathExtension.lowercased() == "png" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
    guard !files.isEmpty else {
        throw AnalyzerError.invalid("no PNG candidates in \(directory.path)")
    }

    var candidates: [Candidate] = []
    var exactMarkerFailureCount = 0
    for file in files {
        let raster = try Raster(pngAt: file)
        let state: LivePressState
        do {
            state = try classify(raster, marker: markerCrop)
        } catch AnalyzerError.markerMismatch {
            exactMarkerFailureCount += 1
            continue
        }
        let ink = try measureInk(raster, crop: frame.inkCrop, luminanceThreshold: luminanceThreshold)
        candidates.append(Candidate(
            url: file,
            state: state,
            ink: ink,
            sha256: try digest(of: file),
            dimensions: "\(raster.width)x\(raster.height)"
        ))
    }
    guard let rest = candidates.filter({ $0.state == .rest }).min(by: {
        $0.ink.y == $1.ink.y
            ? $0.url.lastPathComponent < $1.url.lastPathComponent
            : $0.ink.y < $1.ink.y
    }) else {
        throw AnalyzerError.invalid("missing valid exact rest marker; rejected \(exactMarkerFailureCount) candidates")
    }
    guard let pressed = candidates.filter({ $0.state == .pressed }).max(by: {
        $0.ink.y == $1.ink.y
            ? $0.url.lastPathComponent > $1.url.lastPathComponent
            : $0.ink.y < $1.ink.y
    }) else {
        throw AnalyzerError.invalid("missing valid exact pressed marker; rejected \(exactMarkerFailureCount) candidates")
    }
    return (rest, pressed)
}

private func format(_ candidate: Candidate) -> String {
    "file=\(candidate.url.lastPathComponent) dimensions=\(candidate.dimensions) sha256=\(candidate.sha256) ink=\(candidate.ink.darkPixelCount) bounds=\(candidate.ink.x),\(candidate.ink.y),\(candidate.ink.width),\(candidate.ink.height)"
}

private func argumentValue(_ arguments: [String], named name: String) throws -> String {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else {
        throw AnalyzerError.invalid("missing \(name)")
    }
    return arguments[index + 1]
}

private func runSelection(arguments: [String]) throws {
    let candidates = URL(fileURLWithPath: try argumentValue(arguments, named: "--candidates"), isDirectory: true)
    let frame = try ExportedFrame(file: URL(fileURLWithPath: try argumentValue(arguments, named: "--frame")))
    let restOutput = URL(fileURLWithPath: try argumentValue(arguments, named: "--rest-output"))
    let pressedOutput = URL(fileURLWithPath: try argumentValue(arguments, named: "--pressed-output"))
    let label = try argumentValue(arguments, named: "--label")
    guard !FileManager.default.fileExists(atPath: restOutput.path),
          !FileManager.default.fileExists(atPath: pressedOutput.path)
    else {
        throw AnalyzerError.invalid("selection output already exists")
    }

    let selection = try selectedCandidate(in: candidates, frame: frame)
    let topDelta = displacement(rest: selection.rest.ink, pressed: selection.pressed.ink)
    let centerDelta = (Double(selection.pressed.ink.y) + Double(selection.pressed.ink.height) / 2)
        - (Double(selection.rest.ink.y) + Double(selection.rest.ink.height) / 2)
    guard topDelta > 0 else {
        throw AnalyzerError.invalid("pressed ink must be positively displaced from rest")
    }
    try FileManager.default.copyItem(at: selection.rest.url, to: restOutput)
    try FileManager.default.copyItem(at: selection.pressed.url, to: pressedOutput)
    print("\(label) rest \(format(selection.rest))")
    print("\(label) pressed \(format(selection.pressed))")
    let formattedCenterDelta = String(format: "%.1f", centerDelta)
    print("RESULT label=\(label) top_displacement=\(topDelta) center_displacement=\(formattedCenterDelta)")
}

private func usage() -> Never {
    fputs("usage: measure-place-card-press.swift --self-test\n       measure-place-card-press.swift --select --candidates DIR --frame FILE --rest-output PNG --pressed-output PNG --label NAME\n", stderr)
    exit(64)
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["--self-test"] {
        try runSelfTest()
    } else if arguments.first == "--select" {
        try runSelection(arguments: arguments)
    } else {
        usage()
    }
} catch {
    fputs("measure-place-card-press: \(error.localizedDescription)\n", stderr)
    exit(1)
}
