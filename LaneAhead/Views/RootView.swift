import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppModel
    var body: some View {
        TabView {
            NavigationStack { HomeView() }
                .tabItem { Label("出发", systemImage: "location.north.line.fill") }
            NavigationStack { ToolsView() }
                .tabItem { Label("驾驶工具", systemImage: "gauge.with.dots.needle.50percent") }
            NavigationStack { MyView() }
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
        }
        .toolbarBackground(Theme.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .fullScreenCover(isPresented: $app.showNavigation, onDismiss: {
            app.closeNavigation(); app.homeVisibility(true)
        }) { NativeNavigationView().environmentObject(app).environmentObject(app.motion) }
    }
}

struct HomeView: View {
    @EnvironmentObject private var app: AppModel
    @State private var search = false
    @State private var settings = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("LANE AHEAD").font(.system(size: 16, weight: .black, design: .rounded)).italic().tracking(1)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Theme.yellow).overlay { Rectangle().strokeBorder(Theme.ink, lineWidth: 2) }
                            .rotationEffect(.degrees(-2))
                        Text("提前看，安心走。").font(.system(size: 29, weight: .black, design: .rounded))
                    }
                    Spacer()
                    Button { settings = true } label: { Image(systemName: "slider.horizontal.3").font(.title3.bold()) }
                        .buttonStyle(PopButtonStyle(fill: Theme.card, compact: true))
                        .accessibilityLabel("设置").accessibilityIdentifier("home.settings")
                }
                ZStack(alignment: .bottomLeading) {
                    if app.ready, let map = app.map {
                        ServiceMap(view: map.view)
                    } else {
                        RoadIllustration()
                        VStack(alignment: .leading, spacing: 15) {
                            PopBadge(title: "向前看！", fill: Theme.pink).rotationEffect(.degrees(-4))
                            Text("下一路口，\n早有准备。").font(.system(size: 33, weight: .black, design: .rounded))
                                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                            Text("当前 + 后续两个引导点\n实时车道 · 历史参考")
                                .font(.system(size: 12, weight: .semibold)).lineSpacing(3)
                        }.foregroundStyle(Theme.ink).padding(22)
                    }
                    if app.ready {
                        Button { app.recenter() } label: { Label("重新定位", systemImage: "location.fill").font(.caption.bold()) }
                            .buttonStyle(PopButtonStyle(fill: Theme.card, compact: true))
                            .padding(14)
                    }
                }
                .frame(height: 245).clipShape(RoundedRectangle(cornerRadius: 18))
                .popSurface(Theme.yellow)

                if !app.ready {
                    Card {
                        Label(app.hasKey ? "从你的位置出发" : "先认识你的下一段路", systemImage: app.hasKey ? "location.circle" : "sparkles").font(.headline)
                        Text(app.consent ? app.platformMessage : "地图、定位和导航服务将由高德处理位置、设备与网络信息。驾驶工具及虚构演示可独立使用。")
                            .font(.subheadline).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                        if !app.consent { PrimaryButton(title: "同意并定位", icon: "location.fill") { app.agree() } }
                        else if app.hasKey { Button("开启定位") { app.initializeMap() } }
                        Link("阅读高德隐私政策", destination: URL(string: "https://lbs.amap.com/pages/privacy/")!).font(.caption.bold())
                    }
                } else {
                    Button { search = true } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "magnifyingglass").font(.title3).foregroundStyle(Theme.accent)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(app.destination?.name ?? "你要去哪里？").font(.headline).foregroundStyle(Theme.ink)
                                Text(app.destination?.address ?? "搜索地点、地址").font(.caption).foregroundStyle(Theme.muted).lineLimit(2)
                            }
                            Spacer(); Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
                        }.padding(18).popSurface()
                    }
                    Text(app.locationStatus).font(.caption).foregroundStyle(Theme.muted)
                    PrimaryButton(title: "选择路线", icon: "point.topleft.down.to.point.bottomright.curvepath") { app.plan() }.disabled(!app.canNavigate)
                }
                if !app.message.isEmpty { Text(app.message).font(.footnote).foregroundStyle(Theme.amber) }
                if !app.storageError.isEmpty { Text(app.storageError).font(.footnote).foregroundStyle(Theme.amber) }
                Text("车道提示仅覆盖导航引导点。历史记录仅供参考，以实际道路标线为准。")
                    .font(.caption).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }.padding(22)
        }
        .background(Theme.background).toolbar(.hidden, for: .navigationBar)
        .onAppear { app.homeVisibility(true); if app.consent { app.initializeMap() } }
        .onDisappear { app.homeVisibility(false) }
        .sheet(isPresented: $search, onDismiss: { app.homeVisibility(true) }) { NavigationStack { DestinationSearchView() } }
        .sheet(isPresented: $settings) { NavigationStack { SettingsView() } }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var clearing: String?
    var body: some View {
        Form {
            Section("导航") {
                LabeledContent("地图服务", value: app.hasKey ? "已配置" : "待配置")
                Text("车道记录在本机长期保存，满 3 个月标记待更新；再次收到有效车道时更新观测时间。")
                    .font(.footnote).foregroundStyle(.secondary)
                NavigationLink("指定起点规划") { SpecifiedRouteView() }.disabled(!app.ready)
                NavigationLink("车道演示") { DemoView() }.accessibilityIdentifier("settings.demo")
            }
            Section("本机数据") {
                Button("清除车道历史", role: .destructive) { clearing = "lanes" }
                Button("清除搜索记录", role: .destructive) { clearing = "searches" }
                Button("清除采集诊断", role: .destructive) { clearing = "diagnostics" }
            }
            Section("关于") {
                LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")
                Text("原生 iOS 版 · 个人导航工具").foregroundStyle(.secondary)
                Link("高德隐私政策", destination: URL(string: "https://lbs.amap.com/pages/privacy/")!)
                if !app.storageError.isEmpty { Text(app.storageError).foregroundStyle(Theme.amber) }
            }
        }
        .scrollContentBackground(.hidden).background(Theme.background)
        .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        .confirmationDialog("清除这类本机数据？其他历史会继续保留。", isPresented: Binding(get: { clearing != nil }, set: { if !$0 { clearing = nil } })) {
            Button("确认清除", role: .destructive) { if let kind = clearing { Task { await app.clear(kind) } }; clearing = nil }
        }
    }
}
