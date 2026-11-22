import Foundation
import Combine
import IOBluetooth

/// What the user picked in the noise-control segmented control.
///
/// Deliberately a closed set rather than raw bytes: the UI cannot express a
/// value the protocol does not allow.
public enum NoiseControlChoice: String, CaseIterable, Identifiable {
    case noiseCancelling
    case ambient
    case off

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .noiseCancelling: return "Noise cancelling"
        case .ambient: return "Ambient sound"
        case .off: return "Off"
        }
    }

    public var symbol: String {
        switch self {
        case .noiseCancelling: return "waveform.path.ecg"
        case .ambient: return "ear"
        case .off: return "speaker.slash"
        }
    }
}

/// Coordinates transport + engine and publishes UI-ready state.
///
/// Threading contract: everything here runs on the main thread. Bluetooth
/// delegate callbacks are hopped to main before touching the engine, so no
/// locking is required and the engine is never entered concurrently.
public final class HeadphoneSession: ObservableObject {
    @Published public private(set) var status = HeadphoneStatus()
    @Published public private(set) var devices: [PairedDevice] = []
    @Published public private(set) var connected: PairedDevice?
    @Published public private(set) var activity: String = ""
    @Published public private(set) var lastError: String?

    /// Set once the handshake completes; drives the UI's enabled state.
    public var isReady: Bool { status.phase.isReady }

    private var link: BluetoothLink?
    private var engine: Engine?
    private var timer: Timer?
    private var handshakeDeadline: Date?

    /// Diagnostic trail, newest last. The inspector renders this verbatim so a
    /// bug report can be reproduced without guesswork.
    @Published public private(set) var log: [String] = []
    /// Number of early log lines dropped by the 200-line cap.
    public private(set) var droppedLogLines = 0

    public init() {
        if ProcessInfo.processInfo.environment["SONY_UI_PREVIEW"] == "1" {
            loadDesignPreview()
        }
        refreshDevices()
    }

    /// Populates sample state so the interface can be reviewed while the
    /// headphones are asleep. Only runs when `SONY_UI_PREVIEW=1` is set in the
    /// environment; a normal launch never takes this path, and nothing here is
    /// reported as device data.
    private func loadDesignPreview() {
        var sample = HeadphoneStatus()
        sample.phase = .ready
        sample.model = "WH-1000XM6"
        sample.firmware = "3.1.5"
        sample.batteryPercent = 72
        sample.charging = .notCharging
        sample.noiseControl = .ambient(voice: false, level: 8)
        sample.noiseAdaptation = true
        var eq = EqualizerView()
        eq.preset = 0xA0
        eq.presetName = "Custom"
        eq.bands = [11, 10, 9, 6, 5, 8, 9, 8, 10, 11]
        eq.bandCount = 10
        eq.clearBass = 2
        eq.clearBassRange = -10...10
        eq.presets = [
            .init(id: 0x00, name: "Off"),
            .init(id: 0x20, name: "Gaming"),
            .init(id: 0x30, name: "Heavy"),
            .init(id: 0x31, name: "Clear"),
            .init(id: 0x32, name: "Hard"),
            .init(id: 0x33, name: "Soft"),
            .init(id: 0xA0, name: "Custom"),
            .init(id: 0xA1, name: "User 1"),
            .init(id: 0xA2, name: "User 2"),
        ]
        sample.equalizer = eq
        sample.playback = PlaybackState(enabled: true, state: 2, source: 0)
        sample.musicHandOver = false
        sample.usbSubmersion = false
        // Every other section, so the whole page can be reviewed. Sample
        // values only; none of these were read from a device.
        sample.equalizer?.bandStep = 13
        sample.codec = "AAC"
        sample.protocolVersion = 0x0200_0000
        sample.connectionMode = ConnectionMode(classic: true, le: false)
        sample.upscaling = true
        sample.listening = .standard
        sample.volume = MusicVolume(value: 18, max: 30)
        sample.callVolume = MusicVolume(value: 10, max: 15)
        sample.smartTalking = SmartTalkingView(enabled: true, effect: 0, sensitivity: 0, modeOut: 1)
        sample.headGesture = true
        sample.controlByWearing = true
        sample.quickAccess = [0, 0]
        sample.micOnOff = false
        sample.safeVolume = 0
        sample.voiceGuidance = true
        sample.voiceGuidanceVolume = 0
        sample.autoStandby = true
        sample.autoStandbyEnabled = true
        sample.autoPowerOffWearing = AutoPowerOffWearing(current: 0x10, last: 0x10, enabled: true)
        sample.pairingKnown = true
        sample.pairedDevices = [
            PairedDeviceView(address: "58:18:62:00:00:01", name: "Sample Mac", connected: true, classOfDevice: nil),
            PairedDeviceView(address: "58:18:62:00:00:02", name: "Sample Phone", connected: false, classOfDevice: nil),
        ]
        sample.pairingCapability = PairingCapabilityView(maxPaired: 8, maxConnected: 2, fileTransfer: 0)
        sample.supportedFunctions = ["NOISE_CANCELLING_AND_AMBIENT_SOUND_MODE", "BATTERY_LEVEL_INDICATOR"]
        status = sample
        connected = PairedDevice(
            address: "00:11:22:AA:BB:CC",
            name: "WH-1000XM6",
            isConnected: true
        )
        activity = ""
        record("design preview — not live device data")
    }

