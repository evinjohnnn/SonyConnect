import Foundation
// SwiftPM exposes the C shim as a module. Inside an Xcode target the same
// declarations arrive through a bridging header instead, so the import is
// conditional and this one file serves both build systems.
#if canImport(CSonyMDR)
import CSonyMDR
#endif

/// Thrown when the Rust core refuses an operation because the session is not in
/// a state where the operation is legal (e.g. writing before the handshake).
public struct EngineNotReady: Error, CustomStringConvertible {
    public let operation: String
    public var description: String { "engine refused \(operation): session not ready" }
}

/// A thin, safe Swift wrapper over the C ABI of the MDR engine.
///
/// The wrapper owns exactly one session handle. It never exposes the raw
/// pointer, never blocks, and never spawns threads — the caller decides when to
/// pump the run loop.
public final class Engine {
    private let handle: UnsafeMutableRawPointer

    public init?() {
        guard let h = mdr_session_new() else { return nil }
        handle = h
    }

    deinit {
        mdr_session_free(handle)
    }

    /// The engine version, for diagnostics.
    public static var version: String {
        String(cString: mdr_version())
    }

    /// Begin the handshake. Returns the bytes that must be written to the link.
    public func connect(nowMs: UInt64) throws -> Data {
        var buf = MdrBuffer()
        guard mdr_connect(handle, nowMs, &buf) == MDR_OK, let data = take(&buf) else {
            throw EngineNotReady(operation: "connect")
        }
        return data
    }

