import SwiftUI

/// Tapnad POS — dark neon design system.
enum T {
    static let bg = Color(red: 0.035, green: 0.031, blue: 0.051)          // #09080D
    static let panel = Color(red: 0.075, green: 0.067, blue: 0.102)       // #13111A
    static let panel2 = Color(red: 0.106, green: 0.094, blue: 0.141)      // #1B1824
    static let stroke = Color.white.opacity(0.07)
    static let text = Color(red: 0.96, green: 0.95, blue: 1.0)
    static let dim = Color(red: 0.6, green: 0.58, blue: 0.7)
    static let faint = Color(red: 0.38, green: 0.36, blue: 0.46)

    static let violet = Color(red: 0.514, green: 0.431, blue: 0.976)      // #836EF9
    static let magenta = Color(red: 0.78, green: 0.35, blue: 1.0)
    static let pink = Color(red: 1.0, green: 0.38, blue: 0.64)
    static let flame = Color(red: 1.0, green: 0.55, blue: 0.25)
    static let mint = Color(red: 0.22, green: 0.92, blue: 0.6)

    static let fire = LinearGradient(colors: [violet, magenta, pink], startPoint: .leading, endPoint: .trailing)
    static let fireDiag = LinearGradient(colors: [violet, magenta, pink, flame], startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct Panel: ViewModifier {
    var radius: CGFloat = 16
    var padding: CGFloat = 18
    var glow: Color? = nil
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: [T.panel2.opacity(0.9), T.panel], startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.10), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
            .shadow(color: (glow ?? .clear).opacity(0.25), radius: 24, y: 8)
    }
}

extension View {
    func panel(radius: CGFloat = 16, padding: CGFloat = 18, glow: Color? = nil) -> some View {
        modifier(Panel(radius: radius, padding: padding, glow: glow))
    }
}

struct FireButton: ButtonStyle {
    var enabled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(enabled ? AnyShapeStyle(T.fire) : AnyShapeStyle(Color.white.opacity(0.08)))
            )
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(enabled ? 0.25 : 0.05), lineWidth: 1))
            .shadow(color: enabled ? T.magenta.opacity(configuration.isPressed ? 0.2 : 0.45) : .clear, radius: 18, y: 6)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

struct GhostButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(T.text)
            .padding(.horizontal, 12).frame(height: 32)
            .background(Color.white.opacity(configuration.isPressed ? 0.1 : 0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(T.stroke))
    }
}

/// Slowly drifting mesh-gradient backdrop.
struct AuroraBackground: View {
    var colors: [Color] = [T.bg, T.violet.opacity(0.55), T.bg, T.magenta.opacity(0.45), T.bg, T.pink.opacity(0.35), T.bg, T.violet.opacity(0.3), T.bg]
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let s = Float(sin(t * 0.35)) * 0.12, c = Float(cos(t * 0.27)) * 0.12
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5 + s, 0], [1, 0],
                [0, 0.5 + c], [0.5 + c, 0.5 - s], [1, 0.5 + s],
                [0, 1], [0.5 - c, 1], [1, 1],
            ], colors: colors)
        }
        .ignoresSafeArea()
    }
}

/// Confetti burst rendered with Canvas.
struct Confetti: View {
    struct P { let x: Double; let vx: Double; let vy: Double; let spin: Double; let color: Color; let size: Double }
    @State private var start = Date()
    private let particles: [P] = (0..<140).map { _ in
        P(x: Double.random(in: 0.3...0.7), vx: Double.random(in: -0.5...0.5), vy: Double.random(in: -1.25 ... -0.55),
          spin: Double.random(in: -8...8), color: [T.violet, T.magenta, T.pink, T.flame, T.mint, .white].randomElement()!,
          size: Double.random(in: 5...10))
    }

    var body: some View {
        TimelineView(.animation) { ctx in
            Canvas { g, size in
                let t = ctx.date.timeIntervalSince(start)
                guard t < 3.2 else { return }
                for p in particles {
                    let x = (p.x + p.vx * t * 0.6) * size.width
                    let y = size.height * 0.55 + (p.vy * t + 0.9 * t * t) * size.height * 0.5
                    var r = g
                    r.translateBy(x: x, y: y)
                    r.rotate(by: .radians(p.spin * t))
                    r.opacity = max(0, 1 - t / 3.2)
                    r.fill(Path(CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.size / 2)), with: .color(p.color))
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear { start = Date() }
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 30, weight: .bold)).foregroundStyle(T.text)
            if let subtitle { Text(subtitle).font(.system(size: 14)).foregroundStyle(T.dim) }
        }
    }
}

struct Tag: View {
    let text: String
    var color: Color = T.violet
    var body: some View {
        Text(text).font(.system(size: 10.5, weight: .bold)).tracking(0.4)
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.25)))
    }
}

struct StatePill: View {
    let state: CommitState
    var color: Color {
        switch state {
        case .proposed: T.flame
        case .voted: Color(red: 0.4, green: 0.65, blue: 1)
        case .finalized: T.mint
        case .verified: T.violet
        }
    }
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6).shadow(color: color, radius: 3)
            Text(state.rawValue)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
    }
}

/// Tiny sparkline.
struct Sparkline: View {
    let values: [Double]
    var color: Color = T.violet
    var body: some View {
        GeometryReader { g in
            let mx = max(values.max() ?? 1, 0.0001), mn = values.min() ?? 0
            let pts = values.enumerated().map { i, v in
                CGPoint(x: g.size.width * Double(i) / Double(max(values.count - 1, 1)),
                        y: g.size.height * (1 - (v - mn) / max(mx - mn, 0.0001)))
            }
            ZStack {
                Path { p in
                    guard let f = pts.first else { return }
                    p.move(to: CGPoint(x: f.x, y: g.size.height)); pts.forEach { p.addLine(to: $0) }
                    p.addLine(to: CGPoint(x: pts.last!.x, y: g.size.height)); p.closeSubpath()
                }
                .fill(LinearGradient(colors: [color.opacity(0.35), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                Path { p in
                    guard let f = pts.first else { return }
                    p.move(to: f); pts.dropFirst().forEach { p.addLine(to: $0) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
