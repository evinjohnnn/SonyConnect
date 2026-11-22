import SwiftUI
import MDRKit

// Shape lock for this app: grouped rows and sheets use the system Form shapes;
// custom controls are circles (mode buttons, status dots) or capsules (tags).
// No other corner radii are introduced here.

// MARK: - Devices

extension PairedDevice {
    /// macOS lists an LE-audio pairing of the same headphones as a separate
    /// device named `LE_<name>`; it has no RFCOMM control channel.
    var isLEEntry: Bool { name.hasPrefix("LE_") }

    /// Sony-like classic entries first, connected before idle, LE entries last.
    static func preferred(_ devices: [PairedDevice]) -> [PairedDevice] {
        devices.filter(\.isSonyLike).sorted { a, b in
            if a.isLEEntry != b.isLEEntry { return !a.isLEEntry }
            if a.isConnected != b.isConnected { return a.isConnected }
            return false
        }
    }
}

// MARK: - Noise control presentation

extension NoiseControlChoice {
    /// Title-case labels, as Mac controls and menus use.
    var uiTitle: String {
        switch self {
        case .noiseCancelling: return "Noise Cancelling"
        case .ambient: return "Ambient Sound"
        case .off: return "Off"
        }
    }

    /// One symbol family: the listener, isolated, open to the room, or neither.
    var uiSymbol: String {
        switch self {
        case .noiseCancelling: return "person.and.background.dotted"
        case .ambient: return "person.wave.2"
        case .off: return "person"
        }
    }
}

/// The primary control of the app: three modes, laid out like the Control
/// Center module people already know for headphones.
struct NoiseModeSelector: View {
    let selection: NoiseControlChoice?
    var pending: Bool = false
    var compact: Bool = false
    let onSelect: (NoiseControlChoice) -> Void