    /// Feed bytes received from the link. Returns follow-up bytes to write, if
    /// the engine produced any.
    @discardableResult
    public func receive(_ data: Data) -> Data? {
        var buf = MdrBuffer()
        let nowMs = UInt64(Date().timeIntervalSince1970 * 1000)
        let status = data.withUnsafeBytes { raw -> MdrStatus in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return MDR_NO_DATA }
            return mdr_receive(handle, base, raw.count, nowMs, &buf)
        }
        guard status == MDR_OK else { return nil }
        return take(&buf)
    }

    /// Request a battery refresh.
    ///
    /// Returns nil when the session is not ready, or when the request was
    /// queued behind an outstanding command — in that case the engine sends it
    /// as soon as that command is acknowledged.
    public func requestBattery(nowMs: UInt64) -> Data? {
        var buf = MdrBuffer()
        guard mdr_request_battery(handle, nowMs, &buf) == MDR_OK else { return nil }
        return take(&buf)
    }

    /// Write noise-control state.
    ///
    /// Returns nil when the session is not ready, or when the write was queued
    /// behind an outstanding command.
    public func setNoiseControl(
        enabled: Bool, mode: UInt8, ambient: UInt8, level: UInt8, nowMs: UInt64
    ) -> Data? {
        var buf = MdrBuffer()
        guard mdr_set_noise_control(handle, enabled, mode, ambient, level, nowMs, &buf) == MDR_OK else {
            return nil
        }
        return take(&buf)
    }

    /// Read the current state snapshot.
    /// Queue an arbitrary payload on a ready session (diagnostics only).
    public func sendRaw(_ bytes: Data, nowMs: UInt64) -> Data? {
        var buf = MdrBuffer()
        let status = bytes.withUnsafeBytes { raw -> MdrStatus in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return MDR_NO_DATA }
            return mdr_send_raw(handle, base, raw.count, nowMs, &buf)
        }
        guard status == MDR_OK else { return nil }
        return take(&buf)
    }

    /// Queue a raw payload for a specific table (1 or 2).
    public func sendRawTable(_ table: UInt8, _ bytes: Data, nowMs: UInt64) -> Data? {
        var buf = MdrBuffer()
        let status = bytes.withUnsafeBytes { raw -> MdrStatus in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return MDR_NO_DATA }
            return mdr_send_raw_table(handle, table, base, raw.count, nowMs, &buf)
        }
        guard status == MDR_OK else { return nil }
        return take(&buf)
    }

    public func snapshot() -> MdrSnapshot {
        var snap = MdrSnapshot()
        _ = mdr_snapshot(handle, &snap)
        return snap
    }

    /// Why the device has the equaliser off (`PresetEqErrorCodeType`).
    public func eqErrorCode() -> UInt8? {
        var code: Int32 = -1
        guard mdr_eq_error_code(handle, &code) == MDR_OK, code >= 0 else { return nil }
        return UInt8(truncatingIfNeeded: code)
    }

    /// `ModelColor` byte the device reported, or nil before it answers.
    public func modelColor() -> UInt8? {
        var series: Int32 = -1, color: Int32 = -1
        guard mdr_model_color(handle, &series, &color) == MDR_OK, color >= 0 else { return nil }
        return UInt8(truncatingIfNeeded: color)
    }

    // MARK: Equaliser

    /// The presets the device actually advertised, in device order.
    ///
    /// Read from the engine rather than hard-coded: a model may offer a subset,
    /// and a preset list guessed from the protocol would show options the
    /// headphones will reject.
    public func eqPresets() -> [EqualizerPreset] {
        var count = 0
        guard mdr_eq_preset_count(handle, &count) == MDR_OK, count > 0 else { return [] }
        var out: [EqualizerPreset] = []
        out.reserveCapacity(count)
        for index in 0..<count {
            var id: UInt8 = 0
            var name = [CChar](repeating: 0, count: 64)
            let status = name.withUnsafeMutableBufferPointer { buf -> MdrStatus in
                guard let base = buf.baseAddress else { return MDR_NO_DATA }
                return mdr_eq_preset_at(handle, index, &id, base, buf.count)
            }
            guard status == MDR_OK else { continue }
            let text = name.withUnsafeBufferPointer { buf in
                String(cString: buf.baseAddress!)
            }
            // The device often reports a preset without naming it. Fall back to
            // the product name for that wire id rather than showing "Preset 48".
            let label = text.isEmpty ? HeadphoneStatus.presetName(id) : text
            out.append(EqualizerPreset(id: id, name: label))
        }
        return out
    }

    /// Choose a preset. `bands` may be empty to keep the preset's own curve.
    public func setEqPreset(_ preset: UInt8, bands: [UInt8], nowMs: UInt64) -> Data? {
        var buf = MdrBuffer()
        let status: MdrStatus = bands.withUnsafeBufferPointer { raw in
            mdr_eq_set_preset(handle, preset, raw.baseAddress, raw.count, nowMs, &buf)
        }
        guard status == MDR_OK else { return nil }
        return take(&buf)
    }

    /// Table-1 functions the device advertises as supported, by name.
    public func supportedFunctions() -> [String] {
        supportedNames(count: mdr_supported_count, at: mdr_supported_at)
    }

    /// Table-2 functions the device advertises, named with the table-2 enum
    /// (the same byte means a different function on each table).
    public func supportedFunctionsTable2() -> [String] {
        supportedNames(count: mdr_supported_count_table2, at: mdr_supported_at_table2)
    }

    private func supportedNames(
        count countFn: (UnsafeMutableRawPointer?, UnsafeMutablePointer<Int>?) -> MdrStatus,
        at atFn: (UnsafeMutableRawPointer?, Int, UnsafeMutablePointer<UInt8>?,
                  UnsafeMutablePointer<CChar>?, Int) -> MdrStatus
    ) -> [String] {
        var count = 0
        guard countFn(handle, &count) == MDR_OK, count > 0 else { return [] }
        var out: [String] = []
        for index in 0..<count {
            var value: UInt8 = 0
            var name = [CChar](repeating: 0, count: 128)
            let status = name.withUnsafeMutableBufferPointer { buf -> MdrStatus in
                guard let base = buf.baseAddress else { return MDR_NO_DATA }
                return atFn(handle, index, &value, base, buf.count)
            }
            guard status == MDR_OK else { continue }
            out.append(name.withUnsafeBufferPointer { String(cString: $0.baseAddress!) })
        }
        return out
    }

    /// Paired Classic Bluetooth devices, in the order the headset reports them.
    public func pairedDevices() -> [PairedDeviceView] {
        var count = 0
        guard mdr_paired_count(handle, &count) == MDR_OK, count > 0 else { return [] }
        var out: [PairedDeviceView] = []
        out.reserveCapacity(count)
        for index in 0..<count {
            var connected: UInt8 = 0
            var codKnown: UInt8 = 0
            var cod: UInt32 = 0
            var address = [CChar](repeating: 0, count: 18)
            var name = [CChar](repeating: 0, count: 64)
            let status = address.withUnsafeMutableBufferPointer { addressBuf -> MdrStatus in
                name.withUnsafeMutableBufferPointer { nameBuf -> MdrStatus in
                    mdr_paired_at(
                        handle,
                        index,
                        &connected,
                        &codKnown,
                        &cod,
                        addressBuf.baseAddress,
                        addressBuf.count,
                        nameBuf.baseAddress,
                        nameBuf.count
                    )
                }
            }
            guard status == MDR_OK else { continue }
            let addressText = address.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
            let nameText = name.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
            out.append(
                PairedDeviceView(
                    address: addressText,
                    name: nameText.isEmpty ? addressText : nameText,
                    connected: connected == 1,
                    classOfDevice: codKnown == 1 ? cod : nil
                )
            )
        }
        return out
    }

    /// Advertised pairing limits, or nil when the device has not reported them.
    public func pairingCapability() -> PairingCapabilityView? {
        var maxPaired: UInt8 = 0
        var maxConnected: UInt8 = 0
        var fileTransfer: UInt8 = 0
        guard mdr_pairing_capability(handle, &maxPaired, &maxConnected, &fileTransfer) == MDR_OK
        else {
            return nil
        }
        return PairingCapabilityView(
            maxPaired: maxPaired,
            maxConnected: maxConnected,
            fileTransfer: fileTransfer
        )
    }

    /// Connect the headset to a paired device by its index in the list.
    public func pairingConnect(index: Int, nowMs: UInt64) -> Data? {
        var buf = MdrBuffer()
        guard mdr_pairing_connect(handle, index, nowMs, &buf) == MDR_OK else { return nil }
        return take(&buf)
    }

    /// Disconnect a paired device by its index in the list.
    public func pairingDisconnect(index: Int, nowMs: UInt64) -> Data? {
        var buf = MdrBuffer()
        guard mdr_pairing_disconnect(handle, index, nowMs, &buf) == MDR_OK else { return nil }
        return take(&buf)
    }

    /// Enter or leave Bluetooth inquiry-scan (pairing) mode.
    public func setPairingMode(_ pairing: Bool, nowMs: UInt64) -> Data? {
        var buf = MdrBuffer()
        guard mdr_pairing_set_mode(handle, pairing, nowMs, &buf) == MDR_OK else { return nil }
        return take(&buf)
    }

    /// Last connect/disconnect result pushed by the headset.
    public func pairingEvent() -> PairingEventView? {
        var action: UInt8 = 0
        var result: UInt8 = 0
        var address = [CChar](repeating: 0, count: 18)
        let status = address.withUnsafeMutableBufferPointer { buf -> MdrStatus in
            mdr_pairing_event(handle, &action, &result, buf.baseAddress, buf.count)
        }
        guard status == MDR_OK else { return nil }
        let text = address.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        return PairingEventView(action: action, result: result, address: text)
    }

    /// Current Bluetooth mode reported by the headset.
    public func pairingMode() -> PairingModeView? {
        var mode: UInt8 = 0
        var enabled: UInt8 = 0
        guard mdr_pairing_mode(handle, &mode, &enabled) == MDR_OK else { return nil }
        return PairingModeView(mode: mode, enabled: enabled == 1)
    }

    /// Voice-assistant state, or nil when the device has not reported one.
    public func voiceAssistant() -> VoiceAssistantView? {
        var current: UInt8 = 0
        var count = 0
        guard mdr_va_state(handle, &current, &count) == MDR_OK else { return nil }
        var options: [(UInt8, String)] = []
        for index in 0..<count {
            var value: UInt8 = 0
            var name = [CChar](repeating: 0, count: 64)
            let status = name.withUnsafeMutableBufferPointer { buf -> MdrStatus in
                guard let base = buf.baseAddress else { return MDR_NO_DATA }
                return mdr_va_at(handle, index, &value, base, buf.count)
            }
            guard status == MDR_OK else { continue }
            let text = name.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
            options.append((value, text))
        }
        return VoiceAssistantView(current: current, options: options)
    }

    /// Choose the voice assistant.
    public func setVoiceAssistant(_ value: UInt8, nowMs: UInt64) -> Data? {
        var buf = MdrBuffer()
        guard mdr_set_voice_assistant(handle, value, nowMs, &buf) == MDR_OK else { return nil }
        return take(&buf)
    }

    /// The general-setting slots the device described, in device order.
    public func generalSettings() -> [GeneralSetting] {
        var count = 0
        guard mdr_gs_count(handle, &count) == MDR_OK, count > 0 else { return [] }
        var out: [GeneralSetting] = []
        for index in 0..<count {
            var gsType: UInt8 = 0
            var known: UInt8 = 0
            var value: UInt8 = 0
            var title = [CChar](repeating: 0, count: 64)
            var detail = [CChar](repeating: 0, count: 128)
            let status = title.withUnsafeMutableBufferPointer { tb in
                detail.withUnsafeMutableBufferPointer { db -> MdrStatus in
                    guard let t = tb.baseAddress, let d = db.baseAddress else { return MDR_NO_DATA }
                    return mdr_gs_at(handle, index, &gsType, &known, &value,
                                     t, tb.count, d, db.count)
                }
            }
            guard status == MDR_OK else { continue }
            let label = title.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
            let sub = detail.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
            out.append(GeneralSetting(
                id: gsType,
                title: label.isEmpty ? "Setting \(gsType)" : label,
                detail: sub,
                value: known == 1 ? value == 1 : nil))
        }
        return out
    }

    /// Set one general-setting slot.
    public func setGeneralSetting(_ gsType: UInt8, _ enabled: Bool, nowMs: UInt64) -> Data? {
        var buf = MdrBuffer()
        guard mdr_set_gs_setting(handle, gsType, enabled, nowMs, &buf) == MDR_OK else { return nil }
        return take(&buf)
    }

    /// Toggle noise adaptation.
    public func setNoiseAdaptation(_ enabled: Bool, nowMs: UInt64) -> Data? {
        var buf = MdrBuffer()
        guard mdr_set_nc_adaptation(handle, enabled, nowMs, &buf) == MDR_OK else { return nil }
        return take(&buf)
    }

    /// Toggle audio upscaling.
    public func setUpscaling(_ enabled: Bool, nowMs: UInt64) -> Data? {
        var buf = MdrBuffer()
        guard mdr_set_upscaling(handle, enabled, nowMs, &buf) == MDR_OK else { return nil }
        return take(&buf)
    }

    /// Commands still queued or in flight.
    public var pendingCount: Int { Int(mdr_pending_count(handle)) }

    /// The engine's complete state as JSON, for the protocol inspector.
    public func stateJSON() -> String? {
        let cap = 16_384
        var buf = [CChar](repeating: 0, count: cap)
        let written = buf.withUnsafeMutableBufferPointer { base in
            mdr_state_json(handle, base.baseAddress, cap)
        }
        guard written > 0 else { return nil }
        return String(cString: buf)
    }

    /// Send a playback control action (play, pause, next, previous, stop).
    public func setPlaybackControl(_ control: UInt8, nowMs: UInt64) -> Data? {
        var buf = MdrBuffer()
        guard mdr_playback_control(handle, control, nowMs, &buf) == MDR_OK else { return nil }
        return take(&buf)
    }

    /// Set the music volume; the engine clamps to the advertised steps.
    public func setMusicVolume(_ volume: Int, nowMs: UInt64) -> Data? {
        var buf = MdrBuffer()
        guard mdr_set_music_volume(handle, UInt8(clamping: volume), nowMs, &buf) == MDR_OK else {
            return nil
        }
        return take(&buf)
    }

    /// Set the call volume; the engine clamps to the advertised steps.
    public func setCallVolume(_ volume: Int, nowMs: UInt64) -> Data? {
        var buf = MdrBuffer()
        guard mdr_set_call_volume(handle, UInt8(clamping: volume), nowMs, &buf) == MDR_OK else {
            return nil
        }
        return take(&buf)
    }

    /// Toggle playback control by wearing/removing the headphones.
    public func setControlByWearing(_ enabled: Bool, nowMs: UInt64) -> Data? {
        var buf = MdrBuffer()
        guard mdr_set_control_by_wearing(handle, enabled, nowMs, &buf) == MDR_OK else { return nil }
        return take(&buf)
    }

    /// Set one general-setting boolean slot.
    public func setGeneralSetting(_ gsType: UInt8, on: Bool, nowMs: UInt64) -> Data? {
        var buf = MdrBuffer()
        guard mdr_set_gs_boolean(handle, gsType, on, nowMs, &buf) == MDR_OK else { return nil }
        return take(&buf)
    }

    /// Start or stop adaptive control.
    public func setAdaptiveControl(_ start: Bool, nowMs: UInt64) -> Data? {
        var buf = MdrBuffer()
        guard mdr_set_adaptive_control(handle, start, nowMs, &buf) == MDR_OK else { return nil }
        return take(&buf)
    }

    /// Replace the Quick Access function list.
    public func setQuickAccessFunctions(_ functions: [UInt8], nowMs: UInt64) -> Data? {
        var buf = MdrBuffer()
        let status = functions.withUnsafeBufferPointer { ptr -> MdrStatus in
            guard let base = ptr.baseAddress else { return MDR_NO_DATA }
            return mdr_set_quick_access_functions(handle, base, ptr.count, nowMs, &buf)
        }
        guard status == MDR_OK else { return nil }
        return take(&buf)
    }


    /// Toggle mic on/off by headphone operation.
    public func setMicOnOff(_ enabled: Bool, nowMs: UInt64) -> Data? {
        var buf = MdrBuffer()
        guard mdr_set_mic_on_off(handle, enabled, nowMs, &buf) == MDR_OK else { return nil }
        return take(&buf)
    }

    /// Toggle Sony Voice Assistant.
    public func setSonyVoiceAssistant(_ enabled: Bool, nowMs: UInt64) -> Data? {
        var buf = MdrBuffer()
        guard mdr_set_sony_voice_assistant(handle, enabled, nowMs, &buf) == MDR_OK else { return nil }
        return take(&buf)
    }

    /// Toggle voice guidance.
    public func setVoiceGuidance(_ enabled: Bool, nowMs: UInt64) -> Data? {
        var buf = MdrBuffer()
        guard mdr_set_voice_guidance(handle, enabled, nowMs, &buf) == MDR_OK else { return nil }
        return take(&buf)
    }

    /// Set the voice guidance volume.
    public func setVoiceGuidanceVolume(_ volume: Int8, nowMs: UInt64) -> Data? {
        var buf = MdrBuffer()
        guard mdr_set_voice_guidance_volume(handle, volume, nowMs, &buf) == MDR_OK else { return nil }
        return take(&buf)
    }

    /// Start or finish head gesture training.
    public func setHeadGestureTraining(_ start: Bool, nowMs: UInt64) -> Data? {
        var buf = MdrBuffer()
        guard mdr_set_head_gesture_training(handle, start, nowMs, &buf) == MDR_OK else { return nil }
        return take(&buf)
    }

    /// Set the safe-volume WHO standard level.
    public func setSafeVolume(_ level: UInt8, nowMs: UInt64) -> Data? {
        var buf = MdrBuffer()
        guard mdr_set_safe_volume(handle, level, nowMs, &buf) == MDR_OK else { return nil }
        return take(&buf)
    }

    /// Toggle head gesture control.
    public func setHeadGesture(_ enabled: Bool, nowMs: UInt64) -> Data? {
        var buf = MdrBuffer()
        guard mdr_set_head_gesture(handle, enabled, nowMs, &buf) == MDR_OK else { return nil }
        return take(&buf)
    }

    /// Ask the headphones to power off.
    public func powerOff(nowMs: UInt64) -> Data? {
        var buf = MdrBuffer()
        guard mdr_power_off(handle, nowMs, &buf) == MDR_OK else { return nil }
        return take(&buf)
    }

    /// Toggle Speak-to-Chat.
    public func setSmartTalking(_ enabled: Bool, nowMs: UInt64) -> Data? {
        var buf = MdrBuffer()
        guard mdr_set_smart_talking(handle, enabled, nowMs, &buf) == MDR_OK else { return nil }
        return take(&buf)
    }

    /// Set Speak-to-Chat sensitivity and auto-off time.
    public func setSmartTalkingDetail(
        sensitivity: UInt8,
        modeOut: UInt8,
        nowMs: UInt64
    ) -> Data? {
        var buf = MdrBuffer()
        guard mdr_set_smart_talking_detail(handle, sensitivity, modeOut, nowMs, &buf) == MDR_OK
        else { return nil }
        return take(&buf)
    }

    /// Toggle auto standby.
    public func setAutoStandby(_ enabled: Bool, nowMs: UInt64) -> Data? {
        var buf = MdrBuffer()
        guard mdr_set_auto_standby(handle, enabled, nowMs, &buf) == MDR_OK else {
            return nil
        }
        return take(&buf)
    }

    /// Toggle table-2 music hand-over.
    public func setMusicHandOver(_ enabled: Bool, nowMs: UInt64) -> Data? {
        var buf = MdrBuffer()
        guard mdr_set_music_hand_over(handle, enabled, nowMs, &buf) == MDR_OK else {
            return nil
        }
        return take(&buf)
    }

    /// Switch the listening mode.
    public func setListeningMode(_ mode: ListeningModeView, nowMs: UInt64) -> Data? {
        var buf = MdrBuffer()
        guard mdr_set_listening_mode(handle, mode.rawValue, nowMs, &buf) == MDR_OK else {
            return nil
        }
        return take(&buf)
    }

    /// Set the wearing-detection auto-power-off element.
    public func setAutoPowerOffWearing(current: UInt8, last: UInt8, nowMs: UInt64) -> Data? {
        var buf = MdrBuffer()
        guard mdr_set_auto_power_off_wearing(handle, current, last, nowMs, &buf) == MDR_OK else {
            return nil
        }
        return take(&buf)
    }

    /// Set Clear Bass. The engine clamps to the range the device reported.
    public func setClearBass(_ level: Int, nowMs: UInt64) -> Data? {
        var buf = MdrBuffer()
        guard mdr_eq_set_clear_bass(handle, Int8(clamping: level), nowMs, &buf) == MDR_OK else {
            return nil
        }
        return take(&buf)
    }

    /// Advance the retry clock. Returns bytes to resend when a command timed out
    /// and policy still allows a retry.
    public func poll(nowMs: UInt64) -> Data? {
        var buf = MdrBuffer()
        let status = mdr_poll(handle, nowMs, &buf)
        guard status == MDR_OK else { return nil }
        return take(&buf)
    }

    private func take(_ buf: inout MdrBuffer) -> Data? {
        defer { var copy = buf; mdr_bytes_free(&copy) }
        guard let base = buf.data, buf.len > 0 else { return nil }
        return Data(bytes: base, count: buf.len)
    }
}

