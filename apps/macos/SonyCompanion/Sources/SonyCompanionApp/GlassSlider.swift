import SwiftUI
import AppKit

/// A Liquid Glass slider in two styles.
///
/// - `.lens`: the iOS 26 slider. A thin track and a white pill thumb that
///   turns into a clear glass lens while it is held, so the track shows
///   through it, magnified. Clicking the track jumps there.
/// - `.bar`: the Control Center slider. A thick glass capsule that fills
///   with the accent from its start (or from its centre when `bipolar`),
///   with an optional symbol inside. Dragging moves the value relative to
///   where the drag began, so a grab never jumps.
///
/// Values snap to `step`. Each step passed gives a trackpad tick. Arrow keys
/// adjust a focused slider; VoiceOver gets an adjustable element. Reduce
/// Motion removes the lens swell; Reduce Transparency is handled by the
/// glass itself.
struct GlassSlider: View {
    enum Style { case lens, bar }

    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var axis: Axis = .horizontal
    var style: Style = .lens
    /// Fill from the middle of the range instead of its start (`.bar` only).
    var bipolar = false
    /// Symbol drawn inside a `.bar` at its start.
    var symbol: String? = nil
    /// Cross-axis size: track height for `.lens`, capsule thickness for `.bar`.
    var thickness: CGFloat? = nil
    var label: String
    var valueText: (Double) -> String = { String(Int($0.rounded())) }
    /// Called with `true` when a drag or key press starts changing the value
    /// and `false` when it settles; commit on `false`.
    var onEditingChanged: (Bool) -> Void = { _ in }
    /// How a value set from outside (the device reporting a change) moves
    /// the slider. A drag always follows the finger directly.
    var externalAnimation: Animation? = Motion.fast

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragging = false
    @State private var grabValue: Double?
    @State private var lastTick: Double?
    @FocusState private var focused: Bool
    /// The focus ring shows once the keyboard is in use, not on click or at
    /// window open.
    @State private var keyboardActive = false

    private var span: Double { max(range.upperBound - range.lowerBound, .ulpOfOne) }
    private var fraction: Double { min(max((value - range.lowerBound) / span, 0), 1) }
    private var cross: CGFloat { thickness ?? (style == .bar ? 36 : 6) }

    var body: some View {
        GeometryReader { geo in
            let length = axis == .horizontal ? geo.size.width : geo.size.height
            ZStack {
                switch style {
                case .lens: lens(length: length)
                case .bar: bar(length: length)
                }
            }
            .animation(dragging ? nil : externalAnimation, value: value)
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(drag(length: length))
        }
        .frame(width: axis == .vertical ? frameCross : nil,
               height: axis == .horizontal ? frameCross : nil)
        .opacity(isEnabled ? 1 : 0.45)
        .focusable(isEnabled)
        .focusEffectDisabled()
        .focused($focused)
        .overlay {
            if focused && keyboardActive {
                Capsule()
                    .strokeBorder(.tint.opacity(0.6), lineWidth: 3)
                    .padding(style == .bar ? -4 : 2)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: focused) { if !focused { keyboardActive = false } }
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            keyboardActive = true
            let up = press.key == .rightArrow || press.key == .upArrow
            nudge(up ? step : -step)
            return .handled
        }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(valueText(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: nudge(step)
            case .decrement: nudge(-step)
            @unknown default: break
            }
        }
    }

    /// Room on the cross axis: the lens thumb swells past the track.
    private var frameCross: CGFloat { style == .bar ? cross : 30 }

    // MARK: Lens

    private let thumbAlong: CGFloat = 30
    private let thumbAcross: CGFloat = 20

