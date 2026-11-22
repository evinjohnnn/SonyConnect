import Foundation
import Combine

/// Coordinates the accessory transport and the shared engine, and publishes
/// UI-ready state. Mirrors the macOS session, with the transport swapped.
@MainActor
final class IOSHeadphoneSession: ObservableObject {
    @Published private(set) var status = HeadphoneStatus()
    @Published private(set) var devices: [AccessoryDevice] = []
    @Published private(set) var connected: AccessoryDevice?
    @Published private(set) var lastError: String?
    @Published private(set) var log: [String] = []

    var isReady: Bool { status.phase.isReady }

    private var link: AccessoryLink?
    private var engine: Engine?
    private var timer: Timer?
    private var handshakeDeadline: Date?
    private var logOffset = 0

    init() { refresh() }

    func refresh() {
        devices = AccessoryLink.connectedDevices
    }

    func connect(to device: AccessoryDevice) {
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
        record("engine \(Engine.version) · \(device.name)")

        let link = AccessoryLink()
        self.link = link
        link.onReceive = { [weak self] data in
            Task { @MainActor in self?.handleInbound(data) }
        }
        link.onClose = { [weak self] in
            Task { @MainActor in self?.fail("The control channel closed.") }
        }
        do {
            try link.open(matching: device)
            let first = try engine.connect(nowMs: Self.nowMs())
            try link.write(first)
            record("→ CONNECT_GET_PROTOCOL_INFO")
        } catch {
            fail("\(error)")
            return
        }

        handshakeDeadline = Date().addingTimeInterval(30)
        startTimer()
        publish()
    }

    func disconnect() {
        timer?.invalidate()
        timer = nil
        link?.close()
        link = nil
        engine = nil
        connected = nil
        handshakeDeadline = nil
        status = HeadphoneStatus()
        record("disconnected")
    }

    // MARK: Playback