    // MARK: Device list

    public func refreshDevices() {
        devices = BluetoothLink.pairedDevices
    }

    // MARK: Connect / disconnect

    public func connect(to device: PairedDevice) {
        disconnect()
        guard let engine = Engine() else {
            lastError = "Could not allocate the protocol engine."
            return
        }
        self.engine = engine
        connected = device
        lastError = nil
        status = HeadphoneStatus()
        status.phase = .connecting
        record("engine \(Engine.version) · target \(device.displayName) [\(device.address)]")

        let link = BluetoothLink()
        self.link = link
        link.onReceive = { [weak self] data in
            DispatchQueue.main.async { self?.handleInbound(data) }
        }
        link.onClose = { [weak self] in
            DispatchQueue.main.async { self?.handleLinkClosed() }
        }

        do {
            try link.open(address: device.address) { [weak self] milestone in
                DispatchQueue.main.async { self?.activity = milestone }
            }
        } catch {
            fail("\(error)")
            return
        }

        do {
            let first = try engine.connect(nowMs: Self.nowMs())
            try link.write(first)
            record("→ CONNECT_GET_PROTOCOL_INFO  \(Self.hex(first))")
        } catch {
            fail("\(error)")
            return
        }

        activity = "Handshaking"
        // The link is stop-and-wait: each command waits for its acknowledgement
        // before the next one goes out, so a full handshake takes several
        // round trips.
        handshakeDeadline = Date().addingTimeInterval(30)
        startTimer()
        publish()
    }

    public func disconnect() {
        timer?.invalidate()
        timer = nil
        link?.close()
        link = nil
        engine = nil
        connected = nil
        handshakeDeadline = nil
        activity = ""
        status = HeadphoneStatus()
        record("disconnected")
    }

    // MARK: Commands

    /// Commands still queued or in flight.
    public var pendingCommands: Int { engine?.pendingCount ?? 0 }

    public func refreshStatus() {
        guard let engine, isReady else { return }
        // The request may be queued behind an outstanding command; the engine
        // sends it as soon as that command is acknowledged.
        if let bytes = engine.requestBattery(nowMs: Self.nowMs()) {
            do {
                try send(bytes, label: "→ POWER_GET_STATUS")
            } catch {
                fail("\(error)")
            }
        }
    }

    public func setNoiseControl(_ choice: NoiseControlChoice, ambientLevel: Int? = nil) {
        guard let engine, isReady else { return }
        let level = UInt8(max(0, min(20, ambientLevel ?? status.noiseControl.level)))
        let enabled = choice != .off
        let mode: UInt8 = choice == .noiseCancelling ? 0 : 1
        let ambient: UInt8 = status.noiseControl.voiceSelected ? 1 : 0
        guard let bytes = engine.setNoiseControl(
            enabled: enabled, mode: mode, ambient: ambient, level: level, nowMs: Self.nowMs())
        else { return }
        do {
            try send(bytes, label: "→ NCASM_SET_PARAM \(choice.title)")
            // Optimistic until the device confirms; the UI shows the write as
            // pending rather than pretending it landed.
            status.pendingWrite = true
        } catch {
            fail("\(error)")
        }
    }

