import XCTest
@testable import LaneAheadCore

final class LaneEngineTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_000)
    let lanes = [Lane(directions: [.left], recommended: [.left]), Lane(directions: [.ahead, .right], recommended: [])]
    func point(_ index: Int = 0, learnable: Bool = true) -> GuidancePoint {
        GuidancePoint(index: index, endMeters: Double(index + 1) * 500, road: "公开测试路 → 测试街", action: "左转",
            key: "test-\(index)", learnable: learnable, reason: "未标注信号灯，不保存车道")
    }
    func engine(learnable: Bool = true) -> LaneEngine {
        let e = LaneEngine(); e.begin(history: [], at: now); e.setRoute("r", points: [point(learnable: learnable), point(1), point(2)], at: now)
        return e
    }
    func testSavesImmediatelyAtThreeHundredMeters() {
        let e = engine(); e.progress(route: "r", step: 0, remaining: 300, at: now, realtime: true)
        e.receive(lanes, at: now)
        XCTAssertEqual(e.history.count, 1); XCTAssertEqual(e.diagnostics.accepted, 1)
        XCTAssertEqual(e.drainMutations().count, 1)
        XCTAssertEqual(e.preview(count: 3, at: now).rows.first?.source, .history)
    }
    func testLiveLaneBindsOnlyWithinTwoHundredMeters() {
        let e = engine(); e.progress(route: "r", step: 0, remaining: 150, at: now, realtime: true); e.receive(lanes, at: now)
        XCTAssertEqual(e.preview(count: 2, at: now).rows.first?.source, .live)
        XCTAssertEqual(e.preview(count: 2, at: now).rows.count, 2)
    }
    func testNoSignalNeverLearnsButStillShowsLiveUnassociated() {
        let e = engine(learnable: false); e.progress(route: "r", step: 0, remaining: 50, at: now, realtime: true); e.receive(lanes, at: now)
        XCTAssertTrue(e.history.isEmpty); XCTAssertEqual(e.preview(count: 3, at: now).live, lanes)
    }
    func testWrongRouteSuspendsAndDoesNotLearn() {
        let e = engine(); e.progress(route: "other", step: 0, remaining: 50, at: now, realtime: true); e.receive(lanes, at: now)
        XCTAssertTrue(e.history.isEmpty); XCTAssertTrue(e.preview(count: 3, at: now).rows.isEmpty)
    }
    func testSimulationNeverLearns() {
        let e = engine(); e.progress(route: "r", step: 0, remaining: 50, at: now, realtime: false); e.receive(lanes, at: now)
        XCTAssertTrue(e.history.isEmpty)
    }
    func testStaleOrFuturePositionCannotLearn() {
        for delta in [-1.0, 3.0] {
            let e = engine(); e.progress(route: "r", step: 0, remaining: 50, at: now, realtime: true)
            e.receive(lanes, at: now.addingTimeInterval(delta)); XCTAssertTrue(e.history.isEmpty)
        }
    }
    func testRepeatedCallbacksAndProgressDoNotRewriteObservationTime() {
        let e = engine(); e.progress(route: "r", step: 0, remaining: 100, at: now, realtime: true); e.receive(lanes, at: now)
        e.progress(route: "r", step: 0, remaining: 90, at: now.addingTimeInterval(1), realtime: true)
        e.receive(lanes, at: now.addingTimeInterval(1))
        XCTAssertEqual(e.diagnostics.accepted, 1); XCTAssertEqual(e.history["test-0"]?.recordedAt, now)
    }
    func testDifferentLaneStructureRevokesAlreadySavedRecord() {
        let e = engine(); e.progress(route: "r", step: 0, remaining: 100, at: now, realtime: true); e.receive(lanes, at: now)
        e.receive([Lane(directions: [.left], recommended: [.left])], at: now)
        XCTAssertTrue(e.history.isEmpty); XCTAssertEqual(e.diagnostics.removals, 1)
        e.receive(lanes, at: now); XCTAssertTrue(e.history.isEmpty)
    }
    func testDifferentRecommendationDirectionRevokesHistory() {
        let e = engine(); e.progress(route: "r", step: 0, remaining: 100, at: now, realtime: true); e.receive(lanes, at: now)
        e.receive([Lane(directions: [.left], recommended: []), Lane(directions: [.ahead, .right], recommended: [.right])], at: now)
        XCTAssertTrue(e.history.isEmpty)
    }
    func testRecommendedLanePositionChangeImmediatelyUpdates() {
        let e = engine(); e.progress(route: "r", step: 0, remaining: 100, at: now, realtime: true)
        e.receive([Lane(directions: [.ahead], recommended: [.ahead]), Lane(directions: [.ahead], recommended: [])], at: now)
        e.receive([Lane(directions: [.ahead], recommended: []), Lane(directions: [.ahead], recommended: [.ahead])], at: now)
        XCTAssertEqual(e.diagnostics.accepted, 2); XCTAssertEqual(e.history["test-0"]?.lanes[1].recommended, [.ahead])
    }
    func testHideWeakGPSReplanAndFinishPreserveSavedHistory() {
        let e = engine(); e.progress(route: "r", step: 0, remaining: 100, at: now, realtime: true); e.receive(lanes, at: now)
        e.hide(at: now); e.suspend("弱定位", at: now); e.setRoute("r2", points: [], at: now); e.finish(at: now)
        XCTAssertEqual(e.history.count, 1)
    }
    func testNewStepCannotReuseLastLaneCallback() {
        let e = engine(); e.progress(route: "r", step: 0, remaining: 100, at: now, realtime: true); e.receive(lanes, at: now)
        e.progress(route: "r", step: 1, remaining: 500, at: now.addingTimeInterval(1), realtime: true)
        XCTAssertNil(e.history["test-1"]); XCTAssertEqual(e.preview(count: 3, at: now.addingTimeInterval(1)).rows.first?.source, .unknown)
    }
    func testPositionExpiryHidesRows() {
        let e = engine(); e.progress(route: "r", step: 0, remaining: 100, at: now, realtime: true)
        XCTAssertTrue(e.preview(count: 3, at: now.addingTimeInterval(16)).rows.isEmpty)
    }
    func testInvalidRemainingDistanceRejected() {
        for distance in [-1.0, .nan, .infinity, 600] {
            let e = engine(); e.progress(route: "r", step: 0, remaining: distance, at: now, realtime: true); e.receive(lanes, at: now)
            XCTAssertTrue(e.history.isEmpty)
        }
    }
    func testIOSLaneCodeAndMixedRecommendations() {
        let decoded = LaneDecoder.decode(background: "1|0|0|4", selection: "255|0|0|0")
        XCTAssertEqual(decoded.count, 4); XCTAssertTrue(decoded[0].recommended.isEmpty)
        XCTAssertEqual(decoded[3].directions, [.ahead, .right]); XCTAssertEqual(decoded[3].recommended, [.ahead])
        XCTAssertEqual(LaneDecoder.directions(5), [.leftUTurn]); XCTAssertEqual(LaneDecoder.directions(8), [.rightUTurn])
    }
    func testInvalidLaneStringsRejected() {
        for input in [("0|", "0|0"), ("0|1", "0"), ("a", "0"), ("-1", "0")] {
            XCTAssertTrue(LaneDecoder.decode(background: input.0, selection: input.1).isEmpty)
        }
    }
    func testDemoNeverReferencesPersistenceAndCanShowUnknown() {
        let rows = DemoScenario.rows(traveled: 0, count: 3, missing: true)
        XCTAssertEqual(rows.count, 3); XCTAssertTrue(rows.allSatisfy { $0.source == .demo && !$0.point.learnable })
        XCTAssertTrue(rows[1].lanes.isEmpty); XCTAssertTrue(DemoScenario.rows(traveled: 1_800, count: 3, missing: false).isEmpty)
    }
    func testRefreshUsesCalendarMonthsIncludingMonthEndAndLeapYear() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        for (year, month, day, targetYear, targetMonth, targetDay) in [(2026,1,31,2026,4,30),(2023,11,30,2024,2,29),(2026,11,6,2027,2,6)] {
            let from = calendar.date(from: DateComponents(year: year, month: month, day: day))!
            let due = calendar.date(from: DateComponents(year: targetYear, month: targetMonth, day: targetDay))!
            let record = LaneObservation(key: "key", recordedAt: from, road: "测试路", lanes: lanes)
            XCTAssertFalse(record.needsRefresh(at: due.addingTimeInterval(-1), calendar: calendar))
            XCTAssertTrue(record.needsRefresh(at: due, calendar: calendar))
        }
    }
    func testDiagnosticsBoundedAndContainNoRouteOrCoordinates() {
        var d = Diagnostics()
        for i in 0..<100 { d.report("event-\(i)", "固定状态", at: now) }
        XCTAssertEqual(d.events.count, 60)
        let encoded = String(data: try! JSONEncoder().encode(d), encoding: .utf8)!
        XCTAssertFalse(encoded.contains("test-0")); XCTAssertFalse(encoded.contains("latitude"))
    }
    func testBlockedCallbackCountsWithoutPretendingDecodeOrLearning() {
        let e = engine(); e.blockedCallback(at: now)
        XCTAssertEqual(e.diagnostics.received, 1); XCTAssertEqual(e.diagnostics.decoded, 0)
        XCTAssertEqual(e.diagnostics.accepted, 0); XCTAssertTrue(e.history.isEmpty)
    }
    func testAdditionalSlotsExcludeCurrentAndKeepUnknownPointBeforeKnownHistory() {
        let e = engine()
        e.begin(history: [LaneObservation(key: point(2).key, recordedAt: now, road: "测试街", lanes: lanes)], at: now)
        e.progress(route: "r", step: 0, remaining: 100, at: now, realtime: true)
        e.receive(lanes, at: now)
        let state = e.preview(count: 3, at: now)
        XCTAssertEqual(state.rows.first?.source, .live)
        XCTAssertEqual(state.upcoming.map { $0.point.index }, [1, 2])
        XCTAssertEqual(state.upcoming.map(\.distance), [600, 1_100])
        XCTAssertEqual(state.upcoming.map(\.source), [.unknown, .history])
        XCTAssertTrue(state.upcoming[0].lanes.isEmpty)
        XCTAssertEqual(state.upcoming[1].lanes, lanes)
    }
    func testAdditionalSlotsAdvanceAndNeverCopyThePreviousLiveLanes() {
        let e = engine(); e.progress(route: "r", step: 0, remaining: 100, at: now, realtime: true)
        e.receive(lanes, at: now)
        e.progress(route: "r", step: 1, remaining: 400, at: now.addingTimeInterval(1), realtime: true)
        let future = e.preview(count: 3, at: now.addingTimeInterval(1)).upcoming
        XCTAssertEqual(future.map { $0.point.index }, [2])
        XCTAssertEqual(future.first?.distance, 900)
        XCTAssertTrue(future.allSatisfy { $0.lanes.isEmpty && $0.source == .unknown })
    }
    func testAdditionalSlotsClearForStalePositionWeakGPSAndReplan() {
        let e = engine(); e.progress(route: "r", step: 0, remaining: 100, at: now, realtime: true)
        XCTAssertEqual(e.preview(count: 3, at: now).upcoming.count, 2)
        XCTAssertTrue(e.preview(count: 3, at: now.addingTimeInterval(16)).upcoming.isEmpty)
        e.suspend("弱定位", at: now)
        XCTAssertTrue(e.preview(count: 3, at: now).upcoming.isEmpty)
        e.setRoute("r2", points: [point(), point(1)], at: now)
        XCTAssertTrue(e.preview(count: 3, at: now).upcoming.isEmpty)
        e.progress(route: "r", step: 0, remaining: 100, at: now, realtime: true)
        XCTAssertTrue(e.preview(count: 3, at: now).upcoming.isEmpty)
    }
    func testAdditionalSlotsOmitDestinationAndPreserveHistoryMetadata() {
        let e = engine(); var destination = point(2); destination.action = "到达终点"
        let old = LaneObservation(key: point(1).key, recordedAt: now.addingTimeInterval(-100), road: "测试街", lanes: lanes)
        e.begin(history: [old], at: now)
        e.setRoute("r", points: [point(), point(1), destination], at: now)
        e.progress(route: "r", step: 0, remaining: 100, at: now, realtime: true)
        XCTAssertEqual(e.preview(count: 3, at: now).upcoming.map { $0.point.index }, [1])
        XCTAssertEqual(e.preview(count: 3, at: now).upcoming.first?.observation, old)
        e.progress(route: "r", step: 2, remaining: 10, at: now, realtime: true)
        XCTAssertTrue(e.preview(count: 3, at: now).upcoming.isEmpty)
    }
}

