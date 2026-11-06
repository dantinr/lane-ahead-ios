import SwiftUI

enum Theme {
    static let background = Color(red: 0.035, green: 0.09, blue: 0.075)
    static let card = Color(red: 0.075, green: 0.16, blue: 0.125)
    static let lime = Color(red: 0.71, green: 0.96, blue: 0.54)
    static let muted = Color(red: 0.66, green: 0.75, blue: 0.69)
    static let amber = Color(red: 1, green: 0.83, blue: 0.54)
    static func distance(_ meters: Double) -> String {
        meters < 1_000 ? "\(Int(max(0, meters).rounded())) 米" : String(format: "%.1f 公里", meters / 1_000)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22))
    }
}

struct PrimaryButton: View {
    var title: String
    var icon: String = "arrow.up.right"
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.headline)
                .frame(maxWidth: .infinity).padding(.vertical, 17)
        }
        .buttonStyle(.borderedProminent).tint(Theme.lime).foregroundStyle(Theme.background)
        .buttonBorderShape(.roundedRectangle(radius: 17))
    }
}

struct ServiceMap: UIViewRepresentable {
    var view: UIView
    func makeUIView(context: Context) -> UIView {
        // A dedicated host keeps SwiftUI from reparenting SDK-owned subviews.
        let host = UIView()
        attach(to: host)
        return host
    }
    private func attach(to host: UIView) {
        view.removeFromSuperview(); view.translatesAutoresizingMaskIntoConstraints = false; host.addSubview(view)
        NSLayoutConstraint.activate([view.topAnchor.constraint(equalTo: host.topAnchor), view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: host.leadingAnchor), view.trailingAnchor.constraint(equalTo: host.trailingAnchor)])
    }
    func updateUIView(_ uiView: UIView, context: Context) {
        if view.superview !== uiView {
            uiView.subviews.forEach { $0.removeFromSuperview() }
            attach(to: uiView)
        }
    }
}

struct RoadIllustration: View {
    var body: some View {
        Canvas { context, size in
            for offset in stride(from: -200.0, through: Double(size.width) + 200, by: 85) {
                var road = Path(); road.move(to: CGPoint(x: offset, y: -20))
                road.addLine(to: CGPoint(x: offset - 150, y: size.height + 20))
                context.stroke(road, with: .color(.white.opacity(0.045)), lineWidth: 18)
            }
            for y in stride(from: 45.0, through: Double(size.height), by: 75) {
                var road = Path(); road.move(to: CGPoint(x: 0, y: y)); road.addLine(to: CGPoint(x: size.width, y: y - 35))
                context.stroke(road, with: .color(.white.opacity(0.045)), lineWidth: 12)
            }
            var route = Path()
            route.move(to: CGPoint(x: size.width * 0.47, y: size.height + 10))
            route.addLine(to: CGPoint(x: size.width * 0.47, y: size.height * 0.53))
            route.addQuadCurve(to: CGPoint(x: size.width * 0.61, y: size.height * 0.4),
                control: CGPoint(x: size.width * 0.47, y: size.height * 0.4))
            route.addLine(to: CGPoint(x: size.width * 0.78, y: size.height * 0.4))
            route.addLine(to: CGPoint(x: size.width * 0.78, y: -10))
            context.stroke(route, with: .color(Theme.lime.opacity(0.08)), style: StrokeStyle(lineWidth: 24, lineCap: .round, lineJoin: .round))
            context.stroke(route, with: .color(Theme.lime.opacity(0.4)), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [7, 8]))
        }
        .accessibilityHidden(true)
    }
}