    func setPlaybackControl(_ control: UInt8) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setPlaybackControl(control, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ PLAY_SET_STATUS \(control)")
            status.pendingWrite = true
        } catch { fail("\(error)") }
    }

    // MARK: Music volume

    func setMusicVolume(_ volume: Int) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setMusicVolume(volume, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ PLAY_SET_PARAM music volume \(volume)")
            status.pendingWrite = true
        } catch { fail("\(error)") }
    }

    func setCallVolume(_ volume: Int) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setCallVolume(volume, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ PLAY_SET_PARAM call volume \(volume)")
            status.pendingWrite = true
        } catch { fail("\(error)") }
    }

    func setControlByWearing(_ enabled: Bool) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setControlByWearing(enabled, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ SYSTEM_SET_PARAM control by wearing \(enabled ? "on" : "off")")
        } catch { fail("\(error)") }
    }

    func setAdaptiveControl(_ start: Bool) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setAdaptiveControl(start, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ SENSE_SET_STATUS adaptive \(start ? "start" : "stop")")
        } catch { fail("\(error)") }
    }

    func setQuickAccessFunctions(_ functions: [UInt8]) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setQuickAccessFunctions(functions, nowMs: Self.nowMs()) else { return }
        do {
            let hex = functions.map { String(format: "%02X", $0) }.joined(separator: " ")
            try send(bytes, label: "→ QUICK_ACCESS_EASY_SETTING \(hex)")
        } catch { fail("\(error)") }
    }

    func setMicOnOff(_ enabled: Bool) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setMicOnOff(enabled, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ SYSTEM_SET_PARAM mic \(enabled ? "on" : "off")")
        } catch { fail("\(error)") }
    }

    func setSonyVoiceAssistant(_ enabled: Bool) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setSonyVoiceAssistant(enabled, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ SYSTEM_SET_PARAM Sony VA \(enabled ? "on" : "off")")
        } catch { fail("\(error)") }
    }

    func setVoiceGuidance(_ enabled: Bool) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setVoiceGuidance(enabled, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ VOICE_GUIDANCE_SET_PARAM \(enabled ? "on" : "off")")
        } catch { fail("\(error)") }
    }

    func setVoiceGuidanceVolume(_ volume: Int8) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setVoiceGuidanceVolume(volume, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ VOICE_GUIDANCE_SET_PARAM volume \(volume)")
        } catch { fail("\(error)") }
    }

    func setSafeVolume(_ level: UInt8) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setSafeVolume(level, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ SAFE_LISTENING_SET_STATUS safe volume \(level)")
        } catch { fail("\(error)") }
    }

    func setHeadGesture(_ enabled: Bool) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setHeadGesture(enabled, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ SYSTEM_SET_STATUS head gesture \(enabled)")
            status.pendingWrite = true
        } catch { fail("\(error)") }
    }

    func powerOff() {
        guard let engine, isReady else { return }
        guard let bytes = engine.powerOff(nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ POWER_SET_STATUS user power off")
        } catch { fail("\(error)") }
    }

    func setSmartTalking(_ enabled: Bool) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setSmartTalking(enabled, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ SYSTEM_SET_PARAM speak-to-chat \(enabled)")
            status.pendingWrite = true
        } catch { fail("\(error)") }
    }

    func setSmartTalkingDetail(sensitivity: UInt8, modeOut: UInt8) {
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

    func setAutoStandby(_ enabled: Bool) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setAutoStandby(enabled, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ POWER_SET_PARAM auto standby \(enabled)")
            status.pendingWrite = true
        } catch { fail("\(error)") }
    }

    // MARK: Music hand-over

    func setMusicHandOver(_ enabled: Bool) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setMusicHandOver(enabled, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ PERI_SET_PARAM music hand-over \(enabled)")
            status.pendingWrite = true
        } catch { fail("\(error)") }
    }

    func connectPairedDevice(at index: Int) {
        guard let engine, isReady else { return }
        guard let bytes = engine.pairingConnect(index: index, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ PERI_SET_EX_PARAM connect #\(index)")
        } catch { fail("\(error)") }
    }

    func disconnectPairedDevice(at index: Int) {
        guard let engine, isReady else { return }
        guard let bytes = engine.pairingDisconnect(index: index, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ PERI_SET_EX_PARAM disconnect #\(index)")
        } catch { fail("\(error)") }
    }

    func setPairingMode(_ pairing: Bool) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setPairingMode(pairing, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ PERI_SET_STATUS pairing mode \(pairing)")
        } catch { fail("\(error)") }
    }

    // MARK: Listening mode

    func setListeningMode(_ mode: ListeningModeView) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setListeningMode(mode, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ AUDIO_SET_PARAM listening \(mode.label)")
            status.pendingWrite = true
        } catch { fail("\(error)") }
    }

    // MARK: Equalizer

    func setEqualizerPreset(_ preset: UInt8) {
        guard let engine, isReady else { return }
        // Fixed presets carry no band list; the device supplies its own curve.
        let isCustomCurve = preset == 0xA0 || (0xA1...0xA5).contains(preset)
        let bands = isCustomCurve ? (status.equalizer?.bands ?? []) : []
        guard let bytes = engine.setEqPreset(preset, bands: bands, nowMs: Self.nowMs()) else {
            return
        }
        do {
            try send(bytes, label: "→ EQEBB_SET_PARAM preset \(preset)")
            status.pendingWrite = true
        } catch { fail("\(error)") }
    }

    func setGeneralSetting(_ gs: GeneralSetting, enabled: Bool) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setGeneralSetting(gs.id, enabled, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ GENERAL_SETTING_SET_PARAM \(gs.title) \(enabled)")
            status.pendingWrite = true
        } catch { fail("\(error)") }
    }

    func setVoiceAssistant(_ value: UInt8) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setVoiceAssistant(value, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ SYSTEM_SET_PARAM voice assistant \(value)")
            status.pendingWrite = true
        } catch { fail("\(error)") }
    }

    func setEqualizerBands(_ bands: [UInt8]) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setEqPreset(0xA0, bands: bands, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ EQEBB_SET_PARAM band curve")
            status.pendingWrite = true
        } catch { fail("\(error)") }
    }

    func setClearBass(_ level: Int) {
        guard let engine, isReady else { return }
        guard let bytes = engine.setClearBass(level, nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ EQEBB_SET_PARAM Clear Bass \(level)")
            status.pendingWrite = true
        } catch { fail("\(error)") }
    }

    func setNoiseControl(enabled: Bool, ambient: Bool, level: Int) {
        guard let engine, isReady else { return }
        let mode: UInt8 = ambient ? 1 : 0
        guard let bytes = engine.setNoiseControl(
            enabled: enabled, mode: mode, ambient: 1, level: UInt8(clamping: level),
            nowMs: Self.nowMs()) else { return }
        do {
            try send(bytes, label: "→ NCASM_SET_PARAM")
            status.pendingWrite = true
        } catch { fail("\(error)") }
    }

    // MARK: Data path

    private func send(_ bytes: Data, label: String) throws {
        try link?.write(bytes)
        record(label)
    }

    private func handleInbound(_ data: Data) {
        guard let engine else { return }
        let followUp = engine.receive(data)
        publish()
        record("← \(data.count) B")
        if let followUp {
            try? link?.write(followUp)
        }
        if status.phase.isReady, handshakeDeadline != nil {
            handshakeDeadline = nil
            record("handshake complete · ready")
        }
    }

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard let engine else { return }
        let now = Self.nowMs()
        if let retry = engine.poll(nowMs: now) {
            try? link?.write(retry)
        }
        publish()
        if !status.phase.isReady, let deadline = handshakeDeadline, Date() > deadline {
            fail("The headphones did not answer. Check they are connected and not busy with another device.")
        }
    }

    private func publish() {
        guard let engine else { return }
        var next = HeadphoneStatus(snapshot: engine.snapshot())
        next.modelColor = engine.modelColor()
        if next.equalizer != nil { next.equalizer?.offReason = engine.eqErrorCode() }
        if next.voiceAssistant != nil {
            if let va = engine.voiceAssistant() { next.voiceAssistant = va }
        }
        if next.equalizer != nil {
            let presets = engine.eqPresets()
            if !presets.isEmpty {
                next.equalizer?.presets = presets
                if let match = presets.first(where: { $0.id == next.equalizer?.preset }) {
                    next.equalizer?.presetName = match.name
                }
            }
        }
        if next.pairingKnown {
            next.pairedDevices = engine.pairedDevices()
            next.pairingCapability = engine.pairingCapability()
            next.pairingEvent = engine.pairingEvent()
            next.pairingMode = engine.pairingMode()
        }
        if next != status { status = next }
    }

    private func fail(_ message: String) {
        lastError = message
        status.phase = .error
        record("error: \(message)")
        timer?.invalidate()
        timer = nil
    }

    private func record(_ line: String) {
        log.append(line)
        if log.count > 200 { log.removeFirst(log.count - 200) }
    }

    private static func nowMs() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1000)
    }
}