    var body: some View {
        HStack(spacing: compact ? 4 : 8) {
            ForEach(NoiseControlChoice.allCases) { choice in
                let isOn = choice == selection
                Button {
                    if !isOn { onSelect(choice) }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: choice.uiSymbol)
                            .font(.system(size: compact ? 14 : 16, weight: .medium))
                            .foregroundStyle(isOn ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
                            .frame(width: compact ? 32 : 38, height: compact ? 32 : 38)
                            .background(
                                Circle().fill(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary))
                            )
                            .opacity(isOn && pending ? 0.6 : 1)
                        Text(choice.uiTitle)
                            .font(compact ? .caption : .callout)
                            .foregroundStyle(isOn ? .primary : .secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressDimStyle())
                .accessibilityLabel(choice.uiTitle)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(.vertical, compact ? 2 : 4)
        .animation(.easeOut(duration: 0.15), value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Noise control")
    }
}

/// Mac press feedback: controls darken on press and never scale.
struct PressDimStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

// MARK: - Status

extension SessionPhase {
    var tint: Color {
        switch self {
        case .ready: return .green
        case .error, .unsupported: return .red
        case .disconnected, .suspended: return .secondary
        default: return .orange
        }
    }

    var isBusy: Bool {
        switch self {
        case .connecting, .handshaking, .discoveringCapabilities, .syncing, .reconnecting:
            return true
        default:
            return false
        }
    }
}

struct StatusLine: View {
    let phase: SessionPhase
    var pendingWrite: Bool = false
    var activity: String = ""

    var body: some View {
        HStack(spacing: 6) {
            if phase.isBusy {
                ProgressView().controlSize(.mini)
            } else {
                Circle().fill(phase.tint).frame(width: 7, height: 7)
            }
            Text(label)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }

    private var label: String {
        if phase.isBusy, !activity.isEmpty { return activity }
        if phase == .ready, pendingWrite { return "Applying…" }
        return phase == .ready ? "Connected" : phase.label
    }
}

/// Battery level with the system battery glyph that matches it.
struct BatteryLabel: View {
    let percent: Int
    let charging: ChargingState

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(percent <= 15 && charging != .charging ? .red : .primary)
                .font(.system(size: 15))
            Text("\(percent)%")
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(percent)))
            if !charging.label.isEmpty, charging != .notCharging {
                Text(charging.label)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        if charging == .charging { return "battery.100percent.bolt" }
        switch percent {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }
}

// MARK: - Equalizer curve

/// The reported band curve, drawn as a response line over a 0 dB reference.
/// Values come from the device, in device order; nothing is interpolated into
/// the data itself, only into the drawn line.
struct EqualizerCurve: View {
    let bands: [UInt8]
    let bandStep: UInt8

    static let frequencies = ["31", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

    private var top: Double {
        let steps = Double(max(Int(bandStep), Int(bands.max() ?? 0) + 1, 2))
        return steps - 1
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let points = layout(in: geo.size)
                ZStack {
                    // 0 dB reference.
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                        p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
                    }
                    .stroke(.separator, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                    Self.smooth(points, closingAt: geo.size.height)
                        .fill(.tint.opacity(0.14))
                    Self.smooth(points, closingAt: nil)
                        .stroke(.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    ForEach(points.indices, id: \.self) { i in
                        Circle()
                            .fill(.background)
                            .overlay(Circle().strokeBorder(.tint, lineWidth: 1.5))
                            .frame(width: 7, height: 7)
                            .position(points[i])
                    }
                }
            }
            .frame(height: 84)

            if bands.count == Self.frequencies.count {
                HStack(spacing: 0) {
                    ForEach(Self.frequencies, id: \.self) { f in
                        Text(f)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .animation(.smooth(duration: 0.25), value: bands)
        .accessibilityElement()
        .accessibilityLabel("Equalizer curve")
        .accessibilityValue(bands.map(String.init).joined(separator: ", "))
    }

    private func layout(in size: CGSize) -> [CGPoint] {
        guard !bands.isEmpty else { return [] }
        let slot = size.width / CGFloat(bands.count)
        let inset: CGFloat = 6
        return bands.enumerated().map { i, v in
            let t = CGFloat(Double(v) / top)
            return CGPoint(
                x: slot * (CGFloat(i) + 0.5),
                y: inset + (1 - t) * (size.height - inset * 2)
            )
        }
    }

    /// Catmull-Rom through the points, optionally closed down to `bottom`.
    private static func smooth(_ pts: [CGPoint], closingAt bottom: CGFloat?) -> Path {
        Path { p in
            guard let first = pts.first, let last = pts.last else { return }
            if let bottom {
                p.move(to: CGPoint(x: first.x, y: bottom))
                p.addLine(to: first)
            } else {
                p.move(to: first)
            }
            for i in 0..<(pts.count - 1) {
                let p0 = pts[max(i - 1, 0)], p1 = pts[i], p2 = pts[i + 1]
                let p3 = pts[min(i + 2, pts.count - 1)]
                let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
                let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
                p.addCurve(to: p2, control1: c1, control2: c2)
            }
            if let bottom {
                p.addLine(to: CGPoint(x: last.x, y: bottom))
                p.closeSubpath()
            }
        }
    }
}

// MARK: - Rows

/// A toggle row with a one-line explanation under the title, as System
/// Settings writes them.
struct DescribedToggle: View {
    let title: String
    var detail: String? = nil
    let isOn: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: onChange)) {
            Text(title)
            if let detail {
                Text(detail)
            }
        }
        .toggleStyle(.switch)
    }
}

/// A slider that reports its value only when the drag settles, so the
/// stop-and-wait link sees one write per gesture instead of dozens.
struct SettlingSlider: View {
    let title: String
    let value: Int
    let range: ClosedRange<Int>
    var format: (Int) -> String = { "\($0)" }
    let onCommit: (Int) -> Void

    @State private var dragging: Int?

    var body: some View {
        LabeledContent {
            HStack(spacing: 12) {
                GlassSlider(
                    value: Binding(
                        get: { Double(dragging ?? value) },
                        set: { dragging = Int($0.rounded()) }
                    ),
                    range: Double(range.lowerBound)...Double(range.upperBound),
                    style: .lens,
                    label: title,
                    valueText: { format(Int($0.rounded())) }
                ) { editing in
                    if !editing, let settled = dragging {
                        dragging = nil
                        if settled != value { onCommit(settled) }
                    }
                }
                .frame(minWidth: 160, maxWidth: 260)
                Text(format(dragging ?? value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: Double(dragging ?? value)))
                    .frame(minWidth: 26, alignment: .trailing)
            }
        } label: {
            Text(title)
        }
    }
}

// MARK: - Glass segmented control

/// A segmented control on the app's Liquid Glass vocabulary: a quiet
/// track, and the chosen segment as a white glass lens that slides to the
/// next choice (0.25 s, smooth). Hover lightens a segment; VoiceOver and
/// the keyboard get a standard picker.
struct GlassSegmented<Value: Hashable & Identifiable>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String

    @Namespace private var lens
    @State private var hovered: Value.ID?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                let on = option.id == selection.id
                Button {
                    withAnimation(Motion.fast) { selection = option }
                } label: {
                    Text(title(option))
                        .font(.callout.weight(on ? .semibold : .regular))
                        .foregroundStyle(on ? .primary : .secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background {
                            if on {
                                Capsule()
                                    .fill(Color.thumb.opacity(0.85))
                                    .glassEffect(.regular.interactive(), in: .capsule)
                                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                                    .matchedGeometryEffect(id: "lens", in: lens)
                            } else if hovered == option.id {
                                Capsule().fill(Color.primary.opacity(0.05))
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? option.id : (hovered == option.id ? nil : hovered) }
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.raised))
        .animation(Motion.quick, value: hovered)
        .accessibilityRepresentation {
            Picker("", selection: $selection) {
                ForEach(options) { Text(title($0)).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }
}

// MARK: - Pull-down picker

/// A setting chosen from a list, as a pull-down: the menu drops straight
/// below the control with its leading edge on the control's, instead of a
/// pop-up that opens over the control, shifted to line the checked item up
/// with the label (which reads as misaligned in a grouped form). The
/// control shows the current value and the system pull-down chevron.
struct PullDownPicker<Value: Hashable, Content: View>: View {
    let title: String
    let current: String
    @Binding var selection: Value
    @ViewBuilder let content: Content

    init(_ title: String, current: String, selection: Binding<Value>, @ViewBuilder content: () -> Content) {
        self.title = title
        self.current = current
        _selection = selection
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            Menu {
                Picker(title, selection: $selection) { content }
                    .pickerStyle(.inline)
                    .labelsHidden()
            } label: {
                Text(current).lineLimit(1)
            }
            .menuStyle(.button)
            .menuIndicator(.visible)
            .buttonStyle(.glass)
            .fixedSize()
            .accessibilityLabel(title)
            .accessibilityValue(current)
        }
    }
}
