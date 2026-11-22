import SwiftUI

/// Original, procedural artwork for the connected headphone.
///
/// Drawn entirely with SwiftUI shapes: it stays sharp at any size, adapts to
/// light and dark, adds no image assets, and redistributes nobody's product
/// photography. It is a stylised illustration, not a render of a specific
/// product, and it varies by form factor so an over-ear headset and a pair of
/// buds do not look identical.
struct HeadphoneArtwork: View {
    let model: String
    var tint: Color = .accentColor
    var showsShadow: Bool = true

    @Environment(\.colorScheme) private var scheme

    private var form: FormFactor {
        let m = model.uppercased()
        if m.contains("WF-") || m.contains("BUD") || m.contains("SP800")
            || m.contains("LINKBUDS") || m.contains("EAR") {
            return .buds
        }
        return .overEar
    }

    private enum FormFactor { case overEar, buds }

    // Graphite body with a hint of the accent, readable on both backgrounds.
    private var bodyTop: Color {
        scheme == .dark ? Color(white: 0.42) : Color(white: 0.72)
    }
    private var bodyBottom: Color {
        scheme == .dark ? Color(white: 0.16) : Color(white: 0.40)
    }

    private var bodyGradient: LinearGradient {
        LinearGradient(colors: [bodyTop, bodyBottom], startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                if showsShadow { groundShadow(s: s) }
                switch form {
                case .overEar: overEar(s: s)
                case .buds: buds(s: s)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    // MARK: Over-ear

    private func overEar(s: CGFloat) -> some View {
        let bandRadius = s * 0.30
        let cupW = s * 0.19
        let cupH = s * 0.30

        return ZStack {
            // Headband
            Path { p in
                p.addArc(
                    center: CGPoint(x: s * 0.5, y: s * 0.56),
                    radius: bandRadius,
                    startAngle: .degrees(196),
                    endAngle: .degrees(344),
                    clockwise: false
                )
            }
            .stroke(
                LinearGradient(
                    colors: [bodyTop.opacity(0.95), bodyBottom.opacity(0.9)],
                    startPoint: .top, endPoint: .bottom
                ),
                style: StrokeStyle(lineWidth: s * 0.055, lineCap: .round)
            )
            .overlay(
                Path { p in
                    p.addArc(
                        center: CGPoint(x: s * 0.5, y: s * 0.56),
                        radius: bandRadius - s * 0.018,
                        startAngle: .degrees(205),
                        endAngle: .degrees(335),
                        clockwise: false
                    )
                }
                .stroke(Color.white.opacity(scheme == .dark ? 0.18 : 0.55),
                        style: StrokeStyle(lineWidth: s * 0.008, lineCap: .round))
            )

            // Yokes
            ForEach([-1.0, 1.0], id: \.self) { side in
                RoundedRectangle(cornerRadius: s * 0.012, style: .continuous)
                    .fill(bodyGradient)
                    .frame(width: s * 0.028, height: s * 0.10)
                    .offset(x: side * bandRadius * 0.82, y: s * 0.10)
            }

            // Ear cups
            ForEach([-1.0, 1.0], id: \.self) { side in
                earCup(s: s, width: cupW, height: cupH, side: side)
                    .offset(x: side * bandRadius * 0.86, y: s * 0.19)
            }

            // Hinge dots
            ForEach([-1.0, 1.0], id: \.self) { side in
                Circle()
                    .fill(tint.opacity(0.85))
                    .frame(width: s * 0.018, height: s * 0.018)
                    .offset(x: side * bandRadius * 0.86, y: s * 0.055)
            }
        }
    }

    private func earCup(s: CGFloat, width: CGFloat, height: CGFloat, side: Double) -> some View {
        RoundedRectangle(cornerRadius: width * 0.46, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        bodyTop.opacity(0.98),
                        bodyBottom,
                        bodyBottom.opacity(0.95),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                // Outer plate, slightly inset, gives the cup depth.
                RoundedRectangle(cornerRadius: width * 0.40, style: .continuous)
                    .inset(by: width * 0.14)
                    .fill(
                        RadialGradient(
                            colors: [
                                tint.opacity(0.28),
                                Color.black.opacity(scheme == .dark ? 0.35 : 0.18),
                            ],
                            center: .topLeading,
                            startRadius: 1,
                            endRadius: width * 1.1
                        )
                    )
            )
            .overlay(
                // Specular streak.
                RoundedRectangle(cornerRadius: width * 0.40, style: .continuous)
                    .inset(by: width * 0.20)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(scheme == .dark ? 0.22 : 0.45), .clear],
                            startPoint: .topLeading,
                            endPoint: .center
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: width * 0.46, style: .continuous)
                    .strokeBorder(.white.opacity(scheme == .dark ? 0.10 : 0.30), lineWidth: 0.8)
            )
            .frame(width: width, height: height)
            .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.18), radius: s * 0.02, y: s * 0.012)
            .rotationEffect(.degrees(side * 4))
    }

    // MARK: Buds

    private func buds(s: CGFloat) -> some View {
        ZStack {
            ForEach([-1.0, 1.0], id: \.self) { side in
                ZStack {
                    // Body
                    RoundedRectangle(cornerRadius: s * 0.075, style: .continuous)
                        .fill(bodyGradient)
                        .frame(width: s * 0.20, height: s * 0.20)
                        .overlay(
                            RoundedRectangle(cornerRadius: s * 0.075, style: .continuous)
                                .strokeBorder(.white.opacity(scheme == .dark ? 0.12 : 0.35), lineWidth: 0.8)
                        )
                        // Nozzle
                        .overlay(alignment: .top) {
                            Capsule()
                                .fill(bodyGradient)
                                .frame(width: s * 0.055, height: s * 0.085)
                                .offset(y: -s * 0.035)
                        }
                    // Stem
                    Capsule()
                        .fill(bodyGradient)
                        .frame(width: s * 0.055, height: s * 0.17)
                        .offset(y: s * 0.14)
                        .overlay(
                            Capsule()
                                .strokeBorder(.white.opacity(scheme == .dark ? 0.10 : 0.28), lineWidth: 0.8)
                                .frame(width: s * 0.055, height: s * 0.17)
                                .offset(y: s * 0.14)
                        )
                    // Silicone tip
                    Circle()
                        .fill(tint.opacity(0.35))
                        .frame(width: s * 0.10, height: s * 0.10)
                        .offset(x: -s * 0.055, y: -s * 0.02)
                }
                .rotationEffect(.degrees(side * 8))
                .offset(x: side * s * 0.19, y: 0)
                .shadow(color: .black.opacity(scheme == .dark ? 0.4 : 0.15), radius: s * 0.02, y: s * 0.01)
            }
        }
    }

    // MARK: Shadow

    private func groundShadow(s: CGFloat) -> some View {
        Ellipse()
            .fill(Color.black.opacity(scheme == .dark ? 0.35 : 0.12))
            .frame(width: s * 0.62, height: s * 0.06)
            .blur(radius: s * 0.02)
            .offset(y: s * 0.42)
    }
}

#Preview("Over-ear") {
    HeadphoneArtwork(model: "WH-1000XM6")
        .frame(width: 220, height: 220)
        .padding()
}

#Preview("Buds") {
    HeadphoneArtwork(model: "WF-1000XM5")
        .frame(width: 220, height: 220)
        .padding()
}
