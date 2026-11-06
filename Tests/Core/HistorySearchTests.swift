import XCTest
@testable import LaneAheadCore

final class HistorySearchTests: XCTestCase {
    func trip(_ name: String = "图书馆", city: String = "北京市", address: String = "北京市朝阳区", at: Double = 2_000) -> Trip {
        Trip(destination: name, address: address, city: city, startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: at), plannedMeters: 100, status: .arrived)
    }
    func place(_ name: String) -> Place { Place(id: name, name: name, address: "公共地址", city: "北京市", latitude: 39, longitude: 116) }
    func testExplicitCityWithSpaceAndAdministrativePrefix() throws {
        XCTAssertEqual(try SearchScope.resolve("北京 望京花园", defaultCity: "上海市").city, "北京市")
        XCTAssertEqual(try SearchScope.resolve("北京市望京花园", defaultCity: "上海市").keyword, "望京花园")
    }
    func testStreetAndBusinessNamesNotMistakenForCities() throws {
        XCTAssertFalse(try SearchScope.resolve("北京路", defaultCity: "广州市").explicit)
        XCTAssertFalse(try SearchScope.resolve("南京饭店", defaultCity: "北京市").explicit)
        XCTAssertThrowsError(try SearchScope.resolve("图书馆", defaultCity: ""))
    }
    func testFrequentKeepsCitiesAndBranchesSeparateAndIgnoresDuplicates() {
        let same = trip()
        let records = [same, same, trip(), trip(city: "天津市"), trip(address: "北京市海淀区")]
        let result = SearchLogic.frequent(records)
        XCTAssertEqual(result.count, 3); XCTAssertEqual(result.first?.visits, 2)
    }
    func testUnfinishedTripDoesNotCountAsVisited() {
        var record = trip(); record.status = .ended
        XCTAssertTrue(SearchLogic.frequent([record]).isEmpty); XCTAssertTrue(SearchLogic.visitedCities([record]).isEmpty)
    }
    func testOldRecordCityOnlyRecognizedAtAdministrativePrefix() {
        XCTAssertEqual(SearchLogic.city(of: trip(city: "", address: "河北省石家庄市测试街")), "石家庄市")
        XCTAssertEqual(SearchLogic.city(of: trip(city: "", address: "北京路 1 号")), "")
    }
    func testArrivalCannotBeDemotedByExit() {
        var record = trip(); record.finish(.ended, at: Date()); XCTAssertEqual(record.status, .arrived)
    }
    func testStoppedThenArrivedCanCorrectStatus() {
        var record = trip(); record.status = .navigating; record.endedAt = nil
        record.finish(.ended, at: Date(timeIntervalSince1970: 3_000)); record.finish(.arrived, at: Date(timeIntervalSince1970: 4_000))
        XCTAssertEqual(record.status, .arrived); XCTAssertEqual(record.endedAt, Date(timeIntervalSince1970: 3_000))
    }
    @MainActor func testCurrentCityNameMatchStopsFallback() async throws {
        var calls: [String] = []
        let result = try await SearchLogic.search(query: "图书馆", city: "北京市", automatic: true, trips: [trip(city: "天津市")]) { keyword, city in
            calls.append(city); return [self.place("图书馆")]
        }
        XCTAssertEqual(calls, ["北京市"]); XCTAssertFalse(result.fallback)
    }
    @MainActor func testFallbackFindsVisitedCityNameMatchAndStops() async throws {
        var calls: [String] = []
        let result = try await SearchLogic.search(query: "图书馆", city: "上海市", automatic: true,
            trips: [trip(city: "北京市", at: 4_000), trip(city: "天津市", at: 3_000)]) { _, city in
            calls.append(city); return city == "北京市" ? [self.place("图书馆")] : [self.place("相关地点")]
        }
        XCTAssertEqual(calls, ["上海市", "北京市"]); XCTAssertTrue(result.fallback)
    }
    @MainActor func testExplicitCityDoesNotExpand() async throws {
        var calls = 0
        _ = try await SearchLogic.search(query: "北京 图书馆", city: "上海市", automatic: true, trips: [trip(city: "天津市")]) { _, _ in
            calls += 1; return []
        }
        XCTAssertEqual(calls, 1)
    }
    @MainActor func testFailedFallbackPreservesCurrentResults() async throws {
        let result = try await SearchLogic.search(query: "图书馆", city: "上海市", automatic: true, trips: [trip()]) { _, city in
            if city == "北京市" { throw SearchError.message("网络失败") }; return [self.place("相关地点")]
        }
        XCTAssertEqual(result.places.first?.name, "相关地点"); XCTAssertFalse(result.warning.isEmpty)
    }
    @MainActor func testCancellationPreventsNextCityQuery() async {
        let task = Task {
            try await SearchLogic.search(query: "图书馆", city: "上海市", automatic: true, trips: [trip()]) { _, _ in
                try await Task.sleep(for: .seconds(1)); return []
            }
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled search completed") } catch { XCTAssertTrue(error is CancellationError) }
    }
    func testExactNameRanksBeforeContainsAndAddressDoesNotMatch() {
        let result = SearchLogic.rank([place("图书馆分馆"),place("图书馆")], keyword: "图书馆", previous: [])
        XCTAssertEqual(result.first?.name, "图书馆"); XCTAssertEqual(SearchLogic.match("无关地点", "公共地址"), 0)
    }
}

