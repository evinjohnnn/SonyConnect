import SwiftUI
import AppKit
import MDRKit

// The device header, built the way Apple builds the AirPods pane in System
// Settings and the noise controls in Control Center:
//
// - Content layer: the product picture, name and battery sit on the plain
//   grouped background, in system text styles. No glass here.
// - Functional layer: the three noise modes are floating Liquid Glass
//   buttons in one `GlassEffectContainer`, so the selection morphs between
//   them. The selected mode is the only tinted glass on the page.
// - One accent: the system accent colour. Semantic colours everywhere else,
//   so light, dark, increased contrast and Reduce Transparency come free.

// MARK: - Palette


// MARK: - Product

// MARK: - Noise modes

extension Color {
    /// The selector's track: iOS tertiary system fill.
    static let selectorTrack = Color.raised
}

/// The AirPods listening-mode control: icons in a grey capsule, a raised pill
/// on the chosen mode, labels underneath. The pill can be dragged; while
/// held it turns into a clear glass lens and it snaps to the nearest mode on
/// release. Ordered from open to isolated, as Apple orders it.
struct ListeningModeSelector: View {
    let selection: NoiseControlChoice?
    var pending: Bool = false
    let onSelect: (NoiseControlChoice) -> Void

    static let order: [NoiseControlChoice] = [.off, .ambient, .noiseCancelling]

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragX: CGFloat?
    @State private var chosen: NoiseControlChoice?
    @State private var keyboardActive = false
    @State private var hovered: Int?
    @State private var pressed: Int?
    @State private var bounces: [NoiseControlChoice: Int] = [:]
    @FocusState private var focused: Bool

    private let height: CGFloat = 40
    private let inset: CGFloat = 4

    /// What the pill shows: the tap just made, until the device answers.
    private var shown: NoiseControlChoice? { chosen ?? selection }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let seg = geo.size.width / CGFloat(Self.order.count)
                let index = shown.flatMap { Self.order.firstIndex(of: $0) }
                let restX = index.map { seg * (CGFloat($0) + 0.5) }
                let x = dragX.map { min(max($0, seg / 2), geo.size.width - seg / 2) } ?? restX

