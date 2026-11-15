import SwiftUI

/// Tapnad POS — quiet, typographic design system.
/// Near-black surface, hairline rules, monospaced figures. Color is reserved for status.
enum T {
    static let bg = Color(red: 0.047, green: 0.047, blue: 0.051)          // #0C0C0D
    static let raised = Color(red: 0.078, green: 0.078, blue: 0.082)      // #141415
    static let hover = Color.white.opacity(0.035)
    static let rule = Color.white.opacity(0.08)
    static let text = Color(red: 0.93, green: 0.93, blue: 0.925)          // #EDEDEC
    static let dim = Color(red: 0.56, green: 0.56, blue: 0.56)
    static let faint = Color(red: 0.36, green: 0.36, blue: 0.37)

    static let accent = Color(red: 0.6, green: 0.55, blue: 1.0)           // used sparingly
    static let amber = Color(red: 0.86, green: 0.66, blue: 0.32)
    static let blue = Color(red: 0.45, green: 0.62, blue: 0.95)
    static let green = Color(red: 0.42, green: 0.78, blue: 0.52)

    static let mono = Font.system(size: 13, weight: .regular, design: .monospaced)
    static func mono(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font { .system(size: size, weight: w, design: .monospaced) }
    static func sans(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font { .system(size: size, weight: w) }
}

/// Small-caps section label: "COFFEE", "RECEIPT"…
struct Label2: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10.5, weight: .medium)).tracking(1.1).foregroundStyle(T.faint)
    }
}

struct Rule: View {
    var body: some View { Rectangle().fill(T.rule).frame(height: 1) }
}

struct VRule: View {
    var body: some View { Rectangle().fill(T.rule).frame(width: 1) }
}

/// Hairline-outlined block, no fill, no shadow.
struct Outline: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content.padding(padding)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(T.rule))
    }
}

extension View {
    func outlined(padding: CGFloat = 16) -> some View { modifier(Outline(padding: padding)) }
}

/// Primary action: solid off-white, black text.
struct PrimaryAction: ButtonStyle {
    var enabled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(T.sans(13, .medium))
            .foregroundStyle(enabled ? Color.black : T.faint)
            .background(enabled ? T.text.opacity(configuration.isPressed ? 0.8 : 1) : Color.white.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 4))
    }
}

/// Secondary action: text with hairline border.
struct QuietAction: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(T.sans(12, .medium))
            .foregroundStyle(T.text)
            .padding(.horizontal, 10).frame(height: 26)
            .background(configuration.isPressed ? T.hover : .clear, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(T.rule))
    }
}

struct PageTitle: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).font(T.sans(22, .semibold)).foregroundStyle(T.text)
            if let detail { Text(detail).font(T.mono(12)).foregroundStyle(T.dim) }
        }
    }
}

extension CommitState {
    var color: Color {
        switch self {
        case .proposed: T.amber
        case .voted: T.blue
        case .finalized: T.green
        case .verified: T.accent
        }
    }
}

/// "● Finalized" — dot + word, no pill.
struct StateLabel: View {
    let state: CommitState
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(state.color).frame(width: 5, height: 5)
            Text(state.rawValue).font(T.sans(12)).foregroundStyle(T.dim)
        }
    }
}

/// Dotted leader between a label and a value, menu-style.
struct Leader: View {
    var body: some View {
        GeometryReader { g in
            Path { p in p.move(to: .init(x: 0, y: g.size.height - 3)); p.addLine(to: .init(x: g.size.width, y: g.size.height - 3)) }
                .stroke(T.faint.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [1, 4]))
        }
        .frame(height: 12)
    }
}

/// Plain line sparkline, single color.
struct Sparkline: View {
    let values: [Double]
    var color: Color = T.dim
    var body: some View {
        GeometryReader { g in
            let mx = values.max() ?? 1, mn = values.min() ?? 0
            Path { p in
                for (i, v) in values.enumerated() {
                    let pt = CGPoint(x: g.size.width * Double(i) / Double(max(values.count - 1, 1)),
                                     y: g.size.height * (1 - (v - mn) / max(mx - mn, 0.0001)))
                    i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1, lineJoin: .round))
        }
    }
}

/// Key/value row with a dotted leader.
struct KV: View {
    let k: String
    let v: String
    var strong = false
    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text(k).font(T.sans(13)).foregroundStyle(strong ? T.text : T.dim)
            Leader()
            Text(v).font(T.mono(13, strong ? .medium : .regular)).foregroundStyle(T.text)
        }
    }
}