// MARK: - Presentation helpers

/// Named states, used by both the CLI and the app so the two never disagree.
public enum SessionPhase: UInt8 {
    case disconnected = 0, connecting, handshaking, discoveringCapabilities,
         syncing, ready, reconnecting, suspended, unsupported, error

    public init(code: UInt8) {
        self = SessionPhase(rawValue: code) ?? .error
    }

    public var label: String {
        switch self {
        case .disconnected: return "Not connected"
        case .connecting: return "Connecting"
        case .handshaking: return "Handshaking"
        case .discoveringCapabilities: return "Reading capabilities"
        case .syncing: return "Syncing settings"
        case .ready: return "Ready"
        case .reconnecting: return "Reconnecting"
        case .suspended: return "Suspended"
        case .unsupported: return "Unsupported device"
        case .error: return "Error"
        }
    }

    public var isReady: Bool { self == .ready }
}

public enum ChargingState: Int16 {
    case notCharging = 0, charging = 1, unknown = 2, charged = 3, absent = -1

    public init(code: Int16) {
        self = ChargingState(rawValue: code) ?? .unknown
    }

    public var label: String {
        switch self {
        case .charging: return "Charging"
        case .charged: return "Charged"
        case .notCharging: return "On battery"
        case .unknown: return "Unknown"
        case .absent: return ""
        }
    }
}

