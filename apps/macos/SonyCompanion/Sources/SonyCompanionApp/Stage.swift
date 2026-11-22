import SwiftUI

// The showpiece layer: the product presented on a disc, hairline rays that
// turn while the app looks for the headphones, and a thin ring spinner. All
// of it is drawn here; none of it is a product asset.

// MARK: - Disc

/// The product in a softly lit disc.
///
/// With `rays`, the disc gives way to hairlines turning on their own, the
/// "looking for it" moment. When they stop, the disc and product grow back
/// in; with `done`, a check lands on the rim. While `searching` (a reload
/// with the disc up), the picture dims under a thin ring.
struct ProductDisc: View {
    let model: String
    var color: UInt8? = nil
    var finish: HeadphoneFinish = .black
    var diameter: CGFloat = 220
    var searching = false
    var rays = false
    var done = false
    /// The product alone on the page, with a shadow on the floor, instead
    /// of in a disc.
    var bare = false

    /// Shown only once a wait has lasted 250 ms, and hidden at once, so the
    /// short busy phases of a sync never make the picture blink.
    @State private var spinner = false
    @Environment(\.stageNamespace) private var namespace
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            if rays {
                ScanRays()
                    .frame(width: diameter * 1.3, height: diameter * 1.3)
                    .allowsHitTesting(false)
                    .transition(.opacity.animation(Motion.medium))
            } else {
                ZStack {
                    if bare {
                        // A soft shadow where the product would rest.
                        Ellipse()
                            .fill(Color.black.opacity(scheme == .dark ? 0.7 : 0.13))
                            .frame(width: diameter * 0.46, height: diameter * 0.05)
                            .blur(radius: diameter * 0.03)
                            .offset(y: diameter * 0.335)
                    } else {
                        // A white disc, like a card.
                        Circle().fill(Color.cardSolid)
                            .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.06), radius: 16, y: 6)
                    }

                    HeadphoneHero(model: model, color: color, finish: finish)
                        .frame(width: diameter * (bare ? 1 : 0.92), height: diameter * (bare ? 1 : 0.92))
                        .frame(width: diameter, height: diameter)
                        .clipShape(bare ? AnyShape(Rectangle()) : AnyShape(Circle()))
                        .opacity(spinner ? 0.3 : 1)
                        .scaleEffect(spinner ? 0.96 : 1)

                    if spinner {
                        RingSpinner(diameter: max(28, diameter * 0.17))
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                }
                .frame(width: diameter, height: diameter)
                .overlay(alignment: .bottomTrailing) {
                    if done { check }
                }
                .modifier(MatchedDisc(namespace: namespace))
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.88).combined(with: .opacity).animation(Motion.lift),
                    removal: .opacity.animation(Motion.quick)))
            }
        }
        .frame(width: diameter, height: diameter)
        .animation(spinner ? Motion.fast : Motion.quick, value: spinner)
        .animation(Motion.lift, value: done)
        .task(id: searching) {
            guard searching else { spinner = false; return }
            try? await Task.sleep(for: .milliseconds(250))
            if !Task.isCancelled { spinner = true }
        }
    }

    /// A badge on the rim, ringed in the window colour so it reads as
    /// sitting on top of the disc.
    private var check: some View {
        let size = max(30, diameter * 0.2)
        return Image(systemName: "checkmark")
            .font(.system(size: size * 0.46, weight: .bold))
            .frame(width: size, height: size)
            .foregroundStyle(.white)
            .background(Circle().fill(Color.good))
            .background(Circle().fill(Color.canvas).padding(-4))
            .offset(x: -diameter * 0.06, y: -diameter * 0.06)
            .transition(.scale(scale: 0.5).combined(with: .opacity))
            .accessibilityLabel("Connected")
    }
}

/// Lets the disc fly from the connecting stage into the page header.
private struct MatchedDisc: ViewModifier {
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: "product-disc", in: namespace)
        } else {
            content
        }
    }
}

private struct StageNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var stageNamespace: Namespace.ID? {
        get { self[StageNamespaceKey.self] }
        set { self[StageNamespaceKey.self] = newValue }
    }
}

// MARK: - Rays

/// Hairlines through the centre, each turning at its own speed and in its
/// own direction, growing and shrinking a little: the look of something
/// listening for a signal. Under Reduce Motion they hold still.
struct ScanRays: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    /// Angle (rad), speed (rad/s), length (share of radius), breathing phase.
    private static let rays: [(Double, Double, Double, Double)] = [
        (0.00, 0.62, 0.95, 0.0),
        (0.80, -0.38, 0.80, 1.3),
        (1.70, 0.24, 1.00, 2.1),
        (2.45, -0.71, 0.72, 0.7),
    ]

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSince(start)
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let r = min(size.width, size.height) / 2
                for (angle, speed, length, phase) in Self.rays {
                    let a = angle + speed * t
                    let breathe = 0.88 + 0.12 * sin(t * 0.9 + phase)
                    let half = r * length * breathe
                    let dx = cos(a) * half, dy = sin(a) * half
                    let p0 = CGPoint(x: c.x - dx, y: c.y - dy)
                    let p1 = CGPoint(x: c.x + dx, y: c.y + dy)
                    var line = Path()
                    line.move(to: p0)
                    line.addLine(to: p1)
                    // Bright through the middle, fading to nothing at the tips.
                    let shade = GraphicsContext.Shading.linearGradient(
                        Gradient(stops: [
                            .init(color: .primary.opacity(0), location: 0),
                            .init(color: .primary.opacity(0.85), location: 0.5),
                            .init(color: .primary.opacity(0), location: 1),
                        ]),
                        startPoint: p0, endPoint: p1)
                    ctx.stroke(line, with: shade, lineWidth: 1.25)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Spinner

/// A thin ring with a gap, turning steadily.
struct RingSpinner: View {
    var diameter: CGFloat = 32
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { context in
            let turns = context.date.timeIntervalSince(start) / 0.9
            Circle()
                .trim(from: 0, to: 0.72)
                .stroke(.primary, style: StrokeStyle(lineWidth: max(2, diameter / 14), lineCap: .round))
                .rotationEffect(.radians(turns * 2 * .pi))
        }
        .frame(width: diameter, height: diameter)
        .accessibilityLabel("Connecting")
    }
}

// MARK: - Labels

/// A section label: small, semibold, secondary.
struct StageLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .accessibilityLabel(text)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A pool of shade under the header, so the product sits on a darker
/// stage than the page around it. Dark mode only; in light mode a shadow
/// pool reads as dirt.
struct StageShade: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if scheme == .dark {
            // An ellipse that reaches zero well inside its frame, so the
            // frame's edge never shows as a line.
            GeometryReader { geo in
                let r = min(geo.size.width, geo.size.height) / 2
                RadialGradient(colors: [Color.black.opacity(0.5), Color.black.opacity(0.16), .clear],
                               center: .center, startRadius: 0, endRadius: r * 0.95)
                    .scaleEffect(x: geo.size.width / (2 * r), y: 1)
            }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