    @ViewBuilder
    private func lens(length: CGFloat) -> some View {
        let usable = max(length - thumbAlong, 1)
        let pos = thumbAlong / 2 + usable * fraction   // from the start edge

        // Track and fill.
        ZStack(alignment: axis == .horizontal ? .leading : .bottom) {
            Capsule().fill(.quaternary)
            Capsule().fill(.tint)
                .frame(width: axis == .horizontal ? pos : nil,
                       height: axis == .vertical ? pos : nil)
        }
        .frame(width: axis == .horizontal ? length : cross,
               height: axis == .vertical ? length : cross)

        // Thumb: a white pill at rest, a clear glass lens while held.
        Capsule()
            .fill(.white)
            .opacity(dragging ? 0 : 1)
            .shadow(color: .black.opacity(dragging ? 0 : 0.22), radius: 2, y: 1)
            .frame(width: axis == .horizontal ? thumbAlong : thumbAcross,
                   height: axis == .vertical ? thumbAlong : thumbAcross)
            .glassEffect(dragging ? .clear.interactive() : .identity, in: .capsule)
            .scaleEffect(dragging && !reduceMotion ? 1.45 : 1)
            .offset(x: axis == .horizontal ? pos - length / 2 : 0,
                    y: axis == .vertical ? length / 2 - pos : 0)
            // Lifting the lens has life; letting go is quick and flat.
            .animation(dragging ? Motion.lift : Motion.quick, value: dragging)
    }

    // MARK: Bar

    @ViewBuilder
    private func bar(length: CGFloat) -> some View {
        let r = cross / 2
        let usable = max(length - cross, 1)
        let pos = r + usable * fraction
        let origin = bipolar ? r + usable * 0.5 : r
        let lo = min(origin, pos) - r
        let hi = max(origin, pos) + r

        ZStack(alignment: axis == .horizontal ? .leading : .bottom) {
            Capsule()
                .fill(.tint)
                .frame(width: axis == .horizontal ? hi - lo : nil,
                       height: axis == .vertical ? hi - lo : nil)
                .offset(x: axis == .horizontal ? lo : 0, y: axis == .vertical ? -lo : 0)

            if bipolar {
                // The zero line.
                Capsule()
                    .fill(.primary.opacity(0.25))
                    .frame(width: axis == .horizontal ? 1.5 : cross * 0.5,
                           height: axis == .vertical ? 1.5 : cross * 0.5)
                    .offset(x: axis == .horizontal ? origin - 0.75 : 0,
                            y: axis == .vertical ? -(origin - 0.75) : 0)
            }

            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: cross * 0.4, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: cross, height: cross)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .frame(width: axis == .horizontal ? length : cross,
               height: axis == .vertical ? length : cross,
               alignment: axis == .horizontal ? .leading : .bottom)
        .background(Color.raised)
        .clipShape(Capsule())
        .scaleEffect(dragging && !reduceMotion ? (axis == .horizontal ? CGSize(width: 1.015, height: 1.08)
                                                                       : CGSize(width: 1.08, height: 1.015))
                                               : CGSize(width: 1, height: 1))
        .animation(dragging ? Motion.lift : Motion.quick, value: dragging)
    }

    // MARK: Input

    private func drag(length: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                guard isEnabled else { return }
                if !dragging {
                    dragging = true
                    grabValue = value
                    lastTick = value
                    keyboardActive = false
                    onEditingChanged(true)
                }
                let along = axis == .horizontal ? g.location.x : length - g.location.y
                switch style {
                case .lens:
                    let usable = max(length - thumbAlong, 1)
                    set(range.lowerBound + Double((along - thumbAlong / 2) / usable) * span)
                case .bar:
                    let moved = axis == .horizontal ? g.translation.width : -g.translation.height
                    let usable = max(length - cross, 1)
                    set((grabValue ?? value) + Double(moved / usable) * span)
                }
            }
            .onEnded { _ in
                guard dragging else { return }
                dragging = false
                grabValue = nil
                onEditingChanged(false)
            }
    }

    private func set(_ raw: Double) {
        let snapped = (raw / step).rounded() * step
        let clamped = min(max(snapped, range.lowerBound), range.upperBound)
        guard clamped != value else { return }
        value = clamped
        if clamped != lastTick, span / step <= 64 {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        lastTick = clamped
    }

    private func nudge(_ delta: Double) {
        guard isEnabled else { return }
        let next = min(max(value + delta, range.lowerBound), range.upperBound)
        guard next != value else { return }
        onEditingChanged(true)
        value = next
        onEditingChanged(false)
    }
}

// MARK: - Settling bar

/// A Control Center bar that writes once, when the drag settles. The value
/// shown follows the finger, then the device's report.
struct SettlingGlassBar: View {
    let label: String
    var symbol: (Int) -> String
    let value: Int
    let range: ClosedRange<Int>
    var thickness: CGFloat = 44
    var format: (Int) -> String = { "\($0)" }
    /// Write every step while dragging, not only on release. For settings
    /// you judge by ear, such as volume; the engine keeps only the newest
    /// unsent value, so a fast drag cannot build a backlog.
    var live = false
    /// One row: symbol, a slim bar, the value. Without it the
    /// label and value sit above a thick bar with the symbol inside.
    var inline = false
    let onCommit: (Int) -> Void

