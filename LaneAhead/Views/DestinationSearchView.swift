import SwiftUI

struct DestinationSearchView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    var onSelect: ((Place) -> Void)?
    @State private var query = ""
    @State private var scopeCity = ""
    @State private var automatic = true
    @State private var showScope = false
    @State private var searching = false
    @State private var searched = false
    @State private var result: SearchOutcome?
    @State private var message = ""
    @State private var request: Task<Void, Never>?
    @State private var revision = 0
    @FocusState private var focused: Bool

    private var queryBinding: Binding<String> {
        Binding(get: { query }, set: { cancel(); query = $0; result = nil; searched = false; message = "" })
    }
    private var cityBinding: Binding<String> {
        Binding(get: { scopeCity }, set: { cancel(); scopeCity = $0; automatic = false; result = nil; searched = false })
    }
    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.lime)
                    TextField("地点、地址或“北京 望京花园”", text: queryBinding)
                        .submitLabel(.search).focused($focused).onSubmit { search() }
                        .accessibilityIdentifier("search.query")
                    if searching { ProgressView() }
                }
                Button("搜索") { search() }.disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !app.canSearch)
                DisclosureGroup("搜索范围", isExpanded: $showScope) {
                    TextField("城市，例如：北京市", text: cityBinding)
                    Toggle("自动范围，必要时搜索去过的城市", isOn: Binding(get: { automatic }, set: {
                        cancel(); automatic = $0
                        if $0 { scopeCity = app.city; if scopeCity.isEmpty { app.resolveCity() } }
                    })).font(.footnote)
                    Button("恢复当前位置城市") {
                        cancel(); automatic = true; scopeCity = app.city; app.resolveCity()
                    }
                }
                if let result, result.explicit || result.fallback {
                    Label("搜索城市：" + result.city, systemImage: "building.2").font(.caption).foregroundStyle(Theme.lime)
                }
                if !message.isEmpty { Text(message).font(.footnote).foregroundStyle(Theme.amber) }
            }
            if !app.canSearch {
                Text(app.platformMessage).foregroundStyle(Theme.muted)
            } else if !searched && !searching {
                let frequent = SearchLogic.frequent(app.snapshot.trips)
                if !frequent.isEmpty {
                    Section("常去地点") {
                        ForEach(frequent) { place in
                            Button {
                                cancel()
                                query = place.city.isEmpty ? place.name : place.city + " " + place.name
                                if place.city.isEmpty { showScope = true; automatic = false; scopeCity = ""; message = "请先确认这个地点的城市，再搜索并核对地址" }
                                else { search() }
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack { Text(place.name).foregroundStyle(.primary); Spacer(); Text("到达 \(place.visits) 次").font(.caption).foregroundStyle(Theme.lime) }
                                    Text(place.city + " " + place.address).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                        }
                    }
                }
                if !app.snapshot.searches.isEmpty {
                    Section("最近搜索") {
                        ForEach(app.snapshot.searches) { record in
                            Button { query = record.query; search() } label: {
                                Label(record.query, systemImage: "clock").foregroundStyle(.primary)
                            }
                            .swipeActions { Button("删除", role: .destructive) { Task { await app.removeSearch(record.query) } } }
                        }
                        Button("清空搜索记录", role: .destructive) { confirmClear = true }
                    }
                }
            }
            if let result {
                Section("搜索结果") {
                    if result.places.isEmpty {
                        Text("没有找到相关地点，试试其他关键词或搜索范围。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(result.places) { place in
                        Button {
                            cancel()
                            if let onSelect { onSelect(place) } else { app.select(place) }
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "mappin.circle.fill").font(.title2).foregroundStyle(Theme.lime)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(place.name).font(.headline).foregroundStyle(.primary)
                                    Text(place.address).font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 5)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden).background(Theme.background)
        .navigationTitle("搜索目的地").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        .onAppear {
            app.homeVisibility(false); scopeCity = app.city
            if scopeCity.isEmpty { app.resolveCity() }
            Task { await app.refresh() }
        }
        .onDisappear { cancel() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in cancel() }
        .onChange(of: app.city) { _, city in if automatic && scopeCity.isEmpty { scopeCity = city } }
        .confirmationDialog("清空本机搜索记录？导航和车道历史会继续保留。", isPresented: $confirmClear) {
            Button("清空搜索记录", role: .destructive) { Task { await app.clear("searches") } }
        }
    }
    @State private var confirmClear = false
    private func cancel() { revision += 1; request?.cancel(); request = nil; searching = false }
    private func search() {
        guard app.canSearch else { return }
        cancel(); focused = false; result = nil; searched = false; searching = true; message = ""
        let current = revision, keyword = query, city = scopeCity, auto = automatic
        request = Task {
            do {
                let outcome = try await SearchLogic.search(query: keyword, city: city, automatic: auto, trips: app.snapshot.trips,
                    request: { keyword, city in try await AMapQueries.search(keyword: keyword, city: city) },
                    onFallback: { city in message = "正在去过的城市查找：" + city })
                guard !Task.isCancelled, current == revision else { return }
                result = outcome; searched = true
                message = outcome.warning.isEmpty ? (!outcome.matched && outcome.checked > 0 ? "未找到名称匹配地点，以下为相关结果" : "") : outcome.warning
                await app.rememberSearch(keyword)
            } catch {
                if !Task.isCancelled && current == revision {
                    message = error.localizedDescription
                    if city.isEmpty { showScope = true }
                }
            }
            if current == revision { searching = false }
        }
    }
}

struct SpecifiedRouteView: View {
    @EnvironmentObject private var app: AppModel
    @State private var start: Place?
    @State private var end: Place?
    @State private var choosingStart = true
    @State private var search = false
    var body: some View {
        Form {
            Section("指定起终点") {
                Button { choosingStart = true; search = true } label: { LabeledContent("起点", value: start?.name ?? "选择起点") }
                Button { choosingStart = false; search = true } label: { LabeledContent("终点", value: end?.name ?? "选择终点") }
                Button("规划驾车路线") { if let start, let end { app.select(end); app.plan(from: start) } }
                    .disabled(start == nil || end == nil)
            }
            Section {
                Text("指定起点用于规划预览。真实 GPS 导航会从你当前的位置重新规划，不使用虚构位置。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("指定起点规划")
        .sheet(isPresented: $search) {
            NavigationStack { DestinationSearchView(onSelect: { place in if choosingStart { start = place } else { end = place } }) }
        }
    }
}
