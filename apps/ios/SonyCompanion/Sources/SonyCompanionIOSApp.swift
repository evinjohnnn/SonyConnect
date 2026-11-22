import SwiftUI

@main
struct SonyCompanionIOSApp: App {
    @StateObject private var session = IOSHeadphoneSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
        }
    }
}

// MARK: - Root

struct RootView: View {
    @EnvironmentObject private var session: IOSHeadphoneSession
    @State private var showingLog = false

    var body: some View {
        NavigationStack {
            Group {
                if let device = session.connected {
                    DeviceView(device: device)
                } else if session.devices.isEmpty {
                    ContentUnavailableView {
                        Label("No Headphones", systemImage: "headphones")
                    } description: {
                        Text("Connect headphones that support Sony's control protocol. They appear here once the accessory link is up.")
                    } actions: {
                        Button("Refresh") { session.refresh() }
                            .buttonStyle(.glassProminent)
                    }
                } else {
                    deviceList
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        session.refresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.glass)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingLog.toggle()
                    } label: {
                        Label("Activity", systemImage: "list.bullet.rectangle")
                    }
                    .buttonStyle(.glass)
                }
            }
            .sheet(isPresented: $showingLog) {
                LogView(lines: session.log)
            }
        }
        .task { session.refresh() }
    }

    private var deviceList: some View {
        List(session.devices) { device in
            Button {
                session.connect(to: device)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "headphones")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 17))
                        .foregroundStyle(.tint)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name)
                            .foregroundStyle(.primary)
                        Text("Connected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Headphones")
    }
}

struct IOSLinkStatusSection: View {
    let status: HeadphoneStatus
    let onSetMusicHandOver: (Bool) -> Void
    let onConnectPairedDevice: (Int) -> Void
    let onDisconnectPairedDevice: (Int) -> Void
    let onSetPairingMode: (Bool) -> Void

    @State private var confirmingDisconnect: PairedDeviceView?

