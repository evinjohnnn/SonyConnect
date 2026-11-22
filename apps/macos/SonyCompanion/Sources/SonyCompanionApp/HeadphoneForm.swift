import SwiftUI
import MDRKit
import AppKit

/// The connected headphone, as one grouped settings page.
///
/// Modelled on the headphone page in System Settings: a device header, then
/// grouped rows with the label leading and the control trailing, and a footer
/// sentence wherever a setting needs its consequence explained. Every row is
/// shown only once the headphones have reported that setting, so a model that
/// lacks a feature simply does not show it, and nothing claims a value the
/// device has not sent.
struct HeadphoneForm: View {
    @EnvironmentObject private var session: HeadphoneSession
    @EnvironmentObject private var ui: AppUI
    let device: PairedDevice
    /// nil is the main page; a category is one of its pushed pages.
    var page: SettingsPage? = nil
    @State private var refreshSpins = 0

    @State private var confirmingDisconnect: PairedDeviceView?

    private var status: HeadphoneStatus { session.status }
    private var ready: Bool { session.isReady }

    var body: some View {
        if page == nil {
            form
                .navigationDestination(for: SettingsPage.self) { page in
                    HeadphoneForm(device: device, page: page)
                }
                .alert("Power off the headphones?", isPresented: $ui.confirmingPowerOff) {
                    Button("Power Off", role: .destructive) { session.powerOff() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("The connection to this Mac ends. Turn the headphones on again to reconnect.")
                }
        } else {
            form
        }
    }

    private var form: some View {
        Group {
            if page == nil { home } else { settingsForm.pageArrival(from: .trailing) }
        }
        .navigationTitle(page?.title ?? device.displayName)
        .toolbar { toolbar }
        // No toolbar bar or hairline on any page, pushed ones included:
        // the soft scroll edge alone separates content from the title.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .alert(
            "Disconnect \(confirmingDisconnect?.name ?? "this device")?",
            isPresented: Binding(
                get: { confirmingDisconnect != nil },
                set: { if !$0 { confirmingDisconnect = nil } }
            )
        ) {
            Button("Disconnect", role: .destructive) {
                if let target = confirmingDisconnect,
                   let index = status.pairedDevices.firstIndex(where: { $0.id == target.id }) {
                    session.disconnectPairedDevice(at: index)
                }
                confirmingDisconnect = nil
            }
            Button("Cancel", role: .cancel) { confirmingDisconnect = nil }
        } message: {
            Text("The headphones drop this device's Bluetooth link. It stays paired.")
        }
    }