/// One equaliser preset the device reported.
public struct EqualizerPreset: Identifiable, Equatable {
    public let id: UInt8
    public let name: String
}

/// Playback controller state.
/// Listening mode as the protocol reports it.
///
/// `LISTENING_OPTION` on the wire is only a shortcut-availability flag; the
/// mode is the combination of the BGM and Cinema settings.
public enum ListeningModeView: UInt8, CaseIterable, Equatable {
    case standard = 0
    case bgm = 1
    case cinema = 2

    public var label: String {
        switch self {
        case .standard: return "Standard"
        case .bgm: return "BGM"
        case .cinema: return "Cinema"
        }
    }
}

/// Music volume as reported by the playback controller.
public struct MusicVolume: Equatable {
    public let value: Int
    public let max: Int
}

/// Speak-to-Chat state.
public struct SmartTalkingView: Equatable {
    public let enabled: Bool
    public let effect: UInt8
    public let sensitivity: UInt8
    public let modeOut: UInt8

    public var sensitivityLabel: String {
        switch sensitivity {
        case 0: return "Auto"
        case 1: return "High"
        case 2: return "Low"
        default: return "Unknown"
        }
    }

    public var modeOutLabel: String {
        switch modeOut {
        case 0: return "Fast"
        case 1: return "Medium"
        case 2: return "Slow"
        case 3: return "None"
        default: return "Unknown"
        }
    }
}