                ZStack(alignment: .leading) {
                    Capsule().fill(Color.selectorTrack)

                    // Mac feedback: hover lightens a segment, press darkens
                    // it a little more. Never on the selected one.
                    if let i = pressed ?? hovered, Self.order[i] != shown, dragX == nil {
                        Capsule()
                            .fill(Color.primary.opacity(pressed != nil ? 0.10 : 0.05))
                            .frame(width: seg - inset * 2, height: height - inset * 2)
                            .offset(x: seg * CGFloat(i) + inset)
                            .transition(.opacity)
                    }

                    if let x {
                        thumb(width: seg - inset * 2)
                            .offset(x: x - seg / 2 + inset)
                    }

                    HStack(spacing: 0) {
                        ForEach(Self.order) { choice in
                            // Before the first layout the width is 0, and 0 / 0 is NaN.
                            let on = seg > 0 && Self.order.firstIndex(of: choice) == x.map { max(0, min(Int($0 / seg), Self.order.count - 1)) }
                            HStack(spacing: 6) {
                                Image(systemName: choice.selectorSymbol)
                                    .font(.body.weight(.medium))
                                    .symbolEffect(.bounce.down, options: .speed(1.3),
                                                  value: bounces[choice, default: 0])
                                Text(choice.uiTitle)
                                    .font(.body.weight(on ? .semibold : .regular))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                            .foregroundStyle(Color.primary)
                            .padding(.horizontal, 6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .allowsHitTesting(false)
                }
                .contentShape(Capsule())
                .gesture(drag(segment: seg, width: geo.size.width))
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let p): hovered = min(max(Int(p.x / seg), 0), Self.order.count - 1)
                    case .ended: hovered = nil
                    }
                }
                .animation(hovered == nil && pressed == nil ? Motion.hoverOut : Motion.quick,
                           value: (pressed ?? hovered) ?? -1)
                // Keyboard moves are instant; a released drag settles with
                // its momentum; a click glides.
                .animation(keyboardActive ? nil
                           : dragX != nil ? .interactiveSpring(duration: 0.15)
                           : Motion.settle,
                           value: x)
            }
            .frame(height: height)
            .overlay {
                if focused && keyboardActive {
                    Capsule().strokeBorder(.tint.opacity(0.6), lineWidth: 3).padding(-4)
                }
            }

        }
        .opacity(isEnabled ? 1 : 0.45)
        .focusable(isEnabled)
        .focusEffectDisabled()
        .focused($focused)
        .onChange(of: focused) { if !focused { keyboardActive = false } }
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
            keyboardActive = true
            let i = shown.flatMap { Self.order.firstIndex(of: $0) } ?? 0
            let next = press.key == .rightArrow ? min(i + 1, Self.order.count - 1) : max(i - 1, 0)
            choose(Self.order[next])
            return .handled
        }
        .onChange(of: selection) { _, new in
            // A change made on the headphones themselves gets the same
            // acknowledgement as a click here.
            if chosen == nil, let new { bounces[new, default: 0] += 1 }
            chosen = nil
        }
        .task(id: chosen) {
            // Fall back to the device's report if it never confirms.
            guard chosen != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            chosen = nil
        }
        .accessibilityRepresentation {
            Picker("Noise Control", selection: Binding(
                get: { shown ?? .off },
                set: { choose($0) }
            )) {
                ForEach(Self.order) { Text($0.uiTitle).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    /// A glass pill at rest; a clear glass lens while held.
    private func thumb(width: CGFloat) -> some View {
        let held = dragX != nil
        // Liquid Glass: frosted and lightly tinted at rest so the label on
        // it reads; a clear lens that swells past the track while dragged.
        return Capsule()
            .fill(Color.thumb.opacity(held ? 0.15 : 0.8))
            .frame(width: width, height: height - inset * 2)
            .glassEffect(.clear.interactive(), in: .capsule)
            .shadow(color: .black.opacity(held ? 0.16 : 0.08), radius: held ? 8 : 3, y: held ? 3 : 1)
            .opacity(pending ? 0.75 : 1)
            .scaleEffect(held && !reduceMotion ? CGSize(width: 1.1, height: 1.3) : CGSize(width: 1, height: 1))
            .animation(held ? Motion.lift : Motion.quick, value: held)
    }

    private func drag(segment: CGFloat, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                guard isEnabled else { return }
                keyboardActive = false
                // A press that has not moved is a tap; only a real drag
                // lifts the pill.
                if dragX != nil || abs(g.translation.width) > 4 {
                    dragX = g.location.x
                    pressed = nil
                } else {
                    pressed = min(max(Int(g.location.x / segment), 0), Self.order.count - 1)
                }
            }
            .onEnded { g in
                pressed = nil
                guard isEnabled else { dragX = nil; return }
                let i = min(max(Int(g.location.x / segment), 0), Self.order.count - 1)
                dragX = nil
                choose(Self.order[i])
            }
    }

    private func choose(_ choice: NoiseControlChoice) {
        guard choice != shown else { return }
        chosen = choice
        if !keyboardActive { bounces[choice, default: 0] += 1 }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        onSelect(choice)
    }
}

extension NoiseControlChoice {
    /// Filled listener symbols, as in the AirPods listening-mode control.
    var selectorSymbol: String {
        switch self {
        case .noiseCancelling: return "person.and.background.dotted"
        case .ambient: return "person.wave.2.fill"
        case .off: return "person.fill"
        }
    }
}

// MARK: - Battery

/// Battery as the system shows it: a glyph and a percentage.
struct BatteryReadout: View {
    let percent: Int
    let charging: ChargingState

    private var low: Bool { percent <= 15 && charging != .charging }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(low ? Color.red : Color.secondary)
            Text("\(percent)%")
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(percent)))
                .foregroundStyle(low ? Color.red : Color.secondary)
        }
        .animation(Motion.fast, value: percent)
        .font(.body)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery")
        .accessibilityValue(charging == .charging ? "\(percent) percent, charging" : "\(percent) percent")
    }

    private var symbol: String {
        if charging == .charging { return "battery.100percent.bolt" }
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

// MARK: - Header

/// The top of the headphone page: picture, name, status, battery and the
/// noise modes. Sits in a Form section header, on the content layer.
struct ListeningStage: View {
    @EnvironmentObject private var session: HeadphoneSession
    @AppStorage(Pref.headphoneFinish) private var finish: HeadphoneFinish = .black
    let device: PairedDevice

    private var status: HeadphoneStatus { session.status }
    private var model: String { status.model.isEmpty ? device.displayName : status.model }

    var body: some View {
        VStack(spacing: 0) {
            ProductDisc(model: model, color: status.modelColor, finish: finish,
                        diameter: 340, searching: status.phase.isBusy && status.model.isEmpty, bare: true)
                .frame(maxWidth: .infinity)
                .padding(.top, -12)
                .entrance(0)

            // What is playing over the air, on the page under the product.
            if !status.codec.isEmpty {
                codecRow
                    .padding(.top, -30)
                    .padding(.bottom, 12)
                    .entrance(1)
                    .transition(.opacity)
            }

            // The controls float up over the product's shadow.
            if status.noiseControl.choice != nil || status.volume != nil {
                Tile {
                    VStack(spacing: 14) {
                        if let choice = status.noiseControl.choice {
                            ListeningModeSelector(selection: choice, pending: status.pendingWrite) {
                                session.setNoiseControl($0)
                            }
                            .disabled(!session.isReady)
                        }
                        levelBars
                    }
                }
                .padding(.top, status.codec.isEmpty ? -34 : 0)
                .entrance(2)
                .transition(.settle)
            }
        }
        .animation(Motion.fast, value: status.noiseControl.choice)
        // The volume arrives seconds after the rest: a cross-fade over its
        // placeholder (or, the first time, a settle-in).
        .animation(Motion.fast, value: status.volume == nil)
    }

    /// The Bluetooth codec, and upscaling when it is on: a quiet caption
    /// centred under the product, on the page rather than in a card.
    private var codecRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .foregroundStyle(.secondary)
            Text(status.codec)
                .font(.body.weight(.semibold))
                .contentTransition(.opacity)
            if status.upscaling == true {
                Text("·").foregroundStyle(.tertiary)
                Text("Upscaling").foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.raised))
        .frame(maxWidth: .infinity)
        .animation(Motion.fast, value: status.codec)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Audio codec \(status.codec)\(status.upscaling == true ? ", upscaling on" : "")")
    }

    /// Control Center bars for the levels you reach for most.
    /// Whether these headphones have reported a volume before.
    private var expectsVolume: Bool {
        UserDefaults.standard.bool(forKey: Pref.hasVolume(device.address))
    }

    @ViewBuilder
    private var levelBars: some View {
        let volume = status.volume.flatMap { $0.max > 0 ? $0 : nil }
        VStack(spacing: 12) {
            if volume == nil && expectsVolume {
                // The volume is read last, seconds after the rest. Keep its
                // place with an empty bar so the page does not shift when
                // it lands; the real bar cross-fades in over it.
                VolumePlaceholder()
                    .transition(.opacity)
            }
            if let volume {
                SettlingGlassBar(
                    label: "Volume",
                    symbol: { v in
                        let t = Double(v) / Double(volume.max)
                        return v == 0 ? "speaker.slash.fill"
                            : t < 0.34 ? "speaker.wave.1.fill"
                            : t < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
                    },
                    value: volume.value, range: 0...volume.max,
                    live: true, inline: true
                ) { session.setMusicVolume($0) }
                .disabled(!session.isReady)
                .transition(.opacity)
                .onAppear { UserDefaults.standard.set(true, forKey: Pref.hasVolume(device.address)) }
            }
            if case .ambient(let voice, let level) = status.noiseControl {
                SettlingGlassBar(
                    label: voice ? "Ambient Sound, Voice Focus" : "Ambient Sound",
                    symbol: { _ in "ear" },
                    value: level, range: 0...20, inline: true
                ) { session.setAmbientLevel($0) }
                .disabled(!session.isReady)
                .transition(.settle)
            }
        }
    }
}

/// Where the volume bar will be: the same row, empty and quiet.
private struct VolumePlaceholder: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.body)
                .foregroundStyle(.tertiary)
                .frame(width: 22)
            Capsule()
                .fill(Color.raised)
                .frame(height: 24)
            Color.clear.frame(width: 34, height: 1)
        }
        .padding(.horizontal, 4)
        .accessibilityLabel("Volume, loading")
    }
}
