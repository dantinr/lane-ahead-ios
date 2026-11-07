import Foundation

enum LaneMutation: Sendable { case save(LaneObservation), remove(String) }

final class LaneEngine {
    private(set) var points: [GuidancePoint] = []
    private(set) var routeID = ""
    private(set) var diagnostics = Diagnostics()
    private(set) var history: [String: LaneObservation] = [:]
    private var step = -1
    private var traveled = 0.0
    private var positionAt: Date?
    private var liveAt: Date?
    private var live: [Lane] = []
    private var suspended = "等待实时导航"
    private var signature = ""
    private var recommendation = ""
    private var turns: Set<Arrow> = []
    private var savedSignature = ""
    private var conflict = false
    private(set) var mutations: [LaneMutation] = []

    func begin(history: [LaneObservation], at now: Date) {
        self.history = Dictionary(history.map { ($0.key, $0) }, uniquingKeysWith: { _, latest in latest })
        diagnostics = Diagnostics(startedAt: now)
        mutations = []
    }

    func setRoute(_ id: String, points: [GuidancePoint], at now: Date) {
        suspend("路线更新，等待当前路线位置", at: now)
        routeID = id; self.points = points; step = -1; resetStep()
    }

    private func resetStep() {
        signature = ""; recommendation = ""; savedSignature = ""; turns = []; conflict = false
        live = []; liveAt = nil
    }

    func suspend(_ reason: String, at now: Date) {
        suspended = reason; positionAt = nil; liveAt = nil; live = []
        diagnostics.report("suspended", reason, at: now)
    }

    func hide(at now: Date) {
        live = []; liveAt = nil
        diagnostics.report("hidden", "实时车道已隐藏，等待新回调", at: now)
    }
    func blockedCallback(at now: Date) {
        diagnostics.received += 1
        diagnostics.report("callback_blocked", "定位或路线不可靠，收到的车道未采集", at: now)
    }

    func progress(route: String, step: Int, remaining: Double, at now: Date, realtime: Bool) {
        guard realtime, route == routeID, let point = points.first(where: { $0.index == step }),
              step >= 0, remaining.isFinite, remaining >= 0 else {
            suspend(realtime ? "路线位置未匹配，暂停采集" : "模拟导航不记录车道", at: now); return
        }
        let previous = step == 0 ? 0 : points.first(where: { $0.index == step - 1 })?.endMeters
        guard let previous, remaining <= point.endMeters - previous + 30 else {
            suspend("路段距离无效，暂停采集", at: now); return
        }
        if self.step != step { resetStep() }
        else if let positionAt, let liveAt, now.timeIntervalSince(positionAt) <= 5,
                now.timeIntervalSince(liveAt) <= 15 { self.liveAt = now }
        self.step = step; traveled = point.endMeters - remaining; positionAt = now; suspended = ""
    }

    func receive(_ lanes: [Lane], at now: Date) {
        diagnostics.received += 1
        guard Lane.valid(lanes) else {
            live = []; liveAt = nil; diagnostics.report("invalid", "实时车道为空或不完整", at: now); return
        }
        diagnostics.decoded += 1
        guard let positionAt, (0...2.5).contains(now.timeIntervalSince(positionAt)), suspended.isEmpty else {
            live = []; liveAt = nil
            diagnostics.report("no_position", "缺少 2.5 秒内有效路线位置，未保存", at: now); return
        }
        let nextSignature = lanes.map(\.structure).joined(separator: "|")
        let nextRecommendation = lanes.map { $0.recommended.map(\.rawValue).sorted().joined() }.joined(separator: "|")
        let nextTurns = Set(lanes.flatMap(\.recommended))
        let point = points.first { $0.index == step }
        if !signature.isEmpty && (nextSignature != signature || nextTurns != turns) {
            conflict = true
            if let point, history.removeValue(forKey: point.key) != nil {
                mutations.append(.remove(point.key)); diagnostics.removals += 1
            }
        }
        signature = nextSignature; recommendation = nextRecommendation; turns = nextTurns
        live = lanes; liveAt = now
        guard !conflict else { diagnostics.report("conflict", "同一路段车道结构或转向冲突，已撤销历史", at: now); return }
        guard let point, point.learnable else {
            diagnostics.report("unlearnable", point?.reason ?? "缺少引导点，未保存", at: now); return
        }
        let combined = signature + "/" + recommendation
        guard combined != savedSignature else { return }
        let record = LaneObservation(key: point.key, recordedAt: now, road: point.road, lanes: lanes)
        guard record.valid(at: now) else { return }
        history[point.key] = record; mutations.append(.save(record)); savedSignature = combined
        diagnostics.accepted += 1
        diagnostics.report("accepted", "已关联红绿灯引导点，立即保存车道", at: now)
    }

    func drainMutations() -> [LaneMutation] { defer { mutations = [] }; return mutations }
    func persisted(_ success: Bool, at now: Date) {
        if success { diagnostics.writes += 1 }
        else { diagnostics.report("write_failed", "车道写入失败，保留内存记录并等待重试", at: now) }
    }
    func finish(at now: Date) { suspend("导航已结束", at: now); diagnostics.endedAt = now }

    func preview(count: Int, at now: Date) -> (rows: [PreviewRow], upcoming: [PreviewRow], live: [Lane], status: String) {
        guard suspended.isEmpty, let positionAt, (0...15).contains(now.timeIntervalSince(positionAt)) else {
            return ([], [], [], suspended.isEmpty ? "定位更新中，暂不提示车道" : suspended)
        }
        let fresh = liveAt.map { (0...15).contains(now.timeIntervalSince($0)) } ?? false
        let rows = points.filter { $0.index >= step && $0.action != "到达终点" }.prefix(count == 2 ? 2 : 3).map { point in
            let distance = max(0, point.endMeters - traveled)
            if fresh && point.index == step && point.learnable && !conflict && distance <= 200 {
                return PreviewRow(point: point, distance: distance, lanes: live, source: .live)
            }
            if point.learnable, !(point.index == step && conflict), let record = history[point.key], record.recordedAt <= now {
                return PreviewRow(point: point, distance: distance, lanes: record.lanes, source: .history, observation: record)
            }
            return PreviewRow(point: point, distance: distance, lanes: [], source: .unknown)
        }
        // The SDK owns the current lane strip. Extra slots must only contain later
        // guidance points, including unknown ones, so gaps never shift their order.
        return (rows, rows.filter { $0.point.index > step }, fresh && !rows.contains(where: { $0.source == .live }) ? live : [],
            rows.isEmpty ? "即将到达终点" : "仅覆盖导航引导点，部分直行路口可能缺失")
    }
}
