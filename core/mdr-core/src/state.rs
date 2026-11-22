//! Observable device state, reconciled from frames.
//!
//! State is deliberately "last authoritative value wins": a confirmed response
//! or a device-originated notification both overwrite, but a local optimistic
//! write only marks the value pending until the headphone confirms it. That is
//! what stops the UI from lying when another controller (e.g. Sony's own app)
//! changes a setting at the same time.

use crate::protocol::{BatteryStatus, Equalizer, NoiseControl};

/// Where a value came from. Used by the UI to show honest provenance and by
/// reconciliation to decide whether a local write still needs confirming.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Provenance {
    /// Never read from the device in this session.
    Unknown,
    /// Read back from the device.
    Device,
    /// Written by us, not yet confirmed by the device.
    PendingWrite,
    /// Restored from disk cache; may be stale.
    Cached,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Value<T> {
    pub value: T,
    pub provenance: Provenance,
    /// Monotonic milliseconds when this value was set, caller-supplied.
    pub at_ms: u64,
}

impl<T> Value<T> {
    pub fn unknown(default: T) -> Self {
        Value { value: default, provenance: Provenance::Unknown, at_ms: 0 }
    }

    pub fn is_stale(&self, now_ms: u64, max_age_ms: u64) -> bool {
        self.provenance == Provenance::Cached && now_ms.saturating_sub(self.at_ms) > max_age_ms
    }
}

/// Identity of the connected headphone.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct DeviceIdentity {
    pub model: String,
    pub firmware: String,
    pub series: String,
    pub protocol_version: u16,
    /// `ModelSeries` and `ModelColor` bytes from `SERIES_AND_COLOR_INFO`.
    pub model_series: Option<u8>,
    pub model_color: Option<u8>,
}