    public func setAmbientLevel(_ level: Int) {
        guard case .ambient(let voice, _) = status.noiseControl else { return }
        _ = voice
        setNoiseControl(.ambient, ambientLevel: level)
    }

    /// Diagnostic: send a raw payload on the control channel.
    public func sendRaw(_ bytes: [UInt8]) {
        guard let engine, isReady else { return }
        guard let out = engine.sendRaw(Data(bytes), nowMs: Self.nowMs()) else { return }
        do {
            let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
            try send(out, label: "→ raw \(hex)")
        } catch { fail("\(error)") }
    }

    /// Diagnostic: send a raw payload on table 2.
    public func sendRawTable2(_ bytes: [UInt8]) {
        guard let engine, isReady else { return }
        guard let out = engine.sendRawTable(2, Data(bytes), nowMs: Self.nowMs()) else { return }
        do {
            let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
            try send(out, label: "→ t2 \(hex)")
        } catch { fail("\(error)") }
    }

    // MARK: Equaliser

    /// Choose an equaliser preset by its wire id.
    ///
    /// The id comes from the device's own advertised list, so this cannot send
    /// a preset the headphones did not offer.
    public func setEqualizerPreset(_ preset: UInt8) {
        guard let engine, isReady else { return }
        // Band gains belong to the custom curve. Sending the current custom
        // bands with a fixed preset would push the wrong curve onto it, so a
        // fixed preset is written with no bands and the device supplies its own.
        let isCustomCurve = preset == 0xA0 || (0xA1...0xA5).contains(preset)
        let bands = isCustomCurve ? (status.equalizer?.bands ?? []) : []
        guard let bytes = engine.setEqPreset(preset, bands: bands, nowMs: Self.nowMs()) else {
            return
        }
        do {
            try send(bytes, label: "→ EQEBB_SET_PARAM preset \(preset)")
            status.pendingWrite = true
        } catch {
            fail("\(error)")
        }
    }

