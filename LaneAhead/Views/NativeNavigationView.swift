import SwiftUI

struct NativeNavigationView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var motion: MotionService
    @State private var exit = false
    @State private var showCalibration = false
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Theme.background.ignoresSafeArea()
                if let navigation = app.navigation { ServiceMap(view: navigation.view).ignoresSafeArea(edges: .bottom) }
                if app.navigating {
                    NavigationLaneOverlay(rows: app.upcomingLanes, waiting: app.preview.isEmpty && app.previewStatus != "即将到达终点",
                        status: app.previewStatus)
                }
                VStack(spacing: 0) {
                    HStack {
                        Button { exit = true } label: { Label(app.navigating ? "结束" : "返回", systemImage: "xmark").font(.subheadline.bold()) }
                            .buttonStyle(PopButtonStyle(fill: Theme.card, compact: true))
                        Spacer()
                        if app.navigating {
                            Text("\(Int(app.speed)) km/h").font(.subheadline.bold().monospacedDigit()).padding(10)
                                .popSurface(Theme.yellow, radius: 12, shadow: 3)
                        }
                    }.padding(.horizontal, 16).padding(.top, 8)
                    Spacer()
                    if app.navigating {
                        VStack(spacing: 6) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(motion.g.valid ? String(format: "水平 %.2f g", motion.g.total) : "水平 G 值 --")
                                        .font(.caption.bold()).monospacedDigit()
                                    Text(motion.g.status).font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(1)
                                }
                                Spacer()
                                Button("停车校准") { showCalibration = true }.font(.caption.bold())
                                    .buttonStyle(PopButtonStyle(fill: Theme.yellow, compact: true))
                            }.padding(.horizontal, 10).padding(.vertical, 5).popSurface(Theme.card, radius: 12, shadow: 2)
                            if !app.storageError.isEmpty {
                                Text(app.storageError).font(.caption2).foregroundStyle(Theme.amber)
                            }
                        }
                        .frame(maxWidth: geometry.size.width > geometry.size.height ? 260 : 310)
                        .padding(.horizontal, 12).padding(.bottom, 108)
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(app.arrived ? "已到达目的地" : "选择你的路线").font(.title2.bold())
                            Text(app.message).font(.subheadline).foregroundStyle(Theme.muted)
                            if app.planning { ProgressView().frame(maxWidth: .infinity) }
                            ForEach(app.routes) { route in
                                Button { app.chooseRoute(route.id) } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text("\(Int(ceil(route.seconds / 60))) 分钟 · " + Theme.distance(route.meters)).font(.headline)
                                            Text(route.label).font(.caption).foregroundStyle(Theme.muted)
                                        }
                                        Spacer()
                                        Image(systemName: app.selectedRoute == route.id ? "checkmark.circle.fill" : "circle")
                                    }
                                    .foregroundStyle(Theme.ink).padding(14)
                                    .popSurface(app.selectedRoute == route.id ? Theme.cyan : Theme.card, radius: 14, shadow: 3)
                                }.disabled(app.starting || app.arrived)
                            }
                            if !app.arrived {
                                PrimaryButton(title: app.starting ? "正在启动…" : app.plannedFromSpecifiedOrigin ? "从当前位置重新规划" : "开始 GPS 导航", icon: "location.north.fill") {
                                    if app.plannedFromSpecifiedOrigin { app.plan() } else { app.startNavigation() }
                                }.disabled(app.planning || app.starting || app.selectedRoute == nil)
                            } else { PrimaryButton(title: "返回首页", icon: "house") { app.closeNavigation() } }
                        }
                        .padding(22).background(Theme.background, in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
                        .overlay(alignment: .top) { Rectangle().fill(Theme.ink).frame(height: 2) }
                    }
                }
            }
        }
        .confirmationDialog("结束导航并返回首页？", isPresented: $exit) {
            Button("结束并返回", role: .destructive) { app.closeNavigation() }
        }
        .alert("停车后校准", isPresented: $showCalibration) {
            Button("已停车，开始校准") { motion.calibrate() }
            Button("取消", role: .cancel) {}
        } message: { Text("固定手机，屏幕朝向车尾，顶部朝上。保持静止约 2 秒，行驶中请勿操作。") }
    }
}
