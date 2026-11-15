import SwiftUI

enum Brand {
    static let purple = Color(red: 0.514, green: 0.431, blue: 0.976)    // #836EF9 Monad
    static let indigo = Color(red: 0.388, green: 0.357, blue: 1.0)      // #635BFF
    static let deep = Color(red: 0.125, green: 0.0, blue: 0.322)        // #200052
    static let success = Color(red: 0.13, green: 0.77, blue: 0.42)

    static let cardGradient = LinearGradient(
        colors: [Color(red: 0.55, green: 0.45, blue: 1.0), Color(red: 0.36, green: 0.22, blue: 0.86), Brand.deep],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension Font {
    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

/// Subtle surface used for cards/panels (Stripe/Notion-like hairline + soft shadow).
struct Surface: ViewModifier {
    var radius: CGFloat = 16
    var padding: CGFloat = 16
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(scheme == .dark ? Color.white.opacity(0.06) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.04), radius: 8, y: 2)
    }
}

extension View {
    func surface(radius: CGFloat = 16, padding: CGFloat = 16) -> some View {
        modifier(Surface(radius: radius, padding: padding))
    }
}

/// Animated concentric "contactless" rings.
struct ContactlessRings: View {
    var color: Color = Brand.purple
    var size: CGFloat = 220
    var icon: String = "wave.3.right"
    @State private var animate = false

    var body: some View {
        ZStack {
            ForEach(0..<3) { i in
                Circle()
                    .stroke(color.opacity(0.55), lineWidth: 1.5)
                    .scaleEffect(animate ? 1.0 : 0.45)
                    .opacity(animate ? 0 : 1)
                    .animation(.easeOut(duration: 2.1).repeatForever(autoreverses: false).delay(Double(i) * 0.7), value: animate)
            }
            Circle().fill(color.opacity(0.12)).frame(width: size * 0.42, height: size * 0.42)
            Image(systemName: icon)
                .font(.system(size: size * 0.16, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
        .onAppear { animate = true }
    }
}

/// Green success check that pops in.
struct SuccessCheck: View {
    var size: CGFloat = 96
    @State private var shown = false

    var body: some View {
        ZStack {
            Circle().fill(Brand.success).frame(width: size, height: size)
                .shadow(color: Brand.success.opacity(0.4), radius: 20, y: 8)
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
                .scaleEffect(shown ? 1 : 0.2)
        }
        .scaleEffect(shown ? 1 : 0.5)
        .opacity(shown ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { shown = true } }
    }
}

/// Vertical commit-state timeline (Proposed → Voted → Finalized) with live ms.
struct CommitTimeline: View {
    struct Row: Identifiable { let id: String; let title: String; let subtitle: String; let ms: Int? }
    let rows: [Row]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        ZStack {
                            Circle().fill(row.ms != nil ? Brand.purple : Color.secondary.opacity(0.2))
                                .frame(width: 20, height: 20)
                            if row.ms != nil {
                                Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                            }
                        }
                        if i < rows.count - 1 {
                            Rectangle()
                                .fill(rows[i + 1].ms != nil ? Brand.purple : Color.secondary.opacity(0.2))
                                .frame(width: 2, height: 26)
                        }
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.title).font(.subheadline.weight(.semibold))
                            .foregroundStyle(row.ms != nil ? .primary : .secondary)
                        Text(row.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(row.ms.map { $0 == 0 ? "0 ms" : "+\($0) ms" } ?? "—")
                        .font(.subheadline.monospacedDigit().weight(.medium))
                        .foregroundStyle(row.ms != nil ? .primary : .tertiary)
                        .contentTransition(.numericText())
                }
            }
        }
        .animation(.spring(duration: 0.35), value: rows.map(\.ms))
    }
}
