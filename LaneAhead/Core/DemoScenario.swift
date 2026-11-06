import Foundation

enum DemoScenario {
    static let total = 1_800.0
    static func rows(traveled: Double, count: Int, missing: Bool) -> [PreviewRow] {
        let turns: [[Arrow]] = [[.ahead], [.left], [.right], [.ahead]]
        let names = ["梧桐路 → 湖畔路", "湖畔路 → 青禾街", "青禾街 → 星河路", "星河路 → 演示终点"]
        return [420.0, 760, 1_180, 1_650].enumerated().filter { $0.element > traveled }.prefix(count).map { i, end in
            let recommended = turns[i]
            let lanes = [Lane(directions: [.left], recommended: recommended == [.left] ? [.left] : []),
                Lane(directions: [.ahead], recommended: recommended == [.ahead] ? [.ahead] : []),
                Lane(directions: [.ahead, .right], recommended: recommended == [.right] ? [.right] : [])]
            let point = GuidancePoint(index: i, endMeters: end, road: names[i],
                action: recommended[0] == .left ? "左转" : recommended[0] == .right ? "右转" : "直行",
                key: "demo-\(i)", learnable: false, reason: "虚构演示不写入历史")
            return PreviewRow(point: point, distance: end - traveled, lanes: missing && i == 1 ? [] : lanes, source: .demo)
        }
    }
}
