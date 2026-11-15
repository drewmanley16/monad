import SwiftUI

/// The wallet "card" — Apple Wallet proportions (1.586:1).
struct CardView: View {
    let balance: Wei?
    let address: String
    var compact = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [.monadPurple, .monadDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    // subtle hex lattice sheen
                    Canvas { ctx, size in
                        for i in stride(from: -size.height, to: size.width, by: 22) {
                            var p = Path()
                            p.move(to: CGPoint(x: i, y: size.height))
                            p.addLine(to: CGPoint(x: i + size.height, y: 0))
                            ctx.stroke(p, with: .color(.white.opacity(0.04)), lineWidth: 1)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
                )

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "hexagon.fill").font(.system(size: 18, weight: .bold))
                        Text("tapnad").font(.system(size: 20, weight: .bold, design: .rounded))
                    }
                    Spacer()
                    Image(systemName: "wave.3.right").font(.system(size: 20, weight: .semibold))
                }
                Spacer()
                if !compact {
                    Text("BALANCE").font(.caption2.weight(.semibold)).opacity(0.7)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(balance.map { MON.format($0, maxFraction: 3) } ?? "—")
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .contentTransition(.numericText())
                        Text("MON").font(.headline).opacity(0.8)
                    }
                    .padding(.bottom, 6)
                }
                HStack {
                    Text(short(address)).font(.system(.footnote, design: .monospaced)).opacity(0.8)
                    Spacer()
                    Text("TESTNET").font(.caption2.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.white.opacity(0.15), in: Capsule())
                }
            }
            .foregroundStyle(.white)
            .padding(20)
        }
        .aspectRatio(1.586, contentMode: .fit)
        .shadow(color: .monadPurple.opacity(0.35), radius: 24, y: 12)
    }

    private func short(_ a: String) -> String {
        a.count > 12 ? "\(a.prefix(6))…\(a.suffix(4))" : a
    }
}