public struct PlaybackState: Equatable {
    public let enabled: Bool
    public let state: UInt8
    public let source: UInt8

    public var stateLabel: String {
        switch state {
        case 0: return "Unsettled"
        case 1: return "Playing"
        case 2: return "Paused"
        case 3: return "Stopped"
        default: return "Unknown"
        }
    }

    public var sourceLabel: String {
        switch source {
        case 0: return "Music"
        case 1: return "Call"
        default: return "Unknown"
        }
    }

    public var label: String {
        enabled ? "\(stateLabel) (\(sourceLabel))" : "Disabled"
    }
}

/// Auto power off with wearing detection.
public struct AutoPowerOffWearing: Equatable {
    public let current: UInt8
    public let last: UInt8
    public let enabled: Bool?

    public var currentLabel: String { Self.label(current) }
    public var lastLabel: String { Self.label(last) }

    public static func label(_ value: UInt8) -> String {
        switch value {
        case 0: return "After 5 min"
        case 1: return "After 30 min"
        case 2: return "After 60 min"
        case 3: return "After 180 min"
        case 4: return "After 15 min"
        case 0x10: return "When taken off"
        case 0x11: return "Off"
        default: return "Unknown (\(value))"
        }
    }
}

/// Classic / LE audio connection mode flags.
public struct ConnectionMode: Equatable {
    public let classic: Bool
    public let le: Bool

