import SwiftUI
import AppKit
import MDRKit

/// The menu bar panel, measured against the module macOS draws for AirPods
/// (Sound in the menu bar, macOS 26+): a bold title, the system slider with
/// speaker glyphs, the device as a row with its battery beneath the name, and
/// its settings in a tinted band listed as checkmark rows with a small
/// symbol. Menu items close the panel.
///
/// Metrics (points): 306 wide, 13 pt text inset; 13 pt body everywhere,
/// semibold secondary section headers; 24 pt choice rows with the check at
/// x 26, the symbol at x 56 and the label at x 73; 22 pt menu items.
///
/// Motion: none. Like a menu, every change lands at once.
struct MenuBarPanel: View {
    @EnvironmentObject private var session: HeadphoneSession
    @EnvironmentObject private var ui: AppUI
    @Environment(\.openWindow) private var openWindow
    @AppStorage("panelDeviceExpanded") private var expanded = true

    private var status: HeadphoneStatus { session.status }

    /// Whether the device has reported anything the band can show. While
    /// connecting it has not, and the band stays closed.
    private var hasSettings: Bool {
        status.noiseControl.choice != nil || status.smartTalking != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Headphones")
                .font(.headline)
                .padding(.horizontal, Metric.inset)
                .padding(.top, 12)
                .padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)

            if let device = session.connected {
                if let level = status.volume, level.max > 0 {
                    VolumeSlider(level: level) { session.setMusicVolume($0) }
                        .disabled(!session.isReady)
                        .padding(.horizontal, Metric.inset)
                        .padding(.vertical, 4)
                }
                PanelDivider()
                DeviceRow(
                    name: status.model.isEmpty ? device.displayName : status.model,
                    detail: deviceDetail,
                    connected: true,
                    expanded: hasSettings ? expanded : nil
                ) { if hasSettings { expanded.toggle() } }
                if expanded && hasSettings { band }
            } else {
                PanelDivider()
                notConnected
            }

            // The band's own edge separates it from the menu items, as in
            // Sound; without it a hairline does.
            if expanded && hasSettings && session.connected != nil {
                Color.clear.frame(height: 5)
            } else {
                PanelDivider(inset: 4, spacing: 5)
            }
            if let device = session.connected {
                MenuItem("\(status.model.isEmpty ? device.displayName : status.model) Settings…") {
                    // The window shows whichever headphones are selected;
                    // these settings are the connected pair's.
                    ui.selection = device.id
                    NSApp.activate()
                    openWindow(id: "main")
                }
            } else {
                MenuItem("Open Sony Companion…") {
                    NSApp.activate()
                    openWindow(id: "main")
                }
            }
            MenuItem("Quit Sony Companion", shortcut: "⌘Q") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(.bottom, 5)
        .frame(width: Metric.width, alignment: .leading)
    }

    // MARK: Device

    /// The line under the name: battery as AirPods show it, then where the
    /// headphones are, or what the connection is doing.
    private var deviceDetail: DeviceDetail {
        let phase = status.phase
        let state: String
        if phase.isBusy {
            state = session.activity.isEmpty ? phase.label : session.activity
        } else if phase != .ready {
            state = phase.label
        } else {
            switch status.wearingStatus {
            case true?: state = "On your head"
            case false?: state = "Not worn"
            default: state = ""
            }
        }
        return DeviceDetail(percent: status.batteryPercent, charging: status.charging == .charging, state: state)
    }

    // MARK: Band

    /// The device's settings, in the band that opens under it.
    @ViewBuilder
    private var band: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let choice = status.noiseControl.choice {
                SectionHeader("Noise Control")
                ForEach([NoiseControlChoice.noiseCancelling, .ambient, .off]) { mode in
                    ChoiceRow(title: mode.uiTitle, accessibilityTitle: mode.uiTitle, symbol: mode.uiSymbol, on: mode == choice, pending: status.pendingWrite) {
                        session.setNoiseControl(mode)
                    }
                    if mode == .ambient, case .ambient(_, let level) = status.noiseControl {
                        AmbientLevel(level: level) { session.setAmbientLevel($0) }
                    }
                }
            }
            if let talk = status.smartTalking {
                if status.noiseControl.choice != nil { PanelDivider(inset: 4, spacing: 5) }
                SectionHeader("Speak-to-Chat")
                ForEach([false, true], id: \.self) { value in
                    ChoiceRow(title: value ? "On" : "Off", accessibilityTitle: "Speak-to-Chat \(value ? "On" : "Off")",
                              symbol: "waveform.and.person.filled", on: talk.enabled == value, pending: status.pendingWrite) {
                        session.setSmartTalking(value)
                    }
                }
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.055))
        .disabled(!session.isReady)
    }

    // MARK: Not connected

    @ViewBuilder
    private var notConnected: some View {
        let preferred = PairedDevice.preferred(session.devices)
        let candidates = preferred.filter { !$0.isLEEntry }
        if candidates.isEmpty {
            // An LE Audio entry alone has no settings channel; say so rather
            // than claim nothing is paired while the Headphones menu lists it.
            Text(preferred.isEmpty
                 ? "No headphones are paired with this Mac."
                 : "Only an LE Audio pairing was found. Pair the headphones over Bluetooth Classic to change their settings.")
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Metric.inset)
                .padding(.vertical, 6)
        } else {
            ForEach(candidates, id: \.address) { device in
                DeviceRow(
                    name: device.displayName,
                    detail: DeviceDetail(percent: nil, charging: false, state: device.isConnected ? "Connected to this Mac" : "Not connected"),
                    connected: false,
                    expanded: nil
                ) { session.connect(to: device) }
                .disabled(!device.isConnected)
            }
        }
    }
}

