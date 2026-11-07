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
                                    .foregroundStyle(lane.recommended.contains(arrow) ? (history ? Theme.ink : Color.white) :
                                        (!history && !lane.recommended.isEmpty ? Color.white.opacity(0.7) : Theme.muted))
                            }
                        }
                    }
                    .padding(.horizontal, 9).frame(minWidth: 38, minHeight: 42)
                    .background(lane.recommended.isEmpty ? Theme.background : (history ? Theme.yellow : Theme.accent), in: RoundedRectangle(cornerRadius: 8))
                    .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.ink, lineWidth: 1.5) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(lane.special.isEmpty ? lane.directions.map(\.rawValue).joined(separator: "、") : lane.special)
                    .accessibilityValue(lane.recommended.isEmpty ? "未推荐" : "推荐" + lane.recommended.map(\.rawValue).joined(separator: "、"))
                }
            }
        }
    }
}

struct DemoView: View {
    @State private var traveled = 0.0
    @State private var missing = false
    @State private var playing = false
    @Environment(\.scenePhase) private var phase
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("先看清，再选道。").font(.system(.title2, design: .rounded, weight: .black))
                    Spacer(); PopBadge(title: "虚构演示", fill: Theme.pink).rotationEffect(.degrees(3))
                }
                Text("这是一条虚构路线，不代表真实道路，也不会写入车道或导航历史。")
                    .font(.subheadline).foregroundStyle(Theme.muted)
                LaneLayoutDemo(rows: DemoScenario.rows(traveled: traveled, count: 3, missing: missing))
                Text("保留当前提示，下面再看两处。未来车道有匹配历史才显示；没有数据时保留提示位。")
                    .font(.caption).foregroundStyle(Theme.muted)
                Card(fill: Theme.cyan) {
                    HStack { Text("路线进度").font(.headline); Spacer(); Text(Theme.distance(traveled)).monospacedDigit().foregroundStyle(Theme.accent) }
                    Slider(value: $traveled, in: 0...DemoScenario.total).accessibilityLabel("演示路线进度")
                    HStack {
                        Button(playing ? "暂停" : "自动回放", systemImage: playing ? "pause.fill" : "play.fill") {
                            if traveled >= DemoScenario.total { traveled = 0 }; playing.toggle()
                        }.buttonStyle(PopButtonStyle(fill: Theme.yellow, compact: true))
                        Spacer()
                        Button("下一引导点") {
                            traveled = min(DemoScenario.total, ([420.0, 760, 1_180, 1_650].first { $0 > traveled } ?? DemoScenario.total) + 1)
                        }.buttonStyle(PopButtonStyle(fill: Theme.card, compact: true))
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
