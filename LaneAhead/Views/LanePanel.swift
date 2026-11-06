import SwiftUI

struct LaneStrip: View {
    var lanes: [Lane]
    var history = false
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(Array(lanes.enumerated()), id: \.offset) { _, lane in
                    HStack(spacing: 1) {
                        if lane.directions.isEmpty { Text(lane.special).font(.caption2) }
                        else {
                            ForEach(lane.directions, id: \.self) { arrow in
                                Text(arrow.rawValue).font(.system(size: 25, weight: .bold))
                                    .foregroundStyle(lane.recommended.contains(arrow) ? (history ? Theme.amber : Theme.lime) : Theme.muted.opacity(0.6))
                            }
                        }
                    }
                    .padding(.horizontal, 9).frame(minWidth: 38, minHeight: 42)
                    .background(lane.recommended.isEmpty ? Color.white.opacity(0.04) : (history ? Theme.amber : Theme.lime).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(lane.special.isEmpty ? lane.directions.map(\.rawValue).joined(separator: "、") : lane.special)
                    .accessibilityValue(lane.recommended.isEmpty ? "未推荐" : "推荐" + lane.recommended.map(\.rawValue).joined(separator: "、"))
                }
            }
        }
    }
}

struct LanePanel: View {
    var rows: [PreviewRow]
    var live: [Lane] = []
    var status: String
    @Binding var count: Int
    @State private var expanded = true
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("前方车道", systemImage: "arrow.triangle.branch").font(.headline)
                Spacer()
                if expanded {
                    Button("\(count) 个") { count = count == 3 ? 2 : 3 }.font(.caption.bold()).buttonStyle(.bordered)
                }
                Button { expanded.toggle() } label: { Image(systemName: expanded ? "chevron.up" : "chevron.down") }
                    .accessibilityLabel(expanded ? "收起车道面板" : "展开车道面板")
            }
            if expanded {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text("\(index + 1)").font(.caption.bold()).foregroundStyle(Theme.background)
                                .frame(width: 22, height: 22).background(Theme.lime, in: Circle())
                            Text(Theme.distance(row.distance) + " · " + row.point.action).font(.subheadline.bold())
                            Spacer(minLength: 2)
                            Text(row.source.rawValue).font(.system(size: 10, weight: .medium))
                                .foregroundStyle(row.source == .history ? Theme.amber : Theme.muted)
                        }
                        Text(row.point.road).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                        if let observation = row.observation {
                            HStack(spacing: 4) {
                                Text("观测于"); Text(observation.recordedAt, format: .dateTime.year().month().day())
                                if observation.needsRefresh(at: Date()) { Text("· 待更新") }
                            }.font(.caption2).foregroundStyle(Theme.amber)
                        }
                        if row.lanes.isEmpty { Text("暂无车道数据").font(.caption).foregroundStyle(Theme.muted).padding(.vertical, 5) }
                        else { LaneStrip(lanes: row.lanes, history: row.source == .history) }
                    }
                    if index < rows.count - 1 { Divider().overlay(Theme.muted.opacity(0.2)) }
                }
                if !live.isEmpty {
                    Text("当前实时车道 · 未关联引导点").font(.caption2).foregroundStyle(Theme.muted)
                    LaneStrip(lanes: live)
                }
                Text(status).font(.caption2).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(17).background(Theme.card.opacity(0.97), in: RoundedRectangle(cornerRadius: 22))
    }
}

struct DemoView: View {
    @State private var traveled = 0.0
    @State private var count = 3
    @State private var missing = false
    @State private var playing = false
    @Environment(\.scenePhase) private var phase
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("先看清，再选道。").font(.title2.bold())
                    Spacer(); Text("虚构演示").font(.caption.bold()).padding(8).background(Theme.amber.opacity(0.12), in: Capsule()).foregroundStyle(Theme.amber)
                }
                Text("这是一条虚构路线，不代表真实道路，也不会写入车道或导航历史。")
                    .font(.subheadline).foregroundStyle(Theme.muted)
                LanePanel(rows: DemoScenario.rows(traveled: traveled, count: count, missing: missing),
                    status: traveled >= 1_650 ? "演示引导点已通过" : "虚构路线 · 车道由左向右排列", count: $count)
                Card {
                    HStack { Text("路线进度").font(.headline); Spacer(); Text(Theme.distance(traveled)).monospacedDigit().foregroundStyle(Theme.lime) }
                    Slider(value: $traveled, in: 0...DemoScenario.total).accessibilityLabel("演示路线进度")
                    HStack {
                        Button(playing ? "暂停" : "自动回放", systemImage: playing ? "pause.fill" : "play.fill") {
                            if traveled >= DemoScenario.total { traveled = 0 }; playing.toggle()
                        }.buttonStyle(.bordered)
                        Spacer()
                        Button("下一引导点") {
                            traveled = min(DemoScenario.total, ([420.0, 760, 1_180, 1_650].first { $0 > traveled } ?? DemoScenario.total) + 1)
                        }.buttonStyle(.bordered)
                    }
                    Toggle("演示缺少车道数据", isOn: $missing).font(.subheadline)
                    Button("重新开始") { traveled = 0; playing = false }.font(.subheadline)
                }
            }.padding(20)
        }
        .background(Theme.background).navigationTitle("车道演示").navigationBarTitleDisplayMode(.inline)
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                if playing && phase == .active {
                    traveled = min(DemoScenario.total, traveled + 5)
                    if traveled >= DemoScenario.total { playing = false }
                }
            }
        }
        .onChange(of: phase) { _, value in if value != .active { playing = false } }
    }
}
