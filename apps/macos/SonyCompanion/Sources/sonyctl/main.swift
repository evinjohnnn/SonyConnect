import Foundation
import IOBluetooth
import MDRKit

// MARK: - Output helpers

@inline(__always) func jstr(_ s: String) -> String {
    var out = "\""
    for ch in s.unicodeScalars {
        switch ch {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        default:
            if ch.value < 0x20 {
                out += String(format: "\\u%04X", ch.value)
            } else {
                out.unicodeScalars.append(ch)
            }
        }
    }
    return out + "\""
}

func die(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(("error: " + message + "\n").data(using: .utf8)!)
    exit(code)
}

func note(_ message: String) {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
}

func usage() -> Never {
    print("""
    sonyctl — Sony MDR control-channel harness

    USAGE
      sonyctl devices                       List paired devices and link state.
      sonyctl probe  <device>               Open the channel, handshake, print state.
      sonyctl status <device>               Read battery and noise control as JSON.
      sonyctl state  <device>               Print the engine state JSON.
      sonyctl time <device>                 Send the current UTC time to the headphones.
      sonyctl quickaccess <device> <hex…>    Replace the Quick Access function ids.
      sonyctl adaptive <device> start|stop   Start or stop adaptive control.
      sonyctl adaptivewatch <device> [seconds]
                                          Start adaptive control, trace frames and
                                          print each decoded 79 01 parameter, then stop.
      sonyctl multipoint <device> on|off     Toggle two-device multipoint.
      sonyctl pairconnect <device> <index>   Connect a paired device from the list.
      sonyctl pairdisconnect <device> <index> Disconnect a paired device from the list.
      sonyctl pairing <device> on|off         Enter or leave Bluetooth pairing mode.
      sonyctl reset <device> settings|factory --yes
                                              Destructive headset reset; requires --yes.
      sonyctl nc     <device> off|nc|ambient|voice [level]
                                            Set noise cancelling / ambient sound.
      sonyctl eq     <device> [preset <id|name> | bass <level>]
                                            Read or set the equalizer.
      sonyctl watch  <device> [seconds]     Stream state changes as they arrive.
      sonyctl trace  <device>                Show the raw wire bytes of a handshake.
      sonyctl caps   <device>                Probe capability families on the device.
      sonyctl raw    <device> <hex…>         Send one payload and show the reply.
      sonyctl dseeauto <device> auto|off     Set DSEE auto-off (not on/off).
      sonyctl upconversion <device> auto|off Legacy alias for dseeauto.
      sonyctl autooff <device> off|removed|5|15|30|60|180
                                              Set auto power off (worn).
      sonyctl play|pause|next|prev|stop <device>
                                              Send a playback control action.
      sonyctl listening <device> standard|bgm|cinema
                                              Switch the listening mode.
      sonyctl handover <device> on|off       Set music hand-over.
      sonyctl volume <device> <0-255>        Set music volume (clamped by the device range).
      sonyctl callvolume <device> <0-255>    Set call volume (clamped by the device range).
      sonyctl autostandby <device> on|off    Set auto standby.
      sonyctl headgesture <device> on|off    Set head gesture control.
      sonyctl scan2 <device> <cmd> <start> <end>
                                              Probe a table-2 command across type bytes.
      sonyctl wearing <device> on|off  Pause/resume when headphones are removed.
      sonyctl mic <device> on|off       Toggle mic on/off by headphone operation.
      sonyctl sonyva <device> on|off    Toggle Sony Voice Assistant.
      sonyctl voiceguidance <device> on|off
                                              Toggle voice guidance.
      sonyctl vgvolume <device> <n>         Set the voice guidance volume.
      sonyctl hgtraining <device> start|finish
                                              Enter or leave head gesture training.
      sonyctl safevolume <device> normal|sensitive
                                              Set the safe-volume WHO level.
      sonyctl poweroff <device>              Ask the headphones to power off.
      sonyctl stc <device> on|off            Set Speak-to-Chat.
      sonyctl stcdetail <device> auto|high|low fast|mid|slow|none
                                              Set Speak-to-Chat detection and auto-off.
      sonyctl table                         Print the shipped command table summary.
      sonyctl --version

    <device> is a Bluetooth address (00:11:22:AA:BB:CC) or a name substring.

    This tool speaks Sony's control protocol only. It does not pair, does not
    touch firmware, and writes nothing beyond the single setting you ask for.
    """)
    exit(2)
}

// MARK: - JSON rendering