    /// A pushed category: grouped rows on the black canvas, so the section
    /// cards read as tiles.
    private var settingsForm: some View {
        Form {
            switch page {
            case nil: EmptyView()
            case .sound: soundSection
            case .noise: noiseSection
            case .playback: playbackSection
            case .controls: controlsSection
            case .power: powerSection
            case .connections: connectionsSection
            case .about: aboutSection
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background { PageBackdrop() }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        // With the title removed, items flow from the window buttons; a
        // flexible spacer puts refresh in the trailing corner.
        ToolbarSpacer(.flexible)
        ToolbarItemGroup(placement: .automatic) {
            Button {
                refreshSpins += 1
                session.refreshStatus()
            } label: {
                // One turn per click; turns continuously while the page is
                // still loading from the headphones.
                Label("Refresh", systemImage: "arrow.clockwise")
                    .symbolEffect(.rotate.byLayer, options: .speed(1.6), value: refreshSpins)
                    .symbolEffect(.rotate.byLayer, options: .repeat(.continuous),
                                  isActive: status.phase.isBusy)
            }
            .disabled(!ready)
            .help("Read the battery and settings from the headphones again (⌘R)")
            // The frame log is a developer tool: Window ▸ Activity (⌥⌘L).
        }
    }

    // MARK: Home

    /// The main page: the device card, then everything else as tiles on the
    /// black canvas.
    private var home: some View {
        ScrollView {
            VStack(spacing: 12) {
                ListeningStage(device: device)
                if let error = session.lastError { errorTile(error) }
                if status.phase.isBusy && status.model.isEmpty { loadingTile }
                widgets
                categoryList
                aboutTile
                actions
            }
            .frame(maxWidth: 620)
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        // The name and connection state live in the title bar, where they
        // stay put while the page scrolls under them.
        .navigationSubtitle(connectionText)
    }

    private var connectionText: String {
        let phase = status.phase
        if phase.isBusy, !session.activity.isEmpty { return session.activity }
        return phase == .ready ? "Connected" : phase.label
    }

    private func errorTile(_ message: String) -> some View {
        Tile {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("The headphones stopped responding")
                        .font(.headline)
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Button("Try Again") { session.connect(to: device) }
                    .buttonStyle(PillButtonStyle(kind: .glass))
            }
        }
    }

    private var loadingTile: some View {
        Tile {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.activity.isEmpty ? status.phase.label : session.activity)
                        .font(.headline)
                    Text("Settings appear as the headphones report them.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Battery and Sound get widgets; the other categories are rows.
    private var widgetPages: [SettingsPage] {
        [SettingsPage.power, .sound].filter { page in
            categories.contains(page)
                && (page == .power ? status.batteryPercent != nil : status.equalizer != nil)
        }
    }

    @ViewBuilder
    private var widgets: some View {
        let pages = widgetPages
        if !pages.isEmpty {
            HStack(spacing: 12) {
                ForEach(pages, id: \.self) { page in
                    NavigationLink(value: page) {
                        switch page {
                        case .power: BatteryWidget(percent: status.batteryPercent ?? 0, charging: status.charging)
                        default: EqualizerWidget(eq: status.equalizer)
                        }
                    }
                    .buttonStyle(TilePressStyle())
                }
            }
            .entrance(3)
        }
    }

    /// The remaining categories as rows on one glass card.
    @ViewBuilder
    private var categoryList: some View {
        let pages = categories.filter { !widgetPages.contains($0) }
        if !pages.isEmpty {
            Tile(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(pages.enumerated()), id: \.element) { index, page in
                        if index > 0 { Divider().padding(.leading, 48) }
                        NavigationLink(value: page) {
                            CategoryRow(page: page, detail: summary(for: page))
                        }
                        .buttonStyle(CardRowPressStyle())
                    }
                }
                .padding(.vertical, 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .entrance(4)
        }
    }

    /// The facts people look for, inline; the rest one level down.
    private var aboutTile: some View {
        // The header sits above its card, as a grouped section's does.
        VStack(alignment: .leading, spacing: 6) {
            Text("About")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.leading, 16)
            Tile(padding: 0) {
                VStack(spacing: 0) {
                    if !status.model.isEmpty {
                        factRow("Model", status.model)
                        Divider().padding(.leading, 16)
                    }
                    if !status.firmware.isEmpty {
                        factRow("Version", status.firmware)
                        Divider().padding(.leading, 16)
                    }
                    NavigationLink(value: SettingsPage.about) {
                        AboutLinkRow()
                    }
                    .buttonStyle(CardRowPressStyle())
                }
                .padding(.vertical, 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .padding(.top, 8)
    }

    private func factRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button("Disconnect") { session.disconnect() }
                    .buttonStyle(PillButtonStyle(kind: .glass, minWidth: 170))
                Button("Power Off…") { ui.confirmingPowerOff = true }
                    .buttonStyle(PillButtonStyle(kind: .destructive, minWidth: 170))
                    .disabled(!ready)
            }
            Text("Disconnect closes this app's control channel; audio stays connected to the Mac.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 14)
        .frame(maxWidth: .infinity)
    }

    // MARK: Categories

    /// Which categories have anything to show for this model.
    private var categories: [SettingsPage] {
        var out: [SettingsPage] = []
        if status.equalizer != nil || status.upscaling != nil || status.listening != nil { out.append(.sound) }
        if status.noiseControl.choice != nil || status.noiseAdaptation != nil
            || status.adaptiveControlStarted != nil { out.append(.noise) }
        if status.playback != nil || status.callVolume.map({ $0.max > 0 }) == true { out.append(.playback) }
        if hasControls { out.append(.controls) }
        if hasPower { out.append(.power) }
        if status.pairingKnown || status.musicHandOver != nil { out.append(.connections) }
        return out
    }

    /// The current value a category tile shows under its title.
    private func summary(for page: SettingsPage) -> String? {
        switch page {
        case .sound:
            guard let eq = status.equalizer else { return nil }
            if !eq.isOn { return "Off" }
            return eq.presetName.isEmpty ? nil : eq.presetName
        case .connections:
            let n = status.pairedDevices.filter(\.connected).count
            return n > 0 ? "\(n) connected" : nil
        case .power:
            return status.batteryPercent.map { "\($0)%" }
        default:
            return nil
        }
    }

    // MARK: Noise control

    /// Mode and ambient level live on the stage; the refinements stay here.
    @ViewBuilder
    private var noiseSection: some View {
        let choice = status.noiseControl.choice
        if choice != nil {
            Section {
                VStack(spacing: 16) {
                    NoiseField(control: status.noiseControl)
                    ListeningModeSelector(selection: choice, pending: status.pendingWrite) {
                        session.setNoiseControl($0)
                    }
                    .disabled(!ready)
                    if case .ambient(_, let level) = status.noiseControl {
                        AmbientLevelRow(level: level) { session.setAmbientLevel($0) }
                            .disabled(!ready)
                            .transition(.settle)
                    }
                }
                .padding(.vertical, 8)
                .animation(Motion.fast, value: choice)
            }
        }
        if status.noiseAdaptation != nil || status.adaptiveControlStarted != nil {
            Section("Adaptive") {
                if let adaptation = status.noiseAdaptation {
                    DescribedToggle(
                        title: "Noise Adaptation",
                        detail: "Tunes cancelling and ambient sound to the noise around you",
                        isOn: adaptation
                    ) { session.setNoiseAdaptation($0) }
                    .disabled(!ready)
                }
                if let started = status.adaptiveControlStarted {
                    DescribedToggle(
                        title: "Adaptive Sound Control",
                        detail: "Switches modes as you move between places",
                        isOn: started
                    ) { session.setAdaptiveControl($0) }
                    .disabled(!ready)
                }
            }
        }
    }

    // MARK: Sound

    /// The headphones bypass the equaliser in some states and say why
    /// (`PresetEqErrorCodeType`). Writes are still accepted then, but they
    /// change nothing you can hear, so the controls are held until it is on.
    private func equalizerOffNotice(_ eq: EqualizerView) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "slider.vertical.3")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Equalizer is off")
                Text(offReasonText(eq.offReason))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if eq.offReason == 2, let mode = status.listening, mode != .standard {
                Button("Use Standard") { session.setListeningMode(.standard) }
                    .disabled(!ready)
            }
        }
    }

    private func offReasonText(_ reason: UInt8?) -> String {
        switch reason {
        case 0: return "The headphones turn it off during calls."
        case 1: return "The headphones are in demo mode."
        case 2:
            let mode = status.listening.map { "\($0.label) " } ?? ""
            return "The headphones turn it off while the \(mode)listening mode is on."
        default: return "The headphones have turned it off."
        }
    }

    @ViewBuilder
    private var soundSection: some View {
        let eq = status.equalizer
        if let eq, !eq.bands.isEmpty {
            // The sound at a glance: preset, link, and the curve.
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(eq.isOn ? (eq.presetName.isEmpty ? "Custom" : eq.presetName) : "Equalizer Off")
                            .font(.title3.weight(.semibold))
                        Spacer(minLength: 8)
                        if !status.codec.isEmpty { InfoBadge(status.codec) }
                        if status.upscaling == true { InfoBadge("Upconversion") }
                    }
                    EqualizerResponse(bands: eq.bands, bandStep: eq.bandStep, isOn: eq.isOn)
                }
                .padding(.vertical, 6)
            }
        }
        if eq != nil || status.upscaling != nil || status.listening != nil {
            Section {
                if let eq, !eq.isOn {
                    equalizerOffNotice(eq)
                }
                if let eq {
                    if !eq.presets.isEmpty {
                        PullDownPicker("Equalizer", current: eq.presetName.isEmpty ? "Preset \(eq.preset)" : eq.presetName, selection: Binding(
                            get: { eq.preset },
                            set: { session.setEqualizerPreset($0) }
                        )) {
                            ForEach(eq.presets) { preset in
                                Text(preset.name).tag(preset.id)
                            }
                            if !eq.presets.contains(where: { $0.id == eq.preset }) {
                                Text(eq.presetName.isEmpty ? "Preset \(eq.preset)" : eq.presetName)
                                    .tag(eq.preset)
                            }
                        }
                        .disabled(!ready || !eq.isOn)
                    }
                    if !eq.bands.isEmpty {
                        GlassEqualizer(bands: eq.bands, bandStep: eq.bandStep) {
                            session.setEqualizerBands($0)
                        }
                        .disabled(!ready || !eq.isOn)
                        .padding(.vertical, 10)
                    }
                    if eq.clearBassRange.lowerBound != eq.clearBassRange.upperBound {
                        SettlingSlider(
                            title: "Clear Bass",
                            value: eq.clearBass,
                            range: eq.clearBassRange,
                            format: { $0 > 0 ? "+\($0)" : "\($0)" }
                        ) { session.setClearBass($0) }
                        .disabled(!ready)
                    }
                }
                if let mode = status.listening {
                    PullDownPicker("Listening Mode", current: mode.label, selection: Binding(
                        get: { mode },
                        set: { session.setListeningMode($0) }
                    )) {
                        ForEach(ListeningModeView.allCases, id: \.self) { value in
                            Text(value.label).tag(value)
                        }
                    }
                    .disabled(!ready)
                }
                if let upscaling = status.upscaling {
                    DescribedToggle(
                        title: "Upconversion",
                        detail: "Restores high-frequency detail lost in compression.",
                        isOn: upscaling
                    ) { session.setUpscaling($0) }
                    .disabled(!ready)
                }
                if let autoVolume = status.autoVolume {
                    LabeledContent("Auto Volume", value: autoVolume ? "On" : "Off")
                }
            } footer: {
                Text("The equalizer runs on the headphones, so it follows them to every device.")
            }
        }
    }

    // MARK: Playback

    @ViewBuilder
    private var playbackSection: some View {
        let musicVolume = status.volume.flatMap { $0.max > 0 ? $0 : nil }
        let callVolume = status.callVolume.flatMap { $0.max > 0 ? $0 : nil }
        if status.playback != nil || musicVolume != nil {
            Section {
                VStack(spacing: 20) {
                    if let playback = status.playback {
                        PlaybackStatus(playback: playback)
                    }
                    EarcupRemote(
                        playing: status.playback?.state == 1,
                        hasTransport: status.playback != nil,
                        volume: musicVolume,
                        enabled: ready,
                        control: { session.setPlaybackControl($0) },
                        setVolume: { session.setMusicVolume($0) }
                    )
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } footer: {
                Text("Laid out like the touch panel on the right earcup. Drag the ring to set the volume")
            }
        }
        if let callVolume {
            Section("Calls") {
                LevelRow(title: "Call volume", level: callVolume) { session.setCallVolume($0) }
                    .disabled(!ready)
            }
        }
    }

    // MARK: Controls

    /// Names follow the protocol's function enum; only the casing changes.
    private static let quickAccessFunctions: [(UInt8, String)] = [
        (0, "No Function"), (1, "NC/ASM Off"), (2, "NC/ASM"), (3, "NC Off"),
        (4, "Ambient Off"), (16, "Quick Attention"), (17, "NC Optimizer"),
        (32, "Play/Pause"), (33, "Next Track"), (34, "Previous Track"),
        (35, "Volume Up"), (36, "Volume Down"), (48, "Voice Recognition"),
        (49, "Notifications"), (50, "Google Assistant"), (55, "Amazon Alexa"),
        (54, "Quick Access"), (67, "Quick Access 1"), (68, "Quick Access 2"),
        (80, "NC/NCSS/ASM Off"), (81, "NC/NCSS/ASM"), (82, "NC/NCSS Off"),
        (83, "NCSS/ASM Off"), (84, "NC/NCSS"), (85, "NCSS/ASM"), (86, "NCSS Off"),
        (87, "Ambient Setting"), (88, "Standard Voice"), (89, "Listening Mode"),
        (112, "Mic Mute"), (113, "Game Up"), (114, "Chat Up"),
    ]

    private var hasControls: Bool {
        status.smartTalking != nil || status.headGesture != nil || status.controlByWearing != nil
            || status.quickAccess?.count == 2 || status.micOnOff != nil || !status.generalSettings.isEmpty
            || !(status.voiceAssistant?.options.isEmpty ?? true) || status.sonyVoiceAssistant != nil
    }

    @ViewBuilder
    private var controlsSection: some View {
        if hasControls {
            Section {
                if let st = status.smartTalking {
                    DescribedToggle(
                        title: "Speak-to-Chat",
                        detail: "Pauses playback and lets in ambient sound when you start talking.",
                        isOn: st.enabled
                    ) { session.setSmartTalking($0) }
                    if st.enabled {
                        PullDownPicker("Voice Detection", current: ["Automatic", "High", "Low"].indices.contains(Int(st.sensitivity)) ? ["Automatic", "High", "Low"][Int(st.sensitivity)] : "Automatic", selection: Binding(
                            get: { st.sensitivity },
                            set: { session.setSmartTalkingDetail(sensitivity: $0, modeOut: st.modeOut) }
                        )) {
                            Text("Automatic").tag(UInt8(0))
                            Text("High").tag(UInt8(1))
                            Text("Low").tag(UInt8(2))
                        }
                        PullDownPicker("Auto-Off", current: ["Fast", "Medium", "Slow", "Off"].indices.contains(Int(st.modeOut)) ? ["Fast", "Medium", "Slow", "Off"][Int(st.modeOut)] : "Off", selection: Binding(
                            get: { st.modeOut },
                            set: { session.setSmartTalkingDetail(sensitivity: st.sensitivity, modeOut: $0) }
                        )) {
                            Text("Fast").tag(UInt8(0))
                            Text("Medium").tag(UInt8(1))
                            Text("Slow").tag(UInt8(2))
                            Text("Off").tag(UInt8(3))
                        }
                    }
                }
                if let enabled = status.headGesture {
                    DescribedToggle(
                        title: "Head Gestures",
                        detail: "Nod or shake your head to answer or decline calls.",
                        isOn: enabled
                    ) { session.setHeadGesture($0) }
                }
                if let enabled = status.controlByWearing {
                    DescribedToggle(
                        title: "Pause When Taken Off",
                        detail: "Playback pauses when you remove the headphones and resumes when you put them on.",
                        isOn: enabled
                    ) { session.setControlByWearing($0) }
                }
                if let functions = status.quickAccess, functions.count == 2 {
                    ForEach(0..<2, id: \.self) { index in
                        PullDownPicker("Quick Access \(index + 1)", current: Self.quickAccessFunctions.first(where: { $0.0 == functions[index] })?.1 ?? "Function \(functions[index])", selection: Binding(
                            get: { functions[index] },
                            set: { newValue in
                                var updated = functions
                                updated[index] = newValue
                                session.setQuickAccessFunctions(updated)
                            }
                        )) {
                            ForEach(Self.quickAccessFunctions, id: \.0) { value, name in
                                Text(name).tag(value)
                            }
                            if !Self.quickAccessFunctions.contains(where: { $0.0 == functions[index] }) {
                                Text("Function \(functions[index])").tag(functions[index])
                            }
                        }
                    }
                }
                if let enabled = status.micOnOff {
                    DescribedToggle(
                        title: "Mute From the Headphones",
                        detail: "Lets the headphone controls mute your microphone during calls.",
                        isOn: enabled
                    ) { session.setMicOnOff($0) }
                }
                ForEach(status.generalSettings) { gs in
                    DescribedToggle(
                        title: Self.titleCased(gs.title),
                        detail: gs.detail.isEmpty ? nil : gs.detail,
                        isOn: gs.value ?? false
                    ) { session.setGeneralSetting(gs, enabled: $0) }
                    .disabled(gs.value == nil)
                }
                if let va = status.voiceAssistant, !va.options.isEmpty {
                    PullDownPicker("Voice Assistant", current: va.options.first(where: { $0.0 == va.current })?.1 ?? "None", selection: Binding(
                        get: { va.current },
                        set: { session.setVoiceAssistant($0) }
                    )) {
                        ForEach(va.options, id: \.0) { option in
                            Text(option.1).tag(option.0)
                        }
                        Text("None").tag(UInt8(0xFF))
                    }
                }
                if let enabled = status.sonyVoiceAssistant {
                    DescribedToggle(title: "Sony Voice Assistant", isOn: enabled) {
                        session.setSonyVoiceAssistant($0)
                    }
                }
            }
            .disabled(!ready)
        }
    }

    /// Device-reported titles arrive in sentence case ("Touch panel"); Mac
    /// rows here use title case. Words that already carry capitals are kept.
    private static func titleCased(_ text: String) -> String {
        text.split(separator: " ").map { word in
            word.contains(where: \.isUppercase) ? String(word) : word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }

    // MARK: Power and alerts

    private var hasPower: Bool {
        // Settings rows only; the battery level has its own sections.
        status.autoPowerOffWearing != nil || status.autoStandbyEnabled != nil || status.autoPowerOff != nil
            || status.safeVolume != nil || status.voiceGuidance != nil
    }

    @ViewBuilder
    private var powerSection: some View {
        if let percent = status.batteryPercent {
            Section {
                BatteryOverview(percent: percent, charging: status.charging, worn: status.wearingStatus)
            }
            if let address = session.connected?.address {
                Section {
                    BatteryHistory(address: address)
                } footer: {
                    Text("Recorded by this Mac while the headphones are connected. Gaps are times they were not.")
                }
            }
        }
        if hasPower {
            Section {
                if let apow = status.autoPowerOffWearing {
                    PullDownPicker("Turn Off When Not Worn", current: AutoPowerOffWearing.label(apow.current), selection: Binding(
                        get: { apow.current },
                        set: { session.setAutoPowerOffWearing($0) }
                    )) {
                        ForEach([UInt8(0x10), 0x00, 0x04, 0x01, 0x02, 0x03, 0x11], id: \.self) { value in
                            Text(AutoPowerOffWearing.label(value)).tag(value)
                        }
                    }
                } else if let on = status.autoPowerOff {
                    LabeledContent("Automatic Power Off", value: on ? "On" : "Off")
                }
                if let enabled = status.autoStandbyEnabled {
                    DescribedToggle(
                        title: "Standby When Idle",
                        detail: status.autoStandby == false
                            ? "Not available on this firmware."
                            : "Saves battery after 15 minutes without audio.",
                        isOn: enabled
                    ) { session.setAutoStandby($0) }
                }
                if let level = status.safeVolume {
                    PullDownPicker("Safe Listening", current: level == 1 ? "Sensitive" : "Normal", selection: Binding(
                        get: { level },
                        set: { session.setSafeVolume($0) }
                    )) {
                        Text("Normal").tag(UInt8(0))
                        Text("Sensitive").tag(UInt8(1))
                    }
                }
                if let enabled = status.voiceGuidance {
                    DescribedToggle(
                        title: "Voice Guidance",
                        detail: "Spoken prompts for power, connection and battery.",
                        isOn: enabled
                    ) { session.setVoiceGuidance($0) }
                    if enabled, let volume = status.voiceGuidanceVolume {
                        LabeledContent("Guidance Volume") {
                            HStack(spacing: 6) {
                                Text(volume > 0 ? "+\(volume)" : "\(volume)")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                // Range: 5 steps; the WH-1000XM6 reads 0.
                                Stepper("Guidance Volume", value: Binding(
                                    get: { volume },
                                    set: { session.setVoiceGuidanceVolume(Int8(clamping: $0)) }
                                ), in: -2...2)
                                .labelsHidden()
                            }
                        }
                    }
                }
            }
            .disabled(!ready)
        }
    }

    // MARK: Connections

    @ViewBuilder
    private var connectionsSection: some View {
        if status.pairingKnown || status.musicHandOver != nil {
            Section {
                ForEach(status.pairedDevices) { peer in
                    pairedRow(peer)
                }
                if status.pairingKnown && status.pairedDevices.isEmpty {
                    Text("No other devices reported.")
                        .foregroundStyle(.secondary)
                }
                if let on = status.musicHandOver {
                    DescribedToggle(
                        title: "Hand Over Music",
                        detail: "Moves playback to the device you start playing on.",
                        isOn: on
                    ) { session.setMusicHandOver($0) }
                }
                if status.pairingKnown {
                    let pairing = status.pairingMode?.enabled == true && status.pairingMode?.mode == 0x01
                    LabeledContent {
                        Button(pairing ? "Stop Pairing" : "Pair New Device…") {
                            session.setPairingMode(!pairing)
                        }
                    } label: {
                        Text("Pairing Mode")
                        Text(pairing ? "The headphones are discoverable." : "Makes the headphones discoverable to a new device.")
                    }
                }
            } footer: {
                if let footer = connectionsFooter { Text(footer) }
            }
            .disabled(!ready)
        }
    }

    private var connectionsFooter: String? {
        var parts: [String] = []
        if let cap = status.pairingCapability {
            parts.append("Up to \(cap.maxConnected) devices connected at once and \(cap.maxPaired) remembered.")
        }
        if let event = status.pairingEvent {
            parts.append("Last change: \(event.label).")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// Addresses compare without separators or case: IOBluetooth and the
    /// headphones format them differently.
    private static func normalized(_ address: String) -> String {
        address.lowercased().filter(\.isHexDigit)
    }

    private func pairedRow(_ peer: PairedDeviceView) -> some View {
        let isThisMac = BluetoothLink.hostAddress.map {
            Self.normalized($0) == Self.normalized(peer.address)
        } ?? false
        return LabeledContent {
            if isThisMac {
                Text("This Mac")
                    .foregroundStyle(.secondary)
            } else if peer.connected {
                Button("Disconnect") { confirmingDisconnect = peer }
            } else {
                Button("Connect") {
                    if let index = status.pairedDevices.firstIndex(where: { $0.id == peer.id }) {
                        session.connectPairedDevice(at: index)
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: peer.connected ? "link.circle.fill" : "circle.dotted")
                    .font(.system(size: 15))
                    .foregroundStyle(peer.connected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(peer.name.isEmpty ? peer.address : peer.name)
                    Text(peer.connected ? "Connected" : "Not connected")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: About

    private var aboutSection: some View {
        Section {
            if !status.model.isEmpty { LabeledContent("Model", value: status.model) }
            if !status.firmware.isEmpty { LabeledContent("Firmware", value: status.firmware) }
            LabeledContent("Bluetooth Address") {
                Text(device.address)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }
            if !status.codec.isEmpty { LabeledContent("Codec", value: status.codec) }
            if let mode = status.connectionMode { LabeledContent("Audio Link", value: mode.label) }
            if status.protocolVersion != 0 {
                LabeledContent("Protocol", value: String(format: "0x%08X", status.protocolVersion))
            }
            if isEarbudModel, let inEar = status.wearingStatus {
                // SYSTEM 0x06 is earpiece fitting; over-ear models report
                // MODE_OUT whether worn or not, so it shows on buds only.
                LabeledContent(
                    "Earpiece Fitting",
                    value: (inEar ? "In ear" : "Out of ear")
                        + (status.wearingDetectionEnabled == false ? " (detection off)" : "")
                )
            }
            if let submerged = status.usbSubmersion {
                LabeledContent("USB Submersion", value: submerged ? "Submerged" : "Not submerged")
            }
            if !status.supportedFunctions.isEmpty {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(status.supportedFunctions + status.supportedFunctionsTable2, id: \.self) { name in
                            Text(name.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                } label: {
                    LabeledContent(
                        "Supported Functions",
                        value: "\(status.supportedFunctions.count + status.supportedFunctionsTable2.count)"
                    )
                }
            }
            if let json = session.stateJSON(), !json.isEmpty {
                DisclosureGroup("Engine State") {
                    Text(json)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var isEarbudModel: Bool {
        let model = status.model.uppercased()
        return model.hasPrefix("WF-") || model.hasPrefix("WI-") || model.contains("LINKBUDS")
    }

}

// MARK: - Categories

enum SettingsPage: String, Hashable {
    case sound, noise, playback, controls, power, connections, about

    var title: String {
        switch self {
        case .sound: return "Sound & Equalizer"
        case .noise: return "Noise Options"
        case .playback: return "Playback & Calls"
        case .controls: return "Controls & Gestures"
        case .power: return "Battery & Power"
        case .connections: return "Connections"
        case .about: return "Technical Details"
        }
    }

    var symbol: String {
        switch self {
        case .sound: return "speaker.wave.2.fill"
        case .noise: return "ear.fill"
        case .playback: return "play.fill"
        case .controls: return "hand.tap.fill"
        case .power: return "power"
        case .connections: return "link"
        case .about: return "info"
        }
    }

    /// The icon tile's colour, after System Settings' conventions.
    var colour: Color {
        switch self {
        case .sound: return .pink
        case .noise: return .indigo
        case .playback: return .orange
        case .controls: return .gray
        case .power: return .green
        case .connections: return .blue
        case .about: return .gray
        }
    }
}

/// The "Technical Details" link at the foot of About: lightens under the
/// pointer like the category rows.
private struct AboutLinkRow: View {
    @State private var hovering = false

    var body: some View {
        HStack {
            Text("Technical Details")
            Spacer()
            Image(systemName: "chevron.right")
                .font(.body.weight(.semibold))
                .imageScale(.small)
                .foregroundStyle(hovering ? .secondary : .tertiary)
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(hovering ? Motion.quick : Motion.hoverOut, value: hovering)
    }
}

/// A small grey capsule naming a fact, such as the codec.
struct InfoBadge: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.raised))
    }
}

/// A category as a row: symbol, title, current value, chevron. Lightens
/// under the pointer.
private struct CategoryRow: View {
    let page: SettingsPage
    var detail: String?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            SettingsIcon(symbol: page.symbol, colour: page.colour, size: 22)
            Text(page.title)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Image(systemName: "chevron.right")
                .font(.body.weight(.semibold))
                .imageScale(.small)
                .foregroundStyle(hovering ? .secondary : .tertiary)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(hovering ? Motion.quick : Motion.hoverOut, value: hovering)
        .animation(Motion.fast, value: detail)
    }
}

/// Battery as a widget: the level as a ring, the number inside it.
private struct BatteryWidget: View {
    let percent: Int
    let charging: ChargingState
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(charging == .charging ? "Battery, charging" : "Battery")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            ZStack {
                BatteryRing(percent: percent, charging: charging == .charging, diameter: 100)
                Text("\(percent)")
                    .font(.title.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(percent)))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 168, maxHeight: 168, alignment: .topLeading)
        .cardSurface(highlighted: hovering)
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .onHover { hovering = $0 }
        .animation(hovering ? Motion.quick : Motion.hoverOut, value: hovering)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery")
        .accessibilityValue(charging == .charging ? "\(percent) percent, charging" : "\(percent) percent")
    }
}

/// The equaliser as a widget: its bands as bars, the preset under them.
private struct EqualizerWidget: View {
    let eq: EqualizerView?
    @State private var hovering = false

    private var levels: [Double] {
        guard let eq, eq.isOn, !eq.bands.isEmpty else { return Array(repeating: 0.5, count: 10) }
        // Same scale as the equaliser page: the advertised step count, or
        // enough steps to hold the highest band reported.
        let top = Double(max(2, Int(eq.bandStep), Int(eq.bands.max() ?? 0) + 1) - 1)
        return eq.bands.map { min(max(Double($0) / top, 0), 1) }
    }

    private var preset: String {
        guard let eq else { return "" }
        if !eq.isOn { return "Off" }
        return eq.presetName.isEmpty ? "Custom" : eq.presetName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Equalizer")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 10)
            EqualizerBars(levels: levels)
                .frame(height: 64)
                .opacity(eq?.isOn == false ? 0.4 : 1)
            Spacer(minLength: 10)
            Text(preset)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 168, maxHeight: 168, alignment: .topLeading)
        .cardSurface(highlighted: hovering)
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .onHover { hovering = $0 }
        .animation(hovering ? Motion.quick : Motion.hoverOut, value: hovering)
        .animation(Motion.medium, value: levels)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Equalizer")
        .accessibilityValue(preset)
    }
}

// MARK: - Playback

/// What is playing: the live dot, lit while music plays, and the source.
private struct PlaybackStatus: View {
    let playback: PlaybackState
    private var playing: Bool { playback.state == 1 }

    var body: some View {
        HStack(spacing: 8) {
            LiveDot(live: playing)
            Text(playback.source == 1 ? "On a call" : playback.stateLabel)
                .font(.headline)
                .contentTransition(.opacity)
            Text(playback.source == 1 ? "Call" : "Music")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Motion.fast, value: playing)
        .accessibilityElement(children: .combine)
    }
}

/// The right earcup as a remote. The headphones take a double tap in the
/// middle for play/pause, a swipe forward or back for tracks and a swipe up
/// or down for volume; the controls sit where those gestures are. The
/// volume is the ring around the cup, filled to the level and draggable.
private struct EarcupRemote: View {
    let playing: Bool
    let hasTransport: Bool
    let volume: MusicVolume?
    let enabled: Bool
    let control: (UInt8) -> Void
    let setVolume: (Int) -> Void

    @State private var dragging: Int?

    private let size: CGFloat = 248
    private let ringWidth: CGFloat = 10
    /// The ring is a 270° gauge with its gap at the bottom.
    private let sweep = 0.75
    private let startAngle = 135.0

    private var level: Int? { dragging ?? volume?.value }
    private var fraction: Double {
        guard let volume, let level, volume.max > 0 else { return 0 }
        return Double(level) / Double(volume.max)
    }

    var body: some View {
        ZStack {
            ring
            cup
            if hasTransport {
                VStack {
                    stepKey("plus", help: "Volume up", delta: 1)
                    Spacer()
                    stepKey("minus", help: "Volume down", delta: -1)
                }
                .padding(.vertical, 46)
                HStack {
                    key("backward.fill", help: "Previous track") { control(0x03) }
                    Spacer()
                    key("forward.fill", help: "Next track") { control(0x02) }
                }
                .padding(.horizontal, 46)
                playPause
            }
            if let level, let volume {
                VStack(spacing: 0) {
                    Spacer()
                    Text("\(level)")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(level)))
                    Text("of \(volume.max)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .offset(y: 22)
                .accessibilityHidden(true)
            }
        }
        .frame(width: size, height: size)
        .padding(.bottom, 24)
        .disabled(!enabled)
        .animation(Motion.quick, value: level)
    }

    // MARK: Parts

    /// The cup: a soft neutral disc with a hairline edge.
    private var cup: some View {
        let d = size - ringWidth * 2 - 28
        return Circle()
            .fill(RadialGradient(colors: [Color.cardSolid, Color.cardSolid.mix(with: .black, by: 0.04)],
                                 center: .init(x: 0.4, y: 0.35), startRadius: 0, endRadius: d * 0.7))
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
            .frame(width: d, height: d)
            .accessibilityHidden(true)
    }

    private var ring: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: sweep)
                .stroke(Color.raised, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
            Circle()
                .trim(from: 0, to: sweep * fraction)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                .opacity(volume == nil ? 0 : 1)
        }
        .rotationEffect(.degrees(startAngle))
        .padding(ringWidth / 2)
        .contentShape(RingShape(width: ringWidth + 24), eoFill: true)
        .gesture(volume == nil ? nil : ringDrag)
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue(volume.map { "\($0.value) of \($0.max)" } ?? "")
        .accessibilityAdjustableAction { direction in
            step(direction == .increment ? 1 : -1)
        }
    }

    private var ringDrag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                guard let volume else { return }
                let c = CGPoint(x: size / 2, y: size / 2)
                var angle = atan2(g.location.y - c.y, g.location.x - c.x) * 180 / .pi
                angle = (angle - startAngle + 720).truncatingRemainder(dividingBy: 360)
                // In the gap at the bottom, stick to the nearer end.
                var t = angle / (sweep * 360)
                if t > 1 { t = angle > (sweep * 360 + 360) / 2 ? 0 : 1 }
                let v = Int((t * Double(volume.max)).rounded())
                if v != dragging {
                    dragging = v
                    setVolume(v)
                }
            }
            .onEnded { _ in dragging = nil }
    }

    private var playPause: some View {
        Button {
            control(playing ? 0x01 : 0x07)
        } label: {
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 56, height: 56)
                .contentShape(Circle())
                .glassEffect(.regular.tint(Color.accentColor).interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .help(playing ? "Pause" : "Play")
        .accessibilityLabel(playing ? "Pause" : "Play")
    }

    private func key(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(KeyPressStyle())
        .help(help)
        .accessibilityLabel(help)
    }

    private func stepKey(_ symbol: String, help: String, delta: Int) -> some View {
        key(symbol, help: help) { step(delta) }
            .disabled(volume == nil)
    }

    private func step(_ delta: Int) {
        guard let volume else { return }
        let next = min(max(volume.value + delta, 0), volume.max)
        if next != volume.value { setVolume(next) }
    }
}

/// An annulus, for hit-testing the volume ring only.
private struct RingShape: Shape {
    let width: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addEllipse(in: rect.insetBy(dx: -width / 2, dy: -width / 2))
        p.addEllipse(in: rect.insetBy(dx: width / 2, dy: width / 2))
        return p
    }
}

/// A level as a labelled row: the title and its value out of the device's
/// steps, the slider across the full width under them. `live` writes each
/// step while dragging (volume, judged by ear); otherwise on release.
private struct LevelRow: View {
    let title: String
    let level: MusicVolume
    var live = false
    let onCommit: (Int) -> Void

    @State private var dragging: Int?
    private var shown: Int { dragging ?? level.value }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer()
                Text("\(shown) of \(level.max)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            GlassSlider(
                value: Binding(
                    get: { Double(shown) },
                    set: { v in
                        let step = Int(v.rounded())
                        if live, step != dragging { onCommit(step) }
                        dragging = step
                    }
                ),
                range: 0...Double(level.max),
                style: .lens,
                label: title,
                valueText: { "\(Int($0.rounded())) of \(level.max)" }
            ) { editing in
                guard !editing, let settled = dragging else { return }
                dragging = nil
                if !live, settled != level.value { onCommit(settled) }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Mac press feedback for a bare glyph: it darkens, it does not scale.
private struct KeyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Circle().fill(Color.primary.opacity(configuration.isPressed ? 0.08 : 0)))
    }
}

// MARK: - Noise field

/// What each mode does to the sound around you, drawn as the sound itself:
/// uneven rings of outside noise travelling in toward the listener.
///
/// - Noise cancelling: the rings meet a blue shield, lose their ripple as
///   they reach it and stop; inside, the air is calm and lit.
/// - Ambient sound: the shield opens into a turning teal lattice and the
///   rings come through, as strong as the ambient level.
/// - Off: grey rings, dimmed only by the ear cups' seal, a thin ring
///   around the headphones.
///
/// A switch glides from one picture to the next (each part eases toward
/// its new value over about half a second). Reduce Motion holds the
/// picture still.
private struct NoiseField: View {
    let control: NoiseControlView
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = FieldModel()

    var body: some View {
        VStack(spacing: 12) {
            TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { context in
                Canvas { ctx, size in
                    model.step(toward: FieldModel.Target(control), at: context.date.timeIntervalSinceReferenceDate,
                               instant: reduceMotion)
                    model.draw(&ctx, size: size)
                }
            }
            .frame(height: 240)
            .overlay {
                Image(systemName: "headphones")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(Color.cardSolid).shadow(color: .black.opacity(0.08), radius: 6, y: 2))
            }
            .accessibilityHidden(true)
            Text(caption)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .animation(Motion.fast, value: caption)
        }
        .accessibilityElement(children: .combine)
    }

    private var caption: String {
        switch control {
        case .noiseCancelling: return "Outside sound is cancelled"
        case .ambient(let voice, let level):
            return voice ? "Voices come through, level \(level) of 20" : "Outside sound comes through, level \(level) of 20"
        case .off: return "Only the ear cups' seal blocks outside sound"
        case .unknown: return ""
        }
    }
}

