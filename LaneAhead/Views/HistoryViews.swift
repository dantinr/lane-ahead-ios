import SwiftUI

struct MyView: View {
    @EnvironmentObject private var app: AppModel
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("走过的路，留在这里。").font(.system(.title2, design: .rounded, weight: .black))
                    HStack(spacing: 30) {
                        summary("导航", app.snapshot.trips.count)
                        summary("已到达", app.snapshot.trips.filter { $0.status == .arrived }.count)
                        summary("车道记录", app.snapshot.lanes.count)
                    }
                }.padding(.vertical, 12)
            }
            Section {
                NavigationLink { TripHistoryView() } label: { Label("导航历史", systemImage: "clock.arrow.circlepath") }
                    .accessibilityIdentifier("my.trips")
                NavigationLink { LaneRecordsView() } label: { Label("车道记录", systemImage: "arrow.triangle.branch") }
                    .accessibilityIdentifier("my.lanes")
                NavigationLink { DiagnosticsView() } label: { Label("车道采集诊断", systemImage: "waveform.path.ecg") }
                    .accessibilityIdentifier("my.diagnostics")
            }
            Section {
                Text("导航历史、搜索记录与车道缓存分别保存在本机。应用不上传这些历史，不记录完整行驶轨迹。")
                    .font(.footnote).foregroundStyle(.secondary)
                if !app.snapshot.errors.isEmpty { ForEach(app.snapshot.errors, id: \.self) { Text($0).foregroundStyle(Theme.amber).font(.footnote) } }
                if !app.storageError.isEmpty { Text(app.storageError).foregroundStyle(Theme.amber).font(.footnote) }
            }
        }
        .scrollContentBackground(.hidden).background(Theme.background).navigationTitle("我的")
        .task { await app.refresh() }
        .refreshable { await app.refresh() }
    }
    private func summary(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)").font(.system(size: 28, weight: .semibold, design: .rounded)).foregroundStyle(Theme.accent)
            Text(label).font(.caption).foregroundStyle(Theme.muted)
        }
    }
}

struct TripHistoryView: View {
    @EnvironmentObject private var app: AppModel
    @State private var clear = false
    var body: some View {
        List {
            Section {
                Text("最近 200 次真实 GPS 导航。时长包含停留，里程为出发时的规划里程。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if app.snapshot.trips.isEmpty {
                ContentUnavailableView("还没有导航历史", systemImage: "point.topleft.down.to.point.bottomright.curvepath", description: Text("真正开始 GPS 导航后会自动记录。车道演示不会创建行程。"))
                    .listRowBackground(Color.clear)
            }
            ForEach(app.snapshot.trips) { trip in
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text(trip.destination).font(.headline)
                        Spacer(); Text(trip.status.label).font(.caption).foregroundStyle(trip.status == .arrived ? Theme.accent : Theme.amber)
                    }
                    Text(trip.address).font(.caption).foregroundStyle(.secondary)
                    Text("出发：" + trip.startedAt.formatted(date: .numeric, time: .shortened)).font(.caption)
                    if let end = trip.endedAt {
                        Text("结束：" + end.formatted(date: .numeric, time: .shortened) + " · \(Int(end.timeIntervalSince(trip.startedAt) / 60)) 分钟").font(.caption)
                    } else { Text("结束时间及完整时长未记录").font(.caption).foregroundStyle(.secondary) }
                    if trip.plannedMeters > 0 { Text("出发时规划里程：" + Theme.distance(trip.plannedMeters)).font(.caption).foregroundStyle(Theme.muted) }
                }.padding(.vertical, 7)
                    .swipeActions { Button("删除", role: .destructive) { Task { await app.removeTrip(trip.id) } } }
            }
            if !app.snapshot.trips.isEmpty { Button("清空导航历史", role: .destructive) { clear = true } }
        }
        .scrollContentBackground(.hidden).background(Theme.background)
        .navigationTitle("导航历史").navigationBarTitleDisplayMode(.inline)
        .task { await app.refresh() }.refreshable { await app.refresh() }
        .confirmationDialog("清空导航历史？车道数据与搜索记录会继续保留。", isPresented: $clear) {
            Button("清空导航历史", role: .destructive) { Task { await app.clear("trips") } }
        }
    }
}

struct LaneRecordsView: View {
    @EnvironmentObject private var app: AppModel
    @State private var dueOnly = false
    private var records: [LaneObservation] { app.snapshot.lanes.filter { !dueOnly || $0.needsRefresh(at: Date()) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("记录范围", selection: $dueOnly) { Text("全部").tag(false); Text("待更新").tag(true) }.pickerStyle(.segmented)
                Text("共 \(app.snapshot.lanes.count) 条 · 待更新 \(app.snapshot.lanes.filter { $0.needsRefresh(at: Date()) }.count) 条")
                    .font(.subheadline).foregroundStyle(Theme.accent)
                Text("长期保存在本机，满 3 个月建议更新。道路方向不代表完整物理路口清单。")
                    .font(.caption).foregroundStyle(Theme.muted)
                if records.isEmpty {
                    ContentUnavailableView(dueOnly ? "暂无待更新记录" : "还没有车道记录", systemImage: "arrow.triangle.branch",
                        description: Text(dueOnly ? "再次导航收到有效车道时会更新观测日期。" : "真实导航中收到并成功关联红绿灯引导点的车道后，会显示在这里。"))
                }
                ForEach(records) { record in
                    Card {
                        Text(record.road.isEmpty ? "道路名称暂不可用" : record.road).font(.headline)
                        LaneStrip(lanes: record.lanes, history: true)
                        HStack {
                            Text(record.recordedAt, format: .dateTime.year().month().day().hour().minute())
                            Spacer()
                            Text(record.needsRefresh(at: Date()) ? "待更新" : "历史参考").fontWeight(.bold)
                        }.font(.caption).foregroundStyle(Theme.amber)
                    }
                }
            }.padding(20)
        }
        .background(Theme.background).navigationTitle("车道记录").navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("刷新") { Task { await app.refresh() } } }
        .task { await app.refresh() }.refreshable { await app.refresh() }
    }
}

struct DiagnosticsView: View {
    @EnvironmentObject private var app: AppModel
    var body: some View {
        List {
            Section("最近一次导航") {
                LabeledContent("收到回调", value: "\(app.diagnostics.received)")
                LabeledContent("有效解码", value: "\(app.diagnostics.decoded)")
                LabeledContent("关联采集", value: "\(app.diagnostics.accepted)")
                LabeledContent("本次文件写入", value: "\(app.diagnostics.writes)")
                LabeledContent("冲突撤销", value: "\(app.diagnostics.removals)")
                LabeledContent("本机历史", value: "\(app.snapshot.lanes.count)")
                Text(app.diagnostics.reason).font(.footnote).foregroundStyle(Theme.amber)
            }
            Section {
                Text("统计属于最近一次真实导航。文件写入包含更新和撤销，不等于路口数量。仅保留最近 60 条状态事件，不记录道路、坐标、路线标识或 Key。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("状态事件") {
                if app.diagnostics.events.isEmpty { Text("暂无事件").foregroundStyle(.secondary) }
                ForEach(app.diagnostics.events.reversed()) { event in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(event.message).font(.subheadline)
                        Text(event.at, style: .time).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden).background(Theme.background)
        .navigationTitle("采集诊断").navigationBarTitleDisplayMode(.inline)
        .task { await app.refresh() }.refreshable { await app.refresh() }
    }
}
