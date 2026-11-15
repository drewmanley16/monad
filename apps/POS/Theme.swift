import SwiftUI

/// Tapnad POS — bright countertop-register look: white surfaces, flat colored item tiles,
/// one blue for actions, tabular figures.
enum T {
    static let bg = Color(red: 0.965, green: 0.965, blue: 0.965)           // page gray
    static let surface = Color.white
    static let raised = Color.white
    static let hover = Color.black.opacity(0.04)
    static let rule = Color.black.opacity(0.10)
    static let text = Color(red: 0.10, green: 0.10, blue: 0.10)
    static let dim = Color(red: 0.42, green: 0.42, blue: 0.44)
    static let faint = Color(red: 0.62, green: 0.62, blue: 0.64)

    static let blue = Color(red: 0.11, green: 0.11, blue: 0.11)            // primary action (near-black)
    static let accent = blue
    // status is expressed in grays: light → dark as a payment settles
    static let amber = Color(red: 0.72, green: 0.72, blue: 0.72)
    static let green = Color(red: 0.11, green: 0.11, blue: 0.11)
    static let red = Color(red: 0.35, green: 0.35, blue: 0.35)
    static let tile = Color(red: 0.93, green: 0.93, blue: 0.925)

    static func mono(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font { .system(size: size, weight: w).monospacedDigit() }
    static func sans(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font { .system(size: size, weight: w) }

    /// Flat tile palette.
    static let tiles: [Color] = [
        Color(red: 0.0, green: 0.42, blue: 1.0),     // blue
        Color(red: 0.0, green: 0.62, blue: 0.33),    // green
        Color(red: 0.95, green: 0.45, blue: 0.1),    // orange
        Color(red: 0.55, green: 0.3, blue: 0.85),    // purple
        Color(red: 0.86, green: 0.2, blue: 0.35),    // red
        Color(red: 0.0, green: 0.6, blue: 0.65),     // teal
        Color(red: 0.85, green: 0.65, blue: 0.0),    // mustard
        Color(red: 0.4, green: 0.4, blue: 0.45),     // gray
    ]
}

/// Small section heading.
struct Label2: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(T.dim) }
}

struct Rule: View { var body: some View { Rectangle().fill(T.rule).frame(height: 1) } }
struct VRule: View { var body: some View { Rectangle().fill(T.rule).frame(width: 1) } }

/// White card with a light border.
struct Card: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content.padding(padding)
            .background(T.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(T.rule))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(Card(padding: padding)) }
    func outlined(padding: CGFloat = 16) -> some View { modifier(Card(padding: padding)) }
}

/// Blue primary button.
struct PrimaryAction: ButtonStyle {
    var enabled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(T.sans(15, .semibold))
            .foregroundStyle(enabled ? .white : T.faint)
            .background(enabled ? T.blue.opacity(configuration.isPressed ? 0.85 : 1) : Color.black.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 6))
    }
}

/// White bordered button.
struct QuietAction: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(T.sans(13, .medium))
            .foregroundStyle(T.text)
            .padding(.horizontal, 12).frame(height: 30)
            .background(configuration.isPressed ? Color.black.opacity(0.05) : T.surface, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(T.rule))
    }
}

extension CommitState {
    var color: Color {
        switch self {
        case .proposed: T.amber
        case .voted: Color(red: 0.45, green: 0.45, blue: 0.45)
        case .finalized: T.green
        case .verified: T.green
        }
    }
}

struct StateLabel: View {
    let state: CommitState
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(state.color).frame(width: 7, height: 7)
            Text(state.rawValue).font(T.sans(13)).foregroundStyle(T.text)
        }
    }
}

/// Kept for layout compatibility: flexible gap between label and value.
struct Leader: View { var body: some View { Spacer(minLength: 8) } }

struct Sparkline: View {
    let values: [Double]
    var color: Color = T.blue
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
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
    }
}

struct KV: View {
    let k: String
    let v: String
    var strong = false
    var body: some View {
        HStack {
            Text(k).font(T.sans(14, strong ? .semibold : .regular)).foregroundStyle(strong ? T.text : T.dim)
            Spacer()
            Text(v).font(T.mono(14, strong ? .semibold : .regular)).foregroundStyle(T.text)
        }
    }
}

struct Metric: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(T.sans(13)).foregroundStyle(T.dim)
            Text(value).font(T.mono(26, .semibold)).contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16)
    }
}

/// Two-letter tile abbreviation: "Oat Latte" → "OL", "Espresso" → "Es".
func tileAbbrev(_ name: String) -> String {
    let words = name.split(separator: " ")
    if words.count >= 2 { return String(words[0].prefix(1) + words[1].prefix(1)).uppercased() }
    return String(name.prefix(2)).capitalized
}

// MARK: - Item pictures

enum ItemPicture {
    /// Bundled photo named after the item, e.g. "oat-latte.jpg" in POS/Images.
    static func photo(for name: String) -> NSImage? {
        let slug = name.lowercased().replacingOccurrences(of: " ", with: "-")
        for ext in ["jpg", "jpeg", "png", "webp"] {
            if let url = Bundle.main.url(forResource: slug, withExtension: ext), let img = NSImage(contentsOf: url) { return img }
        }
        return nil
    }

    /// Illustration fallback.
    static func symbol(for p: Product) -> String {
        let n = p.name.lowercased()
        let table: [(String, String)] = [
            ("espresso", "cup.and.saucer.fill"), ("cortado", "cup.and.saucer.fill"), ("latte", "mug.fill"),
            ("cold brew", "takeoutbag.and.cup.and.straw.fill"), ("matcha", "leaf.fill"), ("chai", "mug.fill"), ("tea", "leaf.fill"),
            ("croissant", "birthday.cake.fill"), ("bagel", "circle.circle"), ("toast", "fork.knife"),
            ("water", "waterbottle.fill"), ("juice", "drop.fill"), ("tee", "tshirt.fill"), ("shirt", "tshirt.fill"),
            ("cap", "hat.cap.fill"), ("hat", "hat.cap.fill"),
        ]
        return table.first { n.contains($0.0) }?.1 ?? p.category.icon
    }
}