/// The field's moving parts. A class so the canvas can ease them frame to
/// frame without publishing anything.
private final class FieldModel {
    struct Target {
        var shield = 0.0, lattice = 0.0, seal = 0.0, pass = 0.0
        var tint = RGB.grey
        init(_ control: NoiseControlView) {
            switch control {
            case .noiseCancelling: shield = 1; tint = .blue
            case .ambient(_, let level):
                lattice = 1; pass = 0.35 + 0.65 * Double(level) / 20; tint = .teal
            case .off: seal = 1; pass = 0.45
            case .unknown: pass = 0.3
            }
        }
    }

    struct RGB {
        var r, g, b: Double
        static let grey = RGB(r: 0.52, g: 0.52, b: 0.56)
        static let blue = RGB(r: 0.0, g: 0.48, b: 1.0)
        static let teal = RGB(r: 0.0, g: 0.68, b: 0.68)
        func mixed(_ o: RGB, _ k: Double) -> RGB {
            RGB(r: r + (o.r - r) * k, g: g + (o.g - g) * k, b: b + (o.b - b) * k)
        }
        func color(_ a: Double) -> Color { Color(red: r, green: g, blue: b).opacity(max(0, min(1, a))) }
    }

    private var now = Target(.unknown)
    private var started = false
    private var t = 0.0
    private var last: Double?