final class RouteAdapterTests: XCTestCase {
    let a = Coordinate(latitude: 39, longitude: 116), b = Coordinate(latitude: 39.001, longitude: 116)
    let c = Coordinate(latitude: 39.002, longitude: 116)
    func segments(signals: Int = 1) -> [RouteSegment] {
        [RouteSegment(index: 0, length: 100, icon: 2, signals: signals, coordinates: [a,b],
            links: [RouteLink(length: 100, road: "测试路", signal: signals == 1, internalRoad: false, coordinates: [a,b])]),
         RouteSegment(index: 1, length: 100, icon: 15, signals: 0, coordinates: [b,c],
            links: [RouteLink(length: 100, road: "测试街", signal: false, internalRoad: false, coordinates: [b,c])])]
    }
    func testUniqueSignalAndConnectedExitEligible() { XCTAssertTrue(RouteAdapter.points(segments())[0].learnable) }
    func testNoSignalOrMultipleSignalsNotEligible() {
        XCTAssertFalse(RouteAdapter.points(segments(signals: 0))[0].learnable)
        XCTAssertFalse(RouteAdapter.points(segments(signals: 2))[0].learnable)
    }
    func testDisconnectedExitAndInvalidCoordinateRejected() {
        var s = segments(); s[1].coordinates[0] = c; XCTAssertFalse(RouteAdapter.points(s)[0].learnable)
        XCTAssertFalse(RouteAdapter.same(Coordinate(latitude: .nan, longitude: 1), a))
    }
    func testShortInternalRoadAcceptedOrdinaryOrOverSixtyMetersRejected() {
        var s = segments()
        s[0].links[0].coordinates = [a, Coordinate(latitude: 39.0005, longitude: 116)]
        let end = s[0].links[0].coordinates.last!
        s[0].links.append(RouteLink(length: 60, road: "", signal: false, internalRoad: true, coordinates: [end,b]))
        XCTAssertTrue(RouteAdapter.points(s)[0].learnable)
        s[0].links[1].length = 61; XCTAssertFalse(RouteAdapter.points(s)[0].learnable)
        s[0].links[1].length = 40; s[0].links[1].internalRoad = false; XCTAssertFalse(RouteAdapter.points(s)[0].learnable)
    }
    func testMalformedSegmentLengthReturnsNoRoutePoints() {
        var s = segments(); s[0].length = .nan; XCTAssertTrue(RouteAdapter.points(s).isEmpty)
    }
}
