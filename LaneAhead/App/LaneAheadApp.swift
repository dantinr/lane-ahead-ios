import SwiftUI

@main
struct LaneAheadApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(model.motion)
                .tint(Theme.lime)
                .preferredColorScheme(.dark)
                .onChange(of: phase) { _, value in model.setForeground(value == .active) }
        }
    }
}