func statusJSON(_ s: HeadphoneStatus) -> String {
    var parts: [String] = [jstr("state") + ": " + jstr(s.phase.label)]
    if !s.model.isEmpty {
        parts.append(jstr("model") + ": " + jstr(s.model))
    }
    if !s.firmware.isEmpty {
        parts.append(jstr("firmware") + ": " + jstr(s.firmware))
    }
    if let color = s.modelColor {
        parts.append(jstr("model_color") + ": \(color)")
    }
    if let apo = s.autoPowerOff {
        parts.append(jstr("auto_power_off") + ": " + (apo ? "true" : "false"))
    }
    if let cm = s.connectionMode {
        parts.append(jstr("connection_mode") + ": " + jstr(cm.label))
    }
    if let worn = s.wearingStatus {
        parts.append(jstr("wearing") + ": " + jstr(worn ? "worn" : "not worn"))
    }
    if let mho = s.musicHandOver {
        parts.append(jstr("music_hand_over") + ": " + (mho ? "true" : "false"))
    }
    if let usb = s.usbSubmersion {
        parts.append(jstr("usb_submersion") + ": " + (usb ? "true" : "false"))
    }
    if s.pairingKnown {
        let devices = s.pairedDevices.map { device in
            "{" + jstr("address") + ": " + jstr(device.address)
                + ", " + jstr("name") + ": " + jstr(device.name)
                + ", " + jstr("connected") + ": " + (device.connected ? "true" : "false")
                + "}"
        }
        parts.append(jstr("paired_devices") + ": [" + devices.joined(separator: ", ") + "]")
        if let cap = s.pairingCapability {
            parts.append(
                jstr("pairing_limit") + ": " + jstr("\(cap.maxConnected) connected, \(cap.maxPaired) paired")
            )
        }
    }
    if let play = s.playback {
        parts.append(jstr("playback") + ": " + jstr(play.label))
    }
    if let listen = s.listening {
        parts.append(jstr("listening") + ": " + jstr(listen.label))
    }
    if let volume = s.volume {
        parts.append(jstr("volume") + ": \(volume.value)")
        parts.append(jstr("volume_max") + ": \(volume.max)")
    }
    if let volume = s.callVolume {
        parts.append(jstr("call_volume") + ": \(volume.value)")
        parts.append(jstr("call_volume_max") + ": \(volume.max)")
    }
    if let autoVolume = s.autoVolume {
        parts.append(jstr("auto_volume") + ": " + (autoVolume ? "true" : "false"))
    }
    if let autoStandby = s.autoStandby {
        parts.append(jstr("auto_standby") + ": " + (autoStandby ? "true" : "false"))
    }
    if let autoStandbyEnabled = s.autoStandbyEnabled {
        parts.append(jstr("auto_standby_enabled") + ": " + (autoStandbyEnabled ? "true" : "false"))
    }
    if let st = s.smartTalking {
        parts.append(jstr("smart_talking") + ": " + (st.enabled ? "true" : "false"))
        parts.append(jstr("smart_talking_sensitivity") + ": " + jstr(st.sensitivityLabel))
        parts.append(jstr("smart_talking_mode_out") + ": " + jstr(st.modeOutLabel))
    }
    if let hg = s.headGesture {
        parts.append(jstr("head_gesture") + ": " + (hg ? "true" : "false"))
    }
    if let cbw = s.controlByWearing {
        parts.append(jstr("control_by_wearing") + ": " + (cbw ? "true" : "false"))
    }
    if let mic = s.micOnOff {
        parts.append(jstr("mic_on_off") + ": " + (mic ? "true" : "false"))
    }
    if let sva = s.sonyVoiceAssistant {
        parts.append(jstr("sony_voice_assistant") + ": " + (sva ? "true" : "false"))
    }
    if let language = s.sonyVoiceAssistantLanguage {
        parts.append(jstr("sony_voice_assistant_language") + ": \(language)")
    }
    if let vg = s.voiceGuidance {
        parts.append(jstr("voice_guidance") + ": " + (vg ? "true" : "false"))
    }
    if let vgv = s.voiceGuidanceVolume {
        parts.append(jstr("voice_guidance_volume") + ": \(vgv)")
    }
    if let sv = s.safeVolume {
        parts.append(jstr("safe_volume") + ": \(sv)")
    }
    if let apow = s.autoPowerOffWearing {
        parts.append(jstr("auto_power_off_wearing") + ": " + jstr(apow.currentLabel))
    }
    if !s.codec.isEmpty {
        parts.append(jstr("codec") + ": " + jstr(s.codec))
    }
    if s.protocolVersion != 0 {
        parts.append(jstr("protocol") + ": \(s.protocolVersion)")
    }
    if let battery = s.batteryPercent {
        parts.append(jstr("battery") + ": \(battery)")
        if !s.charging.label.isEmpty {
            parts.append(jstr("charging") + ": " + jstr(s.charging.label))
        }
    }
    if case .unknown = s.noiseControl {
        parts.append(jstr("noise_control") + ": null")
    } else {
        parts.append(jstr("noise_control") + ": " + jstr(s.noiseControl.mode))
        if case .ambient(_, let level) = s.noiseControl {
            parts.append(jstr("ambient_level") + ": \(level)")
        }
    }
    if let eq = s.equalizer {
        parts.append(jstr("eq_preset") + ": " + jstr(eq.presetName))
        parts.append(jstr("eq_preset_id") + ": \(eq.preset)")
        parts.append(jstr("eq_bands") + ": [" + eq.bands.map(String.init).joined(separator: ",") + "]")
        parts.append(jstr("clear_bass") + ": \(eq.clearBass)")
        parts.append(jstr("clear_bass_range") + ": [" + "\(eq.clearBassRange.lowerBound),\(eq.clearBassRange.upperBound)" + "]")
        parts.append(jstr("eq_presets") + ": " + jstr(
            eq.presets.map { "\($0.name)=\($0.id)" }.joined(separator: ",")))
    } else {
        parts.append(jstr("eq_preset") + ": null")
    }
    if let up = s.upscaling {
        parts.append(jstr("upscaling") + ": " + (up ? "true" : "false"))
    }
    parts.append(jstr("pending_write") + ": " + (s.pendingWrite ? "true" : "false"))
    parts.append(jstr("revision") + ": \(s.revision)")
    return "{" + parts.joined(separator: ", ") + "}"
}

