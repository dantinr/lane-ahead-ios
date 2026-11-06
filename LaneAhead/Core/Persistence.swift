import Foundation

enum LocalDataError: LocalizedError {
    case damaged(String)
    case storage
    var errorDescription: String? {
        switch self {
        case .damaged(let name): return "\(name)文件损坏或读取失败，已保留原文件。请显式清除后重新记录。"
        case .storage: return "本机存储写入失败，请检查可用空间后重试。"
        }
    }
}

private struct Envelope<T: Codable>: Codable {
    var version = 1
    var records: [T]
}

final class AtomicRecords<T: Codable> {
    let url: URL
    let name: String
    private let validate: ([T]) -> Bool
    private(set) var blocked = false
    init(directory: URL, file: String, name: String, validate: @escaping ([T]) -> Bool) {
        url = directory.appendingPathComponent(file)
        self.name = name; self.validate = validate
    }
    func load() throws -> [T] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let value = try JSONDecoder().decode(Envelope<T>.self, from: Data(contentsOf: url))
            guard value.version == 1, validate(value.records) else { throw LocalDataError.damaged(name) }
            blocked = false
            return value.records
        } catch {
            blocked = true
            throw LocalDataError.damaged(name)
        }
    }
    func save(_ records: [T]) throws {
        guard !blocked else { throw LocalDataError.damaged(name) }
        guard validate(records) else { throw LocalDataError.storage }
        try write(records)
    }
    private func write(_ records: [T]) throws {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Envelope(records: records)).write(to: url, options: .atomic)
            #if os(iOS)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path)
            #endif
        } catch { throw LocalDataError.storage }
    }
    func clear() throws { try write([]); blocked = false }
}

struct LocalSnapshot: Sendable {
    var lanes: [LaneObservation] = []
    var trips: [Trip] = []
    var searches: [SearchRecord] = []
    var diagnostics = Diagnostics()
    var errors: [String] = []
}

// All disk work is isolated from the main actor. Files are independent, and a
// malformed file is never overwritten by an automatic save.
actor LocalRepository {
    private let laneFile: AtomicRecords<LaneObservation>
    private let tripFile: AtomicRecords<Trip>
    private let searchFile: AtomicRecords<SearchRecord>
    private let diagnosticFile: AtomicRecords<Diagnostics>
    private var state = LocalSnapshot()
    private var loaded = false

    init(directory: URL) {
        laneFile = AtomicRecords(directory: directory, file: "lane-observations-ios-v1.json", name: "车道历史") {
            $0.allSatisfy { $0.valid(at: Date()) } && Set($0.map(\.key)).count == $0.count
        }
        tripFile = AtomicRecords(directory: directory, file: "navigation-history-v1.json", name: "导航历史") {
            $0.count <= 200 && $0.allSatisfy(\.valid) && Set($0.map(\.id)).count == $0.count
        }
        searchFile = AtomicRecords(directory: directory, file: "search-history-v1.json", name: "搜索历史") {
            $0.count <= 20 && $0.allSatisfy { !$0.query.isEmpty && $0.query.count <= 500 && $0.at.timeIntervalSince1970.isFinite } &&
            Set($0.map(\.query)).count == $0.count
        }
        diagnosticFile = AtomicRecords(directory: directory, file: "lane-diagnostics-v2.json", name: "采集诊断") {
            $0.count <= 1 && $0.allSatisfy { $0.version == 2 && $0.events.count <= 60 &&
                [$0.received, $0.decoded, $0.accepted, $0.writes, $0.removals].allSatisfy { $0 >= 0 } }
        }
    }

    func snapshot() -> LocalSnapshot {
        if !loaded {
            loaded = true
            do { state.lanes = try laneFile.load() } catch { state.errors.append(error.localizedDescription) }
            do {
                state.trips = try tripFile.load()
                var changed = false
                for i in state.trips.indices where state.trips[i].status == .navigating {
                    state.trips[i].status = .interrupted; changed = true
                }
                if changed { try tripFile.save(state.trips) }
            } catch { state.errors.append(error.localizedDescription) }
            do { state.searches = try searchFile.load() } catch { state.errors.append(error.localizedDescription) }
            do { state.diagnostics = try diagnosticFile.load().first ?? Diagnostics() }
            catch { state.errors.append(error.localizedDescription) }
        }
        var copy = state
        copy.lanes.sort { $0.recordedAt > $1.recordedAt }
        copy.trips.sort { $0.startedAt > $1.startedAt }
        return copy
    }

    func apply(_ changes: [LaneMutation]) throws {
        _ = snapshot()
        var records = Dictionary(state.lanes.map { ($0.key, $0) }, uniquingKeysWith: { _, b in b })
        for change in changes {
            switch change {
            case .save(let record): records[record.key] = record
            case .remove(let key): records.removeValue(forKey: key)
            }
        }
        let next = Array(records.values)
        try laneFile.save(next)
        state.lanes = next
    }

    func putTrip(_ trip: Trip) throws {
        _ = snapshot()
        guard trip.valid else { return }
        if let old = state.trips.first(where: { $0.id == trip.id }) {
            if old.status == .arrived && trip.status != .arrived { return }
            if old.status != .navigating && trip.status == .navigating { return }
        }
        var next = state.trips.filter { $0.id != trip.id }
        next.append(trip); next.sort { $0.startedAt > $1.startedAt }
        next = Array(next.prefix(200))
        try tripFile.save(next); state.trips = next
    }
    func removeTrip(_ id: UUID) throws {
        _ = snapshot()
        let next = state.trips.filter { $0.id != id }; try tripFile.save(next); state.trips = next
    }
    func remember(_ query: String, at now: Date = Date()) throws {
        _ = snapshot()
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 500 else { return }
        let next = Array(([SearchRecord(query: clean, at: now)] + state.searches.filter { $0.query != clean }).prefix(20))
        try searchFile.save(next); state.searches = next
    }
    func removeSearch(_ query: String) throws {
        _ = snapshot()
        let next = state.searches.filter { $0.query != query }; try searchFile.save(next); state.searches = next
    }
    func saveDiagnostics(_ value: Diagnostics) throws {
        _ = snapshot(); try diagnosticFile.save([value]); state.diagnostics = value
    }
    func clear(_ kind: String) throws {
        _ = snapshot()
        switch kind {
        case "lanes": try laneFile.clear(); state.lanes = []
        case "trips": try tripFile.clear(); state.trips = []
        case "searches": try searchFile.clear(); state.searches = []
        case "diagnostics": try diagnosticFile.clear(); state.diagnostics = Diagnostics()
        default: return
        }
        // Reload errors only for files that still cannot be read.
        state.errors = []
        do { _ = try laneFile.load() } catch { state.errors.append(error.localizedDescription) }
        do { _ = try tripFile.load() } catch { state.errors.append(error.localizedDescription) }
        do { _ = try searchFile.load() } catch { state.errors.append(error.localizedDescription) }
        do { _ = try diagnosticFile.load() } catch { state.errors.append(error.localizedDescription) }
    }
}
