import SwiftUI

struct ToolsView: View {
    @EnvironmentObject private var motion: MotionService
    @State private var calibration = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("感受每一次转向。").font(.title2.bold())
                Text("实时传感器 · 数据仅在本次测量中保留")
                    .font(.caption).foregroundStyle(Theme.muted)
                Card {
                    HStack { Label("驾驶 G 值", systemImage: "gauge.with.dots.needle.50percent").font(.headline); Spacer(); Text("水平合成").font(.caption).foregroundStyle(Theme.muted) }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(motion.g.valid ? String(format: "%.2f", motion.g.total) : "--")
                            .font(.system(size: 64, weight: .light, design: .rounded)).monospacedDigit()
                        Text("g").font(.title2).foregroundStyle(Theme.lime)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 10) {
                            metric(motion.g.longitudinal >= 0 ? "加速" : "刹车", motion.g.longitudinal)
                            metric(motion.g.lateral >= 0 ? "右向" : "左向", motion.g.lateral)
                        }
                    }
                    Text(motion.g.status).font(.caption).foregroundStyle(Theme.muted)
                    if motion.g.calibrating { ProgressView(value: motion.g.calibrationProgress).tint(Theme.lime) }
                    HStack {
                        Text(String(format: "峰值  加速 %.2f · 刹车 %.2f · 横向 %.2f · 合成 %.2f g",
                            motion.g.peakAcceleration, motion.g.peakBraking, motion.g.peakLateral, motion.g.peakTotal))
                            .font(.caption2).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Button("停车校准") { calibration = true }.buttonStyle(.borderedProminent).foregroundStyle(Theme.background)
                            .disabled(!motion.g.available).accessibilityIdentifier("tools.calibrate")
                        Spacer()
                        Button("重置峰值") { motion.resetPeaks() }.font(.caption).buttonStyle(.bordered)
                    }
                }
                Card {
                    Label("磁北指南针", systemImage: "safari").font(.headline)
                    HStack(spacing: 24) {
                        ZStack {
                            Circle().stroke(Theme.muted.opacity(0.2), lineWidth: 1)
                            ForEach(0..<12) { i in
                                Rectangle().fill(Theme.muted.opacity(0.5)).frame(width: 1, height: i % 3 == 0 ? 12 : 6)
                                    .offset(y: -69).rotationEffect(.degrees(Double(i) * 30))
                            }
                            if motion.compass.valid {
                                Image(systemName: "location.north.fill").font(.system(size: 58))
                                    .foregroundStyle(Theme.lime).rotationEffect(.degrees(motion.compass.rotation))
                            } else { Text("--").font(.title).foregroundStyle(Theme.muted) }
                        }.frame(width: 150, height: 150).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(motion.compass.valid ? "\(Int(motion.compass.heading))°" : "--°").font(.system(size: 35, weight: .medium, design: .rounded)).monospacedDigit()
                            Text(motion.compass.valid ? motion.compass.direction : "等待方向").foregroundStyle(Theme.lime)
                            Text(motion.compass.reference).font(.caption2).foregroundStyle(Theme.muted)
                        }
                    }.frame(maxWidth: .infinity)
                    Text(motion.compass.status).font(.caption).foregroundStyle(Theme.muted)
                }
                Card {
                    Label("双轴水平仪", systemImage: "level").font(.headline)
                    ZStack {
                        Circle().fill(Theme.background).overlay(Circle().stroke(Theme.muted.opacity(0.2)))
                        Circle().stroke(Theme.muted.opacity(0.18)).padding(40)
                        Rectangle().fill(Theme.muted.opacity(0.2)).frame(height: 1)
                        Rectangle().fill(Theme.muted.opacity(0.2)).frame(width: 1)
                        if motion.level.valid {
                            Circle().fill(motion.level.level ? Theme.lime : Theme.amber).frame(width: 34, height: 34)
                                .shadow(color: Theme.lime.opacity(0.2), radius: 12)
                                .offset(x: motion.level.bubbleX * 78, y: motion.level.bubbleY * 78)
                        } else { Text("--").font(.title).foregroundStyle(Theme.muted) }
                    }.frame(width: 210, height: 210).frame(maxWidth: .infinity).accessibilityHidden(true)
                    HStack {
                        levelMetric("左右", motion.level.roll); Spacer()
                        levelMetric("前后", motion.level.pitch); Spacer()
                        levelMetric("总倾角", motion.level.tilt)
                    }
                    Text(motion.level.status).font(.caption).foregroundStyle(Theme.muted)
                }
                Card {
                    Text("正确放置，读数才有意义").font(.headline)
                    Text("G 值：手机固定在支架上，屏幕朝向车尾，顶部朝上。停车静止约 2 秒完成校准；调整支架后需重校。\n\n水平仪：屏幕朝上平放，无需 G 值校准。\n\n指南针指向磁北，磁吸支架与金属可能造成干扰。测量仅供参考，不作为碰撞检测或道路坡度测量。")
                        .font(.footnote).foregroundStyle(Theme.muted).lineSpacing(4)
                }
            }.padding(20)
        }
        .background(Theme.background).navigationTitle("驾驶工具")
        .onAppear { motion.start("tools") }.onDisappear { motion.stop("tools") }
        .alert("停车后校准", isPresented: $calibration) {
            Button("已停车，开始校准") { motion.calibrate() }
            Button("取消", role: .cancel) {}
        } message: { Text("手机勿平放，屏幕朝向车尾。固定后保持静止约 2 秒。") }
    }
    private func metric(_ title: String, _ value: Double) -> some View {
        HStack { Text(title).foregroundStyle(Theme.muted); Text(motion.g.valid ? String(format: "%.2f g", abs(value)) : "-- g").monospacedDigit() }.font(.caption)
    }
    private func levelMetric(_ title: String, _ value: Double) -> some View {
        VStack(spacing: 5) {
            Text(title).font(.caption2).foregroundStyle(Theme.muted)
            Text(motion.level.valid ? String(format: "%.1f°", value) : "--°").font(.headline).monospacedDigit()
        }
    }
}