/// Run an async session to completion on the main run loop.
func runSession(
    device: PairedDevice,
    seconds: TimeInterval,
    trace: Bool = false,
    waitForSync: Bool = true,
    then action: @escaping (HeadphoneSession) -> Void
) {
    let session = HeadphoneSession()
    var connectError: String?
    for attempt in 0..<4 {
        session.connect(to: device)
        connectError = session.lastError
        if connectError == nil { break }
        if attempt < 3 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
    }
    if let err = connectError { die(err) }

    let deadline = Date().addingTimeInterval(seconds)
    var acted = false
    var printed = 0
    var quietSince: Date?
    var confirmDeadline: Date?
    while Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        if let err = session.lastError { die(err) }
        if trace {
            // Stream the wire trail as it happens.
            let dropped = session.droppedLogLines
            if printed < dropped { printed = dropped }
            while printed < dropped + session.log.count {
                note(session.log[printed - dropped])
                printed += 1
            }
        }
        if session.isReady && !acted {
            if waitForSync && session.pendingCommands > 0 {
                quietSince = nil
                continue
            }
            // The device acknowledges a command before sending its reply, so
            // the queue can look empty while the last response is still on the
            // wire. Wait for a short quiet window instead of printing stale
            // state.
            if waitForSync {
                if quietSince == nil {
                    quietSince = Date()
                    continue
                }
                if Date().timeIntervalSince(quietSince!) < 0.5 {
                    continue
                }
            }
            acted = true
            action(session)
            // A write is confirmed asynchronously; give the device a moment so
            // the printed state reflects what the headphones actually accepted.
            let preActionDeadline = Date().addingTimeInterval(4)
            while session.status.pendingWrite && Date() < preActionDeadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }
            quietSince = Date()
            confirmDeadline = Date().addingTimeInterval(6)
        }
        if acted {
            if let confirmDeadline,
               session.status.pendingWrite,
               Date() < confirmDeadline {
                continue
            }
            if waitForSync && session.pendingCommands > 0 {
                quietSince = Date()
            } else if let quietSince,
                      Date().timeIntervalSince(quietSince) > 0.8 {
                break
            }
        }
    }
    if trace {
        while printed < session.log.count {
            note(session.log[printed])
            printed += 1
        }
    }
    if !session.isReady {
        die("handshake did not complete — is the headphone powered on and free?")
    }
    print(statusJSON(session.status))
    session.disconnect()
}

func resolve(_ query: String) -> PairedDevice {
    let all = BluetoothLink.pairedDevices
    let q = query.uppercased().replacingOccurrences(of: "-", with: ":")
    let matches = all.filter {
        $0.address.uppercased() == q
            || $0.name.uppercased() == query.uppercased()
            || $0.name.uppercased().contains(query.uppercased())
    }
    // The XM6 is paired twice: the Classic entry `WH-1000XM6` (MDR/RFCOMM)
    // and an LE entry `LE_WH-1000XM6` (pairing/LE-audio only). A name query
    // must prefer the exact Classic match, or every command lands on the LE
    // address and fails with kIOReturnOffline.
    func score(_ device: PairedDevice) -> Int {
        let exact = device.address.uppercased() == q
            || device.name.uppercased() == query.uppercased()
        if exact { return device.isConnected ? 0 : 1 }
        return device.isConnected ? 2 : 3
    }
    guard let first = matches.min(by: { score($0) < score($1) }) else {
        die("no paired device matches '\(query)'")
    }
    if matches.count > 1 {
        note("matched \(matches.count) devices; using \(first.displayName)")
    }
    note("using \(first.displayName) [\(first.address)]")
    return first
}

// MARK: - Commands

func cmdDevices() {
    let rows = BluetoothLink.pairedDevices.map {
        "  {\(jstr("name")): \(jstr($0.displayName)), \(jstr("address")): \(jstr($0.address)), "
            + "\(jstr("link")): \(jstr($0.isConnected ? "connected" : "paired"))}"
    }
    print("[\n" + rows.joined(separator: ",\n") + "\n]")
}

func cmdProbe(_ device: PairedDevice) {
    runSession(device: device, seconds: 20) { _ in }
}

func cmdState(_ device: PairedDevice) {
    runSession(device: device, seconds: 60, waitForSync: true) { session in
        if let json = session.stateJSON() { print(json) }
    }
}

/// Destructive headset reset. Requires the literal --yes flag.
func cmdReset(_ device: PairedDevice, kind: String, confirmed: Bool) {
    guard confirmed else {
        note("refusing: add --yes to confirm \(kind) reset (this erases headset settings)")
        return
    }
    let value: UInt8
    switch kind.lowercased() {
    case "settings": value = 0x00
    case "factory": value = 0x01
    default:
        note("usage: sonyctl reset <device> settings|factory --yes")
        return
    }
    runSession(device: device, seconds: 40, trace: true, waitForSync: true) { session in
        session.sendRaw([0xF4, 0x09, value])
        RunLoop.current.run(until: Date().addingTimeInterval(3.0))
        if let json = session.stateJSON() { print(json) }
    }
}

/// Toggle multipoint (GS 0xD2).
func cmdMultipoint(_ device: PairedDevice, value: String) {
    let on: Bool
    switch value.lowercased() {
    case "on": on = true
    case "off": on = false
    default:
        note("usage: sonyctl multipoint <device> on|off")
        return
    }
    runSession(device: device, seconds: 40, trace: true, waitForSync: true) { session in
        session.setGeneralSetting(0xD2, on: on)
        RunLoop.current.run(until: Date().addingTimeInterval(2.0))
        if let json = session.stateJSON() { print(json) }
    }
}

/// Connect or disconnect one entry of the headset's paired-device list.
func cmdPairConnection(_ device: PairedDevice, index: Int, connect: Bool) {
    runSession(device: device, seconds: 40, trace: true, waitForSync: true) { session in
        if connect {
            session.connectPairedDevice(at: index)
        } else {
            session.disconnectPairedDevice(at: index)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(2.5))
        if let json = session.stateJSON() { print(json) }
    }
}