    public var label: String {
        switch (classic, le) {
        case (true, true): return "Classic and LE audio"
        case (true, false): return "Classic audio"
        case (false, true): return "LE audio"
        default: return "Unknown"
        }
    }
}

/// A paired Classic Bluetooth device reported by the headset.
public struct PairedDeviceView: Identifiable, Equatable {
    public let address: String
    public let name: String
    public let connected: Bool
    public let classOfDevice: UInt32?

    public var id: String { address }
}

/// Advertised pairing limits.
public struct PairingCapabilityView: Equatable {
    public let maxPaired: UInt8
    public let maxConnected: UInt8
    public let fileTransfer: UInt8
}

/// Paired-device list plus the trailing playback index.
public struct PairingView: Equatable {
    public var devices: [PairedDeviceView] = []
    public var capability: PairingCapabilityView? = nil
    public var playbackDevice: UInt8? = nil
}

/// Current Bluetooth mode reported by the headset.
public struct PairingModeView: Equatable {
    public let mode: UInt8
    public let enabled: Bool

    public var label: String {
        switch mode {
        case 0x01: return enabled ? "Pairing mode" : "Pairing mode (inactive)"
        default: return enabled ? "Normal" : "Normal (inactive)"
        }
    }
}

/// Last connect/disconnect result from the headset.
public struct PairingEventView: Equatable {
    public let action: UInt8
    public let result: UInt8
    public let address: String

    public var label: String {
        switch result {
        case 0x00: return "Disconnected"
        case 0x01: return "Disconnect failed"
        case 0x02: return "Disconnecting"
        case 0x03: return "Disconnect busy"
        case 0x10: return "Connected"
        case 0x11: return "Connect failed"
        case 0x12: return "Connecting"
        case 0x13: return "Connect busy"
        case 0x20: return "Unpaired"
        case 0x21: return "Unpair failed"
        case 0x22: return "Unpairing"
        case 0x23: return "Unpair busy"
        default: return "Unknown result"
        }
    }
}

/// One general-setting slot the device described.
public struct GeneralSetting: Identifiable, Equatable {
    public let id: UInt8          // wire type
    public let title: String
    public let detail: String
    public let value: Bool?       // nil when not read yet
}

/// Voice-assistant assignment and the assistants the device supports.
public struct VoiceAssistantView: Equatable {
    public let current: UInt8
    public let options: [(UInt8, String)]

    public static func == (a: VoiceAssistantView, b: VoiceAssistantView) -> Bool {
        a.current == b.current && a.options.map(\.0) == b.options.map(\.0)
    }
}

/// Equaliser state as the UI presents it.
public struct EqualizerView: Equatable {
    public var isOn: Bool = true
    /// `PresetEqErrorCodeType` the device gave for turning the equaliser off:
    /// 0 calling, 1 demo mode, 2 listening mode.
    public var offReason: UInt8? = nil
    /// Current preset id.
    public var preset: UInt8 = 0
    /// Product name of the current preset, when the device named it.
    public var presetName: String = ""
    /// Per-band step values, in device order.
    public var bands: [UInt8] = []
    /// Number of bands the device advertises.
    public var bandCount: Int = 0
    /// Number of discrete steps per band.
    public var bandStep: UInt8 = 0
    /// Clear Bass level and its allowed range.
    public var clearBass: Int = 0
    public var clearBassRange: ClosedRange<Int> = -10...10
    /// Presets the device offers.
    public var presets: [EqualizerPreset] = []

    public init() {}
}

/// A decoded, UI-ready view of the engine snapshot.
/// Head gesture training mode as reported by the device.
public struct HeadGestureTrainingState: Equatable {
    public var inTest: Bool
    public var enabled: Bool
}