    /// Choose the voice assistant.
    public func setVoiceAssistant(_ value: UInt8) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setVoiceAssistant(value, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ SYSTEM_SET_PARAM voice assistant \(value)")
            status.pendingWrite = true
        } catch { fail("\(error)") }
    }

    /// Set one general-setting slot.
    public func setGeneralSetting(_ gs: GeneralSetting, enabled: Bool) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setGeneralSetting(gs.id, enabled, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ GENERAL_SETTING_SET_PARAM \(gs.title) \(enabled)")
            status.pendingWrite = true
        } catch { fail("\(error)") }
    }

    /// Toggle noise adaptation (auto ambient).
    public func setNoiseAdaptation(_ enabled: Bool) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setNoiseAdaptation(enabled, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ NCASM_SET_PARAM adaptation \(enabled)")
            status.pendingWrite = true
        } catch { fail("\(error)") }
    }

    /// Toggle audio upscaling.
    public func setUpscaling(_ enabled: Bool) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setUpscaling(enabled, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ AUDIO_SET_STATUS upscaling \(enabled)")
            status.pendingWrite = true
        } catch { fail("\(error)") }
    }

    /// The engine's complete JSON state, for diagnostics.
    public func stateJSON() -> String? { engine?.stateJSON() }

    /// Send a playback control action.
    public func setPlaybackControl(_ control: UInt8) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setPlaybackControl(control, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ PLAY_SET_STATUS \(control)")
            status.pendingWrite = true
        } catch { fail("\(error)") }
    }

    /// Set the music volume. Sent only when the device advertised a range.
    public func setMusicVolume(_ volume: Int) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setMusicVolume(volume, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ PLAY_SET_PARAM music volume \(volume)")
            status.pendingWrite = true
        } catch { fail("\(error)") }
    }

    /// Set the call volume, when the device advertised a range.
    public func setCallVolume(_ volume: Int) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setCallVolume(volume, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ PLAY_SET_PARAM call volume \(volume)")
            status.pendingWrite = true
        } catch { fail("\(error)") }
    }

    /// Set one general-setting boolean slot.
    public func setGeneralSetting(_ gsType: UInt8, on: Bool) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setGeneralSetting(gsType, on: on, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ GENERAL_SETTING_SET_PARAM 0x\(String(gsType, radix: 16)) \(on)")
            status.pendingWrite = true
        } catch { fail("\(error)") }
    }

    /// Start or stop adaptive control.
    public func setAdaptiveControl(_ start: Bool) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setAdaptiveControl(start, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ SENSE_SET_STATUS adaptive \(start ? "start" : "stop")")
            status.pendingWrite = true
        } catch { fail("\(error)") }
    }

    /// Replace the Quick Access function list.
    public func setQuickAccessFunctions(_ functions: [UInt8]) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setQuickAccessFunctions(functions, nowMs: Self.nowMs()) else { return }
        do {
            let hex = functions.map { String(format: "%02X", $0) }.joined(separator: " ")
            try send(bytes, label: "→ QUICK_ACCESS_EASY_SETTING \(hex)")
            status.pendingWrite = true
        } catch { fail("\(error)") }
    }

    /// Toggle playback control by wearing/removing the headphones.
    public func setControlByWearing(_ enabled: Bool) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setControlByWearing(enabled, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ SYSTEM_SET_PARAM control by wearing \(enabled ? "on" : "off")")
            status.pendingWrite = true
        } catch { fail("\(error)") }
    }

    /// Toggle mic on/off by headphone operation.
    public func setMicOnOff(_ enabled: Bool) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setMicOnOff(enabled, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ SYSTEM_SET_PARAM mic \(enabled ? "on" : "off")")
            status.pendingWrite = true
        } catch { fail("\(error)") }
    }

    /// Toggle Sony Voice Assistant.
    public func setSonyVoiceAssistant(_ enabled: Bool) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setSonyVoiceAssistant(enabled, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ SYSTEM_SET_PARAM Sony VA \(enabled ? "on" : "off")")
            status.pendingWrite = true
        } catch { fail("\(error)") }
    }

    /// Toggle voice guidance.
    public func setVoiceGuidance(_ enabled: Bool) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setVoiceGuidance(enabled, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ VOICE_GUIDANCE_SET_PARAM \(enabled ? "on" : "off")")
            status.pendingWrite = true
        } catch { fail("\(error)") }
    }

    /// Set the voice guidance volume.
    public func setVoiceGuidanceVolume(_ volume: Int8) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setVoiceGuidanceVolume(volume, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ VOICE_GUIDANCE_SET_PARAM volume \(volume)")
            status.pendingWrite = true
        } catch { fail("\(error)") }
    }

    /// Start or finish head gesture training.
    public func setHeadGestureTraining(_ start: Bool) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setHeadGestureTraining(start, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ SYSTEM_SET_STATUS head gesture training \(start ? "start" : "finish")")
        } catch { fail("\(error)") }
    }

    /// Set the safe-volume WHO standard level.
    public func setSafeVolume(_ level: UInt8) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setSafeVolume(level, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ SAFE_LISTENING_SET_STATUS safe volume \(level)")
        } catch { fail("\(error)") }
    }

    /// Toggle head gesture control.
    public func setHeadGesture(_ enabled: Bool) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setHeadGesture(enabled, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ SYSTEM_SET_STATUS head gesture \(enabled)")
            status.pendingWrite = true
        } catch { fail("\(error)") }
    }

    /// Ask the headphones to power off.
    public func powerOff() {
        guard let engine, isReady else { return }
        guard let bytes = engine.powerOff(nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ POWER_SET_STATUS user power off")
        } catch { fail("\(error)") }
    }

    /// Toggle Speak-to-Chat.
    public func setSmartTalking(_ enabled: Bool) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setSmartTalking(enabled, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ SYSTEM_SET_PARAM speak-to-chat \(enabled)")
            status.pendingWrite = true
        } catch { fail("\(error)") }
    }

    /// Set Speak-to-Chat sensitivity and auto-off time.
    public func setSmartTalkingDetail(sensitivity: UInt8, modeOut: UInt8) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setSmartTalkingDetail(
            sensitivity: sensitivity,
            modeOut: modeOut,
            nowMs: Self.nowMs()
        ) else { return }
        do {
            try send(bytes, label: "→ SYSTEM_SET_EXT_PARAM speak-to-chat \(sensitivity)/\(modeOut)")
            status.pendingWrite = true
        } catch { fail("\(error)") }
    }

    /// Toggle auto standby.
    public func setAutoStandby(_ enabled: Bool) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setAutoStandby(enabled, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ POWER_SET_PARAM auto standby \(enabled)")
            status.pendingWrite = true
        } catch { fail("\(error)") }
    }

    /// Toggle table-2 music hand-over.
    public func setMusicHandOver(_ enabled: Bool) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setMusicHandOver(enabled, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ PERI_SET_PARAM music hand-over \(enabled)")
            status.pendingWrite = true
        } catch { fail("\(error)") }
    }

    /// Ask the headset to connect to a paired device.
    public func connectPairedDevice(at index: Int) {
        guard let engine, isReady else { return }
        guard let bytes = engine.pairingConnect(index: index, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ PERI_SET_EX_PARAM connect #\(index)")
        } catch { fail("\(error)") }
    }

    /// Ask the headset to disconnect a paired device. The device list re-reads
    /// itself; no optimistic state is written here.
    public func disconnectPairedDevice(at index: Int) {
        guard let engine, isReady else { return }
        guard let bytes = engine.pairingDisconnect(index: index, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ PERI_SET_EX_PARAM disconnect #\(index)")
        } catch { fail("\(error)") }
    }

    /// Enter or leave Bluetooth pairing (inquiry-scan) mode.
    public func setPairingMode(_ pairing: Bool) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setPairingMode(pairing, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ PERI_SET_STATUS pairing mode \(pairing)")
        } catch { fail("\(error)") }
    }

    /// Switch the listening mode. The engine refuses until both BGM and Cinema
    /// have been read, because the BGM setter carries the current room size.
    public func setListeningMode(_ mode: ListeningModeView) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setListeningMode(mode, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ AUDIO_SET_PARAM listening \(mode.label)")
            status.pendingWrite = true
        } catch { fail("\(error)") }
    }

    /// Set the wearing-detection auto-power-off element. `last` is kept as the
    /// device reported it; the firmware normalises it on its own.
    public func setAutoPowerOffWearing(_ value: UInt8) {
        guard let engine, isReady else { return }
        let last = status.autoPowerOffWearing?.last ?? 0x00
        guard let bytes = engine.setAutoPowerOffWearing(current: value, last: last, nowMs: Self.nowMs()) else {
            return
        }
        do {
            try send(bytes, label: "→ POWER_SET_PARAM auto-off \(AutoPowerOffWearing.label(value))")
            status.pendingWrite = true
        } catch { fail("\(error)") }
    }

    /// Write a custom band curve. Selecting a band value implies the custom
    /// preset, because the fixed presets own their own curves.
    public func setEqualizerBands(_ bands: [UInt8]) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setEqPreset(0xA0, bands: bands, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ EQEBB_SET_PARAM custom band curve")
            status.pendingWrite = true
        } catch { fail("\(error)") }
    }

    /// Set the Clear Bass level.
    public func setClearBass(_ level: Int) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setClearBass(level, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ EQEBB_SET_PARAM Clear Bass \(level)")
            status.pendingWrite = true
        } catch {
            fail("\(error)")
        }
    }

    // MARK: Data path

    private func send(_ bytes: Data, label: String) throws {
        guard let link else { return }
        guard !bytes.isEmpty else {
            // Queued behind an in-flight command; the engine flushes it on the
            // next ack via the receive callback.
            record("\(label)  (queued)")
            return
        }
        try link.write(bytes)
        record("\(label)  \(Self.hex(bytes))")
    }

    private func handleInbound(_ data: Data) {
        guard let engine else { return }
        let followUp = engine.receive(data)
        publish()
        record("←  \(Self.hex(data))")
        if let followUp {
            try? link?.write(followUp)
            record("→  \(Self.hex(followUp))")
        }
        if status.phase.isReady, handshakeDeadline != nil {
            handshakeDeadline = nil
            activity = ""
            record("handshake complete · ready")
            refreshStatus()
        }
    }

    /// Hex rendering of a wire buffer, for the diagnostic trail.
    ///
    /// Long buffers are truncated: the point is to make the frame boundaries
    /// and the sequence numbers visible, not to dump a log.
    private static func hex(_ data: Data, limit: Int = 220) -> String {
        let bytes = [UInt8](data)
        let shown = bytes.prefix(limit)
        var out = shown.map { String(format: "%02X", $0) }.joined(separator: " ")
        if bytes.count > limit { out += " … (\(bytes.count) B)" }
        return out.isEmpty ? "(empty)" : out
    }

    private func handleLinkClosed() {
        timer?.invalidate()
        timer = nil
        lastError = "The control channel closed."
        status.phase = .disconnected
        activity = ""
        record("link closed by remote")
    }

    // MARK: Polling

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard let engine else { return }
        let now = Self.nowMs()
        if let retry = engine.poll(nowMs: now) {
            try? link?.write(retry)
            record("→ tick  \(Self.hex(retry))")
        }
        publish()
        if !status.phase.isReady, let deadline = handshakeDeadline, Date() > deadline {
            fail("The headphones did not answer the handshake. Turn them on and make sure they are not connected to another device.")
        }
    }

    /// Milliseconds since the epoch, the clock the engine expects.
    private static func nowMs() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1000)
    }

    private func publish() {
        guard let engine else { return }
        var next = HeadphoneStatus(snapshot: engine.snapshot())
        next.modelColor = engine.modelColor()
        if next.equalizer != nil { next.equalizer?.offReason = engine.eqErrorCode() }
        // Preset names are variable-length, so they come from the engine rather
        // than the flat snapshot. Only enrich when the device reported an EQ.
        if next.equalizer != nil {
            let presets = engine.eqPresets()
            if !presets.isEmpty {
                next.equalizer?.presets = presets
                if let match = presets.first(where: { $0.id == next.equalizer?.preset }) {
                    next.equalizer?.presetName = match.name
                }
            }
        }
        // General-setting slots are device-named, like preset names.
        let gs = engine.generalSettings()
        if !gs.isEmpty { next.generalSettings = gs }
        let supported = engine.supportedFunctions()
        if !supported.isEmpty { next.supportedFunctions = supported }
        let supported2 = engine.supportedFunctionsTable2()
        if !supported2.isEmpty { next.supportedFunctionsTable2 = supported2 }
        if next.pairingKnown {
            next.pairedDevices = engine.pairedDevices()
            next.pairingCapability = engine.pairingCapability()
            next.pairingEvent = engine.pairingEvent()
            next.pairingMode = engine.pairingMode()
        }
        if next.voiceAssistant != nil {
            if let va = engine.voiceAssistant() { next.voiceAssistant = va }
        }
        if next != status {
            status = next
        }
    }

    // MARK: Helpers

    private func fail(_ message: String) {
        lastError = message
        activity = ""
        status.phase = .error
        record("error: \(message)")
        timer?.invalidate()
        timer = nil
    }

    /// Set `SONY_LOG_STDOUT=1` to stream the wire trail to stdout with
    /// timestamps, for timing a write against its confirmation.
    private static let logToStdout = ProcessInfo.processInfo.environment["SONY_LOG_STDOUT"] != nil

    private func record(_ line: String) {
        if Self.logToStdout {
            print(String(format: "%.3f ", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1000)) + line)
            fflush(stdout)
        }
        log.append(line)
        if log.count > 1000 {
            let drop = log.count - 1000
            log.removeFirst(drop)
            droppedLogLines += drop
        }
    }
}

private extension NoiseControlView {
    /// Ambient "voice" flag, read back through the shared enum.
    var voiceSelected: Bool {
        if case .ambient(let voice, _) = self { return voice }
        return false
    }
}
