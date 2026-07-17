import XCTest
import MakingTracksData
@testable import MakingTracksMapStyle

final class PinLayersTests: XCTestCase {
    private let matrix: [PinState] = [
        PinState(saved: false, visit: .none),
        PinState(saved: true, visit: .none),
        PinState(saved: false, visit: .visited),
        PinState(saved: true, visit: .visited),
        PinState(saved: false, visit: .loved),
        PinState(saved: true, visit: .loved),
    ]

    func testGeneratedExpressionsMatchPinAppearanceForEveryCell() {
        for state in matrix {
            let want = pinAppearance(state)
            let props = FeatureEncoding.featureProperties(state)
            guard case let .double(opacity) = Expression.evaluate(PinLayers.fadeOpacityExpression(), props) else {
                return XCTFail("opacity not a number for \(state)")
            }
            XCTAssertEqual(opacity, want.opacity, accuracy: 1e-9, "opacity \(state)")
            XCTAssertEqual(Expression.evaluate(PinLayers.bookmarkFilter(), props), .bool(want.showBookmarkBadge), "bookmark \(state)")
            XCTAssertEqual(Expression.evaluate(PinLayers.heartFilter(), props), .bool(want.showHeartBadge), "heart \(state)")
        }
    }

    func testPinSubstrateIsShapeSourcePlusStyleLayersNotAnnotations() {
        let layers = PinLayers.pinLayers()
        let circle = layer(id: "pins-circle", in: layers)
        let bookmark = layer(id: "pins-bookmark", in: layers)
        let heart = layer(id: "pins-heart", in: layers)

        XCTAssertEqual(circle?["type"], .string("circle"), "circle pin layer")
        XCTAssertEqual(bookmark?["type"], .string("symbol"), "bookmark badge symbol layer")
        XCTAssertEqual(heart?["type"], .string("symbol"), "heart badge symbol layer")
        XCTAssertEqual(layers.count, 3, "circle pin layer + bookmark/heart badges only")
        for layer in [circle, bookmark, heart] {
            XCTAssertEqual(layer?["source"], .string(PinLayers.sourceID))
        }
        XCTAssertNotEqual(PinLayers.bookmarkOffset, PinLayers.heartOffset, "badges would collide at one anchor")

        if case let .object(paint)? = circle?["paint"] {
            XCTAssertEqual(paint["circle-color"], .string(PinLayers.pinColor))
            XCTAssertEqual(paint["circle-opacity"], PinLayers.fadeOpacityExpression())
            XCTAssertEqual(paint["circle-radius"], .double(6))
        } else {
            XCTFail("pin circle paint")
        }

        XCTAssertEqual(bookmark?["filter"], PinLayers.bookmarkFilter())
        XCTAssertEqual(heart?["filter"], PinLayers.heartFilter())
        XCTAssertEqual(layoutValue("icon-image", in: bookmark), .string("badge-bookmark"))
        XCTAssertEqual(layoutValue("icon-image", in: heart), .string("badge-heart"))
        XCTAssertEqual(layoutValue("icon-allow-overlap", in: bookmark), .bool(true))
        XCTAssertEqual(layoutValue("icon-allow-overlap", in: heart), .bool(true))
        XCTAssertEqual(layoutValue("icon-offset", in: bookmark), PinLayers.bookmarkOffset)
        XCTAssertEqual(layoutValue("icon-offset", in: heart), PinLayers.heartOffset)
    }

    func testFoundationObjectBridgePreservesRecursiveShapeAndBooleanNSNumber() {
        let number = JSONValue.bool(true).foundationObject as? NSNumber
        XCTAssertNotNil(number)
        XCTAssertEqual(CFGetTypeID(number!), CFBooleanGetTypeID(), "bool must bridge to a boolean NSNumber, not 0/1")

        let object = JSONValue.object([
            "array": .array([.string("x"), .double(2), .bool(false), .null]),
            "filter": PinLayers.bookmarkFilter(),
        ]).foundationObject
        guard let dict = object as? [String: Any],
              let array = dict["array"] as? [Any],
              let filter = dict["filter"] as? [Any]
        else { return XCTFail("recursive bridge shape") }
        XCTAssertEqual(array[0] as? String, "x")
        XCTAssertEqual(array[1] as? Double, 2)
        XCTAssertEqual(CFGetTypeID(array[2] as! NSNumber), CFBooleanGetTypeID())
        XCTAssertTrue(array[3] is NSNull)
        XCTAssertEqual(filter.count, 3)
    }

    func testFeatureIsGeoJSONPointWithLonLatOrder() {
        let feature = FeatureEncoding.feature(
            MapPlace(id: "mt1_x", lat: 3.14, lon: 101.69, tier: 2),
            PinState(saved: true, visit: .loved)
        )
        guard case let .object(feat) = feature,
              case let .object(geometry) = feat["geometry"],
              case let .array(coords) = geometry["coordinates"] else {
            return XCTFail("geometry")
        }
        XCTAssertEqual(feat["type"], .string("Feature"))
        XCTAssertEqual(geometry["type"], .string("Point"))
        XCTAssertEqual(coords, [.double(101.69), .double(3.14)])
        guard case let .object(props) = feat["properties"] else { return XCTFail("props") }
        XCTAssertEqual(props["place_id"], .string("mt1_x"))
        XCTAssertEqual(props["tier"], .double(2))
        XCTAssertEqual(props["visit"], .string("loved"))
        XCTAssertEqual(props["saved"], .bool(true))
        XCTAssertEqual(props["hidden"], .bool(false))

        let collection = FeatureEncoding.featureCollection([feature])
        guard case let .object(root) = collection,
              case let .array(features) = root["features"]
        else { return XCTFail("feature collection") }
        XCTAssertEqual(root["type"], .string("FeatureCollection"))
        XCTAssertEqual(features, [feature])
    }

    private func layer(id: String, in layers: [JSONValue]) -> [String: JSONValue]? {
        for case let .object(layer) in layers where layer["id"] == .string(id) {
            return layer
        }
        return nil
    }

    private func layoutValue(_ key: String, in layer: [String: JSONValue]?) -> JSONValue? {
        guard case let .object(layout)? = layer?["layout"] else { return nil }
        return layout[key]
    }
}