// MARK: - Metrics

private enum Metric {
    static let width: CGFloat = 306
    /// Text and icons start 13 pt from the panel edge.
    static let inset: CGFloat = 13
    /// Hover highlights stop 5 pt short of the panel edge.
    static let highlightInset: CGFloat = 5
    static let choiceHeight: CGFloat = 24
    static let menuHeight: CGFloat = 22
    /// Choice-row columns, from the panel edge: check centred at 26,
    /// symbol centred at 56, label from 73.
    static let checkLeading: CGFloat = 18
    static let checkWidth: CGFloat = 16
    static let symbolGap: CGFloat = 12
    static let symbolWidth: CGFloat = 20
    static let labelGap: CGFloat = 7
    static var labelLeading: CGFloat { checkLeading + checkWidth + symbolGap + symbolWidth + labelGap }
}

// MARK: - Parts

/// A section header in the band: 13 pt semibold, secondary.
private struct SectionHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.body.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, Metric.inset)
            .padding(.top, 10)
            .padding(.bottom, 3)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct PanelDivider: View {
    var inset: CGFloat = Metric.inset
    var spacing: CGFloat = 8
    var body: some View {
        Divider()
            .padding(.horizontal, inset)
            .padding(.vertical, spacing)
    }
}

/// The system slider between a quiet and a loud speaker, as in Sound. The
/// level is written at each step, so it can be heard while dragging. The
/// slider shows the level it set until the headphones report it (or a moment
/// passes), so it does not jump back on release. Keyboard and VoiceOver
/// changes go through the same setter and need no drag callbacks.
private struct VolumeSlider: View {
    let level: MusicVolume
    let onCommit: (Int) -> Void
    @State private var shown: Int?
    @State private var editing = false

    var body: some View {
        Slider(
            value: Binding(
                get: { Double(shown ?? level.value) },
                set: { v in
                    let step = Int(v.rounded())
                    if step != (shown ?? level.value) { onCommit(step) }
                    shown = step
                }
            ),
            in: 0...Double(level.max)
        ) {
            Text("Volume")
        } minimumValueLabel: {
            Image(systemName: "speaker.fill").foregroundStyle(.secondary)
        } maximumValueLabel: {
            Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
        } onEditingChanged: { editing = $0 }
        .labelsHidden()
        .controlSize(.regular)
        .accessibilityValue("\(shown ?? level.value) of \(level.max)")
        .onChange(of: level.value) { _, reported in
            if !editing, reported == shown { shown = nil }
        }
        .task(id: Settle(value: shown, editing: editing)) {
            // Fall back to the reported level if no report matches.
            guard shown != nil, !editing else { return }
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { shown = nil }
        }
    }
}

private struct Settle: Equatable {
    let value: Int?
    let editing: Bool
}

struct DeviceDetail {
    let percent: Int?
    let charging: Bool
    let state: String
}