/// Enter or leave Bluetooth inquiry-scan (pairing) mode.
func cmdPairingMode(_ device: PairedDevice, value: String) {
    let on: Bool
    switch value.lowercased() {
    case "on": on = true
    case "off": on = false
    default:
        note("usage: sonyctl pairing <device> on|off")
        return
    }
    runSession(device: device, seconds: 30, trace: true, waitForSync: true) { session in
        session.setPairingMode(on)
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
    }
}

/// Start or stop adaptive control.
func cmdAdaptive(_ device: PairedDevice, value: String) {
    let start: Bool
    switch value.lowercased() {
    case "start", "on": start = true
    case "stop", "off": start = false
    default:
        note("usage: sonyctl adaptive <device> start|stop")
        return
    }
    runSession(device: device, seconds: 40, trace: true, waitForSync: true) { session in
        session.setAdaptiveControl(start)
        RunLoop.current.run(until: Date().addingTimeInterval(2.0))
        if let json = session.stateJSON() { print(json) }
    }
}

/// Start adaptive control, keep the channel open so device-pushed `79 01`
/// parameter notifications reach this client, print the engine state whenever
/// it carries an `adaptive_parameter`, then stop adaptive control again.
/// Read-only apart from the verified `74 01 01/00` start/stop; never sends `78 01`.
func cmdAdaptiveWatch(_ device: PairedDevice, seconds: TimeInterval) {
    runSession(device: device, seconds: seconds + 30, trace: true, waitForSync: true) { session in
        session.setAdaptiveControl(true)
        let deadline = Date().addingTimeInterval(seconds)
        var lastParameter: String?
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            guard let json = session.stateJSON(),
                  let range = json.range(of: "\"adaptive_parameter\":") else { continue }
            let parameter = String(json[range.lowerBound...].prefix(200))
            if parameter != lastParameter {
                lastParameter = parameter
                note("adaptive_parameter changed")
                print(json)
                fflush(stdout)
            }
        }
        if lastParameter == nil { note("no adaptive_parameter notification in \(Int(seconds)) s") }
        session.setAdaptiveControl(false)
        RunLoop.current.run(until: Date().addingTimeInterval(2.0))
    }
}

/// Replace the Quick Access function list.
func cmdQuickAccess(_ device: PairedDevice, tokens: [String]) {
    let functions = tokens.compactMap { UInt8($0, radix: 16) }
    guard !functions.isEmpty else {
        note("usage: sonyctl quickaccess <device> <hex…>")
        return
    }
    runSession(device: device, seconds: 60, trace: true, waitForSync: true) { session in
        session.setQuickAccessFunctions(functions)
        RunLoop.current.run(until: Date().addingTimeInterval(2.5))
        if let json = session.stateJSON() { print(json) }
    }
}

/// Send the connection-established time (UTC) to the headphones.
func cmdTime(_ device: PairedDevice) {
    runSession(device: device, seconds: 30, trace: true, waitForSync: true) { session in
        let now = Date()
        let secs = UInt64(now.timeIntervalSince1970)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
        var payload: [UInt8] = [0x18, 0x05, 0x00]
        for shift in stride(from: 56, through: 0, by: -8) {
            payload.append(UInt8((secs >> UInt64(shift)) & 0xFF))
        }
        let year = UInt16(bitPattern: Int16(c.year ?? 1970))
        payload.append(UInt8(year >> 8))
        payload.append(UInt8(year & 0xFF))
        payload.append(UInt8(c.month ?? 1))
        payload.append(UInt8(c.day ?? 1))
        payload.append(UInt8(c.hour ?? 0))
        payload.append(UInt8(c.minute ?? 0))
        payload.append(UInt8(c.second ?? 0))
        payload.append(0x00) // timezone hour (UTC)
        payload.append(0x00) // timezone minute
        session.sendRaw(payload)
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        if let json = session.stateJSON() { print(json) }
    }
}

func cmdStatus(_ device: PairedDevice) {
    // The full sync now includes optional diagnostics; allow it to finish.
    runSession(device: device, seconds: 60, waitForSync: true) { $0.refreshStatus() }
}

func cmdNoiseControl(_ device: PairedDevice, setting: String, level: Int?) {
    let choice: NoiseControlChoice
    switch setting {
    case "off": choice = .off
    case "nc": choice = .noiseCancelling
    case "ambient": choice = .ambient
    case "voice": choice = .ambient
    default: die("unknown setting '\(setting)'; expected off, nc, ambient or voice")
    }
    runSession(device: device, seconds: 20, trace: true) { session in
        session.setNoiseControl(choice, ambientLevel: level)
    }
}

/// Probe capability families on the live device so nothing is guessed.
func cmdCaps(_ device: PairedDevice) {
    runSession(device: device, seconds: 90, trace: true, waitForSync: true) { session in
        let probes: [[UInt8]] = [
            [0x60, 0x00],   // NCASM_GET_CAPABILITY (PRESET)
            [0xE0, 0x00],   // AUDIO_GET_CAPABILITY (CONNECTION_MODE)
            [0x70, 0x00],   // SENSE_GET_CAPABILITY
            [0xD0, 0x00],   // GENERAL_SETTING_GET_CAPABILITY
        ]
        for probe in probes {
            session.sendRaw(probe)
            RunLoop.current.run(until: Date().addingTimeInterval(0.45))
        }
    }
}