public struct HeadphoneStatus: Equatable {
    public var phase: SessionPhase = .disconnected
    public var batteryPercent: Int? = nil
    public var charging: ChargingState = .absent
    public var noiseControl: NoiseControlView = .unknown
    public var pendingWrite: Bool = false
    public var revision: UInt64 = 0
    /// Model name the device reported, if it has told us.
    public var model: String = ""
    /// Firmware version the device reported.
    public var firmware: String = ""
    /// `ModelColor` byte from `SERIES_AND_COLOR_INFO`, when reported.
    public var modelColor: UInt8? = nil
    /// Negotiated protocol version.
    public var protocolVersion: UInt32 = 0
    /// Equaliser, or nil when the device has not reported one.
    public var equalizer: EqualizerView? = nil
    /// Audio upscaling, when the device reports it.
    public var upscaling: Bool? = nil
    /// Noise adaptation (auto ambient), when reported.
    public var noiseAdaptation: Bool? = nil
    /// Device-named general settings (sidetone, multipoint, touch panel…).
    public var generalSettings: [GeneralSetting] = []
    /// Voice assistant, when the device reports one.
    public var voiceAssistant: VoiceAssistantView? = nil
    /// Table-1 functions the device advertises, by name.
    public var supportedFunctions: [String] = []
    /// Table-2 functions the device advertises, by name.
    public var supportedFunctionsTable2: [String] = []
    /// Auto power off (read-only on this protocol).
    public var autoPowerOff: Bool? = nil
    /// Connection mode flags: classic audio, LE audio.
    public var connectionMode: ConnectionMode? = nil
    /// Wearing detection, as reported (read-only on this protocol).
    public var wearingStatus: Bool? = nil
    /// Whether the detector itself is enabled.
    public var wearingDetectionEnabled: Bool? = nil
    /// Auto power off with wearing detection, as reported.
    public var autoPowerOffWearing: AutoPowerOffWearing? = nil
    /// Playback controller state.
    public var playback: PlaybackState? = nil
    /// Table-2 music hand-over setting.
    public var musicHandOver: Bool? = nil
    /// USB submersion status (`true` = submerged).
    public var usbSubmersion: Bool? = nil
    /// Negotiated Bluetooth codec, e.g. "AAC".
    public var codec: String = ""
    /// Listening mode, once BGM and Cinema have both been read.
    public var listening: ListeningModeView? = nil
    /// Music volume, once the step count and value have both been read.
    public var volume: MusicVolume? = nil
    /// Call volume, same gating.
    public var callVolume: MusicVolume? = nil
    /// Auto volume with limitation, read-only.
    public var autoVolume: Bool? = nil
    /// Auto standby candidate (15 minutes).
    public var autoStandby: Bool? = nil
    /// Auto-standby on/off setting.
    public var autoStandbyEnabled: Bool? = nil
    /// Speak-to-Chat state.
    public var smartTalking: SmartTalkingView? = nil
    /// Head gesture control.
    public var headGesture: Bool? = nil
    /// Head gesture training state.
    public var headGestureTraining: HeadGestureTrainingState? = nil
    /// Playback control by wearing/removing the headphones.
    public var controlByWearing: Bool? = nil
    /// Whether control-by-wearing is available.
    public var controlByWearingAvailable: Bool? = nil
    /// Mic on/off by headphone operation.
    public var micOnOff: Bool? = nil
    /// Sony Voice Assistant on/off.
    public var sonyVoiceAssistant: Bool? = nil
    /// Sony Voice Assistant language byte.
    public var sonyVoiceAssistantLanguage: UInt8? = nil
    /// Voice guidance on/off.
    public var voiceGuidance: Bool? = nil
    /// Voice guidance volume.
    public var voiceGuidanceVolume: Int? = nil
    /// Last gesture detected during training: 0 nod, 1 swing.
    public var headGestureAction: UInt8? = nil
    /// Safe-volume WHO level (0 normal, 1 sensitive).
    public var safeVolume: UInt8? = nil
    /// Quick Access function ids.
    public var quickAccess: [UInt8]? = nil
    /// Adaptive control started.
    public var adaptiveControlStarted: Bool? = nil
    /// Paired Classic Bluetooth devices.
    public var pairedDevices: [PairedDeviceView] = []
    /// Whether the device has reported its paired-device list.
    public var pairingKnown: Bool = false
    /// Advertised pairing limits, when read.
    public var pairingCapability: PairingCapabilityView? = nil
    /// Last connect/disconnect result.
    public var pairingEvent: PairingEventView? = nil
    /// Current Bluetooth mode.
    public var pairingMode: PairingModeView? = nil
    /// Trailing "playback right device" index from the pairing list.
    public var pairingPlaybackDevice: UInt8? = nil

    public init() {}