    func step(toward target: Target, at time: Double, instant: Bool) {
        let dt = min(0.05, time - (last ?? time))
        last = time
        t += dt
        if !started || instant { now = target; started = true; return }
        // About half a second to settle, whatever the frame rate.
        let k = 1 - exp(-dt * 7)
        now.shield += (target.shield - now.shield) * k
        now.lattice += (target.lattice - now.lattice) * k
        now.seal += (target.seal - now.seal) * k
        now.pass += (target.pass - now.pass) * k
        now.tint = now.tint.mixed(target.tint, k)
    }

    func draw(_ ctx: inout GraphicsContext, size: CGSize) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let outer = min(size.width, size.height) / 2 - 6
        let disc: CGFloat = 32
        let shieldR = outer * 0.56
        let sealR = disc + 12

        // Calm, lit air inside the shield.
        if now.shield > 0.01 {
            let glow = Gradient(colors: [RGB.blue.color(0.14 * now.shield), RGB.blue.color(0.02 * now.shield)])
            ctx.fill(circle(c, shieldR), with: .radialGradient(glow, center: c, startRadius: disc, endRadius: shieldR))
        }

        // Outside noise, travelling in.
        let count = 7
        let period = 3.4
        for i in 0..<count {
            let p = ((t / period) + Double(i) / Double(count)).truncatingRemainder(dividingBy: 1)
            let r = outer - (outer - disc) * CGFloat(p)
            var alpha = 0.5 * sin(Double.pi * min(1, p * 1.25))
            var ripple = 3.5
            // Toward the shield the ripple is cancelled, then the ring.
            if r < shieldR + 36 {
                let near = Double(min(1, (shieldR + 36 - r) / 36))
                ripple *= 1 - now.shield * near
            }
            if r < shieldR {
                alpha *= (1 - now.shield) * max(now.pass, 1 - now.shield)
                if now.shield < 0.5 { alpha *= 0.4 + 0.6 * now.pass }
            }
            if r < sealR { alpha *= 1 - 0.6 * now.seal }
            let colour = RGB.grey.mixed(now.tint, now.lattice + now.shield * 0.35)
            ctx.stroke(wobbly(c, r, ripple, phase: Double(i) * 1.7 + t * 0.9),
                       with: .color(colour.color(alpha)), lineWidth: 1.6)
        }

