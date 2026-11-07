import XCTest
import LANavigationPayload
@testable import LaneAheadCore

final class RoutePayloadTests: XCTestCase {
    let a: [String: NSNumber] = ["latitude": 39, "longitude": 116]
    let b: [String: NSNumber] = ["latitude": 39.001, "longitude": 116]
    let c: [String: NSNumber] = ["latitude": 39.002, "longitude": 116]

    func testObjectiveCFlagsSerializeAsJSONBooleansAndDecodeInSwift() throws {
        for signal in [false, true] {
            for internalRoad in [false, true] {
                let payload = LAEncodeRouteLink(40, "公共测试路", signal, internalRoad, [a,b])
                let data = try JSONSerialization.data(withJSONObject: payload)
                let link = try JSONDecoder().decode(RouteLink.self, from: data)
                XCTAssertEqual(link.signal, signal)
                XCTAssertEqual(link.internalRoad, internalRoad)
                let json = String(data: data, encoding: .utf8)!
                XCTAssertTrue(json.contains("\"internalRoad\":" + (internalRoad ? "true" : "false")))
            }
        }
    }

    func testNumericFlagIsRejectedInsteadOfWeakeningTheLaneAssociationContract() throws {
        var payload = LAEncodeRouteLink(100, "公共测试路", true, false, [a,b])
        payload["internalRoad"] = NSNumber(value: 0)
        let data = try JSONSerialization.data(withJSONObject: payload)
        XCTAssertThrowsError(try JSONDecoder().decode(RouteLink.self, from: data))
    }

    func testRealBridgePayloadCanReachGuidanceAndImmediateCapture() throws {
        let link = LAEncodeRouteLink(100, "公共测试路", true, false, [a,b])
        let exit = LAEncodeRouteLink(100, "公共测试街", false, false, [b,c])
        let payload: [[String: Any]] = [
            ["index": 0, "length": 100, "icon": 2, "signals": 1, "coordinates": [a,b], "links": [link]],
            ["index": 1, "length": 100, "icon": 15, "signals": 0, "coordinates": [b,c], "links": [exit]]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let segments = try JSONDecoder().decode([RouteSegment].self, from: data)
        let points = RouteAdapter.points(segments)
        XCTAssertTrue(points[0].learnable)
        let now = Date(timeIntervalSince1970: 1_000)
        let engine = LaneEngine()
        engine.begin(history: [], at: now)
        engine.setRoute("public-test-route", points: points, at: now)
        engine.progress(route: "public-test-route", step: 0, remaining: 80, at: now, realtime: true)
        engine.receive([Lane(directions: [.left], recommended: [.left])], at: now)
        XCTAssertEqual(engine.diagnostics.accepted, 1)
        XCTAssertEqual(engine.history.count, 1)
        XCTAssertEqual(engine.drainMutations().count, 1)
    }
}