/// A device as Sound lists outputs: a 26 pt circle, filled with the accent
/// while connected, the name, and battery and state beneath it. A chevron
/// opens or closes the settings band.
private struct DeviceRow: View {
    let name: String
    let detail: DeviceDetail
    let connected: Bool
    /// nil when the row has no band to open.
    let expanded: Bool?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "headphones")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(connected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(connected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.fill.secondary)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).lineLimit(1)
                    detailLine
                }
                Spacer(minLength: 4)
                if let expanded {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 0 : -90))
                        .padding(.trailing, 3)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PanelRowStyle(minHeight: 36))
        .accessibilityLabel(name)
        .accessibilityValue(accessibilityDetail)
        .accessibilityHint(expanded.map { $0 ? "Hides settings" : "Shows settings" } ?? "Connects")
    }

    @ViewBuilder
    private var detailLine: some View {
        HStack(spacing: 4) {
            if let percent = detail.percent {
                Image(systemName: detail.charging ? "bolt.fill" : "headphones")
                    .font(.system(size: 9, weight: .semibold))
                Text("\(percent)%")
                    .monospacedDigit()
                    .foregroundStyle(percent <= 15 && !detail.charging ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                if !detail.state.isEmpty { Text("·") }
            }
            if !detail.state.isEmpty { Text(detail.state).lineLimit(1) }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private var accessibilityDetail: String {
        [detail.percent.map { "Battery \($0) percent" }, detail.state.isEmpty ? nil : detail.state]
            .compactMap { $0 }.joined(separator: ", ")
    }
}

/// One choice in the band: a checkmark when chosen, a small symbol in the
/// secondary colour, then the name. The check dims while the write is out.
private struct ChoiceRow: View {
    let title: String
    /// What VoiceOver reads; includes the section where the title alone
    /// ("On") would not say which setting it is.
    let accessibilityTitle: String
    let symbol: String
    let on: Bool
    let pending: Bool
    let action: () -> Void

    var body: some View {
        Button {
            if !on { action() }
        } label: {
            HStack(spacing: 0) {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .opacity(on ? (pending ? 0.45 : 1) : 0)
                    .frame(width: Metric.checkWidth)
                    .padding(.leading, Metric.checkLeading - Metric.inset)
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: Metric.symbolWidth)
                    .padding(.leading, Metric.symbolGap)
                Text(title)
                    .padding(.leading, Metric.labelGap)
            }
        }
        .buttonStyle(PanelRowStyle(minHeight: Metric.choiceHeight))
        .accessibilityLabel(accessibilityTitle)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The ambient level, under Ambient Sound, aligned with the labels. It is
/// written once the value settles: when a drag ends, or shortly after a
/// keyboard or VoiceOver step, which need no drag callbacks.
private struct AmbientLevel: View {
    let level: Int
    let onCommit: (Int) -> Void
    @State private var shown: Int?
    @State private var editing = false

    var body: some View {
        HStack(spacing: 8) {
            Slider(
                value: Binding(get: { Double(shown ?? level) }, set: { shown = Int($0.rounded()) }),
                in: 0...20
            ) {
                Text("Ambient level")
            } onEditingChanged: { editing = $0 }
            .labelsHidden()
            .controlSize(.small)
            Text("\(shown ?? level)")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)
        }
        .padding(.leading, Metric.labelLeading)
        .padding(.trailing, Metric.inset)
        .frame(height: Metric.choiceHeight)
        .accessibilityValue("\(shown ?? level) of 20")
        .onChange(of: level) { _, reported in
            if !editing, reported == shown { shown = nil }
        }
        .task(id: Settle(value: shown, editing: editing)) {
            guard let settled = shown, !editing else { return }
            // A short pause groups held arrow keys into one write.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            if settled != level { onCommit(settled) }
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { shown = nil }
        }
    }
}

/// A menu item: 13 pt text, an optional shortcut on the right.
private struct MenuItem: View {
    let title: String
    var shortcut: String?
    let action: () -> Void

    init(_ title: String, shortcut: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.shortcut = shortcut
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).lineLimit(1)
                Spacer()
                if let shortcut { Text(shortcut).foregroundStyle(.tertiary) }
            }
        }
        .buttonStyle(PanelRowStyle(minHeight: Metric.menuHeight))
    }
}

/// A full-width row. Content sits at the 13 pt inset; on hover a rounded
/// highlight fills the row to 5 pt from the panel edge, darker on press.
private struct PanelRowStyle: ButtonStyle {
    var minHeight: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        Row(label: configuration.label, pressed: configuration.isPressed, minHeight: minHeight)
    }

    private struct Row<Label: View>: View {
        let label: Label
        let pressed: Bool
        let minHeight: CGFloat
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            label
                .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
                .padding(.horizontal, Metric.inset - Metric.highlightInset)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(!isEnabled ? 0 : pressed ? 0.14 : hovering ? 0.08 : 0))
                )
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .padding(.horizontal, Metric.highlightInset)
                .opacity(isEnabled ? 1 : 0.45)
        }
    }
}