    var body: some View {
        if status.musicHandOver != nil || status.usbSubmersion != nil || status.pairingKnown {
            VStack(alignment: .leading, spacing: 10) {
                Text("Device Link").font(.headline)
                if let mho = status.musicHandOver {
                    Toggle("Music hand-over", isOn: Binding(
                        get: { mho },
                        set: { onSetMusicHandOver($0) }
                    ))
                    .font(.callout)
                }
                if let usb = status.usbSubmersion {
                    row("USB submersion", usb ? "Submerged" : "Not submerged")
                }
                if status.pairingKnown {
                    Divider()
                    ForEach(Array(status.pairedDevices.enumerated()), id: \.element.id) { index, device in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(device.name)
                                Spacer()
                                Text(device.connected ? "Connected" : "Paired")
                                    .foregroundStyle(device.connected ? .green : .secondary)
                            }
                            HStack {
                                Text(device.address)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if device.connected {
                                    Button("Disconnect", role: .destructive) {
                                        confirmingDisconnect = device
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                } else {
                                    Button("Connect") { onConnectPairedDevice(index) }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                }
                            }
                        }
                        .font(.callout)
                    }
                    HStack {
                        Button("Enter pairing mode") { onSetPairingMode(true) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Button("Leave") { onSetPairingMode(false) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    if let cap = status.pairingCapability {
                        row(
                            "Connection limit",
                            "\(cap.maxConnected) connected, \(cap.maxPaired) paired"
                        )
                    }
                    if let event = status.pairingEvent {
                        row("Last pairing action", event.label)
                    }
                    if let mode = status.pairingMode {
                        row("Bluetooth mode", mode.label)
                    }
                }
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .confirmationDialog(
                "Disconnect \(confirmingDisconnect?.name ?? "device")?",
                isPresented: Binding(
                    get: { confirmingDisconnect != nil },
                    set: { if !$0 { confirmingDisconnect = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Disconnect", role: .destructive) {
                    if let device = confirmingDisconnect,
                       let index = status.pairedDevices.firstIndex(where: { $0.id == device.id }) {
                        onDisconnectPairedDevice(index)
                    }
                    confirmingDisconnect = nil
                }
                Button("Cancel", role: .cancel) { confirmingDisconnect = nil }
            } message: {
                Text("The headset will drop this device's Bluetooth link. It stays paired.")
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
        .font(.callout)
    }
}

struct IOSPlaybackSection: View {
    let playback: PlaybackState?
    let onControl: (UInt8) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Playback")
                .font(.headline)
            HStack(spacing: 16) {
                Button { onControl(0x03) } label: {
                    Image(systemName: "backward.fill")
                }
                .buttonStyle(.glass)
                Button { onControl(playback?.state == 1 ? 0x01 : 0x07) } label: {
                    Image(systemName: playback?.state == 1 ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.glassProminent)
                Button { onControl(0x02) } label: {
                    Image(systemName: "forward.fill")
                }
                .buttonStyle(.glass)
                Spacer()
                Text(playback?.label ?? "Not reported")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct IOSVolumeSection: View {
    let music: MusicVolume?
    let call: MusicVolume?
    let autoVolume: Bool?
    let autoStandby: Bool?
    let autoStandbyEnabled: Bool?
    let onMusic: (Int) -> Void
    let onCall: (Int) -> Void
    let onAutoStandby: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Volume").font(.headline)
            if let music, music.max > 0 {
                slider("Music", volume: music, onSet: onMusic)
            }
            if let call, call.max > 0 {
                slider("Call", volume: call, onSet: onCall)
            }
            if let autoVolume {
                HStack {
                    Text("Auto volume")
                    Spacer()
                    Text(autoVolume ? "On (read-only)" : "Off (read-only)")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }
            if let autoStandbyEnabled {
                Toggle(
                    autoStandby == false ? "Auto standby (unavailable)" : "Auto standby (15 min)",
                    isOn: Binding(
                        get: { autoStandbyEnabled },
                        set: { onAutoStandby($0) }
                    )
                )
                .font(.callout)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func slider(
        _ label: String,
        volume: MusicVolume,
        onSet: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .frame(width: 48, alignment: .leading)
            Slider(
                value: Binding(
                    get: { Double(volume.value) },
                    set: { onSet(Int($0.rounded())) }
                ),
                in: 0...Double(volume.max),
                step: 1
            )
            Text("\(volume.value)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
        }
    }
}

// MARK: - Detail

private let quickAccessOptions: [(UInt8, String)] = [
    (0, "No function"), (1, "NC/ASM off"), (2, "NC/ASM"), (3, "NC off"),
    (4, "Ambient off"), (16, "Quick Attention"), (17, "NC optimizer"),
    (32, "Play/Pause"), (33, "Next track"), (34, "Previous track"),
    (35, "Volume up"), (36, "Volume down"), (48, "Voice recognition"),
    (49, "Notifications"), (50, "Google Assistant"), (55, "Amazon Alexa"),
    (54, "Quick Access"), (67, "Quick Access 1"), (68, "Quick Access 2"),
    (80, "NC/NCSS/ASM off"), (81, "NC/NCSS/ASM"), (82, "NC/NCSS off"),
    (83, "NCSS/ASM off"), (84, "NC/NCSS"), (85, "NCSS/ASM"), (86, "NCSS off"),
    (87, "Ambient setting"), (88, "Standard voice"), (89, "Listening mode"),
    (112, "Mic mute"), (113, "Game up"), (114, "Chat up"),
]

private struct QuickAccessPicker: View {
    let index: Int
    let value: UInt8
    let onChange: (UInt8) -> Void

    var body: some View {
        Picker("Quick Access \(index + 1)", selection: Binding(
            get: { Int(value) },
            set: { onChange(UInt8($0)) }
        )) {
            ForEach(quickAccessOptions, id: \.0) { option in
                Text(option.1).tag(Int(option.0))
            }
            if !quickAccessOptions.contains(where: { $0.0 == value }) {
                Text("Unnamed (\(value))").tag(Int(value))
            }
        }
    }
}

struct DeviceView: View {
    @EnvironmentObject private var session: IOSHeadphoneSession
    let device: AccessoryDevice
    @State private var confirmingPowerOff = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DeviceHero(device: device, status: session.status)

                if let error = session.lastError {
                    ErrorBanner(message: error) {
                        session.connect(to: device)
                    }
                }

                BatterySection(status: session.status)
                IOSPlaybackSection(playback: session.status.playback) { control in
                    session.setPlaybackControl(control)
                }
                if session.status.volume?.max ?? 0 > 0
                    || session.status.callVolume?.max ?? 0 > 0
                    || session.status.autoVolume != nil
                    || session.status.autoStandby != nil
                    || session.status.autoStandbyEnabled != nil {
                    IOSVolumeSection(
                        music: session.status.volume,
                        call: session.status.callVolume,
                        autoVolume: session.status.autoVolume,
                        autoStandby: session.status.autoStandby,
                        autoStandbyEnabled: session.status.autoStandbyEnabled,
                        onMusic: { session.setMusicVolume($0) },
                        onCall: { session.setCallVolume($0) },
                        onAutoStandby: { session.setAutoStandby($0) }
                    )
                }
                NoiseControlSection(status: session.status)
                if let st = session.status.smartTalking {
                    IOSSmartTalkingSection(
                        state: st,
                        onToggle: { session.setSmartTalking($0) },
                        onDetail: { session.setSmartTalkingDetail(sensitivity: $0, modeOut: $1) }
                    )
                }
                if let hg = session.status.headGesture {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Head gesture", isOn: Binding(
                            get: { hg },
                            set: { session.setHeadGesture($0) }
                        ))
                        .font(.callout)
                        Text("Nod to answer or end a call.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                if let level = session.status.safeVolume {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Safe volume", selection: Binding(
                            get: { level },
                            set: { session.setSafeVolume($0) }
                        )) {
                            Text("Normal").tag(UInt8(0))
                            Text("Sensitive").tag(UInt8(1))
                        }
                        .font(.callout)
                    }
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                if let started = session.status.adaptiveControlStarted {
                    Toggle("Adaptive control", isOn: Binding(
                        get: { started },
                        set: { session.setAdaptiveControl($0) }
                    ))
                    .font(.callout)
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                if let functions = session.status.quickAccess, functions.count == 2 {
                    VStack(alignment: .leading, spacing: 8) {
                        QuickAccessPicker(index: 0, value: functions[0]) { newValue in
                            session.setQuickAccessFunctions([newValue, functions[1]])
                        }
                        QuickAccessPicker(index: 1, value: functions[1]) { newValue in
                            session.setQuickAccessFunctions([functions[0], newValue])
                        }
                    }
                    .font(.callout)
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                if let enabled = session.status.controlByWearing {
                    Toggle("Pause when removed", isOn: Binding(
                        get: { enabled },
                        set: { session.setControlByWearing($0) }
                    ))
                    .font(.callout)
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                if let enabled = session.status.micOnOff {
                    Toggle("Mic by headphone", isOn: Binding(
                        get: { enabled },
                        set: { session.setMicOnOff($0) }
                    ))
                    .font(.callout)
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                if let enabled = session.status.sonyVoiceAssistant {
                    Toggle("Sony Voice Assistant", isOn: Binding(
                        get: { enabled },
                        set: { session.setSonyVoiceAssistant($0) }
                    ))
                    .font(.callout)
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                if let enabled = session.status.voiceGuidance {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Voice guidance", isOn: Binding(
                            get: { enabled },
                            set: { session.setVoiceGuidance($0) }
                        ))
                        if let volume = session.status.voiceGuidanceVolume {
                            Stepper("Guidance volume \(volume)", value: Binding(
                                get: { volume },
                                set: { session.setVoiceGuidanceVolume(Int8(clamping: $0)) }
                            ), in: -128...127)
                        }
                    }
                    .font(.callout)
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                ListeningModeSection(status: session.status) { mode in
                    session.setListeningMode(mode)
                }
                EqualizerSection(status: session.status)
                IOSLinkStatusSection(
                    status: session.status,
                    onSetMusicHandOver: { session.setMusicHandOver($0) },
                    onConnectPairedDevice: { session.connectPairedDevice(at: $0) },
                    onDisconnectPairedDevice: { session.disconnectPairedDevice(at: $0) },
                    onSetPairingMode: { session.setPairingMode($0) }
                )
                GeneralSettingsSection(settings: session.status.generalSettings) { gs, on in
                    session.setGeneralSetting(gs, enabled: on)
                }
                VoiceAssistantSection(view: session.status.voiceAssistant) { value in
                    session.setVoiceAssistant(value)
                }
                Button(role: .destructive) {
                    confirmingPowerOff = true
                } label: {
                    Text("Power off headphones")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .alert("Power off headphones?", isPresented: $confirmingPowerOff) {
                Button("Power Off", role: .destructive) { session.powerOff() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The control link will drop. Turn the headphones back on to reconnect.")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle(device.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Disconnect") { session.disconnect() }
                    .buttonStyle(.glass)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    session.setNoiseControl(
                        enabled: false, ambient: false, level: 0)
                } label: {
                    Label("Noise Off", systemImage: "speaker.slash")
                }
                .buttonStyle(.glass)
                .disabled(!session.isReady)
            }
        }
    }
}

// MARK: - Hero

/// Content-layer header. The gradient is what the floating glass pill
/// refracts; glass over a flat colour reads as plain translucency.
struct DeviceHero: View {
    let device: AccessoryDevice
    let status: HeadphoneStatus

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.40),
                            Color.accentColor.opacity(0.10),
                            Color.clear,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .background(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(.background.secondary)
                )
                .overlay(alignment: .topTrailing) {
                    Headphone3DView(model: status.model.isEmpty ? device.name : status.model)
                        .frame(width: 200, height: 200)
                        .offset(x: -8, y: 8)
                }

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(device.name)
                        .font(.title.weight(.semibold))
                    HStack(spacing: 7) {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if !status.codec.isEmpty {
                            Text(status.codec)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                }

                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(phaseColor)
                            .frame(width: 7, height: 7)
                        Text(status.phase.label)
                            .font(.footnote.weight(.medium))
                        if status.pendingWrite {
                            Text("· Applying")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .glassEffect(.regular, in: .capsule)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Connection status: \(status.phase.label)")
                }
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var subtitle: String {
        var parts: [String] = []
        if !status.model.isEmpty { parts.append(status.model) }
        if !status.firmware.isEmpty { parts.append("firmware \(status.firmware)") }
        if parts.isEmpty { parts.append(device.protocolString) }
        return parts.joined(separator: " · ")
    }

    private var phaseColor: Color {
        switch status.phase {
        case .ready: return .green
        case .error, .unsupported: return .red
        case .disconnected: return .secondary
        default: return .orange
        }
    }
}

// MARK: - Sections

struct SectionCard<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.background.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
        )
    }
}

struct BatterySection: View {
    let status: HeadphoneStatus

    var body: some View {
        SectionCard(title: "Battery") {
            if let percent = status.batteryPercent {
                HStack(alignment: .center, spacing: 16) {
                    Text("\(percent)%")
                        .font(.system(size: 38, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    VStack(alignment: .leading, spacing: 6) {
                        if !status.charging.label.isEmpty {
                            Label(status.charging.label, systemImage: symbol)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: Double(percent), total: 100)
                            .tint(percent <= 15 ? .red : .accentColor)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                Text("Not reported yet").foregroundStyle(.secondary)
            }
        }
    }

    private var symbol: String {
        switch status.charging {
        case .charging: return "bolt.fill"
        case .charged: return "powerplug.fill"
        default: return "battery.50"
        }
    }
}

struct NoiseControlSection: View {
    @EnvironmentObject private var session: IOSHeadphoneSession
    let status: HeadphoneStatus

    private var selection: Int {
        switch status.noiseControl {
        case .noiseCancelling: return 0
        case .ambient: return 1
        case .off: return 2
        case .unknown: return -1
        }
    }

    var body: some View {
        SectionCard(title: "Noise Control") {
            if selection < 0 {
                Text("This headphone has not reported a noise-control mode.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Mode", selection: Binding(
                    get: { selection },
                    set: { value in
                        session.setNoiseControl(
                            enabled: value != 2,
                            ambient: value == 1,
                            level: status.noiseControl.level)
                    }
                )) {
                    Text("Noise Cancelling").tag(0)
                    Text("Ambient").tag(1)
                    Text("Off").tag(2)
                }
                .pickerStyle(.segmented)

                if case .ambient(_, let level) = status.noiseControl {
                    Stepper(value: Binding(
                        get: { level },
                        set: { session.setNoiseControl(enabled: true, ambient: true, level: $0) }
                    ), in: 0...20) {
                        HStack {
                            Text("Ambient Level").font(.callout)
                            Spacer()
                            Text("\(level)")
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

struct IOSSmartTalkingSection: View {
    let state: SmartTalkingView
    let onToggle: (Bool) -> Void
    let onDetail: (UInt8, UInt8) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Speak-to-Chat").font(.headline)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { state.enabled },
                    set: { onToggle($0) }
                ))
                .labelsHidden()
            }
            Picker("Detection", selection: Binding(
                get: { state.sensitivity },
                set: { onDetail($0, state.modeOut) }
            )) {
                Text("Auto").tag(UInt8(0))
                Text("High").tag(UInt8(1))
                Text("Low").tag(UInt8(2))
            }
            Picker("Auto-off", selection: Binding(
                get: { state.modeOut },
                set: { onDetail(state.sensitivity, $0) }
            )) {
                Text("Fast").tag(UInt8(0))
                Text("Medium").tag(UInt8(1))
                Text("Slow").tag(UInt8(2))
                Text("None").tag(UInt8(3))
            }
            Text("Turns off automatically when you stop talking.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct ListeningModeSection: View {
    let status: HeadphoneStatus
    let onSelect: (ListeningModeView) -> Void

    var body: some View {
        if let mode = status.listening {
            VStack(alignment: .leading, spacing: 12) {
                Text("Listening mode")
                    .font(.headline)
                Picker("Listening mode", selection: Binding(
                    get: { mode },
                    set: { onSelect($0) }
                )) {
                    ForEach(ListeningModeView.allCases, id: \.self) { value in
                        Text(value.label).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                Text("Reported by the headphones from the BGM and Cinema settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

struct EqualizerSection: View {
    @EnvironmentObject private var session: IOSHeadphoneSession
    let status: HeadphoneStatus
    @State private var editing = false

    var body: some View {
        SectionCard(
            title: "Equalizer",
            subtitle: "Applied on the headphones, not in software."
        ) {
            if let eq = status.equalizer {
                if eq.presets.isEmpty {
                    Text("The device reported an equalizer but no presets.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Preset", selection: Binding(
                        get: { eq.preset },
                        set: { session.setEqualizerPreset($0) }
                    )) {
                        ForEach(eq.presets) { preset in
                            Text(preset.name).tag(preset.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                    if !eq.bands.isEmpty {
                        Button("Edit") { editing = true }
                            .buttonStyle(.glass)
                    }
                }

                if !eq.bands.isEmpty { BandCurve(eq: eq) }

                if eq.clearBassRange.lowerBound != eq.clearBassRange.upperBound {
                    Stepper(value: Binding(
                        get: { eq.clearBass },
                        set: { session.setClearBass($0) }
                    ), in: eq.clearBassRange) {
                        HStack {
                            Text("Clear Bass").font(.callout)
                            Spacer()
                            Text("\(eq.clearBass)")
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Text("This headphone has not reported an equalizer.")
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $editing) {
            if let eq = status.equalizer {
                EqualizerEditor(
                    presetName: eq.presetName.isEmpty ? "Manual" : eq.presetName,
                    initialBands: eq.bands,
                    bandStep: eq.bandStep,
                    onSave: { session.setEqualizerBands($0) }
                )
            }
        }
    }
}

struct BandCurve: View {
    let eq: EqualizerView

    var body: some View {
        let peak = max(1, Int(eq.bands.max() ?? 1))
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(eq.bands.enumerated()), id: \.offset) { _, step in
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.accentColor, .accentColor.opacity(0.55)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 11, height: max(3, CGFloat(step) / CGFloat(peak) * 44))
                    Text("\(step)")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: 62, alignment: .bottom)
        .animation(.smooth(duration: 0.25), value: eq.bands)
        .accessibilityElement()
        .accessibilityLabel("Equalizer bands")
        .accessibilityValue(eq.bands.map(String.init).joined(separator: ", "))
    }
}

// MARK: - Device-named settings

struct GeneralSettingsSection: View {
    let settings: [GeneralSetting]
    let onToggle: (GeneralSetting, Bool) -> Void

    var body: some View {
        if !settings.isEmpty {
            SectionCard(title: "Device Settings",
                        subtitle: "Named by the headphones themselves.") {
                VStack(spacing: 12) {
                    ForEach(settings) { gs in
                        Toggle(isOn: Binding(
                            get: { gs.value ?? false },
                            set: { onToggle(gs, $0) }
                        )) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(gs.title).font(.callout)
                                if !gs.detail.isEmpty {
                                    Text(gs.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(gs.value == nil)
                    }
                }
            }
        }
    }
}

struct VoiceAssistantSection: View {
    let view: VoiceAssistantView?
    let onSelect: (UInt8) -> Void

    var body: some View {
        if let va = view, !va.options.isEmpty {
            SectionCard(title: "Voice Assistant",
                        subtitle: "Assigned on the headphones.") {
                Picker("Assistant", selection: Binding(
                    get: { va.current },
                    set: { onSelect($0) }
                )) {
                    ForEach(va.options, id: \.0) { option in
                        Text(option.1).tag(option.0)
                    }
                    Text("Not set").tag(UInt8(0xFF))
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

// MARK: - Chrome

struct ErrorBanner: View {
    let message: String
    var onRetry: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let onRetry {
                Button("Retry", action: onRetry)
                    .buttonStyle(.glass)
            }
        }
        .padding(14)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct LogView: View {
    let lines: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
            }
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .buttonStyle(.glassProminent)
                }
            }
        }
    }
}