/// Send one or more payloads after the handshake and watch the replies.
///
/// Groups are separated by `--`, so a sequence such as
/// `06 00 -- E4 04 01 -- E2 04` can be tested in one session.
func cmdRaw(_ device: PairedDevice, tokens: [String]) {
    var groups: [[UInt8]] = []
    var current: [UInt8] = []
    for token in tokens {
        if token == "--" {
            if !current.isEmpty { groups.append(current); current = [] }
            continue
        }
        if let byte = UInt8(token, radix: 16) { current.append(byte) }
    }
    if !current.isEmpty { groups.append(current) }
    guard !groups.isEmpty else { note("usage: sonyctl raw <device> <hex…> [-- <hex…>]"); return }

    runSession(device: device, seconds: 90, trace: true, waitForSync: true) { session in
        for group in groups {
            session.sendRaw(group)
            RunLoop.current.run(until: Date().addingTimeInterval(1.4))
        }
    }
}

/// Toggle audio upscaling.
/// Set the wearing-detection auto-power-off element and print the read-back.
func cmdAutoOff(_ device: PairedDevice, value: String) {
    let choices: [String: UInt8] = [
        "off": 0x11, "removed": 0x10, "worn": 0x10,
        "5": 0x00, "15": 0x04, "30": 0x01, "60": 0x02, "180": 0x03,
    ]
    guard let code = choices[value.lowercased()] ?? UInt8(value, radix: 16) else {
        note("usage: sonyctl autooff <device> off|removed|5|15|30|60|180")
        return
    }
    runSession(device: device, seconds: 25) { session in
        session.setAutoPowerOffWearing(code)
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        print(statusJSON(session.status))
    }
}

/// `AUDIO_SET_PARAM 0x01` carries `UpscalingTypeAutoOff`, not the on/off state.
/// `auto` = 1, `off` = 0; the enabled/disabled status is read-only.
/// Playback control actions.
func cmdPlaybackControl(_ device: PairedDevice, action: String) {
    let controls: [String: UInt8] = [
        "play": 0x07, "pause": 0x01, "next": 0x02, "prev": 0x03, "stop": 0x06,
    ]
    guard let control = controls[action.lowercased()] else {
        note("usage: sonyctl play|pause|next|prev|stop <device>")
        return
    }
    runSession(device: device, seconds: 25) { session in
        session.setPlaybackControl(control)
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        print(statusJSON(session.status))
    }
}

/// Set the music volume; the engine clamps to the advertised steps.
func cmdMusicVolume(_ device: PairedDevice, value: String) {
    guard let volume = Int(value), (0...255).contains(volume) else {
        note("usage: sonyctl volume <device> <0-255>")
        return
    }
    runSession(device: device, seconds: 25) { session in
        session.setMusicVolume(volume)
        let deadline = Date().addingTimeInterval(4)
        while session.status.volume?.value != volume && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        print(statusJSON(session.status))
    }
}

/// Set the call volume; the engine clamps to the advertised steps.
func cmdCallVolume(_ device: PairedDevice, value: String) {
    guard let volume = Int(value), (0...255).contains(volume) else {
        note("usage: sonyctl callvolume <device> <0-255>")
        return
    }
    runSession(device: device, seconds: 25) { session in
        session.setCallVolume(volume)
        let deadline = Date().addingTimeInterval(4)
        while session.status.callVolume?.value != volume && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        print(statusJSON(session.status))
    }
}

/// Probe a table-2 command across a range of type bytes.
func cmdScan2(_ device: PairedDevice, command: String, start: String, end: String) {
    guard let cmd = UInt8(command, radix: 16),
          let lo = UInt8(start, radix: 16),
          let hi = UInt8(end, radix: 16),
          lo <= hi else {
        note("usage: sonyctl scan2 <device> <cmd-hex> <start-hex> <end-hex>")
        return
    }
    runSession(device: device, seconds: 120, waitForSync: true) { session in
        for type in lo...hi {
            let mark = session.log.count
            session.sendRawTable2([cmd, type])
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            let lines = session.log[mark...].filter { $0.contains("←") }
            if !lines.isEmpty {
                print(String(format: "== %02X %02X", cmd, type))
                for line in lines { print(line) }
            }
        }
    }
}

/// Toggle playback control by wearing/removing the headphones.
func cmdControlByWearing(_ device: PairedDevice, value: String) {
    let enabled: Bool
    switch value.lowercased() {
    case "on": enabled = true
    case "off": enabled = false
    default:
        note("usage: sonyctl wearing <device> on|off")
        return
    }
    runSession(device: device, seconds: 60, trace: true, waitForSync: true) { session in
        session.setControlByWearing(enabled)
        RunLoop.current.run(until: Date().addingTimeInterval(2.0))
        if let json = session.stateJSON() { print(json) }
    }
}

/// Toggle mic on/off by headphone operation.
func cmdMic(_ device: PairedDevice, value: String) {
    let enabled: Bool
    switch value.lowercased() {
    case "on": enabled = true
    case "off": enabled = false
    default:
        note("usage: sonyctl mic <device> on|off")
        return
    }
    runSession(device: device, seconds: 60, trace: true, waitForSync: true) { session in
        session.setMicOnOff(enabled)
        let deadline = Date().addingTimeInterval(4)
        while session.status.micOnOff != enabled && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        if let json = session.stateJSON() { print(json) }
    }
}

/// Toggle Sony Voice Assistant.
func cmdSonyVoiceAssistant(_ device: PairedDevice, value: String) {
    let enabled: Bool
    switch value.lowercased() {
    case "on": enabled = true
    case "off": enabled = false
    default:
        note("usage: sonyctl sonyva <device> on|off")
        return
    }
    runSession(device: device, seconds: 60, trace: true, waitForSync: true) { session in
        session.setSonyVoiceAssistant(enabled)
        let deadline = Date().addingTimeInterval(4)
        while session.status.sonyVoiceAssistant != enabled && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        if let json = session.stateJSON() { print(json) }
    }
}