        // Noise cancelling: the shield.
        if now.shield > 0.01 {
            ctx.stroke(circle(c, shieldR), with: .color(RGB.blue.color(0.85 * now.shield)), lineWidth: 2.5)
        }
        // Ambient: the shield opened into a turning lattice.
        if now.lattice > 0.01 {
            var rotated = ctx
            rotated.translateBy(x: c.x, y: c.y)
            rotated.rotate(by: .radians(t * 0.25))
            rotated.stroke(circle(.zero, shieldR), with: .color(RGB.teal.color(0.7 * now.lattice)),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [2, 10]))
        }
        // Off: just the cups' seal.
        if now.seal > 0.01 {
            ctx.stroke(circle(c, sealR), with: .color(RGB.grey.color(0.45 * now.seal)), lineWidth: 1.2)
        }
    }

    private func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    /// A ring with an uneven edge, the way noise is uneven.
    private func wobbly(_ c: CGPoint, _ r: CGFloat, _ amp: Double, phase: Double) -> Path {
        var p = Path()
        let steps = 96
        for k in 0...steps {
            let a = Double(k) / Double(steps) * 2 * .pi
            let d = amp * (0.6 * sin(5 * a + phase) + 0.4 * sin(9 * a - phase * 1.3))
            let rr = Double(r) + d
            let pt = CGPoint(x: c.x + CGFloat(cos(a) * rr), y: c.y + CGFloat(sin(a) * rr))
            if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// The ambient level, 0…20, as a labelled row with the lens slider.
private struct AmbientLevelRow: View {
    let level: Int
    let onCommit: (Int) -> Void
    @State private var dragging: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ambient level")
                Spacer()
                Text("\(dragging ?? level) of 20")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            GlassSlider(
                value: Binding(get: { Double(dragging ?? level) }, set: { dragging = Int($0.rounded()) }),
                range: 0...20,
                style: .lens,
                label: "Ambient level",
                valueText: { "\(Int($0.rounded())) of 20" }
            ) { editing in
                guard !editing, let settled = dragging else { return }
                dragging = nil
                if settled != level { onCommit(settled) }
            }
        }
    }
}

/// Design review: `SONY_UI_RENDERNOISE=<dir>` writes the noise field in
/// each mode to PNGs.
@MainActor
func renderNoiseFieldsIfRequested() {
    guard let dir = ProcessInfo.processInfo.environment["SONY_UI_RENDERNOISE"] else { return }
    let modes: [(String, NoiseControlView)] = [
        ("nc", .noiseCancelling), ("ambient", .ambient(voice: false, level: 14)), ("off", .off),
    ]
    for (name, mode) in modes {
        let view = NoiseField(control: mode)
            .frame(width: 420)
            .padding(20)
            .background(Color.canvas)
            .environment(\.colorScheme, .light)
        let r = ImageRenderer(content: view)
        r.scale = 2
        // Resolve the theme's dynamic colours in light whatever the system is.
        var rendered: NSImage?
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance { rendered = r.nsImage }
        if let img = rendered, let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("noise-\(name).png"))
        }
    }
}

/// A row in a grouped card that opens a page, as System Settings does it:
/// no fill on hover (only the chevron darkens), a light shade across the
/// whole row while pressed. The card clips the shade to its corners.
private struct CardRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.primary.opacity(configuration.isPressed ? 0.07 : 0))
    }
}
