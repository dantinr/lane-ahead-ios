import Foundation

struct Coordinate: Codable, Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    var valid: Bool {
        latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180 &&
        !(latitude == 0 && longitude == 0)
    }
    var key: String { String(format: "%.6f,%.6f", locale: Locale(identifier: "en_US_POSIX"), latitude, longitude) }
}

struct Place: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var address: String
    var city: String
    var latitude: Double
    var longitude: Double
    var coordinate: Coordinate { Coordinate(latitude: latitude, longitude: longitude) }
}

enum Arrow: String, Codable, CaseIterable, Sendable {
    case ahead = "↑", left = "←", right = "→", leftUTurn = "↶", rightUTurn = "↷"
}

struct Lane: Codable, Equatable, Sendable {
    var directions: [Arrow]
    var recommended: [Arrow]
    var special: String = ""
    var valid: Bool {
        (!directions.isEmpty || !special.isEmpty) && directions.count <= 5 && special.count <= 12 &&
        Set(directions).count == directions.count && Set(recommended).count == recommended.count &&
        recommended.allSatisfy { directions.contains($0) }
    }
    static func valid(_ lanes: [Lane]) -> Bool { (1...16).contains(lanes.count) && lanes.allSatisfy(\.valid) }
    var structure: String { directions.map(\.rawValue).sorted().joined() + ":" + special }
}

struct RouteLink: Codable, Sendable {
    var length: Double
    var road: String
    var signal: Bool
    var internalRoad: Bool
    var coordinates: [Coordinate]
}

struct RouteSegment: Codable, Sendable {
    var index: Int
    var length: Double
    var icon: Int
    var signals: Int
    var coordinates: [Coordinate]
    var links: [RouteLink]
    var road: String { links.reversed().first(where: { !$0.road.isEmpty })?.road ?? "未命名道路" }
}

struct RouteChoice: Codable, Identifiable, Equatable, Sendable {
    var id: Int
    var meters: Double
    var seconds: Double
    var label: String
}

struct GuidancePoint: Codable, Identifiable, Sendable {
    var index: Int
    var endMeters: Double
    var road: String
    var action: String
    var key: String
    var learnable: Bool
    var reason: String
    var id: String { key }
}

struct LaneObservation: Codable, Identifiable, Equatable, Sendable {
    var key: String
    var recordedAt: Date
    var road: String
    var lanes: [Lane]
    var id: String { key }
    func needsRefresh(at now: Date, calendar: Calendar = .current) -> Bool {
        guard let due = calendar.date(byAdding: .month, value: 3, to: recordedAt) else { return false }
        return now >= due
    }
    func valid(at now: Date) -> Bool {
        !key.isEmpty && key.count <= 4096 && recordedAt.timeIntervalSince1970.isFinite &&
        recordedAt.timeIntervalSince1970 >= 0 && recordedAt <= now && road.count <= 500 && Lane.valid(lanes)
    }
}

enum TripStatus: String, Codable, Sendable {
    case navigating, arrived, ended, interrupted, failed
    var label: String {
        switch self {
        case .navigating: return "导航中"
        case .arrived: return "已到达"
        case .ended: return "已结束"
        case .interrupted: return "未正常结束"
        case .failed: return "导航异常结束"
        }
    }
}

// No coordinates or route trace are persisted in navigation/search history.
struct Trip: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var destination: String
    var address: String
    var city: String
    var startedAt: Date
    var endedAt: Date?
    var plannedMeters: Double
    var status: TripStatus = .navigating
    var valid: Bool {
        !destination.isEmpty && destination.count <= 240 && address.count <= 500 && city.count <= 80 &&
        startedAt.timeIntervalSince1970.isFinite && startedAt.timeIntervalSince1970 >= 0 &&
        plannedMeters.isFinite && (0...100_000_000).contains(plannedMeters) &&
        (endedAt == nil || (endedAt!.timeIntervalSince1970.isFinite && endedAt! >= startedAt)) &&
        ([.navigating, .interrupted].contains(status) ? endedAt == nil : endedAt != nil)
    }
    mutating func finish(_ next: TripStatus, at now: Date) {
        guard [.arrived, .ended, .failed].contains(next) else { return }
        guard status == .navigating || (status == .ended && next == .arrived) else { return }
        status = next
        if endedAt == nil { endedAt = max(startedAt, now) }
    }
}

struct SearchRecord: Codable, Identifiable, Equatable, Sendable {
    var query: String
    var at: Date
    var id: String { query }
}

struct FrequentPlace: Identifiable, Sendable {
    var id: String
    var name: String
    var city: String
    var address: String
    var visits: Int
    var lastArrival: Date
}

enum LaneSource: String, Sendable { case live = "实时", history = "历史参考", unknown = "暂无车道数据", demo = "虚构演示" }
struct PreviewRow: Identifiable, Sendable {
    var point: GuidancePoint
    var distance: Double
    var lanes: [Lane]
    var source: LaneSource
    var observation: LaneObservation?
    var id: String { point.key }
}

struct DiagnosticEvent: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    var at: Date
    var code: String
    var message: String
}

struct Diagnostics: Codable, Sendable {
    var version: Int = 2
    var startedAt: Date?
    var endedAt: Date?
    var received: Int = 0
    var decoded: Int = 0
    var accepted: Int = 0
    var writes: Int = 0
    var removals: Int = 0
    var events: [DiagnosticEvent] = []
    var reason: String = "等待导航"
    // Messages are application-owned fixed strings; never put coordinates, roads or keys here.
    mutating func report(_ code: String, _ message: String, at now: Date) {
        reason = message
        guard events.last?.code != code || events.last?.message != message else { return }
        events.append(DiagnosticEvent(at: now, code: code, message: message))
        events = Array(events.suffix(60))
    }
}