/// Toggle voice guidance.
func cmdVoiceGuidance(_ device: PairedDevice, value: String) {
    let enabled: Bool
    switch value.lowercased() {
    case "on": enabled = true
    case "off": enabled = false
    default:
        note("usage: sonyctl voiceguidance <device> on|off")
        return
    }
    runSession(device: device, seconds: 60, trace: true, waitForSync: true) { session in
        session.setVoiceGuidance(enabled)
        RunLoop.current.run(until: Date().addingTimeInterval(2.0))
        if let json = session.stateJSON() { print(json) }
    }
}

/// Set the voice guidance volume.
func cmdVoiceGuidanceVolume(_ device: PairedDevice, value: String) {
    guard let volume = Int8(value) else {
        note("usage: sonyctl vgvolume <device> <n>")
        return
    }
    runSession(device: device, seconds: 60, trace: true, waitForSync: true) { session in
        session.setVoiceGuidanceVolume(volume)
        RunLoop.current.run(until: Date().addingTimeInterval(2.0))
        if let json = session.stateJSON() { print(json) }
    }
}

/// Start or finish head gesture training.
func cmdHeadGestureTraining(_ device: PairedDevice, value: String) {
    let start: Bool
    switch value.lowercased() {
    case "start": start = true
    case "finish", "stop": start = false
    default:
        note("usage: sonyctl hgtraining <device> start|finish")
        return
    }
    runSession(device: device, seconds: 60, trace: true, waitForSync: true) { session in
        session.setHeadGestureTraining(start)
        RunLoop.current.run(until: Date().addingTimeInterval(2.0))
        if let json = session.stateJSON() { print(json) }
    }
}

/// Set the safe-volume WHO standard level.
func cmdSafeVolume(_ device: PairedDevice, value: String) {
    let level: UInt8
    switch value.lowercased() {
    case "normal": level = 0
    case "sensitive": level = 1
    default:
        note("usage: sonyctl safevolume <device> normal|sensitive")
        return
    }
    runSession(device: device, seconds: 60, waitForSync: true) { session in
        session.setSafeVolume(level)
        let deadline = Date().addingTimeInterval(4)
        while session.status.safeVolume != level && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        if let json = session.stateJSON() { print(json) }
    }
}

/// Toggle head gesture control.
func cmdHeadGesture(_ device: PairedDevice, value: String) {
    let enabled: Bool
    switch value.lowercased() {
    case "on", "true", "1": enabled = true
    case "off", "false", "0": enabled = false
    default:
        note("usage: sonyctl headgesture <device> on|off")
        return
    }
    runSession(device: device, seconds: 25) { session in
        session.setHeadGesture(enabled)
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        print(statusJSON(session.status))
    }
}

/// Ask the headphones to power off.
func cmdPowerOff(_ device: PairedDevice) {
    runSession(device: device, seconds: 25) { session in
        session.powerOff()
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        print(statusJSON(session.status))
    }
}

/// Toggle Speak-to-Chat.
func cmdSmartTalking(_ device: PairedDevice, value: String) {
    let enabled: Bool
    switch value.lowercased() {
    case "on", "true", "1": enabled = true
    case "off", "false", "0": enabled = false
    default:
        note("usage: sonyctl stc <device> on|off")
        return
    }
    runSession(device: device, seconds: 25) { session in
        session.setSmartTalking(enabled)
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        print(statusJSON(session.status))
    }
}

/// Set Speak-to-Chat detection sensitivity and auto-off time.
func cmdSmartTalkingDetail(_ device: PairedDevice, sensitivity: String, modeOut: String) {
    let sens: UInt8
    switch sensitivity.lowercased() {
    case "auto": sens = 0
    case "high": sens = 1
    case "low": sens = 2
    default:
        note("usage: sonyctl stcdetail <device> auto|high|low fast|mid|slow|none")
        return
    }
    let time: UInt8
    switch modeOut.lowercased() {
    case "fast": time = 0
    case "mid", "medium": time = 1
    case "slow": time = 2
    case "none": time = 3
    default:
        note("usage: sonyctl stcdetail <device> auto|high|low fast|mid|slow|none")
        return
    }
    runSession(device: device, seconds: 25) { session in
        session.setSmartTalkingDetail(sensitivity: sens, modeOut: time)
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        print(statusJSON(session.status))
    }
}

/// Toggle auto standby.
func cmdAutoStandby(_ device: PairedDevice, value: String) {
    let enabled: Bool
    switch value.lowercased() {
    case "on", "true", "1": enabled = true
    case "off", "false", "0": enabled = false
    default:
        note("usage: sonyctl autostandby <device> on|off")
        return
    }
    runSession(device: device, seconds: 25) { session in
        session.setAutoStandby(enabled)
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        print(statusJSON(session.status))
    }
}

/// Toggle table-2 music hand-over.
func cmdMusicHandOver(_ device: PairedDevice, value: String) {
    let enabled: Bool
    switch value.lowercased() {
    case "on", "true", "1": enabled = true
    case "off", "false", "0": enabled = false
    default:
        note("usage: sonyctl handover <device> on|off")
        return
    }
    runSession(device: device, seconds: 25) { session in
        session.setMusicHandOver(enabled)
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        print(statusJSON(session.status))
    }
}