    @State private var dragging: Int?
    @State private var lastSent: Int?

    var body: some View {
        if inline {
            HStack(spacing: 12) {
                Image(systemName: symbol(dragging ?? value))
                    .font(.body)
                    .frame(width: 22)
                    .contentTransition(.symbolEffect(.replace))
                slider
                value(.title3)
                    .frame(width: 34, alignment: .trailing)
            }
            .padding(.horizontal, 4)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    StageLabel(label)
                    Spacer()
                    value(.body)
                        .foregroundStyle(.secondary)
                }
                slider
            }
        }
    }

    private func value(_ style: Font) -> some View {
        Text(format(dragging ?? value))
            .font(style.weight(.semibold))
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(dragging ?? value)))
            .animation(Motion.quick, value: dragging ?? value)
    }

    private var slider: some View {
            GlassSlider(
                value: Binding(
                    get: { Double(dragging ?? value) },
                    set: {
                        let step = Int($0.rounded())
                        dragging = step
                        if live, step != (lastSent ?? value) {
                            lastSent = step
                            onCommit(step)
                        }
                    }
                ),
                range: Double(range.lowerBound)...Double(range.upperBound),
                style: .bar,
                symbol: inline ? nil : symbol(dragging ?? value),
                thickness: inline ? 24 : thickness,
                label: label,
                valueText: { format(Int($0.rounded())) }
            ) { editing in
                if !editing, let settled = dragging {
                    dragging = nil
                    if settled != (live ? lastSent ?? value : value) { onCommit(settled) }
                    lastSent = nil
                }
            }
    }
}

// MARK: - Equalizer

/// Ten vertical glass bars, each filling from 0 dB, edited in place. A band
/// is written when its drag settles; the curve then shows the device's
/// report. Band centres are 31 Hz to 16 kHz; the device's step count sets
/// the range (13 steps on the WH-1000XM6, shown as −6…+6).
struct GlassEqualizer: View {
    let bands: [UInt8]
    let bandStep: UInt8
    let onCommit: ([UInt8]) -> Void

    @State private var local: [Double]?
    @State private var commits = 0

    static let frequencies = ["31", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

    private var steps: Int { max(2, Int(bandStep), Int(bands.max() ?? 0) + 1) }
    private var centre: Double { Double((steps - 1) / 2) }

    var body: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(bands.indices, id: \.self) { i in
                    column(i).frame(maxWidth: .infinity)
                }
            }
        }
        .onChange(of: bands) { local = nil }
        .task(id: commits) {
            // If the device never confirms, fall back to what it reported.
            guard commits > 0 else { return }
            try? await Task.sleep(for: .seconds(3))
            local = nil
        }
    }

    private func current(_ i: Int) -> Double { local?[i] ?? Double(bands[i]) }

    private func db(_ v: Double) -> String {
        let d = Int((v - centre).rounded())
        return d > 0 ? "+\(d)" : "\(d)"
    }

    private func column(_ i: Int) -> some View {
        let name = Self.frequencies.indices.contains(i) ? Self.frequencies[i] : "\(i + 1)"
        return VStack(spacing: 8) {
            Text(db(current(i)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(current(i) == centre ? .tertiary : .secondary)
                .contentTransition(.numericText(value: current(i)))
                .animation(Motion.quick, value: current(i))
            GlassSlider(
                value: Binding(
                    get: { current(i) },
                    set: { v in
                        var next = local ?? bands.map(Double.init)
                        next[i] = v
                        local = next
                    }
                ),
                range: 0...Double(steps - 1),
                axis: .vertical,
                style: .bar,
                bipolar: true,
                thickness: 30,
                label: "\(name) hertz",
                valueText: { "\(db($0)) decibels" },
                // A new preset arrives as a wave, low bands first.
                externalAnimation: Motion.settle.delay(Double(i) * 0.02)
            ) { editing in
                guard !editing, let local else { return }
                let next = local.map { UInt8($0.rounded()) }
                if next != bands {
                    commits += 1
                    onCommit(next)
                }
            }
            .frame(height: 180)
            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