    public init(snapshot s: MdrSnapshot) {
        phase = SessionPhase(code: s.state)
        if s.battery_level >= 0 { batteryPercent = Int(s.battery_level) }
        charging = s.battery_level >= 0 ? ChargingState(code: s.battery_charging) : .absent
        // Only claim a noise-control state once the device has actually sent
        // one; otherwise the UI would show a confident "off" that is really
        // "unknown".
        if s.nc_known == 1 {
            noiseControl = NoiseControlView(
                enabled: s.nc_enabled == 1,
                mode: s.nc_mode,
                ambientMode: s.ambient_mode,
                ambientLevel: Int(max(0, s.ambient_level)))
        } else {
            noiseControl = .unknown
        }
        pendingWrite = s.pending_write == 1
        revision = s.revision
        model = Self.string(from: s.model)
        firmware = Self.string(from: s.firmware)
        protocolVersion = s.protocol_version
        if s.eq_known == 1 {
            var eq = EqualizerView()
            eq.isOn = s.eq_enabled == 1
            eq.preset = s.eq_preset
            // Fixed-size C arrays import as tuples, so read the bytes generically.
            let bandBytes = withUnsafeBytes(of: s.eq_bands) { Array($0) }
            let n = min(Int(s.eq_band_len), bandBytes.count)
            eq.bands = Array(bandBytes.prefix(n))
            eq.bandCount = Int(s.eq_band_count)
            eq.bandStep = s.eq_band_step
            eq.clearBass = Int(s.clear_bass)
            let lo = Int(s.clear_bass_min)
            let hi = Int(s.clear_bass_max)
            eq.clearBassRange = lo <= hi ? lo...hi : -10...10
            eq.presetName = HeadphoneStatus.presetName(eq.preset)
            equalizer = eq
        } else {
            equalizer = nil
        }
        upscaling = s.upscaling_known == 1 ? s.upscaling_enabled == 1 : nil
        noiseAdaptation = s.nc_known == 1 ? s.nc_adaptation == 1 : nil
        codec = HeadphoneStatus.string(from: s.codec)
        autoPowerOff = s.apo_known == 1 ? s.apo_enabled == 1 : nil
        connectionMode = s.conn_known == 1
            ? ConnectionMode(classic: s.conn_classic == 1, le: s.conn_le == 1)
            : nil
        wearingStatus = s.wear_known == 1 ? s.wear_worn == 1 : nil
        wearingDetectionEnabled = s.wear_known == 1 ? s.wear_detection_enabled == 1 : nil
        musicHandOver = s.mho_known == 1 ? s.mho_enabled == 1 : nil
        usbSubmersion = s.usb_known == 1 ? s.usb_submerged == 1 : nil
        playback = s.play_known == 1
            ? PlaybackState(
                enabled: s.play_enabled == 1,
                state: s.play_state,
                source: s.play_source
              )
            : nil
        autoPowerOffWearing = s.apow_known == 1
            ? AutoPowerOffWearing(
                current: s.apow_current,
                last: s.apow_last,
                enabled: s.apow_enabled_known == 1 ? s.apow_enabled == 1 : nil
              )
            : nil
        listening = s.listen_known == 1 ? ListeningModeView(rawValue: s.listen_mode) : nil
        volume = s.volume_known == 1
            ? MusicVolume(value: Int(s.volume), max: Int(s.volume_steps))
            : nil
        callVolume = s.call_volume_known == 1
            ? MusicVolume(value: Int(s.call_volume), max: Int(s.call_volume_steps))
            : nil
        autoVolume = s.auto_volume_known == 1 ? s.auto_volume_enabled == 1 : nil
        autoStandby = s.auto_standby_known == 1 ? s.auto_standby_available == 1 : nil
        autoStandbyEnabled = s.auto_standby_setting_known == 1
            ? s.auto_standby_setting == 1
            : nil
        smartTalking = s.st_known == 1
            ? SmartTalkingView(
                enabled: s.st_enabled == 1,
                effect: s.st_effect,
                sensitivity: s.st_sensitivity,
                modeOut: s.st_mode_out
              )
            : nil
        headGesture = s.hg_known == 1 ? s.hg_enabled == 1 : nil
        safeVolume = s.safe_volume_known == 1 ? s.safe_volume_level : nil
        adaptiveControlStarted = s.ac_known == 1 ? s.ac_started == 1 : nil
        pairingKnown = s.pair_known == 1
        quickAccess = s.qa_known == 1
            ? Array([s.qa0, s.qa1].prefix(Int(s.qa_count)))
            : nil
        controlByWearing = s.cbw_known == 1 ? s.cbw_enabled == 1 : nil
        micOnOff = s.mic_known == 1 ? s.mic_enabled == 1 : nil
        sonyVoiceAssistant = s.sva_known == 1 ? s.sva_enabled == 1 : nil
        sonyVoiceAssistantLanguage = s.sval_known == 1 ? s.sval_language : nil
        voiceGuidance = s.vg_known == 1 ? s.vg_enabled == 1 : nil
        voiceGuidanceVolume = s.vgv_known == 1 ? Int(s.vgv_volume) : nil
        headGestureTraining = s.hgt_known == 1
            ? HeadGestureTrainingState(inTest: s.hgt_in_test == 0, enabled: s.hgt_enabled == 1)
            : nil
        headGestureAction = s.hga_known == 1 ? s.hga_action : nil
    }

    /// Fallback name for a preset id, used until the device's own name arrives.
    ///
    /// Deliberately conservative: unknown ids become "Preset N" rather than a
    /// wrong product name.
    static func presetName(_ id: UInt8) -> String {
        switch id {
        case 0x00: return "Off"
        case 0x01: return "Rock"
        case 0x02: return "Pop"
        case 0x03: return "Jazz"
        case 0x04: return "Dance"
        case 0x05: return "EDM"
        case 0x06: return "R&B / Hip-Hop"
        case 0x07: return "Acoustic"
        case 0x10: return "Bright"
        case 0x11: return "Excited"
        case 0x12: return "Mellow"
        case 0x13: return "Relaxed"
        case 0x14: return "Vocal"
        case 0x15: return "Treble Boost"
        case 0x16: return "Bass Boost"
        case 0x17: return "Speech"
        case 0x20: return "Gaming"
        case 0x21: return "FPS 1"
        case 0x22: return "FPS 2"
        case 0x23: return "FPS 3"
        case 0x30: return "Heavy"
        case 0x31: return "Clear"
        case 0x32: return "Hard"
        case 0x33: return "Soft"
        case 0xA0: return "Custom"
        case 0xA1: return "User 1"
        case 0xA2: return "User 2"
        case 0xA3: return "User 3"
        case 0xA4: return "User 4"
        case 0xA5: return "User 5"
        case 0xB0...0xBB: return "Artist preset"
        default: return "Preset \(id)"
        }
    }

    /// Reads a NUL-terminated C string out of a fixed-size char array.
    ///
    /// Swift imports `char model[48]` as a tuple, so the bytes are read
    /// generically rather than element by element.
    private static func string<T>(from tuple: T) -> String {
        withUnsafeBytes(of: tuple) { raw in
            let chars = raw.bindMemory(to: CChar.self)
            guard let base = chars.baseAddress else { return "" }
            return String(cString: base)
        }
    }
}

/// Noise-control state as the UI presents it.
public enum NoiseControlView: Equatable {
    case unknown
    case off
    case noiseCancelling
    case ambient(voice: Bool, level: Int)

    init(enabled: Bool, mode: Int16, ambientMode: Int16, ambientLevel: Int) {
        guard enabled else { self = .off; return }
        switch mode {
        case 0: self = .noiseCancelling
        case 1: self = .ambient(voice: ambientMode == 1, level: ambientLevel)
        default: self = .unknown
        }
    }

    public var mode: String {
        switch self {
        case .unknown: return "Priority on stable connection"
        case .off: return "Off"
        case .noiseCancelling: return "Noise cancelling"
        case .ambient(let voice, _): return voice ? "Ambient sound · Voice" : "Ambient sound"
        }
    }

    public var level: Int {
        if case .ambient(_, let level) = self { return level }
        return 0
    }
}
