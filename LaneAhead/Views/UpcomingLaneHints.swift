import SwiftUI

/// Leaves the SDK's current lane strip in place and adds exactly two later points.
struct NavigationLaneOverlay: View {
    var rows: [PreviewRow]
    var waiting: Bool
    var status: String

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            UpcomingLaneHints(rows: rows, waiting: waiting, status: status)
                .frame(width: landscape ? 174 : min(196, geometry.size.width * 0.46))
                // The public SDK has no lane-view frame API. Reserve its standard
                // turn card + current strip; never inspect or reparent SDK subviews.
                .position(x: landscape ? 112 : geometry.size.width / 2,
                    y: (landscape ? 138 : 218) + 62)
        }
        .allowsHitTesting(false)
    }
}

struct UpcomingLaneHints: View {
    var rows: [PreviewRow]
    var waiting = false
    var status = ""

    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<2, id: \.self) { offset in
                CompactLaneHint(row: rows.indices.contains(offset) ? rows[offset] : nil,
                    title: offset == 0 ? "下一处" : "再下一处", waiting: waiting)
                    .accessibilityIdentifier("lane.hint.\(offset + 2)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint(status)
        .dynamicTypeSize(.small ... .large)
    }
}

private struct CompactLaneHint: View {
    var row: PreviewRow?
    var title: String
    var waiting: Bool

    private var hasLanes: Bool { row.map { Lane.valid($0.lanes) } ?? false }
    private var history: Bool { row?.source == .history }
    private var source: String {
        guard hasLanes, let row else { return "" }
        if history { return row.observation?.needsRefresh(at: Date()) == true ? "历史·待更新" : "历史参考" }
        return row.source.rawValue
    }
    private var emptyText: String {
        row != nil ? "暂无车道数据" : waiting ? "等待路线位置" : "后续无引导点"
    }
    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Text(title).fontWeight(.bold)
                if let row { Text(Theme.distance(row.distance)).monospacedDigit() }
                Spacer(minLength: 0)
                if !source.isEmpty { Text(source).foregroundStyle(history ? Theme.amber : Theme.accent) }
            }
            .font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.85)
            if hasLanes, let row {
                CompactLaneArrows(lanes: row.lanes, history: history)
            } else {
                Text(emptyText).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 29)
            }
        }
        .padding(.horizontal, 7).padding(.vertical, 5)
        .frame(height: 58)
        .background {
            RoundedRectangle(cornerRadius: 6).fill(Theme.card.opacity(0.96))
                .shadow(color: Theme.ink.opacity(0.18), radius: 0, x: 2, y: 2)
        }
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(history ? Theme.amber : Theme.accent, lineWidth: 1.5) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        guard let row else { return emptyText }
        let prefix = Theme.distance(row.distance) + "，" + row.point.road + "，" + row.point.action + "，"
        guard hasLanes else { return prefix + emptyText }
        return prefix + source + "，从左到右，" + row.lanes.map { lane in
            let directions = lane.special.isEmpty ? lane.directions.map(\.rawValue).joined() : lane.special
            return directions + (lane.recommended.isEmpty ? "未推荐" : "推荐" + lane.recommended.map(\.rawValue).joined())
        }.joined(separator: "，")
    }
}

struct CompactLaneArrows: View {
    var lanes: [Lane]
    var history = false

    var body: some View {
        // Fit every lane into the strip, including wide roads; none are scrolled
        // off screen or silently omitted. Branches retain individual emphasis.
        HStack(spacing: 1) {
            ForEach(Array(lanes.enumerated()), id: \.offset) { _, lane in
                HStack(spacing: 0) {
                    if lane.directions.isEmpty {
                        Text(lane.special).font(.system(size: 9, weight: .bold))
                    } else {
                        ForEach(lane.directions, id: \.self) { arrow in
                            Text(arrow.rawValue).font(.system(size: 25, weight: .black))
                                .foregroundStyle(lane.recommended.contains(arrow) ? (history ? Theme.ink : .white) :
                                    (lane.recommended.isEmpty ? Theme.muted : (history ? Theme.ink.opacity(0.45) : .white.opacity(0.55))))
                        }
                    }
                }
                .lineLimit(1).minimumScaleFactor(0.2)
                .frame(maxWidth: .infinity, minHeight: 29)
                .background(lane.recommended.isEmpty ? Theme.background : (history ? Theme.yellow : Theme.accent),
                    in: RoundedRectangle(cornerRadius: 3))
            }
        }
    }
}

/// A schematic for checking the same two slots without starting GPS navigation.
/// The first strip here is a demo stand-in; the real page keeps the SDK's strip.
struct LaneLayoutDemo: View {
    var rows: [PreviewRow]
    var body: some View {
        ZStack(alignment: .top) {
            Theme.cyan.opacity(0.28)
            Canvas { context, size in
                for x in stride(from: 0.0, to: Double(size.width), by: 45) {
                    var line = Path(); line.move(to: CGPoint(x: x, y: 0)); line.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(line, with: .color(Theme.accent.opacity(0.1)), lineWidth: 1)
                }
                for y in stride(from: 0.0, to: Double(size.height), by: 40) {
                    var line = Path(); line.move(to: CGPoint(x: 0, y: y)); line.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(line, with: .color(Theme.accent.opacity(0.1)), lineWidth: 1)
                }
                let road = Path(CGRect(x: size.width / 2 - 12, y: 0, width: 24, height: size.height))
                context.fill(road, with: .color(.white))
                context.fill(Path(CGRect(x: size.width / 2 - 8, y: 0, width: 16, height: size.height)), with: .color(Theme.accent))
            }
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Text(rows.first?.point.action == "左转" ? "↰" : rows.first?.point.action == "右转" ? "↱" : "↑")
                        .font(.system(size: 42, weight: .black))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rows.first.map { Theme.distance($0.distance) + " · " + $0.point.action } ?? "演示结束")
                            .font(.headline.bold())
                        Text(rows.first?.point.road ?? "已通过全部演示点").font(.caption)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white).padding(13).background(Theme.ink, in: RoundedRectangle(cornerRadius: 9))
                VStack(spacing: 8) {
                    VStack(spacing: 3) {
                        HStack {
                            Text("当前").bold(); Spacer(); Text("演示")
                        }.font(.system(size: 10)).foregroundStyle(Theme.accent)
                        if let current = rows.first { CompactLaneArrows(lanes: current.lanes) }
                        else { Text("无当前引导点").font(.caption).frame(height: 29) }
                    }
                    .padding(.horizontal, 7).padding(.vertical, 5).frame(height: 58)
                    .background(.white, in: RoundedRectangle(cornerRadius: 6))
                    .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.accent, lineWidth: 1.5) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("当前车道（演示）")
                    .accessibilityIdentifier("lane.hint.current")
                    UpcomingLaneHints(rows: Array(rows.dropFirst()))
                }
                .frame(width: 180)
                Image(systemName: "location.north.fill").font(.title3).foregroundStyle(Theme.accent)
                    .padding(7).background(.white, in: Circle())
            }.padding(14)
        }
        .frame(height: 344).clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.ink, lineWidth: 2) }
    }
}