/// Switch the listening mode (BGM / Cinema / Standard).
func cmdListening(_ device: PairedDevice, mode: String) {
    let value: ListeningModeView
    switch mode.lowercased() {
    case "standard", "normal", "off": value = .standard
    case "bgm": value = .bgm
    case "cinema": value = .cinema
    default:
        note("usage: sonyctl listening <device> standard|bgm|cinema")
        return
    }
    runSession(device: device, seconds: 25) { session in
        session.setListeningMode(value)
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        print(statusJSON(session.status))
    }
}

func cmdUpconversion(_ device: PairedDevice, value: String) {
    let auto = value == "auto" || value == "on"
    runSession(device: device, seconds: 25) { session in
        session.setUpscaling(auto)
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
    }
}

/// Send a raw payload on table 2 (voice guidance and friends).
func cmdRaw2(_ device: PairedDevice, tokens: [String]) {
    // Groups are separated by `--`; a `wait:<seconds>` token keeps the channel
    // open and tracing for that long before the next group.
    enum Step { case send([UInt8]), wait(TimeInterval) }
    var steps: [Step] = []
    var current: [UInt8] = []
    func flush() { if !current.isEmpty { steps.append(.send(current)); current = [] } }
    for token in tokens {
        if token == "--" { flush(); continue }
        if token.hasPrefix("wait:"), let s = TimeInterval(token.dropFirst(5)) {
            flush(); steps.append(.wait(s)); continue
        }
        if let byte = UInt8(token, radix: 16) { current.append(byte) }
    }
    flush()
    guard steps.contains(where: { if case .send = $0 { return true } else { return false } }) else {
        note("usage: sonyctl raw2 <device> <hex…> [-- <hex…>] [wait:<s>]"); return
    }
    let waited = steps.reduce(0.0) { if case .wait(let s) = $1 { return $0 + s } else { return $0 } }
    runSession(device: device, seconds: 90 + waited, trace: true, waitForSync: true) { session in
        for step in steps {
            switch step {
            case .send(let group):
                session.sendRawTable2(group)
                RunLoop.current.run(until: Date().addingTimeInterval(1.4))
            case .wait(let s):
                note("holding the channel for \(Int(s)) s")
                RunLoop.current.run(until: Date().addingTimeInterval(s))
            }
        }
    }
}

func cmdTrace(_ device: PairedDevice) {
    runSession(device: device, seconds: 20, trace: true) { _ in }
}

func cmdEqualizer(_ device: PairedDevice, args: [String]) {
    // `eq` reads; `eq preset <id|name>` writes a preset; `eq bass <n>` writes
    // Clear Bass. Ids come from the device's own list, printed by `eq`.
    let action = args.first
    runSession(device: device, seconds: 30, trace: false) { session in
        // The equaliser is read immediately after the handshake completes, so
        // wait for it rather than racing it.
        let deadline = Date().addingTimeInterval(6)
        while session.status.equalizer == nil && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        guard let eq = session.status.equalizer else {
            note("this device did not report an equaliser")
            return
        }
        switch action {
        case nil:
            break
        case "preset":
            guard args.count >= 2 else { note("usage: sonyctl eq <device> preset <id|name>"); return }
            let query = args[1].lowercased()
            let match = eq.presets.first {
                String($0.id) == query || $0.name.lowercased() == query
            }
            guard let preset = match else {
                note("no such preset; available: "
                     + eq.presets.map { "\($0.name)(\($0.id))" }.joined(separator: ", "))
                return
            }
            session.setEqualizerPreset(preset.id)
        case "bass":
            guard args.count >= 2, let level = Int(args[1]) else {
                note("usage: sonyctl eq <device> bass <level>"); return
            }
            session.setClearBass(level)
        default:
            note("usage: sonyctl eq <device> [preset <id|name> | bass <level>]")
        }
    }
}

func cmdWatch(_ device: PairedDevice, seconds: TimeInterval) {
    let session = HeadphoneSession()
    session.connect(to: device)
    let deadline = Date().addingTimeInterval(seconds)
    var lastRevision: UInt64? = nil
    while Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        if let err = session.lastError { die(err) }
        guard session.isReady else { continue }
        if session.status.revision != lastRevision {
            lastRevision = session.status.revision
            print(statusJSON(session.status))
            fflush(stdout)
        }
    }
    session.disconnect()
}

func cmdTable() {
    print("""
    {"protocol": "MDR V2", "table": 1, "commands": 156}
    """)
}

// MARK: - main

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { usage() }

if command == "--version" || command == "-v" {
    print("sonyctl \(Engine.version)")
    exit(0)
}
if command == "devices" { cmdDevices(); exit(0) }
if command == "table" { cmdTable(); exit(0) }

guard args.count >= 2 else { usage() }
let query = args[1]