/// Everything the UI can show, in one place.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct DeviceState {
    pub identity: DeviceIdentity,
    pub battery: Option<Value<BatteryStatus>>,
    pub noise_control: Option<Value<NoiseControl>>,
    pub equalizer: Option<Value<Equalizer>>,
    /// Audio upscaling (DSEE-family), as reported by the device.
    pub upscaling: Option<Value<bool>>,
    /// General-setting slots (sidetone, multipoint, touch panel…), as the
    /// device describes them.
    pub general_settings: Vec<crate::protocol::GsSetting>,
    /// Negotiated Bluetooth codec, as reported in the common-status JSON.
    pub codec: Option<Value<String>>,
    /// Music hand-over setting (table-2 PERI type 0x03).
    pub music_hand_over: Option<Value<bool>>,
    /// Current multipoint source index (table-2 PERI type 0x01).
    pub source_switch: Option<Value<u8>>,
    /// Paired Classic Bluetooth devices (table-2 PERI type 0x00/0x02).
    pub paired_devices: Option<Value<crate::protocol::PairingDeviceList>>,
    /// Advertised pairing limits (`PERI_RET_CAPABILITY` type 0x00).
    pub pairing_capability: Option<Value<crate::protocol::PairingCapability>>,
    /// Last connect/disconnect result from the headset.
    pub last_pairing_event: Option<Value<crate::protocol::PairingConnectionEvent>>,
    /// Current Bluetooth mode (`PERI_RET_STATUS` type 0x00).
    pub pairing_mode: Option<Value<crate::protocol::PairingModeStatus>>,
    /// USB submersion status (table-2 POWER type 0x02).
    pub usb_submersion: Option<Value<bool>>,
    /// Playback controller state (PLAY family, enquired type 0x01).
    pub playback: Option<Value<crate::protocol::PlaybackState>>,
    /// Music volume steps advertised by the playback controller.
    pub playback_volume_steps: Option<Value<(u8, u8)>>,
    /// Current music volume (`PLAY_PARAM` type 0x20).
    pub music_volume: Option<Value<u8>>,
    /// Current call volume (`PLAY_PARAM` type 0x21).
    pub call_volume: Option<Value<u8>>,
    /// BGM listening mode: `(on, room size)`, read with `AUDIO_GET_PARAM 0x09`.
    pub bgm_mode: Option<Value<(bool, u8)>>,
    /// Cinema listening mode, read with `AUDIO_GET_PARAM 0x04`.
    pub cinema_mode: Option<Value<bool>>,
    /// Earpiece fitting detection (SYSTEM family, enquired type 0x06). Not
    /// whether the headphones are worn; see `worn`.
    pub wearing_status: Option<Value<crate::protocol::WearingStatus>>,
    /// Table-2 wearing checker code: 0 worn, 2 left off, 3 right off, 4 both
    /// off.
    pub wearing_code: Option<Value<u8>>,
    /// Auto power off, as reported (read-only on this protocol).
    pub auto_power_off: Option<Value<bool>>,
    /// Auto volume with limitation, as reported (read-only).
    pub auto_volume: Option<Value<bool>>,
    /// Speak-to-Chat (table-1 SYSTEM type 0x0C), merged from three replies.
    pub smart_talking: Option<Value<crate::protocol::SmartTalking>>,
    /// Head gesture on/off (table-1 SYSTEM type 0x0F).
    pub head_gesture: Option<Value<bool>>,
    /// Head gesture training status: `(0 in test / 1 out, enabled)`.
    pub head_gesture_training: Option<Value<(u8, bool)>>,
    /// Last gesture detected during training: 0 nod, 1 swing.
    pub head_gesture_action: Option<Value<u8>>,
    /// Quick Access assigned function ids.
    pub quick_access: Option<Value<Vec<u8>>>,
    /// Last Quick Access easy-setting result (`0` OK, `1` cancelled).
    pub quick_access_result: Option<Value<u8>>,
    /// Safe volume control level (`0` normal, `1` sensitive).
    pub safe_volume_level: Option<Value<u8>>,
    /// Auto standby candidate (15 minutes), as reported.
    pub auto_standby: Option<Value<bool>>,
    /// Auto-standby on/off setting, from the table-2 param.
    pub auto_standby_enabled: Option<Value<bool>>,
    /// Auto power off with wearing detection: (current, last selected) element.
    pub auto_power_off_wearing: Option<Value<(u8, u8)>>,
    /// Whether the wearing-detection auto-off feature is enabled.
    pub auto_power_off_wearing_enabled: Option<Value<bool>>,
    /// Classic / LE audio connection mode flags.
    pub connection_mode: Option<Value<(bool, bool)>>,
    /// Function bytes the device advertised on table 1.
    pub supported_functions: Vec<u8>,
    /// Function bytes the device advertised on table 2 (may be absent).
    pub supported_functions_table2: Vec<u8>,
    /// Diagnostics read during sync.
    pub ble_setup: Option<Value<(String, String)>>,
    pub repeat_tap_status: Option<Value<u8>>,
    pub sar_capability: Option<Value<u8>>,
    pub gatt_connectable: Option<Value<bool>>,
    pub sar_optimization: Option<Value<(bool, u8)>>,
    pub auto_play_capability: Option<Value<u16>>,
    /// Voice-assistant assignment (SYSTEM family).
    pub voice_assistant: Option<Value<crate::protocol::VoiceAssistantSetting>>,
    /// Last device-pushed alert: `(type, message, action)`.
    pub last_alert: Option<Value<(u8, u8, u8)>>,
    /// Adaptive control started (`74 01`).
    pub adaptive_control_started: Option<Value<bool>>,
    /// Adaptive control capability bytes (`70 01`).
    pub adaptive_control_capability: Option<Value<Vec<u8>>>,
    /// Device-pushed adaptive parameter (`79 01`), read-only.
    pub adaptive_parameter: Option<Value<crate::protocol::SenseParameter>>,
    /// Playback control by wearing/removing the headphones.
    pub control_by_wearing: Option<Value<bool>>,
    /// Whether control-by-wearing is available.
    pub control_by_wearing_available: Option<Value<bool>>,
    /// Mic on/off by headphone operation (table-2 SYSTEM type 0x0B).
    pub mic_on_off: Option<Value<bool>>,
    /// Mic-off sound effect flag.
    pub mic_off_sound_effect: Option<Value<bool>>,
    /// Mic key type from the capability.
    pub mic_key_type: Option<Value<u8>>,
    /// Sony Voice Assistant on/off (table-2 SYSTEM type 0x05).
    pub sony_voice_assistant: Option<Value<bool>>,
    /// Sony Voice Assistant language byte.
    pub sony_voice_assistant_language: Option<Value<u8>>,
    /// LE Audio switch compatibility version (table-2 LEA capability).
    pub le_audio_switch_compat: Option<Value<u8>>,
    /// Link auto-switch for headsets: `(enabled, speaker id, phone address)`.
    pub link_auto_switch: Option<Value<(bool, u16, String)>>,
    /// Voice guidance on/off (table-2 VOICE_GUIDANCE type 0x01).
    pub voice_guidance: Option<Value<bool>>,
    /// Voice guidance language byte.
    pub voice_guidance_language: Option<Value<u8>>,
    /// Raw 4-byte voice-guidance status from firmware 3.1.5.
    pub voice_guidance_status_raw: Option<Value<(u8, u8)>>,
    /// Voice guidance volume (table-2 VOICE_GUIDANCE type 0x20).
    pub voice_guidance_volume: Option<Value<i8>>,
    /// Monotonic counter bumped on every accepted frame, for change detection.
    pub revision: u64,
}

