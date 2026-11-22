import SwiftUI
import AppKit
import MDRKit

// The app's look: Apple's grouped style, in the system appearance.
//
// - Colour: system grouped grey page, cards (white in light, a little
//   lighter than the page in dark), label colours for text.
//   System blue (the accent) marks what you can change: the volume fill,
//   the primary button. Green means good (connected, battery); red means
//   low battery or a destructive action. Settings rows carry coloured
//   icon tiles, as in System Settings.
// - Surfaces: the page, then rounded cards. No borders. In dark a card is a
//   veil of white over the page colour, drawn opaque so a card that overlaps
//   the hero or a picture never shows it through; use `cardSolid` for shapes
//   that cast a shadow. Controls in a
//   card sit on `raised` wells; the chosen segment is a white thumb.
// - Type: SF Pro throughout at system sizes; numbers use fixed-width digits.
// - Shape: cards 24, controls capsules, icon tiles 7.
// - Light and dark follow the system. In dark the page is the Mac's own
//   window grey (tinted by the wallpaper, as System Settings is) and cards
//   are a few percent lighter; iPhone's black page is not used on the Mac.
//   `SONY_UI_APPEARANCE=light|dark` forces one for review.

// MARK: - Colours

extension Color {
    private static func dynamic(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { a in
            a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    /// The page: system grouped background; in dark, the window background.
    static let canvas = dynamic(dark: .windowBackgroundColor, light: NSColor(srgbRed: 0.949, green: 0.949, blue: 0.969, alpha: 1))
    /// A card on the page; in dark, a light veil over the page, as System
    /// Settings draws its groups.
    static let card = dynamic(dark: NSColor(white: 1, alpha: 0.045), light: .white)
    /// The card's colour, opaque, for shapes that cast a shadow or sit on
    /// something other than the page (knobs, discs).
    static let cardSolid = dynamic(dark: NSColor(srgbRed: 0.165, green: 0.169, blue: 0.180, alpha: 1), light: .white)
    /// Primary text.
    static let ink = dynamic(dark: .white, light: .black)
    /// A well inside a card: tracks, the segmented control's ground.
    static let raised = dynamic(dark: NSColor(srgbRed: 0.463, green: 0.463, blue: 0.502, alpha: 0.24),
                                light: NSColor(srgbRed: 0.463, green: 0.463, blue: 0.502, alpha: 0.12))
    /// The chosen segment's thumb.
    static let thumb = dynamic(dark: NSColor(srgbRed: 0.388, green: 0.388, blue: 0.400, alpha: 1), light: .white)
    /// Good: connected, battery healthy.
    static let good = Color(nsColor: .systemGreen)
    /// Low battery, destructive actions.
    static let signal = Color(nsColor: .systemRed)
}

enum Radius {
    static let card: CGFloat = 24
}

extension Font {
    /// Display words (headlines): SF Pro, bold.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight)
    }
}

// MARK: - Backdrop

/// The page colour, edge to edge.
struct PageBackdrop: View {
    var body: some View {
        Color.canvas
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Cards

/// A white card on the grouped page.
struct Tile<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
    }
}

struct CardSurface: ViewModifier {
    var highlighted = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        content
            .background {
                // The page colour first: the dark card is a translucent veil,
                // and a card pulled over other content must hide it.
                shape.fill(Color.canvas)
                shape.fill(Color.card)
                shape.fill(Color.primary.opacity(highlighted ? 0.035 : 0))
            }
    }
}

extension View {
    func cardSurface(highlighted: Bool = false) -> some View {
        modifier(CardSurface(highlighted: highlighted))
    }
}

/// Press feedback for a card you can open: as on the Mac, it darkens while
/// held and does not scale.
struct TilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color.black.opacity(configuration.isPressed ? 0.06 : 0))
                    .allowsHitTesting(false)
            }
    }
}

// MARK: - Buttons

/// A capsule button, all Liquid Glass. `.accent` is the one primary action,
/// glass tinted with the accent; `.glass` is plain glass; `.destructive` is
/// glass with red text. The glass answers presses; nothing scales.
struct PillButtonStyle: ButtonStyle {
    enum Kind { case accent, glass, destructive }
    var kind: Kind = .glass
    var minWidth: CGFloat = 0

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(.body.weight(.semibold))
            .padding(.horizontal, 20)
            .frame(minWidth: minWidth, minHeight: 34)
            .contentShape(Capsule())

        Group {
            switch kind {
            case .accent:
                // Prominent Liquid Glass: tinted with the accent; the glass
                // itself answers the press.
                label
                    .foregroundStyle(.white)
                    .glassEffect(.regular.tint(Color.accentColor).interactive(), in: .capsule)
            case .glass, .destructive:
                label
                    .foregroundStyle(kind == .destructive ? AnyShapeStyle(Color.signal) : AnyShapeStyle(.primary))
                    .glassEffect(.regular.interactive(), in: .capsule)
            }
        }
        .opacity(isEnabled ? 1 : (kind == .accent ? 0.7 : 0.4))
    }
}

/// A round Liquid Glass icon button, as beside the Connect pill.
struct RoundButtonStyle: ButtonStyle {
    var size: CGFloat = 34
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
            .contentShape(Circle())
            .glassEffect(.regular.interactive(), in: .circle)
            .opacity(isEnabled ? 1 : 0.4)
    }
}

/// A small green dot while connected, grey otherwise.
struct LiveDot: View {
    var live: Bool
    var body: some View {
        Circle()
            .fill(live ? Color.good : Color.secondary.opacity(0.5))
            .frame(width: 7, height: 7)
            .animation(Motion.fast, value: live)
            .accessibilityHidden(true)
    }
}

// MARK: - Gauges

/// Battery as a ring, as in the Batteries widget: green, red when low and
/// not charging.
struct BatteryRing: View {
    var percent: Int
    var charging: Bool
    var diameter: CGFloat = 96
    var lineWidth: CGFloat = 9

    private var colour: Color { percent <= 20 && !charging ? .signal : .good }

    var body: some View {
        ZStack {
            Circle().stroke(Color.raised, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(percent, 0), 100)) / 100)
                .stroke(colour, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
        .frame(width: diameter, height: diameter)
        .animation(Motion.medium, value: percent)
        .accessibilityHidden(true)
    }
}

/// The equaliser as rounded bars, each filled from the bottom to its level
/// (0…1), the way a graphic EQ reads.
struct EqualizerBars: View {
    var levels: [Double]

    var body: some View {
        GeometryReader { geo in
            let n = CGFloat(max(levels.count, 1))
            let spacing = geo.size.width / n * 0.45
            let w = (geo.size.width - spacing * (n - 1)) / n
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(levels.indices, id: \.self) { i in
                    Capsule()
                        .fill(Color.raised)
                        .overlay(alignment: .bottom) {
                            Capsule()
                                .fill(.tint)
                                .frame(height: max(w, geo.size.height * levels[i]))
                        }
                        .frame(width: w)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A System Settings icon: a white symbol on a coloured rounded square.
struct SettingsIcon: View {
    let symbol: String
    let colour: Color
    var size: CGFloat = 26

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).fill(colour.gradient))
            .accessibilityHidden(true)
    }
}