switch command {
case "probe":
    cmdProbe(resolve(query))
case "state":
    cmdState(resolve(query))
case "reset":
    guard args.count >= 3 else {
        note("usage: sonyctl reset <device> settings|factory --yes")
        exit(2)
    }
    cmdReset(resolve(query), kind: args[2], confirmed: args.contains("--yes"))
case "multipoint":
    guard args.count >= 3 else {
        note("usage: sonyctl multipoint <device> on|off")
        exit(2)
    }
    cmdMultipoint(resolve(query), value: args[2])
case "pairconnect":
    guard args.count >= 3, let index = Int(args[2]) else {
        note("usage: sonyctl pairconnect <device> <index>")
        exit(2)
    }
    cmdPairConnection(resolve(query), index: index, connect: true)
case "pairdisconnect":
    guard args.count >= 3, let index = Int(args[2]) else {
        note("usage: sonyctl pairdisconnect <device> <index>")
        exit(2)
    }
    cmdPairConnection(resolve(query), index: index, connect: false)
case "pairing":
    guard args.count >= 3 else {
        note("usage: sonyctl pairing <device> on|off")
        exit(2)
    }
    cmdPairingMode(resolve(query), value: args[2])
case "adaptive":
    guard args.count >= 3 else {
        note("usage: sonyctl adaptive <device> start|stop")
        exit(2)
    }
    cmdAdaptive(resolve(query), value: args[2])
case "quickaccess":
    cmdQuickAccess(resolve(query), tokens: Array(args.dropFirst(2)))
case "time":
    cmdTime(resolve(query))
case "status":
    cmdStatus(resolve(query))
case "trace":
    cmdTrace(resolve(query))
case "caps":
    cmdCaps(resolve(query))
case "raw":
    cmdRaw(resolve(query), tokens: Array(args.dropFirst(2)))
case "raw2":
    cmdRaw2(resolve(query), tokens: Array(args.dropFirst(2)))
case "upconversion", "dseeauto":
    guard args.count >= 3 else { usage() }
    cmdUpconversion(resolve(query), value: args[2])
case "autooff":
    guard args.count >= 3 else { usage() }
    cmdAutoOff(resolve(query), value: args[2])
case "play", "pause", "next", "prev", "stop":
    guard args.count >= 2 else { usage() }
    cmdPlaybackControl(resolve(query), action: args[0])
case "listening":
    guard args.count >= 3 else {
        note("usage: sonyctl listening <device> standard|bgm|cinema")
        exit(2)
    }
    cmdListening(resolve(query), mode: args[2])
case "handover":
    guard args.count >= 3 else {
        note("usage: sonyctl handover <device> on|off")
        exit(2)
    }
    cmdMusicHandOver(resolve(query), value: args[2])
case "volume":
    guard args.count >= 3 else {
        note("usage: sonyctl volume <device> <0-255>")
        exit(2)
    }
    cmdMusicVolume(resolve(query), value: args[2])
case "callvolume":
    guard args.count >= 3 else {
        note("usage: sonyctl callvolume <device> <0-255>")
        exit(2)
    }
    cmdCallVolume(resolve(query), value: args[2])
case "autostandby":
    guard args.count >= 3 else {
        note("usage: sonyctl autostandby <device> on|off")
        exit(2)
    }
    cmdAutoStandby(resolve(query), value: args[2])
case "scan2":
    guard args.count >= 5 else {
        note("usage: sonyctl scan2 <device> <cmd-hex> <start-hex> <end-hex>")
        exit(2)
    }
    cmdScan2(resolve(query), command: args[2], start: args[3], end: args[4])
case "wearing":
    guard args.count >= 3 else {
        note("usage: sonyctl wearing <device> on|off")
        exit(2)
    }
    cmdControlByWearing(resolve(query), value: args[2])
case "mic":
    guard args.count >= 3 else {
        note("usage: sonyctl mic <device> on|off")
        exit(2)
    }
    cmdMic(resolve(query), value: args[2])
case "sonyva":
    guard args.count >= 3 else {
        note("usage: sonyctl sonyva <device> on|off")
        exit(2)
    }
    cmdSonyVoiceAssistant(resolve(query), value: args[2])
case "voiceguidance":
    guard args.count >= 3 else {
        note("usage: sonyctl voiceguidance <device> on|off")
        exit(2)
    }
    cmdVoiceGuidance(resolve(query), value: args[2])
case "vgvolume":
    guard args.count >= 3 else {
        note("usage: sonyctl vgvolume <device> <n>")
        exit(2)
    }
    cmdVoiceGuidanceVolume(resolve(query), value: args[2])
case "hgtraining":
    guard args.count >= 3 else {
        note("usage: sonyctl hgtraining <device> start|finish")
        exit(2)
    }
    cmdHeadGestureTraining(resolve(query), value: args[2])
case "safevolume":
    guard args.count >= 3 else {
        note("usage: sonyctl safevolume <device> normal|sensitive")
        exit(2)
    }
    cmdSafeVolume(resolve(query), value: args[2])
case "headgesture":
    guard args.count >= 3 else {
        note("usage: sonyctl headgesture <device> on|off")
        exit(2)
    }
    cmdHeadGesture(resolve(query), value: args[2])
case "poweroff":
    guard args.count >= 2 else { usage() }
    cmdPowerOff(resolve(query))
case "stc":
    guard args.count >= 3 else {
        note("usage: sonyctl stc <device> on|off")
        exit(2)
    }
    cmdSmartTalking(resolve(query), value: args[2])
case "stcdetail":
    guard args.count >= 4 else {
        note("usage: sonyctl stcdetail <device> auto|high|low fast|mid|slow|none")
        exit(2)
    }
    cmdSmartTalkingDetail(resolve(query), sensitivity: args[2], modeOut: args[3])
case "eq":
    cmdEqualizer(resolve(query), args: Array(args.dropFirst(2)))
case "nc":
    guard args.count >= 3 else { usage() }
    var level: Int? = nil
    if args.count >= 4 {
        guard let parsed = Int(args[3]), (0...20).contains(parsed) else {
            die("ambient level must be an integer 0..20")
        }
        level = parsed
    }
    cmdNoiseControl(resolve(query), setting: args[2], level: level)
case "adaptivewatch":
    cmdAdaptiveWatch(resolve(query), seconds: args.count >= 3 ? (Double(args[2]) ?? 60) : 60)
case "watch":
    cmdWatch(resolve(query), seconds: args.count >= 3 ? (Double(args[2]) ?? 30) : 30)
default:
    usage()
}