impl DeviceState {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn apply_battery(&mut self, status: BatteryStatus, at_ms: u64) {
        self.battery = Some(Value { value: status, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_noise_control(&mut self, nc: NoiseControl, at_ms: u64) {
        self.noise_control = Some(Value { value: nc, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    /// Merge an equaliser update, keeping fields the device did not resend.
    ///
    /// The device reports on/off, preset and Clear Bass as separate messages, so
    /// a single message must not erase what the others established.
    pub fn apply_equalizer(&mut self, update: EqualizerUpdate, at_ms: u64) {
        let mut eq = self
            .equalizer
            .as_ref()
            .map(|v| v.value.clone())
            .unwrap_or_default();
        update.apply_to(&mut eq);
        self.equalizer = Some(Value { value: eq, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_playback_volume_steps(&mut self, music: u8, call: u8, at_ms: u64) {
        self.playback_volume_steps =
            Some(Value { value: (music, call), provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_music_volume(&mut self, volume: u8, at_ms: u64) {
        self.music_volume = Some(Value { value: volume, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_call_volume(&mut self, volume: u8, at_ms: u64) {
        self.call_volume = Some(Value { value: volume, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    /// Mark call volume as written but unconfirmed.
    pub fn mark_call_volume_pending(&mut self, volume: u8, at_ms: u64) {
        if let Some(v) = self.call_volume.as_mut() {
            v.value = volume;
            v.provenance = Provenance::PendingWrite;
            v.at_ms = at_ms;
        }
    }

    /// Mark music volume as written but unconfirmed.
    pub fn mark_music_volume_pending(&mut self, volume: u8, at_ms: u64) {
        if let Some(v) = self.music_volume.as_mut() {
            v.value = volume;
            v.provenance = Provenance::PendingWrite;
            v.at_ms = at_ms;
        }
    }

    pub fn apply_bgm_mode(&mut self, enabled: bool, room: u8, at_ms: u64) {
        self.bgm_mode = Some(Value { value: (enabled, room), provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_cinema_mode(&mut self, enabled: bool, at_ms: u64) {
        self.cinema_mode =
            Some(Value { value: enabled, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    /// The listening mode, once both underlying settings have been read.
    ///
    /// Both are required: with only one known, a device that is currently in
    /// the unknown mode would be misreported as "Standard".
    pub fn listening(&self) -> Option<crate::protocol::ListeningState> {
        let bgm = self.bgm_mode.as_ref()?.value;
        let cinema = self.cinema_mode.as_ref()?.value;
        Some(crate::protocol::ListeningState {
            bgm_on: bgm.0,
            room: bgm.1,
            cinema_on: cinema,
        })
    }

    /// Mark both listening settings as locally written but unconfirmed.
    pub fn mark_listening_pending(
        &mut self,
        mode: crate::protocol::ListeningMode,
        at_ms: u64,
    ) {
        if let Some(v) = self.bgm_mode.as_mut() {
            v.value.0 = mode == crate::protocol::ListeningMode::Bgm;
            v.provenance = Provenance::PendingWrite;
            v.at_ms = at_ms;
        }
        if let Some(v) = self.cinema_mode.as_mut() {
            v.value = mode == crate::protocol::ListeningMode::Cinema;
            v.provenance = Provenance::PendingWrite;
            v.at_ms = at_ms;
        }
    }

    pub fn apply_upscaling(&mut self, enabled: bool, at_ms: u64) {
        self.upscaling = Some(Value { value: enabled, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_source_switch(&mut self, value: u8, at_ms: u64) {
        self.source_switch =
            Some(Value { value, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_music_hand_over(&mut self, enabled: bool, at_ms: u64) {
        self.music_hand_over =
            Some(Value { value: enabled, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_paired_devices(
        &mut self,
        list: crate::protocol::PairingDeviceList,
        at_ms: u64,
    ) {
        self.paired_devices =
            Some(Value { value: list, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_pairing_capability(
        &mut self,
        capability: crate::protocol::PairingCapability,
        at_ms: u64,
    ) {
        self.pairing_capability =
            Some(Value { value: capability, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_pairing_mode(
        &mut self,
        status: crate::protocol::PairingModeStatus,
        at_ms: u64,
    ) {
        self.pairing_mode =
            Some(Value { value: status, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_pairing_event(
        &mut self,
        event: crate::protocol::PairingConnectionEvent,
        at_ms: u64,
    ) {
        if crate::protocol::pairing_result_is_success(event.result) {
            if let Some(list) = self.paired_devices.as_mut() {
                if let Some(device) =
                    list.value.devices.iter_mut().find(|d| d.address == event.address)
                {
                    match event.action {
                        crate::protocol::pairing_action::CONNECT => device.connected = true,
                        crate::protocol::pairing_action::DISCONNECT => device.connected = false,
                        crate::protocol::pairing_action::UNPAIR => {
                            list.value.devices.retain(|d| d.address != event.address);
                        }
                        _ => {}
                    }
                }
            }
        }
        self.last_pairing_event =
            Some(Value { value: event, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    /// Mark music hand-over as written but not yet confirmed.
    pub fn mark_music_hand_over_pending(&mut self, enabled: bool, at_ms: u64) {
        if let Some(v) = self.music_hand_over.as_mut() {
            v.value = enabled;
            v.provenance = Provenance::PendingWrite;
            v.at_ms = at_ms;
        }
    }

    pub fn apply_usb_submersion(&mut self, submerged: bool, at_ms: u64) {
        self.usb_submersion =
            Some(Value { value: submerged, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_playback(
        &mut self,
        playback: crate::protocol::PlaybackState,
        at_ms: u64,
    ) {
        self.playback = Some(Value { value: playback, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_wearing_status(
        &mut self,
        status: crate::protocol::WearingStatus,
        at_ms: u64,
    ) {
        self.wearing_status = Some(Value { value: status, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_wearing_code(&mut self, code: u8, at_ms: u64) {
        // Re-read every few seconds: only a change is news.
        let changed = self.wearing_code.as_ref().map(|v| v.value) != Some(code);
        self.wearing_code = Some(Value { value: code, provenance: Provenance::Device, at_ms });
        if changed {
            self.revision += 1;
        }
    }

    pub fn apply_auto_power_off_wearing(&mut self, elements: (u8, u8), at_ms: u64) {
        self.auto_power_off_wearing =
            Some(Value { value: elements, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_auto_power_off_wearing_enabled(&mut self, enabled: bool, at_ms: u64) {
        self.auto_power_off_wearing_enabled =
            Some(Value { value: enabled, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_ble_setup(&mut self, addr: String, id: String, at_ms: u64) {
        self.ble_setup =
            Some(Value { value: (addr, id), provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_repeat_tap_status(&mut self, status: u8, at_ms: u64) {
        self.repeat_tap_status =
            Some(Value { value: status, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_sar_capability(&mut self, count: u8, at_ms: u64) {
        self.sar_capability =
            Some(Value { value: count, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_gatt_connectable(&mut self, enabled: bool, at_ms: u64) {
        self.gatt_connectable =
            Some(Value { value: enabled, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_sar_optimization(&mut self, enabled: bool, status: u8, at_ms: u64) {
        self.sar_optimization =
            Some(Value { value: (enabled, status), provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_auto_play_capability(&mut self, value: u16, at_ms: u64) {
        self.auto_play_capability =
            Some(Value { value, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    /// Merge the status reply (on/off + effect).
    pub fn apply_safe_volume_level(&mut self, level: u8, at_ms: u64) {
        self.safe_volume_level =
            Some(Value { value: level, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn mark_safe_volume_pending(&mut self, level: u8, at_ms: u64) {
        if let Some(v) = self.safe_volume_level.as_mut() {
            v.value = level;
            v.provenance = Provenance::PendingWrite;
            v.at_ms = at_ms;
        }
    }

    pub fn apply_quick_access_result(&mut self, result: u8, at_ms: u64) {
        self.quick_access_result =
            Some(Value { value: result, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_quick_access(&mut self, functions: Vec<u8>, at_ms: u64) {
        self.quick_access =
            Some(Value { value: functions, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_head_gesture_training(&mut self, status: u8, enabled: bool, at_ms: u64) {
        self.head_gesture_training =
            Some(Value { value: (status, enabled), provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_head_gesture_action(&mut self, action: u8, at_ms: u64) {
        self.head_gesture_action =
            Some(Value { value: action, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_head_gesture(&mut self, enabled: bool, at_ms: u64) {
        self.head_gesture = Some(Value { value: enabled, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn mark_head_gesture_pending(&mut self, enabled: bool, at_ms: u64) {
        if let Some(v) = self.head_gesture.as_mut() {
            v.value = enabled;
            v.provenance = Provenance::PendingWrite;
            v.at_ms = at_ms;
        }
    }

    pub fn apply_smart_talking_status(&mut self, enabled: bool, effect: u8, at_ms: u64) {
        let mut st = self
            .smart_talking
            .as_ref()
            .map(|v| v.value)
            .unwrap_or_default();
        st.enabled = enabled;
        st.effect = effect;
        self.smart_talking = Some(Value { value: st, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    /// Merge the param reply (on/off + preview).
    pub fn apply_smart_talking_param(&mut self, enabled: bool, at_ms: u64) {
        let mut st = self
            .smart_talking
            .as_ref()
            .map(|v| v.value)
            .unwrap_or_default();
        st.enabled = enabled;
        self.smart_talking = Some(Value { value: st, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    /// Merge the ext-param reply (sensitivity + auto-off time).
    pub fn apply_smart_talking_ext(&mut self, sensitivity: u8, mode_out: u8, at_ms: u64) {
        let mut st = self
            .smart_talking
            .as_ref()
            .map(|v| v.value)
            .unwrap_or_default();
        st.sensitivity = sensitivity;
        st.mode_out = mode_out;
        self.smart_talking = Some(Value { value: st, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn mark_smart_talking_detail_pending(
        &mut self,
        sensitivity: u8,
        mode_out: u8,
        at_ms: u64,
    ) {
        if let Some(v) = self.smart_talking.as_mut() {
            v.value.sensitivity = sensitivity;
            v.value.mode_out = mode_out;
            v.provenance = Provenance::PendingWrite;
            v.at_ms = at_ms;
        }
    }

    pub fn mark_smart_talking_pending(&mut self, enabled: bool, at_ms: u64) {
        if let Some(v) = self.smart_talking.as_mut() {
            v.value.enabled = enabled;
            v.provenance = Provenance::PendingWrite;
            v.at_ms = at_ms;
        }
    }

    pub fn apply_auto_standby(&mut self, available: bool, at_ms: u64) {
        self.auto_standby =
            Some(Value { value: available, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_auto_standby_enabled(&mut self, enabled: bool, at_ms: u64) {
        self.auto_standby_enabled =
            Some(Value { value: enabled, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    /// Mark the auto-standby setting as written but unconfirmed.
    pub fn mark_auto_standby_pending(&mut self, enabled: bool, at_ms: u64) {
        if let Some(v) = self.auto_standby_enabled.as_mut() {
            v.value = enabled;
            v.provenance = Provenance::PendingWrite;
            v.at_ms = at_ms;
        }
    }

    pub fn apply_auto_volume(&mut self, enabled: bool, at_ms: u64) {
        self.auto_volume = Some(Value { value: enabled, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_auto_power_off(&mut self, enabled: bool, at_ms: u64) {
        self.auto_power_off = Some(Value { value: enabled, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_connection_mode(&mut self, mode: (bool, bool), at_ms: u64) {
        self.connection_mode = Some(Value { value: mode, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_supported_functions(&mut self, functions: Vec<u8>, _at_ms: u64) {
        self.supported_functions = functions;
        self.revision += 1;
    }

    pub fn apply_alert(&mut self, alert: (u8, u8, u8), at_ms: u64) {
        self.last_alert =
            Some(Value { value: alert, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_sense_control(&mut self, started: bool, at_ms: u64) {
        self.adaptive_control_started =
            Some(Value { value: started, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_sense_parameter(
        &mut self,
        parameter: crate::protocol::SenseParameter,
        at_ms: u64,
    ) {
        self.adaptive_parameter =
            Some(Value { value: parameter, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn mark_sense_control_pending(&mut self, started: bool, at_ms: u64) {
        if let Some(v) = self.adaptive_control_started.as_mut() {
            v.value = started;
            v.provenance = Provenance::PendingWrite;
            v.at_ms = at_ms;
        } else {
            self.adaptive_control_started = Some(Value {
                value: started,
                provenance: Provenance::PendingWrite,
                at_ms,
            });
        }
    }

    pub fn apply_sense_capability(&mut self, bytes: Vec<u8>, at_ms: u64) {
        self.adaptive_control_capability =
            Some(Value { value: bytes, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_control_by_wearing(&mut self, enabled: bool, at_ms: u64) {
        self.control_by_wearing =
            Some(Value { value: enabled, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_control_by_wearing_available(&mut self, available: bool, at_ms: u64) {
        self.control_by_wearing_available =
            Some(Value { value: available, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn mark_control_by_wearing_pending(&mut self, enabled: bool, at_ms: u64) {
        if let Some(v) = self.control_by_wearing.as_mut() {
            v.value = enabled;
            v.provenance = Provenance::PendingWrite;
            v.at_ms = at_ms;
        }
    }

    pub fn apply_mic_on_off(&mut self, enabled: bool, sound_effect: bool, at_ms: u64) {
        self.mic_on_off =
            Some(Value { value: enabled, provenance: Provenance::Device, at_ms });
        self.mic_off_sound_effect =
            Some(Value { value: sound_effect, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn mark_mic_on_off_pending(&mut self, enabled: bool, at_ms: u64) {
        if let Some(v) = self.mic_on_off.as_mut() {
            v.value = enabled;
            v.provenance = Provenance::PendingWrite;
            v.at_ms = at_ms;
        }
    }

    pub fn apply_mic_key_type(&mut self, key_type: u8, at_ms: u64) {
        self.mic_key_type =
            Some(Value { value: key_type, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_sony_voice_assistant(&mut self, enabled: bool, at_ms: u64) {
        self.sony_voice_assistant =
            Some(Value { value: enabled, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn mark_sony_voice_assistant_pending(&mut self, enabled: bool, at_ms: u64) {
        if let Some(v) = self.sony_voice_assistant.as_mut() {
            v.value = enabled;
            v.provenance = Provenance::PendingWrite;
            v.at_ms = at_ms;
        }
    }

    pub fn apply_sony_voice_assistant_language(&mut self, language: u8, at_ms: u64) {
        self.sony_voice_assistant_language =
            Some(Value { value: language, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_le_audio_switch_compat(&mut self, version: u8, at_ms: u64) {
        self.le_audio_switch_compat =
            Some(Value { value: version, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_link_auto_switch(&mut self, value: (bool, u16, String), at_ms: u64) {
        self.link_auto_switch =
            Some(Value { value, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_voice_guidance(&mut self, enabled: bool, at_ms: u64) {
        self.voice_guidance =
            Some(Value { value: enabled, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn mark_voice_guidance_pending(&mut self, enabled: bool, at_ms: u64) {
        if let Some(v) = self.voice_guidance.as_mut() {
            v.value = enabled;
            v.provenance = Provenance::PendingWrite;
            v.at_ms = at_ms;
        }
    }

    pub fn apply_voice_guidance_language(&mut self, language: u8, at_ms: u64) {
        self.voice_guidance_language =
            Some(Value { value: language, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_voice_guidance_status_raw(&mut self, pair: (u8, u8), at_ms: u64) {
        self.voice_guidance_status_raw =
            Some(Value { value: pair, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_voice_guidance_volume(&mut self, volume: i8, at_ms: u64) {
        self.voice_guidance_volume =
            Some(Value { value: volume, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn mark_voice_guidance_volume_pending(&mut self, volume: i8, at_ms: u64) {
        if let Some(v) = self.voice_guidance_volume.as_mut() {
            v.value = volume;
            v.provenance = Provenance::PendingWrite;
            v.at_ms = at_ms;
        }
    }

    pub fn apply_voice_assistant_capability(&mut self, supported: Vec<u8>, at_ms: u64) {
        let mut setting = self
            .voice_assistant
            .as_ref()
            .map(|v| v.value.clone())
            .unwrap_or_default();
        setting.supported = supported;
        self.voice_assistant =
            Some(Value { value: setting, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_voice_assistant(&mut self, current: u8, at_ms: u64) {
        let mut setting = self
            .voice_assistant
            .as_ref()
            .map(|v| v.value.clone())
            .unwrap_or_default();
        setting.current = current;
        self.voice_assistant =
            Some(Value { value: setting, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    pub fn apply_codec(&mut self, codec: String, at_ms: u64) {
        self.codec = Some(Value { value: codec, provenance: Provenance::Device, at_ms });
        self.revision += 1;
    }

    /// Merge a slot description from the device's capability response.
    pub fn apply_gs_capability(&mut self, setting: crate::protocol::GsSetting, _at_ms: u64) {
        if let Some(existing) = self.general_settings.iter_mut().find(|s| s.gs_type == setting.gs_type) {
            existing.label = setting.label;
            existing.summary = setting.summary;
        } else {
            self.general_settings.push(setting);
            self.general_settings.sort_by_key(|s| s.gs_type);
        }
        self.revision += 1;
    }

    /// Merge a slot's boolean value.
    pub fn apply_gs_value(&mut self, gs_type: u8, on: bool, _at_ms: u64) {
        if let Some(existing) = self.general_settings.iter_mut().find(|s| s.gs_type == gs_type) {
            existing.value = Some(on);
            self.revision += 1;
        }
    }

    /// Record a write we just sent. The value is not trusted until confirmed.
    pub fn mark_noise_control_pending(&mut self, nc: NoiseControl, at_ms: u64) {
        self.noise_control = Some(Value { value: nc, provenance: Provenance::PendingWrite, at_ms });
        self.revision += 1;
    }

    /// True when a local write is still awaiting device confirmation.
    pub fn has_pending_write(&self) -> bool {
        let nc_pending = self
            .noise_control
            .as_ref()
            .map(|v| v.provenance == Provenance::PendingWrite)
            .unwrap_or(false);
        let eq_pending = self
            .equalizer
            .as_ref()
            .map(|v| v.provenance == Provenance::PendingWrite)
            .unwrap_or(false);
        let up_pending = self
            .upscaling
            .as_ref()
            .map(|v| v.provenance == Provenance::PendingWrite)
            .unwrap_or(false);
        let listen_pending = self
            .bgm_mode
            .as_ref()
            .map(|v| v.provenance == Provenance::PendingWrite)
            .unwrap_or(false)
            || self
                .cinema_mode
                .as_ref()
                .map(|v| v.provenance == Provenance::PendingWrite)
                .unwrap_or(false);
        let mho_pending = self
            .music_hand_over
            .as_ref()
            .map(|v| v.provenance == Provenance::PendingWrite)
            .unwrap_or(false);
        let volume_pending = self
            .music_volume
            .as_ref()
            .map(|v| v.provenance == Provenance::PendingWrite)
            .unwrap_or(false)
            || self
                .call_volume
                .as_ref()
                .map(|v| v.provenance == Provenance::PendingWrite)
                .unwrap_or(false);
        let standby_pending = self
            .auto_standby_enabled
            .as_ref()
            .map(|v| v.provenance == Provenance::PendingWrite)
            .unwrap_or(false);
        let st_pending = self
            .smart_talking
            .as_ref()
            .map(|v| v.provenance == Provenance::PendingWrite)
            .unwrap_or(false)
            || self
                .head_gesture
                .as_ref()
                .map(|v| v.provenance == Provenance::PendingWrite)
                .unwrap_or(false);
        let cbw_pending = self
            .control_by_wearing
            .as_ref()
            .map(|v| v.provenance == Provenance::PendingWrite)
            .unwrap_or(false);
        let mic_pending = self
            .mic_on_off
            .as_ref()
            .map(|v| v.provenance == Provenance::PendingWrite)
            .unwrap_or(false);
        let sv_pending = self
            .sony_voice_assistant
            .as_ref()
            .map(|v| v.provenance == Provenance::PendingWrite)
            .unwrap_or(false);
        let vg_pending = self
            .voice_guidance
            .as_ref()
            .map(|v| v.provenance == Provenance::PendingWrite)
            .unwrap_or(false)
            || self
                .voice_guidance_volume
                .as_ref()
                .map(|v| v.provenance == Provenance::PendingWrite)
                .unwrap_or(false);
        nc_pending
            || cbw_pending
            || mic_pending
            || sv_pending
            || vg_pending
            || eq_pending
            || up_pending
            || listen_pending
            || mho_pending
            || volume_pending
            || standby_pending
            || st_pending
    }

    /// Mark the equaliser as written but not yet confirmed.
    pub fn mark_equalizer_pending(&mut self, at_ms: u64) {
        if let Some(v) = self.equalizer.as_mut() {
            v.provenance = Provenance::PendingWrite;
            v.at_ms = at_ms;
        }
        self.revision += 1;
    }
}

/// A partial equaliser report. Which fields are present depends on the message.
#[derive(Debug, Clone, Default)]
pub struct EqualizerUpdate {
    pub enabled: Option<bool>,
    pub preset: Option<u8>,
    pub band_steps: Option<Vec<u8>>,
    pub clear_bass: Option<i8>,
    pub clear_bass_range: Option<(i8, i8)>,
    pub capability: Option<crate::protocol::EqCapability>,
    pub error_codes: Option<Vec<u8>>,
}

impl EqualizerUpdate {
    fn apply_to(self, eq: &mut Equalizer) {
        if let Some(v) = self.enabled {
            eq.enabled = v;
            eq.status_known = true;
        }
        if let Some(v) = self.error_codes {
            eq.error_codes = v;
        }
        if let Some(v) = self.preset {
            eq.preset = v;
        }
        if let Some(v) = self.band_steps {
            eq.band_steps = v;
        }
        if let Some(v) = self.clear_bass {
            eq.clear_bass = v;
        }
        if let Some((min, max)) = self.clear_bass_range {
            eq.clear_bass_min = min;
            eq.clear_bass_max = max;
        }
        if let Some((count, step, presets)) = self.capability {
            eq.band_count = count;
            eq.band_step = step;
            eq.presets = presets;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn device_frame_upgrades_pending_write() {
        let mut st = DeviceState::new();
        let nc = NoiseControl {
            inquired_type: 0x17,
            enabled: true,
            mode: 1,
            ambient_mode: 1,
            ambient_level: 5,
            adaptation_on: false,
            sensitivity: 0,
        };
        st.mark_noise_control_pending(nc, 10);
        assert!(st.has_pending_write());
        st.apply_noise_control(nc, 20);
        assert!(!st.has_pending_write());
        assert_eq!(st.noise_control.unwrap().provenance, Provenance::Device);
    }

    #[test]
    fn revision_tracks_changes() {
        let mut st = DeviceState::new();
        assert_eq!(st.revision, 0);
        st.apply_battery(
            BatteryStatus { level: 50, charging: 0, inquired_type: 0 },
            1,
        );
        assert_eq!(st.revision, 1);
    }

    #[test]
    fn cached_values_go_stale() {
        let v = Value { value: 1u8, provenance: Provenance::Cached, at_ms: 100 };
        assert!(!v.is_stale(150, 100));
        assert!(v.is_stale(500, 100));
    }
}
