import SwiftUI

enum Theme {
    static let background = Color(red: 1, green: 0.97, blue: 0.89)
    static let card = Color.white
    static let ink = Color(red: 0.08, green: 0.075, blue: 0.10)
    static let accent = Color(red: 0.08, green: 0.24, blue: 0.86)
    static let yellow = Color(red: 1, green: 0.87, blue: 0.18)
    static let pink = Color(red: 1, green: 0.38, blue: 0.64)
    static let cyan = Color(red: 0.53, green: 0.88, blue: 0.95)
    static let lavender = Color(red: 0.83, green: 0.77, blue: 1)
    static let muted = Color(red: 0.31, green: 0.30, blue: 0.35)
    static let amber = Color(red: 0.57, green: 0.24, blue: 0.02)
    static func distance(_ meters: Double) -> String {
        meters < 1_000 ? "\(Int(max(0, meters).rounded())) 米" : String(format: "%.1f 公里", meters / 1_000)
    }
}

private struct PopSurface: ViewModifier {
    var fill: Color
    var radius: CGFloat
    var shadow: CGFloat
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius).fill(fill)
                    .shadow(color: Theme.ink, radius: 0, x: shadow, y: shadow)
            }
            .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.ink, lineWidth: 2) }
    }
}

extension View {
    func popSurface(_ fill: Color = Theme.card, radius: CGFloat = 18, shadow: CGFloat = 5) -> some View {
        modifier(PopSurface(fill: fill, radius: radius, shadow: shadow))
    }
}

struct PopBadge: View {
    var title: String
    var fill: Color = Theme.yellow
    var body: some View {
        Text(title).font(.system(size: 11, weight: .black, design: .rounded))
            .foregroundStyle(Theme.ink).padding(.horizontal, 9).padding(.vertical, 6)
            .background(fill).overlay { Rectangle().strokeBorder(Theme.ink, lineWidth: 1.5) }
            .fixedSize()
    }
}

struct PopButtonStyle: ButtonStyle {
    var fill: Color = Theme.yellow
    var foreground: Color = Theme.ink
    var compact = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(enabled ? foreground : Theme.muted)
            .padding(.horizontal, compact ? 12 : 18).padding(.vertical, compact ? 8 : 14)
            .frame(minHeight: compact ? 40 : 52)
            .background {
                RoundedRectangle(cornerRadius: 12).fill(enabled ? fill : Color(white: 0.88))
                    .shadow(color: enabled ? Theme.ink : Theme.ink.opacity(0.35), radius: 0,
                        x: configuration.isPressed ? 1 : 3, y: configuration.isPressed ? 1 : 4)
            }
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.ink, lineWidth: 2) }
            .offset(x: configuration.isPressed ? 2 : 0, y: configuration.isPressed ? 2 : 0)
    }
}

struct PopDots: View {
    var color: Color = Theme.ink.opacity(0.12)
    var body: some View {
        Canvas { context, size in
            for y in stride(from: 7.0, to: Double(size.height), by: 14) {
                for x in stride(from: 7.0, to: Double(size.width), by: 14) {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2.5, height: 2.5)), with: .color(color))
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct Card<Content: View>: View {
    var fill: Color
    var content: Content
    init(fill: Color = Theme.card, @ViewBuilder content: () -> Content) {
        self.fill = fill; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .popSurface(fill)
    }
}

struct PrimaryButton: View {
    var title: String
    var icon: String = "arrow.up.right"
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.system(.headline, design: .rounded, weight: .heavy))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(PopButtonStyle(fill: Theme.accent, foreground: .white))
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
        ZStack {
            Theme.yellow
            PopDots()
            Canvas { context, size in
                var route = Path()
                route.move(to: CGPoint(x: size.width * 0.70, y: size.height + 35))
                route.addLine(to: CGPoint(x: size.width * 0.70, y: size.height * 0.60))
                route.addQuadCurve(to: CGPoint(x: size.width * 0.91, y: size.height * 0.30),
                    control: CGPoint(x: size.width * 0.70, y: size.height * 0.30))
                route.addLine(to: CGPoint(x: size.width + 40, y: size.height * 0.30))
                context.stroke(route, with: .color(Theme.ink), style: StrokeStyle(lineWidth: 66, lineCap: .round, lineJoin: .round))
                context.stroke(route, with: .color(Theme.accent), style: StrokeStyle(lineWidth: 61, lineCap: .round, lineJoin: .round))
                context.stroke(route, with: .color(.white), style: StrokeStyle(lineWidth: 3, lineCap: .square, dash: [10, 9]))
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}
