import Foundation

enum RouteAdapter {
    static func maneuver(_ icon: Int) -> String {
        switch icon {
        case 2, 4, 6: return "左转"
        case 3, 5, 7: return "右转"
        case 8, 19: return "掉头"
        case 11, 17: return "进入环岛"
        case 12, 18: return "驶出环岛"
        case 15: return "到达终点"
        case 10: return "途经点"
        case 13: return "服务区"
        case 14: return "收费站"
        case 16: return "隧道"
        default: return "继续行驶"
        }
    }

    static func points(_ segments: [RouteSegment]) -> [GuidancePoint] {
        var total = 0.0
        var result: [GuidancePoint] = []
        for (i, segment) in segments.enumerated() {
            guard segment.index == i, segment.length.isFinite, segment.length >= 0 else { return [] }
            total += segment.length
            let next = i + 1 < segments.count ? segments[i + 1] : nil
            let shape = segment.coordinates.suffix(4).map(\.key) + [">"] + (next?.coordinates.prefix(4).map(\.key) ?? [])
            let road = segment.road + " → " + (next?.road ?? "终点")
            let parts = ["ios-v1", segment.road, next?.road ?? "", String(segment.icon), shape.joined(separator: ";")]
            let key = String(data: try! JSONEncoder().encode(parts), encoding: .utf8)!
            let joined = segment.coordinates.last != nil && next?.coordinates.first != nil &&
                same(segment.coordinates.last!, next!.coordinates.first!)
            let eligible = segment.signals == 1 && signalEndsAtJunction(segment) && joined &&
                segment.coordinates.count >= 2 && (next?.coordinates.count ?? 0) >= 2
            let reason = segment.signals == 0 ? "未标注信号灯，不保存车道" : segment.signals > 1 ?
                "路段包含多个信号灯，无法确认对应路口" : "信号灯与进出口几何不足，无法关联车道"
            result.append(GuidancePoint(index: i, endMeters: total, road: road, action: maneuver(segment.icon),
                key: key, learnable: eligible, reason: reason))
        }
        return result
    }

    static func same(_ a: Coordinate, _ b: Coordinate) -> Bool { a.valid && b.valid && a.key == b.key }

    static func signalEndsAtJunction(_ segment: RouteSegment) -> Bool {
        let indices = segment.links.indices.filter { segment.links[$0].signal }
        guard indices.count == 1, let index = indices.first,
              segment.links[index].coordinates.count >= 2,
              var endpoint = segment.links[index].coordinates.last else { return false }
        var meters = 0.0
        for link in segment.links.dropFirst(index + 1) {
            guard link.internalRoad, link.length.isFinite, link.length > 0, link.coordinates.count >= 2,
                  same(endpoint, link.coordinates.first!) else { return false }
            meters += link.length
            guard meters <= 60 else { return false }
            endpoint = link.coordinates.last!
        }
        return segment.coordinates.count >= 2 && same(endpoint, segment.coordinates.last!)
    }
}

enum LaneDecoder {
    // iOS SDK lane strings use their own codes, not HarmonyOS LaneAction values.
    static func directions(_ code: Int) -> [Arrow] {
        switch code {
        case 0: return [.ahead]
        case 1: return [.left]
        case 2: return [.ahead, .left]
        case 3: return [.right]
        case 4: return [.ahead, .right]
        case 5: return [.leftUTurn]
        case 6: return [.left, .right]
        case 7: return [.ahead, .left, .right]
        case 8: return [.rightUTurn]
        case 9: return [.ahead, .leftUTurn]
        case 10: return [.ahead, .rightUTurn]
        case 11: return [.left, .leftUTurn]
        case 12: return [.right, .rightUTurn]
        case 16: return [.ahead, .left, .leftUTurn]
        case 17: return [.right, .leftUTurn]
        case 18: return [.left, .leftUTurn, .right]
        case 19: return [.ahead, .right, .leftUTurn]
        case 20: return [.left, .rightUTurn]
        default: return []
        }
    }
    static func decode(background: String, selection: String) -> [Lane] {
        let back = background.split(separator: "|", omittingEmptySubsequences: false)
        let front = selection.split(separator: "|", omittingEmptySubsequences: false)
        guard (1...16).contains(back.count), back.count == front.count else { return [] }
        var lanes: [Lane] = []
        for i in back.indices {
            guard let b = Int(back[i]), let f = Int(front[i]), (0...255).contains(b), (0...255).contains(f) else { return [] }
            let arrows = directions(b)
            let label = b == 21 ? "公交" : b == 23 ? "可变" : "未识别"
            lanes.append(Lane(directions: arrows, recommended: directions(f).filter { arrows.contains($0) },
                special: arrows.isEmpty ? label : ""))
        }
        return lanes
    }
}