final class PersistenceTests: XCTestCase {
    var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    func testDamagedHistoryNeverOverwritesUntilExplicitClear() throws {
        let store = AtomicRecords<SearchRecord>(directory: directory, file: "test.json", name: "测试", validate: { _ in true })
        let bad = Data("broken".utf8); try bad.write(to: store.url)
        XCTAssertThrowsError(try store.load()); XCTAssertThrowsError(try store.save([]))
        XCTAssertEqual(try Data(contentsOf: store.url), bad)
        try store.clear(); XCTAssertTrue(try store.load().isEmpty)
    }
    func testSearchDedupTwentyLimitAndIndependentClear() async throws {
        let repo = LocalRepository(directory: directory)
        for i in 0..<25 { try await repo.remember("测试 \(i)") }
        try await repo.remember("测试 10")
        var snapshot = await repo.snapshot(); XCTAssertEqual(snapshot.searches.count, 20); XCTAssertEqual(snapshot.searches.first?.query, "测试 10")
        let record = LaneObservation(key: "public-test", recordedAt: Date(), road: "测试路", lanes: [Lane(directions: [.ahead], recommended: [.ahead])])
        try await repo.apply([.save(record)]); try await repo.clear("searches")
        snapshot = await repo.snapshot(); XCTAssertEqual(snapshot.lanes.count, 1); XCTAssertTrue(snapshot.searches.isEmpty)
    }
    func testPermanentHistoryBeyondFiveHundredAndTwoMegabytes() async throws {
        let repo = LocalRepository(directory: directory)
        let old = Date(timeIntervalSince1970: 1_000)
        let changes: [LaneMutation] = (0..<650).map {
            .save(LaneObservation(key: "\($0)-" + String(repeating: "x", count: 3_200), recordedAt: old, road: "公开测试路", lanes: [Lane(directions: [.ahead], recommended: [])]))
        }
        try await repo.apply(changes)
        let second = LocalRepository(directory: directory)
        let state = await second.snapshot(); XCTAssertEqual(state.lanes.count, 650); XCTAssertTrue(state.errors.isEmpty)
        XCTAssertTrue(state.lanes.allSatisfy { $0.recordedAt == old })
    }
    func testTripRecoveryMarksInterruptedWithoutFabricatingEndTime() async throws {
        let repo = LocalRepository(directory: directory)
        let trip = Trip(destination: "测试地点", address: "公共地址", city: "北京市", startedAt: Date(), plannedMeters: 1_000)
        try await repo.putTrip(trip)
        let reloaded = LocalRepository(directory: directory)
        let record = await reloaded.snapshot().trips.first
        XCTAssertEqual(record?.status, .interrupted); XCTAssertNil(record?.endedAt)
    }
    func testLateWritesCannotDemoteArrivedTrip() async throws {
        let repo = LocalRepository(directory: directory)
        var trip = Trip(destination: "测试地点", address: "公开地址", city: "北京市", startedAt: Date(), plannedMeters: 10)
        let old = trip
        trip.finish(.arrived, at: Date()); try await repo.putTrip(trip)
        try await repo.putTrip(old)
        let state = await repo.snapshot()
        XCTAssertEqual(state.trips.first?.status, .arrived)
    }
}
