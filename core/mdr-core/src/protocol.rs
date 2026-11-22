//! MDR version 2 command surface and payload codecs.
//!
//! Command values and payload layouts for the MDR protocol, cross-checked
//! against the MIT-licensed `libmdr` project and against real headphones.
//! Nothing here is guessed.
//!
//! A V2 payload is always `command:u8` followed by an *inquired type* byte for
//! feature families that multiplex several shapes over one command.

/// Command identifiers, table 1 (the common table).
pub mod cmd {
    // Connection / session
    pub const CONNECT_GET_PROTOCOL_INFO: u8 = 0x00;
    pub const CONNECT_RET_PROTOCOL_INFO: u8 = 0x01;
    pub const CONNECT_GET_CAPABILITY_INFO: u8 = 0x02;
    pub const CONNECT_RET_CAPABILITY_INFO: u8 = 0x03;
    pub const CONNECT_GET_DEVICE_INFO: u8 = 0x04;
    pub const CONNECT_RET_DEVICE_INFO: u8 = 0x05;
    pub const CONNECT_GET_SUPPORT_FUNCTION: u8 = 0x06;
    pub const CONNECT_RET_SUPPORT_FUNCTION: u8 = 0x07;

    // Common
    pub const COMMON_GET_CAPABILITY: u8 = 0x10;
    pub const COMMON_RET_CAPABILITY: u8 = 0x11;
    pub const COMMON_GET_STATUS: u8 = 0x12;
    pub const COMMON_RET_STATUS: u8 = 0x13;
    pub const COMMON_NTFY_STATUS: u8 = 0x15;
    pub const COMMON_SET_PARAM: u8 = 0x18;
    pub const COMMON_NTFY_PARAM: u8 = 0x19;

    // Power / battery
    pub const POWER_GET_CAPABILITY: u8 = 0x20;
    pub const POWER_RET_CAPABILITY: u8 = 0x21;
    pub const POWER_GET_STATUS: u8 = 0x22;
    pub const POWER_RET_STATUS: u8 = 0x23;
    pub const POWER_SET_STATUS: u8 = 0x24;
    pub const POWER_NTFY_STATUS: u8 = 0x25;
    pub const POWER_GET_PARAM: u8 = 0x26;
    pub const POWER_RET_PARAM: u8 = 0x27;
    pub const POWER_SET_PARAM: u8 = 0x28;
    pub const POWER_NTFY_PARAM: u8 = 0x29;

    // Equalizer / EBB (Clear Bass)
    pub const EQEBB_GET_CAPABILITY: u8 = 0x50;
    pub const EQEBB_RET_CAPABILITY: u8 = 0x51;
    pub const EQEBB_GET_STATUS: u8 = 0x52;
    pub const EQEBB_RET_STATUS: u8 = 0x53;
    pub const EQEBB_NTFY_STATUS: u8 = 0x55;
    pub const EQEBB_GET_PARAM: u8 = 0x56;
    pub const EQEBB_RET_PARAM: u8 = 0x57;
    pub const EQEBB_SET_PARAM: u8 = 0x58;
    pub const EQEBB_NTFY_PARAM: u8 = 0x59;
    pub const EQEBB_GET_EXTENDED_INFO: u8 = 0x5A;
    pub const EQEBB_RET_EXTENDED_INFO: u8 = 0x5B;

    // Noise cancelling / ambient sound
    pub const NCASM_GET_CAPABILITY: u8 = 0x60;
    pub const NCASM_RET_CAPABILITY: u8 = 0x61;
    pub const NCASM_GET_STATUS: u8 = 0x62;
    pub const NCASM_RET_STATUS: u8 = 0x63;
    pub const NCASM_SET_STATUS: u8 = 0x64;
    pub const NCASM_NTFY_STATUS: u8 = 0x65;
    pub const NCASM_GET_PARAM: u8 = 0x66;
    pub const NCASM_RET_PARAM: u8 = 0x67;
    pub const NCASM_SET_PARAM: u8 = 0x68;
    pub const NCASM_NTFY_PARAM: u8 = 0x69;

    // Alerts (fixed messages pushed by the device)
    pub const ALERT_NTFY_PARAM: u8 = 0x99;
    pub const ALERT_NTFY_STATUS: u8 = 0x95;

    // Sense (wear detection, speak-to-chat and friends)
    pub const SENSE_GET_CAPABILITY: u8 = 0x70;
    pub const SENSE_RET_CAPABILITY: u8 = 0x71;
    pub const SENSE_GET_PARAM: u8 = 0x76;
    pub const SENSE_RET_PARAM: u8 = 0x77;
    pub const SENSE_SET_STATUS: u8 = 0x74;
    pub const SENSE_NTFY_STATUS: u8 = 0x75;
    pub const SENSE_SET_PARAM: u8 = 0x78;
    pub const SENSE_NTFY_PARAM: u8 = 0x79;
    pub const SENSE_GET_EXT_INFO: u8 = 0x7A;
    pub const SENSE_RET_EXT_INFO: u8 = 0x7B;

    // General settings
    pub const GENERAL_SETTING_GET_CAPABILITY: u8 = 0xD0;
    pub const GENERAL_SETTING_RET_CAPABILITY: u8 = 0xD1;
    pub const GENERAL_SETTING_GET_STATUS: u8 = 0xD2;
    pub const GENERAL_SETTING_RET_STATUS: u8 = 0xD3;
    pub const GENERAL_SETTING_NTFY_STATUS: u8 = 0xD5;
    pub const GENERAL_SETTING_GET_PARAM: u8 = 0xD6;
    pub const GENERAL_SETTING_RET_PARAM: u8 = 0xD7;
    pub const GENERAL_SETTING_SET_PARAM: u8 = 0xD8;
    pub const GENERAL_SETTING_NTFY_PARAM: u8 = 0xD9;

    // System (voice assistant, wearing detection, quick access)
    pub const SYSTEM_GET_CAPABILITY: u8 = 0xF0;
    pub const SYSTEM_RET_CAPABILITY: u8 = 0xF1;
    pub const SYSTEM_GET_STATUS: u8 = 0xF2;
    pub const SYSTEM_RET_STATUS: u8 = 0xF3;
    pub const SYSTEM_SET_STATUS: u8 = 0xF4;
    pub const SYSTEM_NTFY_STATUS: u8 = 0xF5;
    pub const SYSTEM_GET_PARAM: u8 = 0xF6;
    pub const SYSTEM_RET_PARAM: u8 = 0xF7;
    pub const SYSTEM_SET_PARAM: u8 = 0xF8;
    pub const SYSTEM_NTFY_PARAM: u8 = 0xF9;
    pub const SYSTEM_GET_EXT_PARAM: u8 = 0xFA;
    pub const SYSTEM_RET_EXT_PARAM: u8 = 0xFB;
    pub const SYSTEM_SET_EXT_PARAM: u8 = 0xFC;
    pub const SYSTEM_NTFY_EXT_PARAM: u8 = 0xFD;

    // LE Audio (table 2)
    pub const LEA_GET_CAPABILITY: u8 = 0x60;
    pub const LEA_RET_CAPABILITY: u8 = 0x61;

    // Voice guidance (table 2)
    pub const VOICE_GUIDANCE_GET_CAPABILITY: u8 = 0x40;
    pub const VOICE_GUIDANCE_RET_CAPABILITY: u8 = 0x41;
    pub const VOICE_GUIDANCE_GET_STATUS: u8 = 0x42;
    pub const VOICE_GUIDANCE_RET_STATUS: u8 = 0x43;
    pub const VOICE_GUIDANCE_SET_STATUS: u8 = 0x44;
    pub const VOICE_GUIDANCE_NTFY_STATUS: u8 = 0x45;
    pub const VOICE_GUIDANCE_GET_PARAM: u8 = 0x46;
    pub const VOICE_GUIDANCE_RET_PARAM: u8 = 0x47;
    pub const VOICE_GUIDANCE_SET_PARAM: u8 = 0x48;
    pub const VOICE_GUIDANCE_NTFY_PARAM: u8 = 0x49;

    // Safe listening (table 2)
    pub const SAFE_LISTENING_SET_STATUS: u8 = 0x54;
    pub const SAFE_LISTENING_GET_PARAM: u8 = 0x56;
    pub const SAFE_LISTENING_RET_PARAM: u8 = 0x57;
    pub const SAFE_LISTENING_NTFY_PARAM: u8 = 0x59;

    // SAR / auto-play / GATT diagnostics
    pub const SAR_GET_CAPABILITY: u8 = 0xB0;
    pub const SAR_RET_CAPABILITY: u8 = 0xB1;
    pub const SAR_GET_STATUS: u8 = 0xB2;
    pub const SAR_RET_STATUS: u8 = 0xB3;

    // Table-2 peripheral (multipoint, music hand-over)
    pub const PERI_GET_CAPABILITY: u8 = 0x30;
    pub const PERI_RET_CAPABILITY: u8 = 0x31;
    pub const PERI_GET_STATUS: u8 = 0x32;
    pub const PERI_RET_STATUS: u8 = 0x33;
    pub const PERI_SET_STATUS: u8 = 0x34;
    pub const PERI_NTFY_STATUS: u8 = 0x35;
    pub const PERI_GET_PARAM: u8 = 0x36;
    pub const PERI_RET_PARAM: u8 = 0x37;
    pub const PERI_SET_PARAM: u8 = 0x38;
    pub const PERI_NTFY_PARAM: u8 = 0x39;
    /// Pairing connection control (V2 shape: `3C 00 <action> <address>`).
    pub const PERI_SET_EX_PARAM: u8 = 0x3C;
    pub const PERI_NTFY_EX_PARAM: u8 = 0x3D;

    // Playback
    pub const PLAY_GET_CAPABILITY: u8 = 0xA0;
    pub const PLAY_RET_CAPABILITY: u8 = 0xA1;
    pub const PLAY_GET_STATUS: u8 = 0xA2;
    pub const PLAY_RET_STATUS: u8 = 0xA3;
    pub const PLAY_SET_STATUS: u8 = 0xA4;
    pub const PLAY_NTFY_STATUS: u8 = 0xA5;
    pub const PLAY_GET_PARAM: u8 = 0xA6;
    pub const PLAY_RET_PARAM: u8 = 0xA7;
    pub const PLAY_SET_PARAM: u8 = 0xA8;
    pub const PLAY_NTFY_PARAM: u8 = 0xA9;

    // Audio (codec, upmix, ...)
    pub const AUDIO_GET_CAPABILITY: u8 = 0xE0;
    pub const AUDIO_RET_CAPABILITY: u8 = 0xE1;
    pub const AUDIO_GET_STATUS: u8 = 0xE2;
    pub const AUDIO_RET_STATUS: u8 = 0xE3;
    pub const AUDIO_SET_STATUS: u8 = 0xE4;
    pub const AUDIO_NTFY_STATUS: u8 = 0xE5;
    pub const AUDIO_GET_PARAM: u8 = 0xE6;
    pub const AUDIO_RET_PARAM: u8 = 0xE7;
    pub const AUDIO_SET_PARAM: u8 = 0xE8;
    pub const AUDIO_NTFY_PARAM: u8 = 0xE9;
}

/// `AudioInquiredType` values used by the listening-mode shapes.
///
/// `BGM_MODE_AND_ERRORCODE` is what the WH-1000XM6 advertises; the legacy
/// `BGM_MODE` shape is the same setter without the status extension.
pub mod audio_type {
    pub const UPSCALING: u8 = 0x01;
    pub const BGM_MODE: u8 = 0x03;
    pub const UPMIX_CINEMA: u8 = 0x04;
    pub const BGM_MODE_AND_ERRORCODE: u8 = 0x09;
}

/// `RoomSize` inside the BGM setter.
pub mod room_size {
    pub const SMALL: u8 = 0x00;
    pub const MIDDLE: u8 = 0x01;
    pub const LARGE: u8 = 0x02;
}

/// `PowerInquiredType` — selects the battery shape.
pub mod power_type {
    pub const BATTERY: u8 = 0x00;
    pub const LEFT_RIGHT_BATTERY: u8 = 0x01;
    pub const CRADLE_BATTERY: u8 = 0x02;
    pub const POWER_OFF: u8 = 0x03;
    pub const AUTO_POWER_OFF: u8 = 0x04;
    pub const BATTERY_WITH_THRESHOLD: u8 = 0x08;
    pub const LR_BATTERY_WITH_THRESHOLD: u8 = 0x09;
    pub const BATTERY_SAFE_MODE: u8 = 0x0B;
    pub const BT_STANDBY: u8 = 0x0D;
}

/// `PlayInquiredType` — selects the playback shape.
pub mod play_type {
    pub const PLAYBACK_CONTROLLER: u8 = 0x01;
    pub const PLAYBACK_CONTROLLER_WITH_FUNCTION_CHANGE: u8 = 0x03;
    pub const MUSIC_VOLUME: u8 = 0x20;
    pub const CALL_VOLUME: u8 = 0x21;
    pub const PLAY_MODE: u8 = 0x40;
}

/// `PLAY_GET_CAPABILITY` for the playback controller.
///
/// The reply carries the number of volume steps for music and calls
/// (`RetPlayCapabilityPlaybackControlWithCallVolumeAdjustment`).
pub fn get_playback_capability() -> Vec<u8> {
    vec![cmd::PLAY_GET_CAPABILITY, play_type::PLAYBACK_CONTROLLER]
}

/// Decode `(music volume steps, call volume steps)`. A zero step count means
/// the device does not expose volume over this shape.
pub fn decode_playback_volume_capability(payload: &[u8]) -> Option<(u8, u8)> {
    if payload.len() != 4 || payload[1] != play_type::PLAYBACK_CONTROLLER {
        return None;
    }
    Some((payload[2], payload[3]))
}

pub fn get_music_volume() -> Vec<u8> {
    vec![cmd::PLAY_GET_PARAM, play_type::MUSIC_VOLUME]
}

/// Decode `PLAY_RET_PARAM` / `PLAY_NTFY_PARAM` for `MUSIC_VOLUME`.
pub fn decode_music_volume(payload: &[u8]) -> Option<u8> {
    if payload.len() != 3 || payload[1] != play_type::MUSIC_VOLUME {
        return None;
    }
    Some(payload[2])
}

/// `PLAY_SET_PARAM` for `MUSIC_VOLUME`.
pub fn set_music_volume(volume: u8) -> Vec<u8> {
    vec![cmd::PLAY_SET_PARAM, play_type::MUSIC_VOLUME, volume]
}

pub fn get_call_volume() -> Vec<u8> {
    vec![cmd::PLAY_GET_PARAM, play_type::CALL_VOLUME]
}

/// Decode `PLAY_RET_PARAM` / `PLAY_NTFY_PARAM` for `CALL_VOLUME`.
pub fn decode_call_volume(payload: &[u8]) -> Option<u8> {
    if payload.len() != 3 || payload[1] != play_type::CALL_VOLUME {
        return None;
    }
    Some(payload[2])
}

/// `PLAY_SET_PARAM` for `CALL_VOLUME`.
pub fn set_call_volume(volume: u8) -> Vec<u8> {
    vec![cmd::PLAY_SET_PARAM, play_type::CALL_VOLUME, volume]
}

/// `PlaybackControl` — the action in `PLAY_SET_STATUS`.
pub mod playback_control {
    pub const KEY_OFF: u8 = 0x00;
    pub const PAUSE: u8 = 0x01;
    pub const TRACK_UP: u8 = 0x02;
    pub const TRACK_DOWN: u8 = 0x03;
    pub const GROUP_UP: u8 = 0x04;
    pub const GROUP_DOWN: u8 = 0x05;
    pub const STOP: u8 = 0x06;
    pub const PLAY: u8 = 0x07;
    pub const FAST_FORWARD: u8 = 0x08;
    pub const FAST_REWIND: u8 = 0x09;
}

/// `PeripheralInquiredType` (table 2).
pub mod peri_type {
    /// `PAIRING_DEVICE_MANAGEMENT_CLASSIC_BT` (no Class-of-Device field).
    pub const PAIRING_DEVICE_MANAGEMENT: u8 = 0x00;
    pub const SOURCE_SWITCH_CONTROL: u8 = 0x01;
    /// Same device list plus the 24-bit Bluetooth Class of Device.
    pub const PAIRING_DEVICE_MANAGEMENT_WITH_COD: u8 = 0x02;
    pub const MUSIC_HAND_OVER_SETTING: u8 = 0x03;
}

/// `ConnectivityActionType` in the pairing connection control.
pub mod pairing_action {
    pub const DISCONNECT: u8 = 0x00;
    pub const CONNECT: u8 = 0x01;
    /// Present in the V2 enum; deliberately not exposed by the app.
    pub const UNPAIR: u8 = 0x02;
}

/// `PeripheralBluetoothMode` for `PERI_SET_STATUS`.
pub mod pairing_mode {
    pub const NORMAL: u8 = 0x00;
    pub const INQUIRY_SCAN: u8 = 0x01;
}

/// `ResultType` for pairing connection notifications.
pub mod pairing_result {
    pub const DISCONNECTION_SUCCESS: u8 = 0x00;
    pub const DISCONNECTION_ERROR: u8 = 0x01;
    pub const DISCONNECTION_IN_PROGRESS: u8 = 0x02;
    pub const DISCONNECTION_BUSY: u8 = 0x03;
    pub const CONNECTION_SUCCESS: u8 = 0x10;
    pub const CONNECTION_ERROR: u8 = 0x11;
    pub const CONNECTION_IN_PROGRESS: u8 = 0x12;
    pub const CONNECTION_BUSY: u8 = 0x13;
    pub const UNPAIRING_SUCCESS: u8 = 0x20;
    pub const UNPAIRING_ERROR: u8 = 0x21;
    pub const UNPAIRING_IN_PROGRESS: u8 = 0x22;
    pub const UNPAIRING_BUSY: u8 = 0x23;
}

/// `SystemInquiredType` (table 2).
pub mod system_type {
    pub const REPEAT_TAP_TRAINING_MODE: u8 = 0x01;
    pub const AUTO_VOLUME_WITH_LIMITATION: u8 = 0x04;
    pub const WEARING_STATUS_DETECTOR: u8 = 0x06;
    /// Table-set 2 Speak-to-Chat (`SMART_TALKING_MODE_TYPE2`).
    pub const SMART_TALKING_MODE_TYPE2: u8 = 0x0C;
    /// Playback control by wearing/removing the headphones.
    pub const CONTROL_BY_WEARING: u8 = 0x01;
    /// Head gesture on/off (nod to answer/end a call).
    pub const HEAD_GESTURE_ON_OFF: u8 = 0x0F;
    /// Head gesture training mode (start/finish, status and action notifications).
    pub const HEAD_GESTURE_TRAINING: u8 = 0x10;
    /// Quick Access button assignment.
    pub const QUICK_ACCESS: u8 = 0x0D;
    /// Quick Access easy setting (function list write).
    pub const QUICK_ACCESS_EASY_SETTING: u8 = 0x02;
    /// Sony Voice Assistant on/off and language (table 2).
    pub const SONY_VOICE_ASSISTANT: u8 = 0x05;
    /// Link auto-switch for headsets (table 2).
    pub const LINK_AUTO_SWITCH_FOR_HEADSETS: u8 = 0x0A;
    /// Mic on/off by headphone operation (table 2).
    pub const MIC_ON_OFF_BY_HEADPHONE_OPERATION: u8 = 0x0B;
}

/// `SenseInquiredType` (table 1).
pub mod sense_type {
    pub const ADAPTIVE_CONTROL_WITH_PARAMETER_NOTIFICATION: u8 = 0x01;
}

/// `LEAInquiredType` (table 2, newer enum order).
pub mod lea_type {
    pub const LE_AUDIO_CONNECTION_STATE_NOTIFICATION: u8 = 0x00;
    pub const LE_AUDIO_SWITCH_SUPPORTED_COMPATIBILITY: u8 = 0x01;
}

/// `VoiceGuidanceInquiredType` (table 2).
pub mod voice_guidance_type {
    pub const MTK_TRANSFER_SUPPORT_LANGUAGE_SWITCH: u8 = 0x01;
    pub const ONLY_ON_OFF_SETTING: u8 = 0x03;
    pub const VOLUME: u8 = 0x20;
}

/// `SARAutoPlayInquiredType` (table 1).
pub mod sar_type {
    pub const SAR: u8 = 0x00;
    pub const AUTO_PLAY: u8 = 0x02;
    pub const GATT_CONNECTABLE: u8 = 0x10;
    pub const SAR_OPTIMIZATION: u8 = 0x21;
}

/// `DetectSensitivity` inside the Speak-to-Chat ext param.
/// `SafeListeningInquiredType` (table 2).
pub mod safe_listening_type {
    pub const SAFE_VOLUME_CONTROL: u8 = 0x04;
}

pub mod detect_sensitivity {
    pub const AUTO: u8 = 0x00;
    pub const HIGH: u8 = 0x01;
    pub const LOW: u8 = 0x02;
}

/// `ModeOutTime` inside the Speak-to-Chat ext param.
pub mod mode_out_time {
    pub const FAST: u8 = 0x00;
    pub const MID: u8 = 0x01;
    pub const SLOW: u8 = 0x02;
    pub const NONE: u8 = 0x03;
}

/// `NcAsmInquiredType` — selects the noise-control shape.
pub mod ncasma_type {
    pub const NC_ON_OFF: u8 = 0x01;
    pub const NC_ON_OFF_AND_ASM_ON_OFF: u8 = 0x11;
    pub const NC_MODE_SWITCH_AND_ASM_ON_OFF: u8 = 0x12;
    pub const NC_ON_OFF_AND_ASM_SEAMLESS: u8 = 0x13;
    pub const NC_MODE_SWITCH_AND_ASM_SEAMLESS: u8 = 0x14;
    pub const MODE_NC_ASM_AUTO_NC_MODE_SWITCH_AND_ASM_SEAMLESS: u8 = 0x15;
    pub const MODE_NC_ASM_DUAL_SINGLE_NC_MODE_SWITCH_AND_ASM_SEAMLESS: u8 = 0x16;
    pub const MODE_NC_ASM_DUAL_NC_MODE_SWITCH_AND_ASM_SEAMLESS: u8 = 0x17;
    pub const MODE_NC_NCSS_ASM_DUAL_NC_MODE_SWITCH_AND_ASM_SEAMLESS: u8 = 0x18;
    pub const MODE_NC_ASM_DUAL_NC_MODE_SWITCH_AND_ASM_SEAMLESS_NA: u8 = 0x19;
    pub const ASM_ON_OFF: u8 = 0x21;
    pub const ASM_SEAMLESS: u8 = 0x22;
    pub const NC_AMB_TOGGLE: u8 = 0x30;
}

/// Ambient-sound sub-mode within ASM.
pub mod asm_mode {
    pub const NORMAL: u8 = 0x00;
    pub const VOICE: u8 = 0x01;
}

/// Active noise-control mode.
pub mod nc_mode {
    pub const NC: u8 = 0x00;
    pub const ASM: u8 = 0x01;
}

/// Battery charging state.
pub mod charging {
    pub const NOT_CHARGING: u8 = 0x00;
    pub const CHARGING: u8 = 0x01;
    pub const UNKNOWN: u8 = 0x02;
    pub const CHARGED: u8 = 0x03;
}

/// Value-change indicator carried by many V2 responses.
pub mod value_change {
    pub const UNDER_CHANGING: u8 = 0x00;
    pub const CHANGED: u8 = 0x01;
}

/// Wireless codec reported by the AUDIO family (for the inspector screen).
pub mod codec {
    pub const UNSETTLED: u8 = 0x00;
    pub const SBC: u8 = 0x01;
    pub const AAC: u8 = 0x02;
    pub const LDAC: u8 = 0x10;
    pub const APTX: u8 = 0x20;
    pub const APTX_HD: u8 = 0x21;
    pub const LC3: u8 = 0x30;
}

// ---------------------------------------------------------------------------
// Builders
// ---------------------------------------------------------------------------

/// `ConnectInquiredType` — the only shape the connect family uses.
pub mod connect_type {
    pub const FIXED_VALUE: u8 = 0x00;
}

/// `DeviceInfoType` — which piece of identity to request.
pub mod device_info_type {
    pub const MODEL_NAME: u8 = 0x01;
    pub const FW_VERSION: u8 = 0x02;
    pub const SERIES_AND_COLOR_INFO: u8 = 0x03;
    pub const INSTRUCTION_GUIDE: u8 = 0x04;
}

/// Decoded `CONNECT_RET_PROTOCOL_INFO`.
///
/// Layout: 0 cmd, 1 inquired type, 2..6 protocol version (Int32BE),
/// 6 table-1 support flag, 7 table-2 support flag.
///
/// The two flags use `EnableDisable`, whose encoding is inverted relative to
/// intuition: `ENABLE = 0`, `DISABLE = 1`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ProtocolInfo {
    pub version: u32,
    pub supports_table1: bool,
    pub supports_table2: bool,
}

/// `EnableDisable.ENABLE`.
pub const ENABLE: u8 = 0x00;
/// `EnableDisable.DISABLE`.
pub const DISABLE: u8 = 0x01;

pub fn decode_protocol_info(payload: &[u8]) -> Option<ProtocolInfo> {
    if payload.len() < 8 || payload[0] != cmd::CONNECT_RET_PROTOCOL_INFO {
        return None;
    }
    Some(ProtocolInfo {
        version: u32::from_be_bytes([payload[2], payload[3], payload[4], payload[5]]),
        supports_table1: payload[6] == ENABLE,
        supports_table2: payload[7] == ENABLE,
    })
}

/// Decoded `CONNECT_RET_DEVICE_INFO` for a single identity field.
///
/// Layout: 0 cmd, 1 device-info type, 2 string length, 3.. UTF-8 bytes.
/// It requires
/// `len == payload.len() - 3` and the length byte is unsigned.
pub fn decode_device_info(payload: &[u8]) -> Option<(u8, String)> {
    if payload.len() < 3 || payload[0] != cmd::CONNECT_RET_DEVICE_INFO {
        return None;
    }
    let len = payload[2] as usize;
    if payload.len() < 3 + len {
        return None;
    }
    let text = String::from_utf8_lossy(&payload[3..3 + len]).into_owned();
    Some((payload[1], text))
}

/// Decoded `CONNECT_RET_DEVICE_INFO` of type `SERIES_AND_COLOR_INFO`.
///
/// Layout: 0 cmd, 1 type (`0x03`), 2 `ModelSeries`, 3 `ModelColor`
/// (4 bytes). Not yet observed on hardware.
pub fn decode_series_and_color(payload: &[u8]) -> Option<(u8, u8)> {
    if payload.len() < 4
        || payload[0] != cmd::CONNECT_RET_DEVICE_INFO
        || payload[1] != device_info_type::SERIES_AND_COLOR_INFO
    {
        return None;
    }
    Some((payload[2], payload[3]))
}

/// `EqEbbInquiredType` — selects the equaliser shape.
/// The NC/ASM enquired type this device actually answers.
///
/// From the support list (`MODE_NC_ASM_NOISE_CANCELLING_DUAL_AMBIENT_
/// SOUND_MODE_LEVEL_ADJUSTMENT_NOISE_ADAPTATION`). Asking with `0x17` returns an
/// all-zero payload, which looks like "noise control off" and is wrong.
pub const NCASM_ACTIVE_TYPE: u8 = 0x19;

pub mod eqebb_type {
    pub const PRESET_EQ: u8 = 0x00;
    pub const EBB: u8 = 0x01;
    pub const PRESET_EQ_NONCUSTOMIZABLE: u8 = 0x02;
    pub const PRESET_EQ_AND_ULT_MODE: u8 = 0x03;
    pub const PRESET_EQ_AND_ERRORCODE: u8 = 0x04;
    pub const SOUND_EFFECT: u8 = 0x30;
    pub const CUSTOM_EQ: u8 = 0x31;
    pub const TURN_KEY_EQ: u8 = 0x32;
}

/// `EqPresetId` wire values.
///
/// The gaps are real: 8 to 15, 24 to 31 and 52 to 47 are reserved, and the
/// high ranges are user and artist slots. Names are the
/// product names, which is what a UI needs; the reserved ones are not exposed.
pub mod eq_preset {
    pub const OFF: u8 = 0x00;
    pub const ROCK: u8 = 0x01;
    pub const POP: u8 = 0x02;
    pub const JAZZ: u8 = 0x03;
    pub const DANCE: u8 = 0x04;
    pub const EDM: u8 = 0x05;
    pub const R_AND_B_HIP_HOP: u8 = 0x06;
    pub const ACOUSTIC: u8 = 0x07;
    pub const BRIGHT: u8 = 0x10;
    pub const EXCITED: u8 = 0x11;
    pub const MELLOW: u8 = 0x12;
    pub const RELAXED: u8 = 0x13;
    pub const VOCAL: u8 = 0x14;
    pub const TREBLE: u8 = 0x15;
    pub const BASS: u8 = 0x16;
    pub const SPEECH: u8 = 0x17;
    pub const GAMING_EQ: u8 = 0x20;
    pub const FPS_1: u8 = 0x21;
    pub const FPS_2: u8 = 0x22;
    pub const FPS_3: u8 = 0x23;
    pub const HEAVY: u8 = 0x30;
    pub const CLEAR: u8 = 0x31;
    pub const HARD: u8 = 0x32;
    pub const SOFT: u8 = 0x33;
    pub const CUSTOM: u8 = 0xA0;
    pub const USER_SETTING1: u8 = 0xA1;
    pub const USER_SETTING5: u8 = 0xA5;
    pub const ARTIST_COLLAB1: u8 = 0xB0;
    pub const ARTIST_COLLAB12: u8 = 0xBB;
    pub const UNSPECIFIED: u8 = 0xFF;
}

/// Human name for a preset id, or `None` for a reserved/unassigned value.
///
/// A UI must be able to say "this device offers a preset this build does not
/// know" rather than silently showing the wrong label.
pub fn eq_preset_name(id: u8) -> Option<&'static str> {
    use eq_preset::*;
    Some(match id {
        OFF => "Off",
        ROCK => "Rock",
        POP => "Pop",
        JAZZ => "Jazz",
        DANCE => "Dance",
        EDM => "EDM",
        R_AND_B_HIP_HOP => "R&B / Hip-Hop",
        ACOUSTIC => "Acoustic",
        BRIGHT => "Bright",
        EXCITED => "Excited",
        MELLOW => "Mellow",
        RELAXED => "Relaxed",
        VOCAL => "Vocal",
        TREBLE => "Treble Boost",
        BASS => "Bass Boost",
        SPEECH => "Speech",
        GAMING_EQ => "Gaming",
        FPS_1 => "FPS 1",
        FPS_2 => "FPS 2",
        FPS_3 => "FPS 3",
        HEAVY => "Heavy",
        CLEAR => "Clear",
        HARD => "Hard",
        SOFT => "Soft",
        CUSTOM => "Custom",
        USER_SETTING1 => "User 1",
        0xA2 => "User 2",
        0xA3 => "User 3",
        0xA4 => "User 4",
        USER_SETTING5 => "User 5",
        ARTIST_COLLAB1..=ARTIST_COLLAB12 => "Artist preset",
        _ => return None,
    })
}

/// `POWER_GET_STATUS` for the plain battery shape.
pub fn get_battery() -> Vec<u8> {
    vec![cmd::POWER_GET_STATUS, power_type::BATTERY]
}

/// `CONNECT_GET_PROTOCOL_INFO`.
///
/// Two bytes: the command and `ConnectInquiredType.FIXED_VALUE`. The shipped
/// app's payload class rejects anything else.
pub fn get_protocol_info() -> Vec<u8> {
    vec![cmd::CONNECT_GET_PROTOCOL_INFO, connect_type::FIXED_VALUE]
}

/// `CONNECT_GET_CAPABILITY_INFO`.
pub fn get_capability_info() -> Vec<u8> {
    vec![cmd::CONNECT_GET_CAPABILITY_INFO, connect_type::FIXED_VALUE]
}

/// `CONNECT_GET_DEVICE_INFO` for one identity field.
pub fn get_device_info(info_type: u8) -> Vec<u8> {
    vec![cmd::CONNECT_GET_DEVICE_INFO, info_type]
}

/// `NCASM_GET_PARAM` for the dual-mode + seamless ASM shape.
pub fn get_noise_control(inquired: u8) -> Vec<u8> {
    vec![cmd::NCASM_GET_PARAM, inquired]
}

/// `NCASM_GET_PARAM` for the shape the device actually answers.
pub fn get_noise_control_active() -> Vec<u8> {
    vec![cmd::NCASM_GET_PARAM, NCASM_ACTIVE_TYPE]
}

/// `EQEBB_GET_PARAM` for the preset equaliser shape.
pub fn get_eq_preset() -> Vec<u8> {
    vec![cmd::EQEBB_GET_PARAM, 0x00]
}

// ---------------------------------------------------------------------------
// Decoders
// ---------------------------------------------------------------------------

/// Decoded `POWER_RET_STATUS` / `POWER_NTFY_STATUS` battery report.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BatteryStatus {
    pub level: u8,
    pub charging: u8,
    pub inquired_type: u8,
}

impl BatteryStatus {
    pub fn charging_label(&self) -> &'static str {
        match self.charging {
            charging::NOT_CHARGING => "not charging",
            charging::CHARGING => "charging",
            charging::CHARGED => "charged",
            _ => "unknown",
        }
    }
}

/// Decode a single-battery `POWER_RET_STATUS` / `POWER_NTFY_STATUS` payload.
///
/// Layout (offset → field): 0 cmd, 1 inquired type, 2 level (0..=100),
/// 3 charging status.
pub fn decode_battery(payload: &[u8]) -> Option<BatteryStatus> {
    if payload.len() < 4 {
        return None;
    }
    let level = payload[2];
    if level > 100 {
        return None;
    }
    Some(BatteryStatus { inquired_type: payload[1], level, charging: payload[3] })
}

/// Decoded noise-control state.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct NoiseControl {
    pub inquired_type: u8,
    pub enabled: bool,
    pub mode: u8,
    pub ambient_mode: u8,
    pub ambient_level: u8,
    /// Noise adaptation (auto ambient) on/off, from the NA shape.
    pub adaptation_on: bool,
    /// Noise-adaptation sensitivity step.
    pub sensitivity: u8,
}

impl NoiseControl {
    pub fn is_noise_cancelling(&self) -> bool {
        self.enabled && self.mode == nc_mode::NC
    }

    pub fn is_ambient(&self) -> bool {
        self.enabled && self.mode == nc_mode::ASM
    }

    pub fn focus_on_voice(&self) -> bool {
        self.is_ambient() && self.ambient_mode == asm_mode::VOICE
    }
}

/// Decode an `NCASM_RET_PARAM` / `NCASM_NTFY_PARAM` payload for the seamless
/// dual-mode shapes.
///
/// Layout: 0 cmd, 1 inquired type, 2 value-change status, 3 nc/asm total effect
/// (0 = off, 1 = on), 4 mode (0 = NC, 1 = ASM), 5 ambient sound mode
/// (0 = normal, 1 = voice), 6 ambient level (0..=20).
pub fn decode_noise_control(payload: &[u8]) -> Option<NoiseControl> {
    if payload.len() < 7 {
        return None;
    }
    let level = payload[6];
    if level > 20 {
        return None;
    }
    Some(NoiseControl {
        inquired_type: payload[1],
        enabled: payload[3] == 1,
        mode: payload[4],
        ambient_mode: payload[5],
        ambient_level: level,
        adaptation_on: payload.get(7).map(|b| *b == 1).unwrap_or(false),
        sensitivity: payload.get(8).copied().unwrap_or(0),
    })
}

/// Build an `NCASM_SET_PARAM` for the dual-mode seamless shape.
///
/// `enabled == false` selects "noise control off"; when enabled, `mode`
/// chooses NC vs ASM and `ambient_level` only applies to ASM.
pub fn set_noise_control(
    inquired: u8,
    enabled: bool,
    mode: u8,
    ambient_mode: u8,
    ambient_level: u8,
) -> Vec<u8> {
    vec![
        cmd::NCASM_SET_PARAM,
        inquired,
        value_change::CHANGED,
        if enabled { 0x01 } else { 0x00 },
        mode,
        ambient_mode,
        ambient_level.min(20),
    ]
}

/// Build an `NCASM_SET_PARAM` for the noise-adaptation shape the device uses.
///
/// Nine bytes: command, type, value-change, effect, mode, ambient mode, level,
/// adaptation on/off, sensitivity.
pub fn set_noise_control_active(
    enabled: bool,
    mode: u8,
    ambient_mode: u8,
    ambient_level: u8,
    adaptation_on: bool,
    sensitivity: u8,
) -> Vec<u8> {
    vec![
        cmd::NCASM_SET_PARAM,
        NCASM_ACTIVE_TYPE,
        value_change::CHANGED,
        if enabled { 0x01 } else { 0x00 },
        mode,
        ambient_mode,
        ambient_level.min(20),
        if adaptation_on { 0x01 } else { 0x00 },
        sensitivity,
    ]
}

/// Build a `POWER_GET_STATUS` for left/right battery (buds).
pub fn get_battery_lr() -> Vec<u8> {
    vec![cmd::POWER_GET_STATUS, power_type::LEFT_RIGHT_BATTERY]
}

// ---------------------------------------------------------------------------
// Equaliser
// ---------------------------------------------------------------------------

/// Decoded equaliser state: the preset, its per-band gains, and Clear Bass.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Equalizer {
    pub enabled: bool,
    /// `EqPresetId` wire value.
    pub preset: u8,
    /// Per-band step values, in the order the device reports its bands.
    pub band_steps: Vec<u8>,
    /// Clear Bass level (`EBB`), signed.
    pub clear_bass: i8,
    pub clear_bass_min: i8,
    pub clear_bass_max: i8,
    /// Number of bands the device advertises.
    pub band_count: u8,
    /// Step granularity per band.
    pub band_step: u8,
    /// Presets the device actually offers, as `(wire id, name)`.
    pub presets: Vec<(u8, String)>,
    /// Why the device has the equaliser off (`PresetEqErrorCodeType`),
    /// empty when it is on or did not say.
    pub error_codes: Vec<u8>,
    /// The device has reported `enabled`; until then it is unknown.
    pub status_known: bool,
}

impl Equalizer {
    pub fn preset_name(&self) -> Option<&'static str> {
        eq_preset_name(self.preset)
    }
}

/// `AUDIO_GET_STATUS` for the upscaling shape.
///
/// Verified on a WH-1000XM6: the device answers with `E3 01 <EnableDisable>`.
pub fn get_audio_upscaling() -> Vec<u8> {
    vec![cmd::AUDIO_GET_STATUS, 0x01]
}

/// `AUDIO_SET_STATUS` for the upscaling shape.
pub fn set_audio_upscaling(enabled: bool) -> Vec<u8> {
    vec![cmd::AUDIO_SET_STATUS, 0x01, if enabled { ENABLE } else { DISABLE }]
}

/// Decoded `AUDIO_RET_STATUS` / `AUDIO_NTFY_STATUS` for upscaling.
pub fn decode_audio_upscaling(payload: &[u8]) -> Option<bool> {
    if payload.len() < 3 || payload[1] != 0x01 {
        return None;
    }
    Some(payload[2] == ENABLE)
}

// ---------------------------------------------------------------------------
// Listening modes (BGM / Cinema)
// ---------------------------------------------------------------------------

/// The listening mode a device is actually in.
///
/// `LISTENING_OPTION` (0xE6) is only the shortcut-availability flag and its
/// status is a single `EnableDisable`; it does not name a mode. The mode comes
/// from five separate settings, in this order:
/// BGM, UPMIX_CINEMA, UPMIX_SERIES, VOICE_CONTENTS, SOUND_LEAKAGE_REDUCTION.
/// This build covers the two modes the WH-1000XM6 advertises.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum ListeningMode {
    #[default]
    Normal,
    Bgm,
    Cinema,
}

impl ListeningMode {
    pub fn label(self) -> &'static str {
        match self {
            ListeningMode::Normal => "Standard",
            ListeningMode::Bgm => "BGM",
            ListeningMode::Cinema => "Cinema",
        }
    }

    /// Wire value used by the FFI and the UIs.
    pub fn code(self) -> u8 {
        match self {
            ListeningMode::Normal => 0,
            ListeningMode::Bgm => 1,
            ListeningMode::Cinema => 2,
        }
    }

    pub fn from_code(code: u8) -> Option<ListeningMode> {
        match code {
            0 => Some(ListeningMode::Normal),
            1 => Some(ListeningMode::Bgm),
            2 => Some(ListeningMode::Cinema),
            _ => None,
        }
    }
}

/// The two settings that make up the listening mode, as read back.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct ListeningState {
    pub bgm_on: bool,
    /// Last `RoomSize`; preserved when BGM is toggled again.
    pub room: u8,
    pub cinema_on: bool,
}

impl ListeningState {
    pub fn mode(&self) -> ListeningMode {
        if self.bgm_on {
            ListeningMode::Bgm
        } else if self.cinema_on {
            ListeningMode::Cinema
        } else {
            ListeningMode::Normal
        }
    }
}

pub fn room_size_label(value: u8) -> &'static str {
    match value {
        room_size::SMALL => "Small",
        room_size::MIDDLE => "Medium",
        room_size::LARGE => "Large",
        _ => "Unknown",
    }
}

/// `AUDIO_GET_PARAM` for the BGM setting (`E6 09` on this device).
pub fn get_bgm_mode() -> Vec<u8> {
    vec![cmd::AUDIO_GET_PARAM, audio_type::BGM_MODE_AND_ERRORCODE]
}

/// `AUDIO_GET_PARAM` for the Cinema setting (`E6 04`).
pub fn get_cinema_mode() -> Vec<u8> {
    vec![cmd::AUDIO_GET_PARAM, audio_type::UPMIX_CINEMA]
}

/// `AUDIO_SET_PARAM` for BGM: type, `OnOffSettingValue`, `RoomSize`.
///
/// `OnOffSettingValue::ON` is 0 and `OFF` is 1, the same encoding as
/// `EnableDisable`.
pub fn set_bgm_mode(enabled: bool, room: u8) -> Option<Vec<u8>> {
    if room > room_size::LARGE {
        return None;
    }
    Some(vec![
        cmd::AUDIO_SET_PARAM,
        audio_type::BGM_MODE_AND_ERRORCODE,
        if enabled { ENABLE } else { DISABLE },
        room,
    ])
}

/// `AUDIO_SET_PARAM` for Cinema: type, `OnOffSettingValue`.
pub fn set_cinema_mode(enabled: bool) -> Vec<u8> {
    vec![
        cmd::AUDIO_SET_PARAM,
        audio_type::UPMIX_CINEMA,
        if enabled { ENABLE } else { DISABLE },
    ]
}

/// Decode `AUDIO_RET_PARAM` / `AUDIO_NTFY_PARAM` for BGM: `type, onOff, room`.
pub fn decode_bgm_mode(payload: &[u8]) -> Option<(bool, u8)> {
    if payload.len() != 4 || payload[2] > DISABLE || payload[3] > room_size::LARGE {
        return None;
    }
    match payload[1] {
        audio_type::BGM_MODE | audio_type::BGM_MODE_AND_ERRORCODE => {
            Some((payload[2] == ENABLE, payload[3]))
        }
        _ => None,
    }
}

/// Decode `AUDIO_RET_PARAM` / `AUDIO_NTFY_PARAM` for Cinema: `type, onOff`.
pub fn decode_cinema_mode(payload: &[u8]) -> Option<bool> {
    if payload.len() != 3 || payload[1] != audio_type::UPMIX_CINEMA || payload[2] > DISABLE {
        return None;
    }
    Some(payload[2] == ENABLE)
}

// ---------------------------------------------------------------------------
// Diagnostics: BLE setup, repeat-tap, SAR / GATT / auto-play
// ---------------------------------------------------------------------------

/// `COMMON_GET_CAPABILITY` type 4: BLE address and ID.
pub fn get_ble_setup() -> Vec<u8> {
    vec![cmd::COMMON_GET_CAPABILITY, 0x04]
}

/// Returns `(address, id)`.
///
/// The device answers with **ASCII text**, not packed bytes:
/// `11 04 "2C:CA:16:75:76:32" "4C78CDDC"` (27 bytes total).
pub fn decode_ble_setup(payload: &[u8]) -> Option<(String, String)> {
    if payload.len() != 27 || payload[1] != 0x04 {
        return None;
    }
    let addr = std::str::from_utf8(&payload[2..19]).ok()?;
    let id = std::str::from_utf8(&payload[19..27]).ok()?;
    Some((addr.to_string(), id.to_string()))
}

pub fn get_repeat_tap_status() -> Vec<u8> {
    vec![cmd::SYSTEM_GET_STATUS, system_type::REPEAT_TAP_TRAINING_MODE]
}

pub fn decode_repeat_tap_status(payload: &[u8]) -> Option<u8> {
    if payload.len() != 3 || payload[1] != system_type::REPEAT_TAP_TRAINING_MODE {
        return None;
    }
    Some(payload[2])
}

/// Table-2 `SYSTEM_GET_STATUS` for the wearing checker: whether the
/// headphones are on the head. Reply and notification: `F3|F5 00 <code>`.
///
/// RET/NTFY_STATUS, inquired type `WEARING_STATUS_CHECKER` = 0, with
/// `WearingStatusCode`. The
/// WH-1000XM6 answers `F3 00 00` while worn.
pub fn get_wearing_checker() -> Vec<u8> {
    vec![cmd::SYSTEM_GET_STATUS, 0x00]
}

/// `WearingStatusCode`: 0 normal (worn), 2 left side off, 3 right side
/// off, 4 both off. `1` (ILLEGAL) and anything else decode to `None`.
pub fn decode_wearing_checker(payload: &[u8]) -> Option<u8> {
    if payload.len() != 3 || payload[1] != 0x00 || !matches!(payload[2], 0 | 2 | 3 | 4) {
        return None;
    }
    Some(payload[2])
}

pub fn get_sar_capability() -> Vec<u8> {
    vec![cmd::SAR_GET_CAPABILITY, sar_type::SAR]
}

pub fn get_gatt_capability() -> Vec<u8> {
    vec![cmd::SAR_GET_CAPABILITY, sar_type::GATT_CONNECTABLE]
}

pub fn get_gatt_status() -> Vec<u8> {
    vec![cmd::SAR_GET_STATUS, sar_type::GATT_CONNECTABLE]
}

/// `true` = connectable (`EnableDisable` 0).
pub fn decode_gatt_status(payload: &[u8]) -> Option<bool> {
    if payload.len() != 3 || payload[1] != sar_type::GATT_CONNECTABLE || payload[2] > DISABLE {
        return None;
    }
    Some(payload[2] == ENABLE)
}

pub fn get_sar_optimization_capability() -> Vec<u8> {
    vec![cmd::SAR_GET_CAPABILITY, sar_type::SAR_OPTIMIZATION]
}

pub fn get_sar_optimization_status() -> Vec<u8> {
    vec![cmd::SAR_GET_STATUS, sar_type::SAR_OPTIMIZATION]
}

/// `(enabled, optimization status)`.
pub fn decode_sar_optimization_status(payload: &[u8]) -> Option<(bool, u8)> {
    if payload.len() != 4 || payload[1] != sar_type::SAR_OPTIMIZATION || payload[2] > DISABLE {
        return None;
    }
    Some((payload[2] == ENABLE, payload[3]))
}

pub fn get_auto_play_capability() -> Vec<u8> {
    vec![cmd::SAR_GET_CAPABILITY, sar_type::AUTO_PLAY]
}

/// The capability is a big-endian 16-bit value (`4B EC` on the XM6).
pub fn decode_auto_play_capability(payload: &[u8]) -> Option<u16> {
    if payload.len() != 4 || payload[1] != sar_type::AUTO_PLAY {
        return None;
    }
    Some(u16::from_be_bytes([payload[2], payload[3]]))
}

// ---------------------------------------------------------------------------
// Table-2 peripheral: paired-device management (function 0x33)
// ---------------------------------------------------------------------------

/// A paired Classic Bluetooth device reported by `PERI_RET_PARAM` type 0x00
/// or 0x02.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PairedDevice {
    /// 17-byte ASCII address as the headset stores it, e.g. `00:11:22:AA:BB:CC`.
    pub address: String,
    pub name: String,
    /// Any non-zero `connectedStatus` means connected.
    pub connected: bool,
    /// Present only for the `WITH_BLUETOOTH_CLASS_OF_DEVICE` shape.
    pub class_of_device: Option<u32>,
}

/// Result of `PERI_RET_PARAM` for pairing device management.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PairingDeviceList {
    pub devices: Vec<PairedDevice>,
    /// Trailing byte the app calls the "playback right device" index.
    pub playback_device: u8,
}

/// Advertised pairing limits (`PERI_RET_CAPABILITY` type 0x00).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PairingCapability {
    pub max_paired: u8,
    pub max_connected: u8,
    /// 0 = file transfer in multi-connection possible.
    pub file_transfer: u8,
}

/// Current Bluetooth mode. Read as `PERI_RET_STATUS` type 0x00
/// (`33 00 <mode> <enabled>`); the XM6 pushes the change after a
/// `34 00` write as `PERI_NTFY_STATUS` type 0x02 (`35 02 <mode> <enabled>`, HW).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PairingModeStatus {
    /// `pairing_mode::NORMAL` or `pairing_mode::INQUIRY_SCAN`.
    pub mode: u8,
    pub enabled: bool,
}

pub fn get_pairing_status() -> Vec<u8> {
    vec![cmd::PERI_GET_STATUS, peri_type::PAIRING_DEVICE_MANAGEMENT]
}

pub fn decode_pairing_status(payload: &[u8]) -> Option<PairingModeStatus> {
    if payload.len() != 4
        || !matches!(payload[0], cmd::PERI_RET_STATUS | cmd::PERI_NTFY_STATUS)
        || !matches!(
            payload[1],
            peri_type::PAIRING_DEVICE_MANAGEMENT | peri_type::PAIRING_DEVICE_MANAGEMENT_WITH_COD
        )
        || payload[2] > pairing_mode::INQUIRY_SCAN
        || payload[3] > 1
    {
        return None;
    }
    Some(PairingModeStatus { mode: payload[2], enabled: payload[3] == 0 })
}

pub fn pairing_mode_label(mode: u8) -> &'static str {
    match mode {
        pairing_mode::INQUIRY_SCAN => "Pairing mode",
        _ => "Normal",
    }
}

pub fn get_pairing_capability() -> Vec<u8> {
    vec![cmd::PERI_GET_CAPABILITY, peri_type::PAIRING_DEVICE_MANAGEMENT]
}

/// Ask for the device list with Class-of-Device, the shape the app uses when
/// the model advertises it. The XM6 answers both 0x00 and 0x02.
pub fn get_pairing_devices() -> Vec<u8> {
    vec![cmd::PERI_GET_PARAM, peri_type::PAIRING_DEVICE_MANAGEMENT_WITH_COD]
}

/// True for `AA:BB:CC:DD:EE:FF` (17 ASCII characters).
fn valid_bluetooth_address(address: &str) -> bool {
    let bytes = address.as_bytes();
    bytes.len() == 17
        && bytes.iter().enumerate().all(|(index, byte)| {
            if matches!(index, 2 | 5 | 8 | 11 | 14) {
                *byte == b':'
            } else {
                byte.is_ascii_hexdigit()
            }
        })
}

/// Connect to, disconnect from, or unpair a paired Classic device.
///
/// V2 shape: `3C 00 <ConnectivityActionType> <address>`
/// (20 bytes). The V1 shape inserted a detail byte, but the XM6 speaks V2.
pub fn set_pairing_connection(action: u8, address: &str) -> Option<Vec<u8>> {
    if action > pairing_action::UNPAIR || !valid_bluetooth_address(address) {
        return None;
    }
    let mut payload = vec![
        cmd::PERI_SET_EX_PARAM,
        peri_type::PAIRING_DEVICE_MANAGEMENT_WITH_COD,
        action,
    ];
    payload.extend_from_slice(address.as_bytes());
    Some(payload)
}

/// One `PERI_NTFY_EX_PARAM` connection-control result.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PairingConnectionEvent {
    pub action: u8,
    pub result: u8,
    pub address: String,
}

/// Decode `3D 02 <action> <result> <address>`.
///
/// The XM6 answers the WITH_COD setter with this shape; result `0x12` is
/// `CONNECTION_IN_PROGRESS`, `0x10` is success.
pub fn decode_pairing_connection_event(payload: &[u8]) -> Option<PairingConnectionEvent> {
    if payload.len() != 21 || payload[0] != cmd::PERI_NTFY_EX_PARAM {
        return None;
    }
    if payload[1] != peri_type::PAIRING_DEVICE_MANAGEMENT
        && payload[1] != peri_type::PAIRING_DEVICE_MANAGEMENT_WITH_COD
    {
        return None;
    }
    let action = payload[2];
    let result = payload[3];
    if action > pairing_action::UNPAIR {
        return None;
    }
    let address = std::str::from_utf8(&payload[4..21]).ok()?.to_string();
    if !valid_bluetooth_address(&address) {
        return None;
    }
    Some(PairingConnectionEvent { action, result, address })
}

pub fn pairing_result_is_success(result: u8) -> bool {
    matches!(
        result,
        pairing_result::DISCONNECTION_SUCCESS
            | pairing_result::CONNECTION_SUCCESS
            | pairing_result::UNPAIRING_SUCCESS
    )
}

pub fn pairing_result_label(result: u8) -> &'static str {
    match result {
        0x00 => "Disconnected",
        0x01 => "Disconnect failed",
        0x02 => "Disconnecting",
        0x03 => "Disconnect busy",
        0x10 => "Connected",
        0x11 => "Connect failed",
        0x12 => "Connecting",
        0x13 => "Connect busy",
        0x20 => "Unpaired",
        0x21 => "Unpair failed",
        0x22 => "Unpairing",
        0x23 => "Unpair busy",
        _ => "Unknown result",
    }
}

/// Enter or leave Bluetooth inquiry-scan (pairing) mode.
///
/// Shape: `34 00 <PeripheralBluetoothMode> 00`.
pub fn set_pairing_mode(pairing: bool) -> Vec<u8> {
    vec![
        cmd::PERI_SET_STATUS,
        peri_type::PAIRING_DEVICE_MANAGEMENT,
        if pairing { pairing_mode::INQUIRY_SCAN } else { pairing_mode::NORMAL },
        0x00,
    ]
}

pub fn decode_pairing_capability(payload: &[u8]) -> Option<PairingCapability> {
    if payload.len() != 5
        || payload[0] != cmd::PERI_RET_CAPABILITY
        || payload[1] != peri_type::PAIRING_DEVICE_MANAGEMENT
    {
        return None;
    }
    Some(PairingCapability {
        max_paired: payload[2],
        max_connected: payload[3],
        file_transfer: payload[4],
    })
}

/// Decode either pairing-list shape.
///
/// Wire layout, with and without the Class-of-Device field:
///
/// ```text
/// 37 <type> <count>
///   <address: 17 ASCII>
///   <connectedStatus: u8>
///   [<classOfDevice: 3 BE>]      only when type == 0x02
///   <nameLength: u8>            1...128
///   <name: UTF-8>
/// <playbackDevice: u8>
/// ```
pub fn decode_pairing_devices(payload: &[u8]) -> Option<PairingDeviceList> {
    if payload.len() < 4 || !matches!(payload[0], cmd::PERI_RET_PARAM | cmd::PERI_NTFY_PARAM) {
        return None;
    }
    let with_cod = match payload[1] {
        peri_type::PAIRING_DEVICE_MANAGEMENT => false,
        peri_type::PAIRING_DEVICE_MANAGEMENT_WITH_COD => true,
        _ => return None,
    };
    let count = usize::from(*payload.get(2)?);
    // The XM6 advertises 8; reject an absurd count before allocating.
    if count > 32 {
        return None;
    }
    let mut devices = Vec::with_capacity(count);
    let mut i = 3usize;
    for _ in 0..count {
        let address_bytes = payload.get(i..i + 17)?;
        let address = std::str::from_utf8(address_bytes).ok()?.to_string();
        i += 17;
        let status = *payload.get(i)?;
        i += 1;
        let class_of_device = if with_cod {
            let cod = payload.get(i..i + 3)?;
            i += 3;
            Some(u32::from_be_bytes([0, cod[0], cod[1], cod[2]]))
        } else {
            None
        };
        let name_len = usize::from(*payload.get(i)?);
        i += 1;
        if name_len == 0 || name_len > 128 {
            return None;
        }
        let name_bytes = payload.get(i..i + name_len)?;
        let name = String::from_utf8_lossy(name_bytes).into_owned();
        i += name_len;
        devices.push(PairedDevice {
            address,
            name,
            connected: status > 0,
            class_of_device,
        });
    }
    let playback_device = *payload.get(i)?;
    if i + 1 != payload.len() {
        return None;
    }
    Some(PairingDeviceList { devices, playback_device })
}

// ---------------------------------------------------------------------------
// Table-2 peripheral: source switch, music hand-over, USB submersion
// ---------------------------------------------------------------------------

/// Current multipoint source index (`37 01 <value>`).
pub fn get_source_switch() -> Vec<u8> {
    vec![cmd::PERI_GET_PARAM, peri_type::SOURCE_SWITCH_CONTROL]
}

pub fn decode_source_switch(payload: &[u8]) -> Option<u8> {
    if payload.len() != 3 || payload[1] != peri_type::SOURCE_SWITCH_CONTROL {
        return None;
    }
    Some(payload[2])
}

pub fn get_music_hand_over() -> Vec<u8> {
    vec![cmd::PERI_GET_PARAM, peri_type::MUSIC_HAND_OVER_SETTING]
}

/// `PERI_SET_PARAM` for music hand-over: type, `OnOffSettingValue`.
///
/// ON is 0, OFF is 1.
pub fn set_music_hand_over(enabled: bool) -> Vec<u8> {
    vec![
        cmd::PERI_SET_PARAM,
        peri_type::MUSIC_HAND_OVER_SETTING,
        if enabled { ENABLE } else { DISABLE },
    ]
}

/// `true` = hand-over enabled (`OnOffSettingValue` 0).
pub fn decode_music_hand_over(payload: &[u8]) -> Option<bool> {
    if payload.len() != 3 || payload[1] != peri_type::MUSIC_HAND_OVER_SETTING || payload[2] > 1 {
        return None;
    }
    Some(payload[2] == 0)
}

pub fn get_usb_submersion() -> Vec<u8> {
    vec![cmd::POWER_GET_STATUS, 0x02]
}

/// `true` = USB is submerged (`UsbSubmersionStatus` 0).
pub fn decode_usb_submersion(payload: &[u8]) -> Option<bool> {
    if payload.len() != 3 || payload[1] != 0x02 || payload[2] > 1 {
        return None;
    }
    Some(payload[2] == 0)
}

// ---------------------------------------------------------------------------
// Playback controller (PLAY, enquired type 0x01)
// ---------------------------------------------------------------------------

/// Decoded `PLAY_RET_STATUS` / `PLAY_NTFY_STATUS` for the playback controller.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PlaybackState {
    pub enabled: bool,
    /// `0` unsettled, `1` play, `2` pause, `3` stop.
    pub playback: u8,
    /// `0` music, `1` call.
    pub source: u8,
}

pub fn get_playback_status() -> Vec<u8> {
    vec![cmd::PLAY_GET_STATUS, play_type::PLAYBACK_CONTROLLER]
}

pub fn decode_playback_status(payload: &[u8]) -> Option<PlaybackState> {
    if payload.len() != 5
        || payload[1] != play_type::PLAYBACK_CONTROLLER
        || payload[2] > 1
        || payload[3] > 3
        || payload[4] > 1
    {
        return None;
    }
    Some(PlaybackState {
        enabled: payload[2] == ENABLE,
        playback: payload[3],
        source: payload[4],
    })
}

pub fn playback_label(value: u8) -> &'static str {
    match value {
        0 => "Unsettled",
        1 => "Playing",
        2 => "Paused",
        3 => "Stopped",
        _ => "Unknown",
    }
}

/// `PLAY_SET_STATUS` for the playback controller.
pub fn set_playback_control(control: u8) -> Option<Vec<u8>> {
    if control > playback_control::FAST_REWIND {
        return None;
    }
    Some(vec![cmd::PLAY_SET_STATUS, play_type::PLAYBACK_CONTROLLER, ENABLE, control])
}

pub fn playback_source_label(value: u8) -> &'static str {
    match value {
        0 => "Music",
        1 => "Call",
        _ => "Unknown",
    }
}

// ---------------------------------------------------------------------------
// Auto power off with wearing detection (POWER, enquired type 0x05)
// ---------------------------------------------------------------------------

/// Valid `AutoPowerOffWearingDetectionElements` values.
///
/// `0..=4` are timers (5/30/60/180/15 minutes); `0x10` is "when removed";
/// `0x11` is "disabled".
pub const AUTO_POWER_OFF_WEARING_VALUES: [u8; 7] = [0, 1, 2, 3, 4, 0x10, 0x11];

pub fn auto_power_off_wearing_valid(value: u8) -> bool {
    AUTO_POWER_OFF_WEARING_VALUES.contains(&value)
}

/// Human label for a power-off element.
pub fn auto_power_off_wearing_label(value: u8) -> &'static str {
    match value {
        0 => "After 5 min",
        1 => "After 30 min",
        2 => "After 60 min",
        3 => "After 180 min",
        4 => "After 15 min",
        0x10 => "When taken off",
        0x11 => "Off",
        _ => "Unknown",
    }
}

/// `POWER_GET_STATUS` for the wearing-detection variant (feature enabled).
pub fn get_auto_power_off_wearing_status() -> Vec<u8> {
    vec![cmd::POWER_GET_STATUS, 0x05]
}

/// `POWER_GET_PARAM` for the wearing-detection variant.
pub fn get_auto_power_off_wearing() -> Vec<u8> {
    vec![cmd::POWER_GET_PARAM, 0x05]
}

/// `POWER_SET_PARAM` for the wearing-detection variant.
pub fn set_auto_power_off_wearing(current: u8, last: u8) -> Option<Vec<u8>> {
    if !auto_power_off_wearing_valid(current) || !auto_power_off_wearing_valid(last) {
        return None;
    }
    Some(vec![cmd::POWER_SET_PARAM, 0x05, current, last])
}

/// Decode `POWER_RET_PARAM` / `POWER_NTFY_PARAM` type `0x05`.
pub fn decode_auto_power_off_wearing(payload: &[u8]) -> Option<(u8, u8)> {
    if payload.len() != 4 || payload[1] != 0x05 {
        return None;
    }
    if !auto_power_off_wearing_valid(payload[2]) || !auto_power_off_wearing_valid(payload[3]) {
        return None;
    }
    Some((payload[2], payload[3]))
}

/// Decode `POWER_RET_STATUS` / `POWER_NTFY_STATUS` type `0x05` (feature enabled).
pub fn decode_auto_power_off_wearing_status(payload: &[u8]) -> Option<bool> {
    if payload.len() != 3 || payload[1] != 0x05 || payload[2] > 1 {
        return None;
    }
    Some(payload[2] == ENABLE)
}

// ---------------------------------------------------------------------------
// Wearing status (SYSTEM, enquired type 0x06)
// ---------------------------------------------------------------------------

/// Decoded `SYSTEM_RET_STATUS` / `SYSTEM_NTFY_STATUS` for wearing detection.
///
/// The reply is fixed at six bytes: `F3 06 <status> <mode> <count> <result>`.
/// On headphones the earpiece count is a sentinel (`0xF0`), because earpiece
/// selection does not apply; the meaningful fields are `status` and `mode`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct WearingStatus {
    /// Detection is enabled.
    pub detection_enabled: bool,
    /// The headset reports itself as being worn.
    pub worn: bool,
    /// Selected-earpiece count, or `0xF0` when not applicable.
    pub selected_earpieces: u8,
    /// Detection result code (`0` = no error).
    pub result_code: u8,
}

/// `SYSTEM_GET_STATUS` for wearing detection.
pub fn get_wearing_status() -> Vec<u8> {
    vec![cmd::SYSTEM_GET_STATUS, 0x06]
}

/// Table-2 `POWER_GET_CAPABILITY` for auto standby.
///
/// The reply is `21 00 <AutoStandbyCandidateElement>`; the only candidate is
/// `AUTO_STANDBY_IN_15_MIN` (0).
pub fn get_auto_standby() -> Vec<u8> {
    vec![cmd::POWER_GET_CAPABILITY, 0x00]
}

/// `true` when the device offers the 15-minute auto-standby candidate.
pub fn decode_auto_standby(payload: &[u8]) -> Option<bool> {
    if payload.len() != 3 || payload[1] != 0x00 {
        return None;
    }
    Some(payload[2] == 0)
}

/// Table-2 `POWER_GET_STATUS` for auto standby (`23 00 <EnableDisable>`).
pub fn get_auto_standby_status() -> Vec<u8> {
    vec![cmd::POWER_GET_STATUS, 0x00]
}

pub fn decode_auto_standby_status(payload: &[u8]) -> Option<bool> {
    if payload.len() != 3 || payload[1] != 0x00 || payload[2] > DISABLE {
        return None;
    }
    Some(payload[2] == ENABLE)
}

/// Table-2 `POWER_GET_PARAM` for the auto-standby setting.
pub fn get_auto_standby_param() -> Vec<u8> {
    vec![cmd::POWER_GET_PARAM, 0x00]
}

/// `OnOffSettingValue` (ON = 0).
pub fn decode_auto_standby_param(payload: &[u8]) -> Option<bool> {
    if payload.len() != 3 || payload[1] != 0x00 || payload[2] > DISABLE {
        return None;
    }
    Some(payload[2] == ENABLE)
}

/// `POWER_SET_STATUS` type `POWER_OFF`, `USER_POWER_OFF` (1).
pub fn power_off() -> Vec<u8> {
    vec![cmd::POWER_SET_STATUS, power_type::POWER_OFF, 0x01]
}

/// Table-2 `POWER_SET_PARAM` for the auto-standby setting.
pub fn set_auto_standby(enabled: bool) -> Vec<u8> {
    vec![
        cmd::POWER_SET_PARAM,
        0x00,
        if enabled { ENABLE } else { DISABLE },
    ]
}

/// Speak-to-Chat state, assembled from status, param and ext-param replies.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct SmartTalking {
    pub enabled: bool,
    /// `SmartTalkingModeEffectStatus`: 0 not active, 1 active.
    pub effect: u8,
    /// `DetectSensitivity`: 0 auto, 1 high, 2 low.
    pub sensitivity: u8,
    /// `ModeOutTime`: 0 fast, 1 mid, 2 slow, 3 none.
    pub mode_out: u8,
}

pub fn smart_talking_sensitivity_label(value: u8) -> &'static str {
    match value {
        detect_sensitivity::AUTO => "Auto",
        detect_sensitivity::HIGH => "High",
        detect_sensitivity::LOW => "Low",
        _ => "Unknown",
    }
}

pub fn smart_talking_mode_out_label(value: u8) -> &'static str {
    match value {
        mode_out_time::FAST => "Fast",
        mode_out_time::MID => "Medium",
        mode_out_time::SLOW => "Slow",
        mode_out_time::NONE => "None",
        _ => "Unknown",
    }
}

pub fn get_quick_access() -> Vec<u8> {
    vec![cmd::SYSTEM_GET_PARAM, system_type::QUICK_ACCESS]
}

/// `F7 0D <count> <function>...` — the assigned function ids.
pub fn decode_quick_access(payload: &[u8]) -> Option<Vec<u8>> {
    if payload.len() < 3 || payload[1] != system_type::QUICK_ACCESS {
        return None;
    }
    let count = payload[2] as usize;
    if payload.len() != 3 + count {
        return None;
    }
    Some(payload[3..].to_vec())
}

/// Quick Access easy-setting write: `F8 02 00 00 <n> <functions...>`.
pub fn set_quick_access_functions(functions: &[u8]) -> Option<Vec<u8>> {
    if functions.is_empty() || functions.len() > 255 {
        return None;
    }
    let mut payload = vec![
        cmd::SYSTEM_SET_PARAM,
        system_type::QUICK_ACCESS_EASY_SETTING,
        0x00,
        0x00,
        functions.len() as u8,
    ];
    payload.extend_from_slice(functions);
    Some(payload)
}

pub fn decode_quick_access_result(payload: &[u8]) -> Option<u8> {
    if payload.len() != 3 || payload[1] != system_type::QUICK_ACCESS_EASY_SETTING || payload[2] > 1
    {
        return None;
    }
    Some(payload[2])
}

/// Names from `ProtocolAssignableFunction`; `10` is still unnamed.
pub fn quick_access_name(value: u8) -> &'static str {
    match value {
        0 => "No function",
        1 => "NC/ASM off",
        2 => "NC/ASM",
        3 => "NC off",
        4 => "ASM off",
        16 => "Quick Attention",
        17 => "NC Optimizer",
        32 => "Play/Pause",
        33 => "Next track",
        34 => "Previous track",
        35 => "Volume up",
        36 => "Volume down",
        48 => "Voice recognition",
        49 => "Get your notification",
        50 => "Talk to Google Assistant",
        51 => "Stop Google Assistant",
        52 => "Cancel voice input",
        53 => "Talk to Tencent Xiaowei",
        54 => "Cancel voice recognition",
        55 => "Talk to Amazon Alexa",
        56 => "Cancel Amazon Alexa",
        57 => "Cancel Tencent Xiaowei",
        58 => "Next track / Stop Gemini Live",
        59 => "Previous track / Stop Gemini Live",
        64 => "Launch MLP",
        65 => "Talk to your MLP",
        66 => "Spotify one-touch",
        67 => "Quick Access 1",
        68 => "Quick Access 2",
        69 => "Talk to Tencent Xiaowei / Cancel",
        70 => "Music one-touch",
        71 => "Teams",
        72 => "Teams voice skills",
        80 => "NC/NCSS/ASM off",
        81 => "NC/NCSS/ASM",
        82 => "NC/NCSS off",
        83 => "NCSS/ASM off",
        84 => "NC/NCSS",
        85 => "NCSS/ASM",
        86 => "NCSS off",
        87 => "Ambient setting",
        88 => "Standard voice sound",
        89 => "Listening mode",
        112 => "Mic mute",
        113 => "Game up",
        114 => "Chat up",
        _ => "Unnamed",
    }
}

pub fn set_head_gesture_training(start: bool) -> Vec<u8> {
    vec![
        cmd::SYSTEM_SET_STATUS,
        system_type::HEAD_GESTURE_TRAINING,
        if start { 0x00 } else { 0x01 },
    ]
}

/// `SYSTEM_NTFY_STATUS` for head gesture training: status (0 in test, 1 out)
/// and whether training is enabled.
pub fn decode_head_gesture_training_status(payload: &[u8]) -> Option<(u8, bool)> {
    if payload.len() != 4
        || payload[1] != system_type::HEAD_GESTURE_TRAINING
        || payload[2] > 1
        || payload[3] > 1
    {
        return None;
    }
    Some((payload[2], payload[3] == 0))
}

/// `SYSTEM_NTFY_PARAM` for head gesture training: 0 nod, 1 swing.
pub fn decode_head_gesture_action(payload: &[u8]) -> Option<u8> {
    if payload.len() != 3 || payload[1] != system_type::HEAD_GESTURE_TRAINING || payload[2] > 1 {
        return None;
    }
    Some(payload[2])
}

/// Control-by-wearing param (`F6 01` -> `F7 01 <OnOff>`).
pub fn get_control_by_wearing() -> Vec<u8> {
    vec![cmd::SYSTEM_GET_PARAM, system_type::CONTROL_BY_WEARING]
}

pub fn decode_control_by_wearing(payload: &[u8]) -> Option<bool> {
    if payload.len() != 3 || payload[1] != system_type::CONTROL_BY_WEARING || payload[2] > 1 {
        return None;
    }
    Some(payload[2] == 0)
}

/// Availability status (`F2 01` -> `F3 01 <EnableDisable>`).
pub fn get_control_by_wearing_status() -> Vec<u8> {
    vec![cmd::SYSTEM_GET_STATUS, system_type::CONTROL_BY_WEARING]
}

pub fn decode_control_by_wearing_status(payload: &[u8]) -> Option<bool> {
    if payload.len() != 3 || payload[1] != system_type::CONTROL_BY_WEARING || payload[2] > 1 {
        return None;
    }
    Some(payload[2] == 0)
}

pub fn set_control_by_wearing(enabled: bool) -> Vec<u8> {
    vec![
        cmd::SYSTEM_SET_PARAM,
        system_type::CONTROL_BY_WEARING,
        if enabled { 0x00 } else { 0x01 },
    ]
}

pub fn get_head_gesture() -> Vec<u8> {
    vec![cmd::SYSTEM_GET_STATUS, system_type::HEAD_GESTURE_ON_OFF]
}

pub fn decode_head_gesture(payload: &[u8]) -> Option<bool> {
    if payload.len() != 3
        || payload[1] != system_type::HEAD_GESTURE_ON_OFF
        || payload[2] > DISABLE
    {
        return None;
    }
    Some(payload[2] == ENABLE)
}

/// `SYSTEM_SET_STATUS` for head gesture; `OnOffSettingValue` ON = 0.
pub fn set_head_gesture(enabled: bool) -> Vec<u8> {
    vec![
        cmd::SYSTEM_SET_STATUS,
        system_type::HEAD_GESTURE_ON_OFF,
        if enabled { ENABLE } else { DISABLE },
    ]
}

pub fn get_smart_talking_status() -> Vec<u8> {
    vec![cmd::SYSTEM_GET_STATUS, system_type::SMART_TALKING_MODE_TYPE2]
}

pub fn decode_smart_talking_status(payload: &[u8]) -> Option<(bool, u8)> {
    if payload.len() != 4
        || payload[1] != system_type::SMART_TALKING_MODE_TYPE2
        || payload[2] > DISABLE
        || payload[3] > 1
    {
        return None;
    }
    Some((payload[2] == ENABLE, payload[3]))
}

pub fn get_smart_talking_param() -> Vec<u8> {
    vec![cmd::SYSTEM_GET_PARAM, system_type::SMART_TALKING_MODE_TYPE2]
}

/// Returns `(main on/off, preview on/off)`.
pub fn decode_smart_talking_param(payload: &[u8]) -> Option<(bool, bool)> {
    if payload.len() != 4
        || payload[1] != system_type::SMART_TALKING_MODE_TYPE2
        || payload[2] > DISABLE
        || payload[3] > DISABLE
    {
        return None;
    }
    Some((payload[2] == ENABLE, payload[3] == ENABLE))
}

pub fn get_smart_talking_ext() -> Vec<u8> {
    vec![cmd::SYSTEM_GET_EXT_PARAM, system_type::SMART_TALKING_MODE_TYPE2]
}

pub fn decode_smart_talking_ext(payload: &[u8]) -> Option<(u8, u8)> {
    if payload.len() != 4
        || payload[1] != system_type::SMART_TALKING_MODE_TYPE2
        || payload[2] > detect_sensitivity::LOW
        || payload[3] > mode_out_time::NONE
    {
        return None;
    }
    Some((payload[2], payload[3]))
}

/// `SYSTEM_SET_PARAM`: main on/off plus the preview flag the device already has.
pub fn set_smart_talking_enabled(enabled: bool, preview: bool) -> Vec<u8> {
    vec![
        cmd::SYSTEM_SET_PARAM,
        system_type::SMART_TALKING_MODE_TYPE2,
        if enabled { ENABLE } else { DISABLE },
        if preview { ENABLE } else { DISABLE },
    ]
}

/// `SYSTEM_SET_EXT_PARAM`: sensitivity and auto-off time.
pub fn set_smart_talking_detail(sensitivity: u8, mode_out: u8) -> Option<Vec<u8>> {
    if sensitivity > detect_sensitivity::LOW || mode_out > mode_out_time::NONE {
        return None;
    }
    Some(vec![
        cmd::SYSTEM_SET_EXT_PARAM,
        system_type::SMART_TALKING_MODE_TYPE2,
        sensitivity,
        mode_out,
    ])
}

/// LE Audio switch compatibility (`60 01` -> `61 01 <version>`).
pub fn get_le_audio_switch_compat() -> Vec<u8> {
    vec![
        cmd::LEA_GET_CAPABILITY,
        lea_type::LE_AUDIO_SWITCH_SUPPORTED_COMPATIBILITY,
    ]
}

pub fn decode_le_audio_switch_compat(payload: &[u8]) -> Option<u8> {
    if payload.len() != 3
        || payload[1] != lea_type::LE_AUDIO_SWITCH_SUPPORTED_COMPATIBILITY
    {
        return None;
    }
    Some(payload[2])
}

/// Adaptive control start/stop (`74 01 01` start, `74 01 00` stop).
pub fn set_sense_control(start: bool) -> Vec<u8> {
    vec![
        cmd::SENSE_SET_STATUS,
        sense_type::ADAPTIVE_CONTROL_WITH_PARAMETER_NOTIFICATION,
        if start { 0x01 } else { 0x00 },
    ]
}

pub fn decode_sense_control(payload: &[u8]) -> Option<bool> {
    if payload.len() != 3
        || payload[1] != sense_type::ADAPTIVE_CONTROL_WITH_PARAMETER_NOTIFICATION
        || payload[2] > 1
    {
        return None;
    }
    Some(payload[2] == 1)
}

/// Device-pushed alert (`99 <type> <message> <action>`).
pub fn decode_alert_param(payload: &[u8]) -> Option<(u8, u8, u8)> {
    if payload.len() != 4 || payload[0] != cmd::ALERT_NTFY_PARAM || payload[1] > 6 {
        return None;
    }
    Some((payload[1], payload[2], payload[3]))
}

pub fn alert_type_name(value: u8) -> &'static str {
    match value {
        0 => "Fixed message",
        1 => "Vibrator alert",
        2 => "Fixed message (L/R)",
        3 => "Voice assistant alert",
        4 => "App foreground",
        5 => "LE Audio alert",
        6 => "Flexible message",
        _ => "Unknown",
    }
}

/// Adaptive control capability (`70 01` -> `71 01 <bytes>`).
pub fn get_sense_capability() -> Vec<u8> {
    vec![
        cmd::SENSE_GET_CAPABILITY,
        sense_type::ADAPTIVE_CONTROL_WITH_PARAMETER_NOTIFICATION,
    ]
}

pub fn decode_sense_capability(payload: &[u8]) -> Option<Vec<u8>> {
    if payload.len() < 3
        || payload[1] != sense_type::ADAPTIVE_CONTROL_WITH_PARAMETER_NOTIFICATION
    {
        return None;
    }
    Some(payload[2..].to_vec())
}

/// One entry of the adaptive-control parameter notification.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SenseFunctionParam {
    /// `RequestResult`: 0 accepted, 1 declined.
    pub result: u8,
    /// `SenseApplicableFunction` byte.
    pub function: u8,
    /// Function-specific bytes, excluding the function id.
    pub data: Vec<u8>,
}

/// Device-pushed adaptive-control parameter (`79 01 <count> …`).
///
/// This is the **read-only** shape. The setter (`78 01 …`) rewrites NC/ASM and
/// can latch the headset off; it remains deliberately unwired.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SenseParameter {
    pub functions: Vec<SenseFunctionParam>,
}

/// Function-specific data length, excluding the function id. From the
/// `t.l(..., n)` calls in `do0/`; `u.a` already consumed the function byte.
fn sense_function_data_len(function: u8) -> Option<usize> {
    match function {
        0x00..=0x03 | 0x06 | 0x07 => Some(5),
        0x04 | 0x05 => Some(6),
        0x08 => Some(7),
        0x10 | 0x20 => Some(1),
        _ => None,
    }
}

pub fn sense_function_name(function: u8) -> &'static str {
    match function {
        0x00 => "NC on/off + ASM on/off",
        0x01 => "NC mode switch + ASM on/off",
        0x02 => "NC on/off + ASM seamless",
        0x03 => "NC mode switch + ASM seamless",
        0x04 => "Auto NC mode switch + ASM seamless",
        0x05 => "Dual single NC mode switch + ASM seamless",
        0x06 => "Dual NC mode switch + ASM seamless",
        0x07 => "NC/NCSS dual NC mode switch + ASM seamless",
        0x08 => "Dual NC mode switch + ASM seamless (NA)",
        0x10 => "EQ preset",
        0x20 => "Smart talking mode",
        _ => "Unknown function",
    }
}

pub fn decode_sense_parameter(payload: &[u8]) -> Option<SenseParameter> {
    if payload.len() < 3
        || !matches!(payload[0], cmd::SENSE_RET_PARAM | cmd::SENSE_NTFY_PARAM)
        || payload[1] != sense_type::ADAPTIVE_CONTROL_WITH_PARAMETER_NOTIFICATION
    {
        return None;
    }
    let count = usize::from(payload[2]);
    if count > 16 {
        return None;
    }
    let mut functions = Vec::with_capacity(count);
    let mut index = 3usize;
    for _ in 0..count {
        let result = *payload.get(index)?;
        if result > 1 {
            return None;
        }
        index += 1;
        let function = *payload.get(index)?;
        let data_len = sense_function_data_len(function)?;
        let start = index.checked_add(1)?;
        let end = start.checked_add(data_len)?;
        let data = payload.get(start..end)?.to_vec();
        functions.push(SenseFunctionParam { result, function, data });
        index = end;
    }
    if index != payload.len() {
        return None;
    }
    Some(SenseParameter { functions })
}

/// Mic on/off by headphone operation (`F2 0B` -> `F3 0B <EnableDisable>`).
pub fn get_mic_on_off() -> Vec<u8> {
    vec![
        cmd::SYSTEM_GET_STATUS,
        system_type::MIC_ON_OFF_BY_HEADPHONE_OPERATION,
    ]
}

pub fn decode_mic_on_off(payload: &[u8]) -> Option<bool> {
    if payload.len() != 3
        || payload[1] != system_type::MIC_ON_OFF_BY_HEADPHONE_OPERATION
        || payload[2] > 1
    {
        return None;
    }
    Some(payload[2] == 0)
}

/// Notify param (`F9 0B <mic> <mic-off sound effect>`).
pub fn decode_mic_notify(payload: &[u8]) -> Option<(bool, bool)> {
    if payload.len() != 4
        || payload[1] != system_type::MIC_ON_OFF_BY_HEADPHONE_OPERATION
        || payload[2] > 1
        || payload[3] > 1
    {
        return None;
    }
    Some((payload[2] == 0, payload[3] == 0))
}

pub fn set_mic_on_off(enabled: bool) -> Vec<u8> {
    vec![
        cmd::SYSTEM_SET_PARAM,
        system_type::MIC_ON_OFF_BY_HEADPHONE_OPERATION,
        if enabled { 0x00 } else { 0x01 },
    ]
}

pub fn get_mic_capability() -> Vec<u8> {
    vec![
        cmd::SYSTEM_GET_CAPABILITY,
        system_type::MIC_ON_OFF_BY_HEADPHONE_OPERATION,
    ]
}

pub fn decode_mic_capability(payload: &[u8]) -> Option<u8> {
    if payload.len() != 3 || payload[1] != system_type::MIC_ON_OFF_BY_HEADPHONE_OPERATION {
        return None;
    }
    Some(payload[2])
}

/// Sony Voice Assistant status (`F2 05` -> `F3 05 <EnableDisable>`).
pub fn get_sony_voice_assistant_status() -> Vec<u8> {
    vec![
        cmd::SYSTEM_GET_STATUS,
        system_type::SONY_VOICE_ASSISTANT,
    ]
}

pub fn decode_sony_voice_assistant_status(payload: &[u8]) -> Option<bool> {
    if payload.len() != 3 || payload[1] != system_type::SONY_VOICE_ASSISTANT || payload[2] > 1 {
        return None;
    }
    Some(payload[2] == 0)
}

pub fn set_sony_voice_assistant_enabled(enabled: bool) -> Vec<u8> {
    vec![
        cmd::SYSTEM_SET_STATUS,
        system_type::SONY_VOICE_ASSISTANT,
        if enabled { 0x00 } else { 0x01 },
    ]
}

/// Sony Voice Assistant language (`F6 05` -> `F7 05 <language>`).
pub fn get_sony_voice_assistant_language() -> Vec<u8> {
    vec![
        cmd::SYSTEM_GET_PARAM,
        system_type::SONY_VOICE_ASSISTANT,
    ]
}

pub fn decode_sony_voice_assistant_language(payload: &[u8]) -> Option<u8> {
    if payload.len() != 3 || payload[1] != system_type::SONY_VOICE_ASSISTANT {
        return None;
    }
    Some(payload[2])
}

/// Link auto-switch status (`F2 0A` -> `F3 0A <EnableDisable>`).
pub fn get_link_auto_switch_status() -> Vec<u8> {
    vec![
        cmd::SYSTEM_GET_STATUS,
        system_type::LINK_AUTO_SWITCH_FOR_HEADSETS,
    ]
}

pub fn decode_link_auto_switch_status(payload: &[u8]) -> Option<bool> {
    if payload.len() != 3
        || payload[1] != system_type::LINK_AUTO_SWITCH_FOR_HEADSETS
        || payload[2] > 1
    {
        return None;
    }
    Some(payload[2] == 0)
}

/// Link auto-switch param (`F6 0A` -> `F7 0A <on> <speaker id u16> <address>`).
pub fn get_link_auto_switch_param() -> Vec<u8> {
    vec![
        cmd::SYSTEM_GET_PARAM,
        system_type::LINK_AUTO_SWITCH_FOR_HEADSETS,
    ]
}

pub fn decode_link_auto_switch_param(payload: &[u8]) -> Option<(bool, u16, String)> {
    if payload.len() != 22
        || payload[1] != system_type::LINK_AUTO_SWITCH_FOR_HEADSETS
        || payload[2] > 1
    {
        return None;
    }
    let speaker = u16::from_be_bytes([payload[3], payload[4]]);
    let address = String::from_utf8_lossy(&payload[5..22]).trim_end_matches('\0').to_string();
    Some((payload[2] == 0, speaker, address))
}

/// Voice guidance on/off (`42 01` -> `43 01 <statusType> <EnableDisable>`).
pub fn get_voice_guidance_status() -> Vec<u8> {
    vec![
        cmd::VOICE_GUIDANCE_GET_STATUS,
        voice_guidance_type::MTK_TRANSFER_SUPPORT_LANGUAGE_SWITCH,
        0x00,
    ]
}

/// On/off is a `VOICE_GUIDANCE_GET_PARAM` (`46 01`) on the XM6, not a status
/// read. The reply is `47 01 <OnOffSettingValue> <language>`.
pub fn get_voice_guidance_param() -> Vec<u8> {
    vec![
        cmd::VOICE_GUIDANCE_GET_PARAM,
        voice_guidance_type::MTK_TRANSFER_SUPPORT_LANGUAGE_SWITCH,
    ]
}

/// `true` = enabled (`OnOffSettingValue` 0).
///
/// The reply shape is `47 01 <onoff> <language>`; the device's own
/// notification is the shorter `49 01 <onoff>`.
pub fn decode_voice_guidance_param(payload: &[u8]) -> Option<bool> {
    if payload.len() < 3
        || payload[1] != voice_guidance_type::MTK_TRANSFER_SUPPORT_LANGUAGE_SWITCH
        || payload[2] > 1
    {
        return None;
    }
    let valid_shape = (payload[0] == cmd::VOICE_GUIDANCE_RET_PARAM && payload.len() == 4)
        || (payload[0] == cmd::VOICE_GUIDANCE_NTFY_PARAM && payload.len() == 3);
    if !valid_shape {
        return None;
    }
    Some(payload[2] == 0)
}

/// Language status (`42 01 01` -> `43 01 01 <language>`).
pub fn get_voice_guidance_language() -> Vec<u8> {
    vec![
        cmd::VOICE_GUIDANCE_GET_STATUS,
        voice_guidance_type::MTK_TRANSFER_SUPPORT_LANGUAGE_SWITCH,
        0x01,
    ]
}

pub fn decode_voice_guidance_language(payload: &[u8]) -> Option<u8> {
    if payload.len() != 4
        || payload[1] != voice_guidance_type::MTK_TRANSFER_SUPPORT_LANGUAGE_SWITCH
        || payload[2] != 0x01
    {
        return None;
    }
    Some(payload[3])
}

pub fn decode_voice_guidance_status(payload: &[u8]) -> Option<bool> {
    if payload.len() != 4
        || payload[1] != voice_guidance_type::MTK_TRANSFER_SUPPORT_LANGUAGE_SWITCH
        || payload[2] != 0x00
        || payload[3] > 1
    {
        return None;
    }
    Some(payload[3] == 0)
}

/// Firmware 3.1.5 replies with a 4-byte status (`43 01 54 08`) that does not
/// match the older `statusType/status` layout. Keep the pair for diagnostics.
pub fn decode_voice_guidance_status_raw(payload: &[u8]) -> Option<(u8, u8)> {
    if payload.len() != 4
        || payload[1] != voice_guidance_type::MTK_TRANSFER_SUPPORT_LANGUAGE_SWITCH
    {
        return None;
    }
    Some((payload[2], payload[3]))
}

pub fn set_voice_guidance_enabled(enabled: bool) -> Vec<u8> {
    vec![
        cmd::VOICE_GUIDANCE_SET_PARAM,
        voice_guidance_type::MTK_TRANSFER_SUPPORT_LANGUAGE_SWITCH,
        if enabled { 0x00 } else { 0x01 },
    ]
}

/// Voice guidance volume (`46 20` -> `47 20 <i8>`).
pub fn get_voice_guidance_volume() -> Vec<u8> {
    vec![
        cmd::VOICE_GUIDANCE_GET_PARAM,
        voice_guidance_type::VOLUME,
    ]
}

pub fn decode_voice_guidance_volume(payload: &[u8]) -> Option<i8> {
    if payload.len() != 3 || payload[1] != voice_guidance_type::VOLUME {
        return None;
    }
    Some(payload[2] as i8)
}

pub fn set_voice_guidance_volume(volume: i8, feedback: bool) -> Vec<u8> {
    vec![
        cmd::VOICE_GUIDANCE_SET_PARAM,
        voice_guidance_type::VOLUME,
        volume as u8,
        if feedback { 0x00 } else { 0x01 },
    ]
}

/// Safe volume control (`SafeListeningWHOStandardLevel`: 0 normal, 1 sensitive).
pub fn get_safe_volume_level() -> Vec<u8> {
    vec![cmd::SAFE_LISTENING_GET_PARAM, safe_listening_type::SAFE_VOLUME_CONTROL]
}

pub fn decode_safe_volume_level(payload: &[u8]) -> Option<u8> {
    if payload.len() != 3
        || payload[1] != safe_listening_type::SAFE_VOLUME_CONTROL
        || payload[2] > 1
    {
        return None;
    }
    Some(payload[2])
}

pub fn set_safe_volume_level(level: u8) -> Option<Vec<u8>> {
    if level > 1 {
        return None;
    }
    Some(vec![
        cmd::SAFE_LISTENING_SET_STATUS,
        safe_listening_type::SAFE_VOLUME_CONTROL,
        level,
    ])
}

/// `SYSTEM_GET_STATUS` for auto volume with limitation.
///
/// The on/off lives in the status shape (`F3 04 <EnableDisable>`); the param
/// shape carries the limitation list and is not needed for the toggle.
pub fn get_auto_volume() -> Vec<u8> {
    vec![cmd::SYSTEM_GET_STATUS, system_type::AUTO_VOLUME_WITH_LIMITATION]
}

pub fn decode_auto_volume(payload: &[u8]) -> Option<bool> {
    if payload.len() != 3
        || payload[1] != system_type::AUTO_VOLUME_WITH_LIMITATION
        || payload[2] > DISABLE
    {
        return None;
    }
    Some(payload[2] == ENABLE)
}

/// Decode the wearing-status reply.
pub fn decode_wearing_status(payload: &[u8]) -> Option<WearingStatus> {
    if payload.len() != 6 || payload[1] != 0x06 || payload[2] > 1 || payload[3] > 1 || payload[5] > 1 {
        return None;
    }
    Some(WearingStatus {
        detection_enabled: payload[2] == ENABLE,
        worn: payload[3] == 1,
        selected_earpieces: payload[4],
        result_code: payload[5],
    })
}

// ---------------------------------------------------------------------------
// Auto power off (POWER, enquired type 0x04) — read-only in the protocol
// ---------------------------------------------------------------------------

/// `POWER_GET_STATUS` for auto power off.
pub fn get_auto_power_off() -> Vec<u8> {
    vec![cmd::POWER_GET_STATUS, 0x04]
}

/// Decode `POWER_RET_STATUS` for auto power off.
pub fn decode_auto_power_off(payload: &[u8]) -> Option<bool> {
    if payload.len() < 3 || payload[1] != 0x04 {
        return None;
    }
    Some(payload[2] == ENABLE)
}

/// `POWER_GET_STATUS` for the classic/LE audio connection mode.
pub fn get_connection_mode() -> Vec<u8> {
    vec![cmd::AUDIO_GET_STATUS, 0x05]
}

/// Decode the two flags of the classic-audio / LE-audio mode reply.
pub fn decode_connection_mode(payload: &[u8]) -> Option<(bool, bool)> {
    if payload.len() < 4 || payload[1] != 0x05 {
        return None;
    }
    Some((payload[2] == ENABLE, payload[3] == ENABLE))
}

// ---------------------------------------------------------------------------
// Support functions: what the device says it can do
// ---------------------------------------------------------------------------

/// `CONNECT_GET_SUPPORT_FUNCTION`.
pub fn get_support_function() -> Vec<u8> {
    vec![cmd::CONNECT_GET_SUPPORT_FUNCTION, connect_type::FIXED_VALUE]
}

/// Decode `CONNECT_RET_SUPPORT_FUNCTION` into the list of function bytes.
///
/// Layout: `07 00 <count> (<function> <value>)*`.
pub fn decode_support_function(payload: &[u8]) -> Option<Vec<u8>> {
    if payload.len() < 3 || payload[0] != cmd::CONNECT_RET_SUPPORT_FUNCTION {
        return None;
    }
    let count = payload[2] as usize;
    if payload.len() < 3 + count * 2 {
        return None;
    }
    Some((0..count).map(|i| payload[3 + i * 2]).collect())
}

// ---------------------------------------------------------------------------
// Voice assistant (SYSTEM, enquired type 0x04)
// ---------------------------------------------------------------------------

pub mod voice_assistant {
    pub const NO_FUNCTION: u8 = 0xFF;
    pub const VOICE_RECOGNITION: u8 = 0x30;
    pub const GOOGLE_ASSISTANT: u8 = 0x31;
    pub const AMAZON_ALEXA: u8 = 0x32;
    pub const TENCENT_XIAOWEI: u8 = 0x33;
    pub const SONY_VOICE_ASSISTANT: u8 = 0x34;

    pub fn name(value: u8) -> &'static str {
        match value {
            NO_FUNCTION => "Not set",
            VOICE_RECOGNITION => "Voice recognition",
            GOOGLE_ASSISTANT => "Google Assistant",
            AMAZON_ALEXA => "Amazon Alexa",
            TENCENT_XIAOWEI => "Tencent Xiaowei",
            SONY_VOICE_ASSISTANT => "Sony Voice Assistant",
            _ => "Unknown",
        }
    }
}

/// Enquired type for the voice-assistant setting inside the SYSTEM family.
pub const VOICE_ASSISTANT_TYPE: u8 = 0x04;

/// Decoded voice-assistant assignment.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct VoiceAssistantSetting {
    pub current: u8,
    /// Assistants the device says it supports, in device order.
    pub supported: Vec<u8>,
}

impl VoiceAssistantSetting {
    pub fn current_name(&self) -> &'static str {
        voice_assistant::name(self.current)
    }
}

/// `SYSTEM_GET_CAPABILITY` for the voice assistant.
pub fn get_voice_assistant_capability() -> Vec<u8> {
    vec![cmd::SYSTEM_GET_CAPABILITY, VOICE_ASSISTANT_TYPE]
}

/// `SYSTEM_GET_PARAM` for the voice assistant.
pub fn get_voice_assistant() -> Vec<u8> {
    vec![cmd::SYSTEM_GET_PARAM, VOICE_ASSISTANT_TYPE]
}

/// `SYSTEM_SET_PARAM` for the voice assistant.
pub fn set_voice_assistant(value: u8) -> Vec<u8> {
    vec![cmd::SYSTEM_SET_PARAM, VOICE_ASSISTANT_TYPE, value]
}

/// Decode `SYSTEM_RET_PARAM` for the voice assistant: `(value)`.
pub fn decode_voice_assistant(payload: &[u8]) -> Option<u8> {
    if payload.len() < 3 || payload[0] != cmd::SYSTEM_RET_PARAM || payload[1] != VOICE_ASSISTANT_TYPE {
        return None;
    }
    Some(payload[2])
}

/// Decode `SYSTEM_RET_CAPABILITY` for the voice assistant into its supported list.
///
/// Observed layout: `F1 04 <count> <len> <values…>`.
pub fn decode_voice_assistant_capability(payload: &[u8]) -> Option<Vec<u8>> {
    if payload.len() < 5 || payload[0] != cmd::SYSTEM_RET_CAPABILITY || payload[1] != VOICE_ASSISTANT_TYPE {
        return None;
    }
    let len = payload[3] as usize;
    let values = payload.get(4..4 + len)?;
    Some(values.iter().copied().filter(|v| *v != 0xFF && *v != 0xFE).collect())
}

// ---------------------------------------------------------------------------
// Common status (JSON): codec, model, firmware
// ---------------------------------------------------------------------------
//
// `COMMON_GET_STATUS` answers with a JSON document rather than packed bytes,
// for example:
//
// {"type":"CS","fVer":"BT22","dInfo":{"model":"WH-1000XM6","sVer":"0315"},
//  "btInfo":{"codec":"A","cntQlty":"S",…}}
//
// The codec letter is what the phone's Bluetooth stack negotiated.

/// `COMMON_GET_STATUS`.
pub fn get_common_status() -> Vec<u8> {
    vec![cmd::COMMON_GET_STATUS, 0x00]
}

/// Codec letter -> product name.
pub fn codec_name(letter: &str) -> &'static str {
    match letter {
        "S" => "SBC",
        "A" => "AAC",
        "L" => "LDAC",
        "1" => "aptX",
        "2" => "aptX HD",
        "3" => "LC3",
        _ => "Unknown",
    }
}

/// Pull the negotiated codec out of a `COMMON_RET_STATUS` JSON payload.
pub fn decode_common_codec(payload: &[u8]) -> Option<&'static str> {
    if payload.len() < 4 || payload[0] != cmd::COMMON_RET_STATUS {
        return None;
    }
    let text = String::from_utf8_lossy(&payload[2..]);
    let key = "\"codec\":\"";
    let start = text.find(key)? + key.len();
    let rest = &text[start..];
    let end = rest.find('"')?;
    Some(codec_name(&rest[..end]))
}

// ---------------------------------------------------------------------------
// General settings (sidetone, multipoint, touch panel)
// ---------------------------------------------------------------------------
//
// `GsInquiredType` slots are generic; the device names each slot in its
// capability response as ASCII, which is how these three were identified:
//   D1 -> SIDETONE_SETTING
//   D2 -> MULTIPOINT_SETTING
//   D3 -> TOUCH_PANEL_SETTING

/// One general-setting slot, as the device describes it.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct GsSetting {
    /// `GsInquiredType` wire byte (0xD1, 0xD2, 0xD3…).
    pub gs_type: u8,
    /// Device-provided identifier, e.g. `SIDETONE_SETTING`.
    pub label: String,
    /// Device-provided summary identifier, when present.
    pub summary: String,
    /// Current boolean value, when read.
    pub value: Option<bool>,
}

impl GsSetting {
    /// A human title derived from the device's identifier.
    pub fn title(&self) -> String {
        match self.label.as_str() {
            "SIDETONE_SETTING" => "Sidetone".into(),
            "MULTIPOINT_SETTING" => "Multipoint".into(),
            "TOUCH_PANEL_SETTING" => "Touch panel".into(),
            other => other
                .trim_end_matches("_SETTING")
                .split('_')
                .map(|w| {
                    let mut c = w.chars();
                    match c.next() {
                        Some(f) => f.to_uppercase().collect::<String>() + &c.as_str().to_lowercase(),
                        None => String::new(),
                    }
                })
                .collect::<Vec<_>>()
                .join(" "),
        }
    }

    pub fn detail(&self) -> &'static str {
        match self.label.as_str() {
            "SIDETONE_SETTING" => "Hear your own voice in calls.",
            "MULTIPOINT_SETTING" => "Stay connected to two devices at once.",
            "TOUCH_PANEL_SETTING" => "Use the touch sensor on the earcup.",
            _ => "",
        }
    }
}

/// `GENERAL_SETTING_GET_CAPABILITY` for one slot.
pub fn get_gs_capability(gs_type: u8) -> Vec<u8> {
    vec![cmd::GENERAL_SETTING_GET_CAPABILITY, gs_type]
}

/// `GENERAL_SETTING_GET_PARAM` for one slot.
pub fn get_gs_param(gs_type: u8) -> Vec<u8> {
    vec![cmd::GENERAL_SETTING_GET_PARAM, gs_type]
}

/// `GENERAL_SETTING_SET_PARAM` for a boolean slot. `ON = 0`, `OFF = 1`.
pub fn set_gs_boolean(gs_type: u8, on: bool) -> Vec<u8> {
    vec![
        cmd::GENERAL_SETTING_SET_PARAM,
        gs_type,
        0x00, // BOOLEAN_TYPE
        if on { 0x00 } else { 0x01 },
    ]
}

/// Decode a `GENERAL_SETTING_RET_CAPABILITY` payload into `(slot, label, summary)`.
///
/// Layout: `D1 <slot> <settingType> <len> <label ascii> [<len> <summary ascii>]`
pub fn decode_gs_capability(payload: &[u8]) -> Option<GsSetting> {
    if payload.len() < 5 || payload[0] != cmd::GENERAL_SETTING_RET_CAPABILITY {
        return None;
    }
    let gs_type = payload[1];
    let mut i = 4usize;
    let len = *payload.get(i)? as usize;
    i += 1;
    let label = String::from_utf8_lossy(payload.get(i..i + len)?).into_owned();
    i += len;
    let mut summary = String::new();
    if let Some(&slen) = payload.get(i) {
        i += 1;
        if let Some(bytes) = payload.get(i..i + slen as usize) {
            summary = String::from_utf8_lossy(bytes).into_owned();
        }
    }
    Some(GsSetting { gs_type, label, summary, value: None })
}

/// Decode a `GENERAL_SETTING_RET_PARAM` boolean payload into `(slot, value)`.
pub fn decode_gs_param(payload: &[u8]) -> Option<(u8, bool)> {
    if payload.len() < 4 || payload[0] != cmd::GENERAL_SETTING_RET_PARAM {
        return None;
    }
    if payload[2] != 0x00 {
        return None; // not a boolean slot
    }
    Some((payload[1], payload[3] == 0x00))
}

/// `EQEBB_GET_CAPABILITY` for the preset equaliser.
pub fn get_eq_capability() -> Vec<u8> {
    vec![cmd::EQEBB_GET_CAPABILITY, eqebb_type::PRESET_EQ]
}

/// `EQEBB_GET_CAPABILITY` for Clear Bass.
pub fn get_clear_bass_capability() -> Vec<u8> {
    vec![cmd::EQEBB_GET_CAPABILITY, eqebb_type::EBB]
}

/// `EQEBB_GET_STATUS` for the preset equaliser (on/off).
pub fn get_eq_status() -> Vec<u8> {
    get_eq_status_of(eqebb_type::PRESET_EQ)
}

/// `EQEBB_GET_STATUS` in a given inquired type. The WH-1000XM6 answers only
/// `52 04` (`53 04 00 00`, HW); `52 00` is acknowledged and never answered.
pub fn get_eq_status_of(inquired: u8) -> Vec<u8> {
    vec![cmd::EQEBB_GET_STATUS, inquired]
}

/// `EQEBB_GET_PARAM` for the preset equaliser (preset + band gains).
pub fn get_eq_param() -> Vec<u8> {
    vec![cmd::EQEBB_GET_PARAM, eqebb_type::PRESET_EQ]
}

/// `EQEBB_SET_PARAM` for the preset equaliser.
///
/// Layout: command, inquired type, preset id, band count, band steps.
pub fn set_eq_preset(preset: u8, band_steps: &[u8]) -> Vec<u8> {
    let mut v = vec![cmd::EQEBB_SET_PARAM, eqebb_type::PRESET_EQ, preset];
    v.push(band_steps.len().min(255) as u8);
    v.extend_from_slice(&band_steps[..band_steps.len().min(255)]);
    v
}

/// `EQEBB_GET_PARAM` for Clear Bass.
pub fn get_clear_bass() -> Vec<u8> {
    vec![cmd::EQEBB_GET_PARAM, eqebb_type::EBB]
}

/// `EQEBB_SET_PARAM` for Clear Bass.
pub fn set_clear_bass(level: i8, min: i8, max: i8) -> Vec<u8> {
    vec![cmd::EQEBB_SET_PARAM, eqebb_type::EBB, level.clamp(min, max) as u8]
}

/// `PresetEqErrorCodeType`: why the device turned the equaliser off.
pub mod preset_eq_error {
    pub const CALLING: u8 = 0x00;
    pub const DEMO_MODE: u8 = 0x01;
    pub const LISTENING_MODE: u8 = 0x02;
    pub const OTHER: u8 = 0xFE;
    pub const OUT_OF_RANGE: u8 = 0xFF;
}

/// Decoded `EQEBB_RET_STATUS` / `EQEBB_NTFY_STATUS` for the preset equaliser.
///
/// Layout: 0 command, 1 inquired type, 2 `EnableDisable` (0 = enabled).
pub fn decode_eq_status(payload: &[u8]) -> Option<bool> {
    decode_eq_status_detail(payload).map(|(enabled, _)| enabled)
}

/// Status with the reasons the device gives for an equaliser that is off.
///
/// Type `PRESET_EQ` carries only `EnableDisable`. Type
/// `PRESET_EQ_AND_ERRORCODE` adds a counted `PresetEqErrorCodeType` list.
/// The WH-1000XM6 answers in the second shape: `55 04 01 01 02` (off,
/// listening mode) and `55 04 00 00` (on).
pub fn decode_eq_status_detail(payload: &[u8]) -> Option<(bool, Vec<u8>)> {
    if payload.len() < 3 {
        return None;
    }
    match payload[1] {
        eqebb_type::PRESET_EQ => Some((payload[2] == ENABLE, Vec::new())),
        eqebb_type::PRESET_EQ_AND_ERRORCODE => {
            let count = payload.get(3).copied().unwrap_or(0) as usize;
            let codes = payload.get(4..4 + count).map(<[u8]>::to_vec).unwrap_or_default();
            Some((payload[2] == ENABLE, codes))
        }
        _ => None,
    }
}

/// Decoded `EQEBB_RET_PARAM` for the preset equaliser.
///
/// Layout: 0 command, 1 inquired type, 2 preset id, 3 band count, 4.. steps.
///
/// The WH-1000XM6 confirms a write with type `PRESET_EQ_AND_ERRORCODE` in the
/// same layout (`59 04 A0 0A <10 steps>` after `58 00 A0 0A …`, HW), so both
/// types decode here.
pub fn decode_eq_param(payload: &[u8]) -> Option<(u8, Vec<u8>)> {
    if payload.len() < 4
        || !matches!(payload[1], eqebb_type::PRESET_EQ | eqebb_type::PRESET_EQ_AND_ERRORCODE)
    {
        return None;
    }
    let count = payload[3] as usize;
    if payload.len() < 4 + count {
        return None;
    }
    Some((payload[2], payload[4..4 + count].to_vec()))
}

/// Decoded `EQEBB_RET_PARAM` for Clear Bass.
pub fn decode_clear_bass(payload: &[u8]) -> Option<i8> {
    if payload.len() < 3 || payload[1] != eqebb_type::EBB {
        return None;
    }
    Some(payload[2] as i8)
}

/// Decoded equaliser capability: band count, step granularity, and the presets
/// the device offers as `(wire id, product name)`.
pub type EqCapability = (u8, u8, Vec<(u8, String)>);

/// Decoded `EQEBB_RET_CAPABILITY` for the preset equaliser.
///
/// The device may answer a `PRESET_EQ` capability request with any of three
/// multiplexed shapes, and the WH-1000XM6 in fact answers with
/// `PRESET_EQ_AND_ERRORCODE`:
///
/// | Inquired type | Layout |
/// | --- | --- |
/// | `PRESET_EQ` (0x00) | band@2, step@3, count@4, presets@5 |
/// | `PRESET_EQ_AND_ULT_MODE` (0x03) | band@2, step@3, ult2@4, count@5, presets@6 |
/// | `PRESET_EQ_AND_ERRORCODE` (0x04) | band@2, step@3, count@4, presets@5 |
///
/// Presets are `(id, name length, name)` triples; the length may be zero, in
/// which case the device offers the preset without naming it.
pub fn decode_eq_capability(payload: &[u8]) -> Option<EqCapability> {
    if payload.len() < 5 {
        return None;
    }
    let count_idx = match payload[1] {
        eqebb_type::PRESET_EQ | eqebb_type::PRESET_EQ_AND_ERRORCODE => 4,
        eqebb_type::PRESET_EQ_AND_ULT_MODE => 5,
        _ => return None,
    };
    let band_count = payload[2];
    let step = payload[3];
    let count = *payload.get(count_idx)? as usize;
    let mut i = count_idx + 1;
    let mut presets = Vec::with_capacity(count);
    for _ in 0..count {
        let id = *payload.get(i)?;
        let len = *payload.get(i + 1)? as usize;
        let name = payload.get(i + 2..i + 2 + len)?;
        presets.push((id, String::from_utf8_lossy(name).into_owned()));
        i += 2 + len;
    }
    Some((band_count, step, presets))
}

/// Decoded `EQEBB_RET_CAPABILITY` for Clear Bass: `(min, max)`.
pub fn decode_clear_bass_capability(payload: &[u8]) -> Option<(i8, i8)> {
    if payload.len() < 4 || payload[1] != eqebb_type::EBB {
        return None;
    }
    Some((payload[2] as i8, payload[3] as i8))
}

/// Decode `LEFT_RIGHT_BATTERY`: 0 cmd, 1 type, 2 left, 3 right, 4 charging.
pub fn decode_battery_lr(payload: &[u8]) -> Option<(u8, u8, u8)> {
    if payload.len() < 5 {
        return None;
    }
    let (l, r) = (payload[2], payload[3]);
    if l > 100 || r > 100 {
        return None;
    }
    Some((l, r, payload[4]))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn eq_error_code_shapes_from_the_xm6_decode() {
        // Captured on the WH-1000XM6: off because of the listening mode, then on.
        assert_eq!(
            decode_eq_status_detail(&[0x55, 0x04, 0x01, 0x01, 0x02]),
            Some((false, vec![preset_eq_error::LISTENING_MODE]))
        );
        assert_eq!(decode_eq_status_detail(&[0x55, 0x04, 0x00, 0x00]), Some((true, vec![])));
        assert_eq!(decode_eq_status(&[0x53, 0x00, 0x00]), Some(true));
        // Write confirmation in the error-code type, same layout as PRESET_EQ.
        let ntfy = [0x59, 0x04, 0x30, 0x0A, 0x0A, 0x0A, 0x05, 0x05, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06];
        assert_eq!(
            decode_eq_param(&ntfy),
            Some((0x30, vec![0x0A, 0x0A, 0x05, 0x05, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06]))
        );
        assert_eq!(decode_eq_param(&[0x59, 0x03, 0x30, 0x00]), None);
    }

    #[test]
    fn series_and_color_reply_decodes_bytes_not_text() {
        assert_eq!(decode_series_and_color(&[0x05, 0x03, 0x10, 0x01]), Some((0x10, 0x01)));
        assert_eq!(decode_series_and_color(&[0x05, 0x01, 0x10, 0x01]), None);
        assert_eq!(decode_series_and_color(&[0x05, 0x03, 0x10]), None);
        assert_eq!(get_device_info(device_info_type::SERIES_AND_COLOR_INFO), vec![0x04, 0x03]);
    }

    #[test]
    fn battery_report_decodes() {
        let payload = [cmd::POWER_RET_STATUS, power_type::BATTERY, 87, charging::CHARGING];
        let b = decode_battery(&payload).expect("valid battery");
        assert_eq!(b.level, 87);
        assert!(b.charging == charging::CHARGING);
    }

    #[test]
    fn battery_rejects_out_of_range() {
        let payload = [cmd::POWER_RET_STATUS, power_type::BATTERY, 200, 0];
        assert!(decode_battery(&payload).is_none());
        assert!(decode_battery(&payload[..3]).is_none());
    }

    #[test]
    fn auto_power_off_wearing_decodes() {
        let payload = [cmd::POWER_RET_PARAM, 0x05, 0x10, 0x11];
        assert_eq!(decode_auto_power_off_wearing(&payload), Some((0x10, 0x11)));
        assert!(decode_auto_power_off_wearing(&[cmd::POWER_RET_PARAM, 0x05, 0x12, 0x10]).is_none());
        assert!(decode_auto_power_off_wearing(&[cmd::POWER_RET_PARAM, 0x05, 0x10]).is_none());
        assert_eq!(auto_power_off_wearing_label(0x10), "When taken off");
        assert_eq!(set_auto_power_off_wearing(0x11, 0x10), Some(vec![cmd::POWER_SET_PARAM, 0x05, 0x11, 0x10]));
    }

    #[test]
    fn table2_reads_decode() {
        assert_eq!(decode_music_hand_over(&[cmd::PERI_RET_PARAM, 0x03, 0x01]), Some(false));
        assert_eq!(decode_music_hand_over(&[cmd::PERI_RET_PARAM, 0x03, 0x00]), Some(true));
        assert_eq!(set_music_hand_over(true), vec![cmd::PERI_SET_PARAM, 0x03, 0x00]);
        assert_eq!(set_music_hand_over(false), vec![cmd::PERI_SET_PARAM, 0x03, 0x01]);
        assert_eq!(decode_usb_submersion(&[cmd::POWER_RET_STATUS, 0x02, 0x01]), Some(false));
        assert_eq!(decode_usb_submersion(&[cmd::POWER_RET_STATUS, 0x02, 0x00]), Some(true));
        assert!(decode_usb_submersion(&[cmd::POWER_RET_STATUS, 0x02, 0x02]).is_none());
    }

    #[test]
    fn pairing_device_list_decodes_both_shapes() {
        // Synthetic addresses and names: the shape is what matters, not the
        // real paired devices of the machine that captured it.
        let mut plain = vec![cmd::PERI_RET_PARAM, peri_type::PAIRING_DEVICE_MANAGEMENT, 2];
        plain.extend_from_slice(b"02:00:00:00:00:01");
        plain.extend_from_slice(&[0x02, 11]);
        plain.extend_from_slice(b"Test Laptop");
        plain.extend_from_slice(b"02:00:00:00:00:02");
        plain.extend_from_slice(&[0x00, 5]);
        plain.extend_from_slice(b"Phone");
        plain.push(0x01);

        let list = decode_pairing_devices(&plain).expect("plain list");
        assert_eq!(list.devices.len(), 2);
        assert_eq!(list.playback_device, 0x01);
        assert_eq!(list.devices[0].address, "02:00:00:00:00:01");
        assert!(list.devices[0].connected);
        assert_eq!(list.devices[0].class_of_device, None);
        assert_eq!(list.devices[1].name, "Phone");
        assert!(!list.devices[1].connected);

        let mut with_cod = vec![cmd::PERI_RET_PARAM, peri_type::PAIRING_DEVICE_MANAGEMENT_WITH_COD, 2];
        with_cod.extend_from_slice(b"02:00:00:00:00:01");
        with_cod.extend_from_slice(&[0x02, 0x38, 0x01, 0x0C, 11]);
        with_cod.extend_from_slice(b"Test Laptop");
        with_cod.extend_from_slice(b"02:00:00:00:00:02");
        with_cod.extend_from_slice(&[0x00, 0xFF, 0xFF, 0xFF, 5]);
        with_cod.extend_from_slice(b"Phone");
        with_cod.push(0x01);

        let list = decode_pairing_devices(&with_cod).expect("list with CoD");
        assert_eq!(list.devices[0].class_of_device, Some(0x38_01_0C));
        assert_eq!(list.devices[1].class_of_device, Some(0xFF_FF_FF));

        let mut notified = with_cod.clone();
        notified[0] = cmd::PERI_NTFY_PARAM;
        assert_eq!(decode_pairing_devices(&notified), Some(list));

        // A headset with no paired devices is a valid empty list.
        let empty = [cmd::PERI_RET_PARAM, peri_type::PAIRING_DEVICE_MANAGEMENT_WITH_COD, 0x00, 0x00];
        let list = decode_pairing_devices(&empty).expect("empty list");
        assert!(list.devices.is_empty());
        assert_eq!(list.playback_device, 0x00);

        // Truncated frame, zero-length name and unknown shape are rejected.
        assert!(decode_pairing_devices(&with_cod[..with_cod.len() - 2]).is_none());
        let zero_name = [cmd::PERI_RET_PARAM, peri_type::PAIRING_DEVICE_MANAGEMENT, 1];
        assert!(decode_pairing_devices(&zero_name).is_none());
        assert!(decode_pairing_devices(&[cmd::PERI_RET_PARAM, 0x01, 0x00, 0x00]).is_none());
    }

    #[test]
    fn pairing_capability_decodes_captured_shape() {
        assert_eq!(
            get_pairing_capability(),
            vec![cmd::PERI_GET_CAPABILITY, peri_type::PAIRING_DEVICE_MANAGEMENT]
        );
        assert_eq!(
            decode_pairing_capability(&[cmd::PERI_RET_CAPABILITY, 0x00, 0x08, 0x02, 0x00]),
            Some(PairingCapability { max_paired: 8, max_connected: 2, file_transfer: 0 })
        );
        assert!(decode_pairing_capability(&[cmd::PERI_RET_CAPABILITY, 0x00, 0x08, 0x02]).is_none());
        assert!(
            decode_pairing_capability(&[cmd::PERI_RET_CAPABILITY, 0x01, 0x08, 0x02, 0x00])
                .is_none()
        );
    }

    #[test]
    fn pairing_connection_and_mode_shapes() {
        let address = "02:00:00:00:00:01";
        let connect = set_pairing_connection(pairing_action::CONNECT, address).expect("connect");
        assert_eq!(connect.len(), 20);
        assert_eq!(&connect[..3], &[cmd::PERI_SET_EX_PARAM, 0x02, 0x01]);
        assert_eq!(&connect[3..], address.as_bytes());

        let disconnect =
            set_pairing_connection(pairing_action::DISCONNECT, address).expect("disconnect");
        assert_eq!(disconnect[2], 0x00);

        assert!(set_pairing_connection(0x01, "02:00:00:00:00").is_none());
        assert!(set_pairing_connection(0x01, "02-00-00-00-00-01").is_none());
        assert!(set_pairing_connection(0x03, address).is_none());

        assert_eq!(
            set_pairing_mode(true),
            vec![cmd::PERI_SET_STATUS, 0x00, pairing_mode::INQUIRY_SCAN, 0x00]
        );
        assert_eq!(
            set_pairing_mode(false),
            vec![cmd::PERI_SET_STATUS, 0x00, pairing_mode::NORMAL, 0x00]
        );

        let mut event = vec![cmd::PERI_NTFY_EX_PARAM, 0x02, 0x01, 0x12];
        event.extend_from_slice(address.as_bytes());
        let event = decode_pairing_connection_event(&event).expect("connection event");
        assert_eq!(event.action, pairing_action::CONNECT);
        assert_eq!(event.result, pairing_result::CONNECTION_IN_PROGRESS);
        assert_eq!(event.address, address);
        assert_eq!(pairing_result_label(0x10), "Connected");
        assert!(pairing_result_is_success(0x10));
        assert!(!pairing_result_is_success(0x12));
        assert!(decode_pairing_connection_event(&[cmd::PERI_NTFY_EX_PARAM, 0x02]).is_none());
    }

    #[test]
    fn pairing_status_shapes_decode() {
        assert_eq!(get_pairing_status(), vec![cmd::PERI_GET_STATUS, 0x00]);
        assert_eq!(
            decode_pairing_status(&[cmd::PERI_RET_STATUS, 0x00, 0x01, 0x00]),
            Some(PairingModeStatus { mode: pairing_mode::INQUIRY_SCAN, enabled: true })
        );
        assert_eq!(
            decode_pairing_status(&[cmd::PERI_NTFY_STATUS, 0x00, 0x00, 0x00]),
            Some(PairingModeStatus { mode: pairing_mode::NORMAL, enabled: true })
        );
        assert_eq!(pairing_mode_label(0x01), "Pairing mode");
        assert_eq!(pairing_mode_label(0x00), "Normal");
        assert!(decode_pairing_status(&[cmd::PERI_RET_STATUS, 0x00, 0x02, 0x00]).is_none());
        assert!(decode_pairing_status(&[cmd::PERI_RET_STATUS, 0x00, 0x00]).is_none());
    }

    #[test]
    fn pairing_status_notification_uses_cod_type_on_xm6() {
        // HW, WH-1000XM6 3.1.5: `34 00 01 00` -> `35 02 01 00`,
        // `34 00 00 00` -> `35 02 00 00`. The write uses inquired type 0x00 but
        // the device notifies with 0x02 (PAIRING_DEVICE_MANAGEMENT_WITH_COD).
        assert_eq!(
            decode_pairing_status(&[cmd::PERI_NTFY_STATUS, 0x02, 0x01, 0x00]),
            Some(PairingModeStatus { mode: pairing_mode::INQUIRY_SCAN, enabled: true })
        );
        assert_eq!(
            decode_pairing_status(&[cmd::PERI_NTFY_STATUS, 0x02, 0x00, 0x00]),
            Some(PairingModeStatus { mode: pairing_mode::NORMAL, enabled: true })
        );
        // Other PERI types are not pairing-mode status.
        assert!(decode_pairing_status(&[cmd::PERI_NTFY_STATUS, 0x03, 0x00, 0x00]).is_none());
    }

    #[test]
    fn playback_status_decodes_captured_payload() {
        let payload = [cmd::PLAY_RET_STATUS, 0x01, 0x00, 0x02, 0x00];
        let play = decode_playback_status(&payload).expect("valid playback");
        assert!(play.enabled);
        assert_eq!(play.playback, 2);
        assert_eq!(play.source, 0);
        assert!(decode_playback_status(&[cmd::PLAY_RET_STATUS, 0x01, 0, 4, 0]).is_none());
    }

    #[test]
    fn playback_volume_builds_and_decodes() {
        assert_eq!(get_playback_capability(), vec![cmd::PLAY_GET_CAPABILITY, 0x01]);
        assert_eq!(
            decode_playback_volume_capability(&[cmd::PLAY_RET_CAPABILITY, 0x01, 30, 15]),
            Some((30, 15))
        );
        assert!(decode_playback_volume_capability(&[cmd::PLAY_RET_CAPABILITY, 0x01, 30]).is_none());

        assert_eq!(get_music_volume(), vec![cmd::PLAY_GET_PARAM, 0x20]);
        assert_eq!(decode_music_volume(&[cmd::PLAY_RET_PARAM, 0x20, 17]), Some(17));
        assert!(decode_music_volume(&[cmd::PLAY_RET_PARAM, 0x21, 17]).is_none());
        assert_eq!(set_music_volume(17), vec![cmd::PLAY_SET_PARAM, 0x20, 17]);

        assert_eq!(get_call_volume(), vec![cmd::PLAY_GET_PARAM, 0x21]);
        assert_eq!(decode_call_volume(&[cmd::PLAY_RET_PARAM, 0x21, 9]), Some(9));
        assert!(decode_call_volume(&[cmd::PLAY_RET_PARAM, 0x20, 9]).is_none());
        assert_eq!(set_call_volume(9), vec![cmd::PLAY_SET_PARAM, 0x21, 9]);
    }

    #[test]
    fn listening_mode_builds_and_decodes() {
        // Read requests use AUDIO_GET_PARAM; the XM6 advertises type 0x09.
        assert_eq!(get_bgm_mode(), vec![cmd::AUDIO_GET_PARAM, 0x09]);
        assert_eq!(get_cinema_mode(), vec![cmd::AUDIO_GET_PARAM, 0x04]);

        // `E7 09 <onOff> <room>` is the BGM param reply.
        assert_eq!(decode_bgm_mode(&[cmd::AUDIO_RET_PARAM, 0x09, 0x00, 0x01]), Some((true, 1)));
        assert_eq!(decode_bgm_mode(&[cmd::AUDIO_RET_PARAM, 0x09, 0x01, 0x02]), Some((false, 2)));
        // The legacy type 0x03 uses the same shape.
        assert_eq!(decode_bgm_mode(&[cmd::AUDIO_RET_PARAM, 0x03, 0x00, 0x00]), Some((true, 0)));
        assert!(decode_bgm_mode(&[cmd::AUDIO_RET_PARAM, 0x09, 0x02, 0x00]).is_none());
        assert!(decode_bgm_mode(&[cmd::AUDIO_RET_PARAM, 0x09, 0x00, 0x03]).is_none());

        // Cinema is `E7 04 <onOff>`; ON is 0.
        assert_eq!(decode_cinema_mode(&[cmd::AUDIO_RET_PARAM, 0x04, 0x00]), Some(true));
        assert_eq!(decode_cinema_mode(&[cmd::AUDIO_RET_PARAM, 0x04, 0x01]), Some(false));
        assert!(decode_cinema_mode(&[cmd::AUDIO_RET_PARAM, 0x09, 0x00]).is_none());

        // Setters mirror the shipped `a1.b.h()` and `g1.b.h()` builders.
        assert_eq!(set_bgm_mode(true, room_size::SMALL), Some(vec![0xE8, 0x09, 0x00, 0x00]));
        assert_eq!(set_bgm_mode(false, room_size::LARGE), Some(vec![0xE8, 0x09, 0x01, 0x02]));
        assert_eq!(set_bgm_mode(true, 3), None);
        assert_eq!(set_cinema_mode(true), vec![0xE8, 0x04, 0x00]);
        assert_eq!(set_cinema_mode(false), vec![0xE8, 0x04, 0x01]);
    }

    #[test]
    fn listening_state_derives_mode() {
        let mut s = ListeningState::default();
        assert_eq!(s.mode(), ListeningMode::Normal);
        s.cinema_on = true;
        assert_eq!(s.mode(), ListeningMode::Cinema);
        s.bgm_on = true;
        assert_eq!(s.mode(), ListeningMode::Bgm);
        assert_eq!(ListeningMode::from_code(2), Some(ListeningMode::Cinema));
        assert_eq!(ListeningMode::from_code(9), None);
    }

    #[test]
    fn lea_switch_compat_shape_decodes() {
        assert_eq!(get_le_audio_switch_compat(), vec![0x60, 0x01]);
        assert_eq!(
            decode_le_audio_switch_compat(&[0x61, 0x01, 0x03]),
            Some(3)
        );
        assert_eq!(decode_le_audio_switch_compat(&[0x61, 0x00, 0x03]), None);
    }

    #[test]
    fn adaptive_control_shapes_decode() {
        assert_eq!(set_sense_control(true), vec![0x74, 0x01, 0x01]);
        assert_eq!(set_sense_control(false), vec![0x74, 0x01, 0x00]);
        assert_eq!(decode_sense_control(&[0x75, 0x01, 0x01]), Some(true));
        assert_eq!(decode_sense_control(&[0x75, 0x01, 0x00]), Some(false));
    }

    #[test]
    fn adaptive_parameter_notification_decodes() {
        let payload = [
            cmd::SENSE_NTFY_PARAM,
            sense_type::ADAPTIVE_CONTROL_WITH_PARAMETER_NOTIFICATION,
            0x03,
            0x00, 0x10, 0x02,
            0x00, 0x20, 0x00,
            0x01, 0x00, 0x01, 0x01, 0x00, 0x05, 0x00,
        ];
        let parameter = decode_sense_parameter(&payload).expect("sense parameter");
        assert_eq!(parameter.functions.len(), 3);
        assert_eq!(parameter.functions[0].function, 0x10);
        assert_eq!(parameter.functions[0].data, vec![0x02]);
        assert_eq!(parameter.functions[1].function, 0x20);
        assert_eq!(parameter.functions[2].result, 1);
        assert_eq!(parameter.functions[2].data.len(), 5);
        assert_eq!(sense_function_name(0x10), "EQ preset");
        assert!(decode_sense_parameter(&payload[..payload.len() - 1]).is_none());
    }

    #[test]
    fn quick_access_easy_shapes_decode() {
        assert_eq!(
            set_quick_access_functions(&[0x01, 0x0A]),
            Some(vec![0xF8, 0x02, 0x00, 0x00, 0x02, 0x01, 0x0A])
        );
        assert!(set_quick_access_functions(&[]).is_none());
        assert_eq!(decode_quick_access_result(&[0xF9, 0x02, 0x00]), Some(0));
        assert_eq!(decode_quick_access_result(&[0xF9, 0x02, 0x01]), Some(1));
    }

    #[test]
    fn alert_shape_decodes() {
        assert_eq!(decode_alert_param(&[0x99, 0x00, 0x01, 0x00]), Some((0, 1, 0)));
        assert_eq!(decode_alert_param(&[0x99, 0x05, 0x02, 0x01]), Some((5, 2, 1)));
        assert_eq!(alert_type_name(0), "Fixed message");
        assert_eq!(alert_type_name(5), "LE Audio alert");
    }

    #[test]
    fn sense_capability_shape_decodes() {
        assert_eq!(get_sense_capability(), vec![0x70, 0x01]);
        assert_eq!(
            decode_sense_capability(&[0x71, 0x01, 0x03, 0x08, 0x10, 0x20]),
            Some(vec![0x03, 0x08, 0x10, 0x20])
        );
    }

    #[test]
    fn control_by_wearing_shapes_decode() {
        assert_eq!(get_control_by_wearing(), vec![0xF6, 0x01]);
        assert_eq!(decode_control_by_wearing(&[0xF7, 0x01, 0x00]), Some(true));
        assert_eq!(get_control_by_wearing_status(), vec![0xF2, 0x01]);
        assert_eq!(
            decode_control_by_wearing_status(&[0xF3, 0x01, 0x00]),
            Some(true)
        );
        assert_eq!(set_control_by_wearing(false), vec![0xF8, 0x01, 0x01]);
    }

    #[test]
    fn mic_on_off_shapes_decode() {
        assert_eq!(get_mic_on_off(), vec![0xF2, 0x0B]);
        assert_eq!(decode_mic_on_off(&[0xF3, 0x0B, 0x00]), Some(true));
        assert_eq!(decode_mic_on_off(&[0xF3, 0x0B, 0x01]), Some(false));
        assert_eq!(decode_mic_notify(&[0xF9, 0x0B, 0x01, 0x00]), Some((false, true)));
        assert_eq!(set_mic_on_off(false), vec![0xF8, 0x0B, 0x01]);
        assert_eq!(get_mic_capability(), vec![0xF0, 0x0B]);
        assert_eq!(decode_mic_capability(&[0xF1, 0x0B, 0x01]), Some(1));
    }

    #[test]
    fn sony_va_and_link_switch_shapes_decode() {
        assert_eq!(get_sony_voice_assistant_status(), vec![0xF2, 0x05]);
        assert_eq!(
            decode_sony_voice_assistant_status(&[0xF3, 0x05, 0x00]),
            Some(true)
        );
        assert_eq!(
            set_sony_voice_assistant_enabled(false),
            vec![0xF4, 0x05, 0x01]
        );
        assert_eq!(
            decode_sony_voice_assistant_language(&[0xF7, 0x05, 0x00]),
            Some(0)
        );
        assert_eq!(get_link_auto_switch_status(), vec![0xF2, 0x0A]);
        assert_eq!(
            decode_link_auto_switch_status(&[0xF3, 0x0A, 0x00]),
            Some(true)
        );
        let mut param = vec![0xF7, 0x0A, 0x00, 0x12, 0x34];
        param.extend_from_slice(b"AA:BB:CC:DD:EE:FF");
        assert_eq!(
            decode_link_auto_switch_param(&param),
            Some((true, 0x1234, "AA:BB:CC:DD:EE:FF".to_string()))
        );
    }

    #[test]
    fn voice_guidance_shapes_decode() {
        assert_eq!(get_voice_guidance_status(), vec![0x42, 0x01, 0x00]);
        assert_eq!(get_voice_guidance_language(), vec![0x42, 0x01, 0x01]);
        assert_eq!(get_voice_guidance_param(), vec![0x46, 0x01]);
        assert_eq!(
            decode_voice_guidance_status(&[0x43, 0x01, 0x00, 0x00]),
            Some(true)
        );
        assert_eq!(
            decode_voice_guidance_language(&[0x43, 0x01, 0x01, 0x01]),
            Some(1)
        );
        assert_eq!(
            decode_voice_guidance_status(&[0x43, 0x01, 0x00, 0x01]),
            Some(false)
        );
        assert_eq!(
            decode_voice_guidance_param(&[0x47, 0x01, 0x00, 0x01]),
            Some(true)
        );
        assert_eq!(
            decode_voice_guidance_param(&[0x47, 0x01, 0x01, 0x01]),
            Some(false)
        );
        assert_eq!(
            decode_voice_guidance_param(&[0x49, 0x01, 0x01]),
            Some(false)
        );
        assert_eq!(
            decode_voice_guidance_param(&[0x49, 0x01, 0x00]),
            Some(true)
        );
        assert_eq!(
            set_voice_guidance_enabled(true),
            vec![0x48, 0x01, 0x00]
        );
        assert_eq!(
            set_voice_guidance_enabled(false),
            vec![0x48, 0x01, 0x01]
        );
        assert_eq!(get_voice_guidance_volume(), vec![0x46, 0x20]);
        assert_eq!(decode_voice_guidance_volume(&[0x47, 0x20, 0x05]), Some(5));
        assert_eq!(
            set_voice_guidance_volume(-2, true),
            vec![0x48, 0x20, 0xFE, 0x00]
        );
    }

    #[test]
    fn head_gesture_training_shapes_decode() {
        assert_eq!(
            set_head_gesture_training(true),
            vec![cmd::SYSTEM_SET_STATUS, 0x10, 0x00]
        );
        assert_eq!(
            set_head_gesture_training(false),
            vec![cmd::SYSTEM_SET_STATUS, 0x10, 0x01]
        );
        assert_eq!(
            decode_head_gesture_training_status(&[cmd::SYSTEM_NTFY_STATUS, 0x10, 0x00, 0x00]),
            Some((0, true))
        );
        assert_eq!(
            decode_head_gesture_training_status(&[cmd::SYSTEM_NTFY_STATUS, 0x10, 0x01, 0x00]),
            Some((1, true))
        );
        assert_eq!(
            decode_head_gesture_action(&[cmd::SYSTEM_NTFY_PARAM, 0x10, 0x01]),
            Some(1)
        );
    }

    #[test]
    fn safe_volume_shapes_decode() {
        assert_eq!(get_safe_volume_level(), vec![cmd::SAFE_LISTENING_GET_PARAM, 0x04]);
        assert_eq!(
            decode_safe_volume_level(&[cmd::SAFE_LISTENING_RET_PARAM, 0x04, 0x01]),
            Some(1)
        );
        assert_eq!(
            set_safe_volume_level(1),
            Some(vec![cmd::SAFE_LISTENING_SET_STATUS, 0x04, 0x01])
        );
        assert!(set_safe_volume_level(2).is_none());
    }

    #[test]
    fn quick_access_decodes() {
        assert_eq!(get_quick_access(), vec![cmd::SYSTEM_GET_PARAM, 0x0D]);
        assert_eq!(
            decode_quick_access(&[cmd::SYSTEM_RET_PARAM, 0x0D, 0x02, 0x01, 0x0A]),
            Some(vec![0x01, 0x0A])
        );
        assert!(decode_quick_access(&[cmd::SYSTEM_RET_PARAM, 0x0D, 0x02, 0x01]).is_none());
        assert_eq!(quick_access_name(0x01), "NC/ASM off");
        assert_eq!(quick_access_name(0x0A), "Unnamed");
    }

    #[test]
    fn diagnostics_decode() {
        let mut ble = vec![cmd::COMMON_RET_CAPABILITY, 0x04];
        ble.extend_from_slice(b"2C:CA:16:75:76:32");
        ble.extend_from_slice(b"4C78CDDC");
        assert_eq!(
            decode_ble_setup(&ble),
            Some(("2C:CA:16:75:76:32".to_string(), "4C78CDDC".to_string()))
        );
        assert_eq!(decode_gatt_status(&[cmd::SAR_RET_STATUS, 0x10, 0x00]), Some(true));
        assert_eq!(
            decode_sar_optimization_status(&[cmd::SAR_RET_STATUS, 0x21, 0x00, 0x00]),
            Some((true, 0))
        );
        assert_eq!(
            decode_auto_play_capability(&[cmd::SAR_RET_CAPABILITY, 0x02, 0x4B, 0xEC]),
            Some(0x4BEC)
        );
        assert_eq!(
            decode_repeat_tap_status(&[cmd::SYSTEM_RET_STATUS, 0x01, 0x01]),
            Some(1)
        );
    }

    #[test]
    fn head_gesture_shapes_decode() {
        assert_eq!(get_head_gesture(), vec![cmd::SYSTEM_GET_STATUS, 0x0F]);
        assert_eq!(
            decode_head_gesture(&[cmd::SYSTEM_RET_STATUS, 0x0F, 0x00]),
            Some(true)
        );
        assert_eq!(
            decode_head_gesture(&[cmd::SYSTEM_RET_STATUS, 0x0F, 0x01]),
            Some(false)
        );
        assert_eq!(
            set_head_gesture(true),
            vec![cmd::SYSTEM_SET_STATUS, 0x0F, 0x00]
        );
    }

    #[test]
    fn power_off_frame() {
        assert_eq!(power_off(), vec![cmd::POWER_SET_STATUS, 0x03, 0x01]);
    }

    #[test]
    fn smart_talking_shapes_decode() {
        assert_eq!(get_smart_talking_status(), vec![cmd::SYSTEM_GET_STATUS, 0x0C]);
        assert_eq!(
            decode_smart_talking_status(&[cmd::SYSTEM_RET_STATUS, 0x0C, 0x00, 0x01]),
            Some((true, 1))
        );
        assert_eq!(get_smart_talking_param(), vec![cmd::SYSTEM_GET_PARAM, 0x0C]);
        assert_eq!(
            decode_smart_talking_param(&[cmd::SYSTEM_RET_PARAM, 0x0C, 0x00, 0x01]),
            Some((true, false))
        );
        assert_eq!(get_smart_talking_ext(), vec![cmd::SYSTEM_GET_EXT_PARAM, 0x0C]);
        assert_eq!(
            decode_smart_talking_ext(&[cmd::SYSTEM_RET_EXT_PARAM, 0x0C, 0x01, 0x02]),
            Some((1, 2))
        );
        assert_eq!(
            set_smart_talking_enabled(true, false),
            vec![cmd::SYSTEM_SET_PARAM, 0x0C, 0x00, 0x01]
        );
        assert_eq!(
            set_smart_talking_detail(2, 3),
            Some(vec![cmd::SYSTEM_SET_EXT_PARAM, 0x0C, 0x02, 0x03])
        );
        assert!(set_smart_talking_detail(3, 0).is_none());
    }

    #[test]
    fn auto_standby_capability_decodes() {
        assert_eq!(get_auto_standby(), vec![cmd::POWER_GET_CAPABILITY, 0x00]);
        assert_eq!(decode_auto_standby(&[cmd::POWER_RET_CAPABILITY, 0x00, 0x00]), Some(true));
        assert_eq!(decode_auto_standby(&[cmd::POWER_RET_CAPABILITY, 0x00, 0x01]), Some(false));
        assert!(decode_auto_standby(&[cmd::POWER_RET_CAPABILITY, 0x00]).is_none());

        assert_eq!(get_auto_standby_status(), vec![cmd::POWER_GET_STATUS, 0x00]);
        assert_eq!(decode_auto_standby_status(&[cmd::POWER_RET_STATUS, 0x00, 0x00]), Some(true));
        assert_eq!(decode_auto_standby_status(&[cmd::POWER_RET_STATUS, 0x00, 0x01]), Some(false));

        assert_eq!(get_auto_standby_param(), vec![cmd::POWER_GET_PARAM, 0x00]);
        assert_eq!(decode_auto_standby_param(&[cmd::POWER_RET_PARAM, 0x00, 0x00]), Some(true));
        assert_eq!(decode_auto_standby_param(&[cmd::POWER_RET_PARAM, 0x00, 0x01]), Some(false));
        assert_eq!(set_auto_standby(true), vec![cmd::POWER_SET_PARAM, 0x00, 0x00]);
        assert_eq!(set_auto_standby(false), vec![cmd::POWER_SET_PARAM, 0x00, 0x01]);
    }

    #[test]
    fn auto_volume_status_decodes() {
        assert_eq!(get_auto_volume(), vec![cmd::SYSTEM_GET_STATUS, 0x04]);
        assert_eq!(decode_auto_volume(&[cmd::SYSTEM_RET_STATUS, 0x04, 0x00]), Some(true));
        assert_eq!(decode_auto_volume(&[cmd::SYSTEM_RET_STATUS, 0x04, 0x01]), Some(false));
        assert!(decode_auto_volume(&[cmd::SYSTEM_RET_STATUS, 0x06, 0x00]).is_none());
        assert!(decode_auto_volume(&[cmd::SYSTEM_RET_STATUS, 0x04, 0x02]).is_none());
    }

    #[test]
    fn wearing_status_decodes_captured_payload() {
        // Exact payload captured from WH-1000XM6 firmware 3.1.5 after `F2 06`.
        let payload = [cmd::SYSTEM_RET_STATUS, 0x06, 0x00, 0x00, 0xF0, 0x00];
        let w = decode_wearing_status(&payload).expect("valid wearing status");
        assert!(w.detection_enabled);
        assert!(!w.worn);
        assert_eq!(w.selected_earpieces, 0xF0);
        assert_eq!(w.result_code, 0);
    }

    #[test]
    fn wearing_status_rejects_short_or_invalid_payloads() {
        assert!(decode_wearing_status(&[cmd::SYSTEM_RET_STATUS, 0x06]).is_none());
        assert!(decode_wearing_status(&[cmd::SYSTEM_RET_STATUS, 0x06, 2, 0, 0, 0]).is_none());
        assert!(decode_wearing_status(&[cmd::SYSTEM_RET_STATUS, 0x06, 0, 2, 0, 0]).is_none());
    }

    #[test]
    fn noise_control_round_trips() {
        let payload = set_noise_control(0x17, true, nc_mode::ASM, asm_mode::VOICE, 12);
        let decoded = decode_noise_control(&payload).expect("valid ncasm");
        assert!(decoded.is_ambient());
        assert!(decoded.focus_on_voice());
        assert_eq!(decoded.ambient_level, 12);
    }

    #[test]
    fn noise_control_clamps_ambient_level() {
        let payload = set_noise_control(0x17, true, nc_mode::ASM, asm_mode::NORMAL, 99);
        assert_eq!(payload[6], 20);
    }

    #[test]
    fn noise_control_rejects_bad_level() {
        let payload = [cmd::NCASM_RET_PARAM, 0x17, 1, 1, 1, 0, 21];
        assert!(decode_noise_control(&payload).is_none());
    }

    #[test]
    fn left_right_battery_decodes() {
        let p = [cmd::POWER_RET_STATUS, power_type::LEFT_RIGHT_BATTERY, 90, 80, 0];
        assert_eq!(decode_battery_lr(&p), Some((90, 80, 0)));
    }

    #[test]
    fn eq_preset_round_trips() {
        let p = set_eq_preset(eq_preset::JAZZ, &[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
        assert_eq!(p[0], cmd::EQEBB_SET_PARAM);
        assert_eq!(p[1], eqebb_type::PRESET_EQ);
        assert_eq!(p[2], eq_preset::JAZZ);
        assert_eq!(p[3], 10);
        // Decode it back the way a RET_PARAM would arrive.
        let mut ret = p.clone();
        ret[0] = cmd::EQEBB_RET_PARAM;
        let (preset, steps) = decode_eq_param(&ret).expect("valid eq param");
        assert_eq!(preset, eq_preset::JAZZ);
        assert_eq!(steps, vec![1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    }

    #[test]
    fn clear_bass_is_signed_and_clamped() {
        let p = set_clear_bass(-12, -10, 10);
        assert_eq!(p, vec![cmd::EQEBB_SET_PARAM, eqebb_type::EBB, (-10i8) as u8]);
        assert_eq!(decode_clear_bass(&[cmd::EQEBB_RET_PARAM, eqebb_type::EBB, 0xF6]), Some(-10));
    }

    #[test]
    fn eq_status_uses_the_inverted_enable_value() {
        // EnableDisable.ENABLE == 0, so "enabled" is byte 0.
        assert_eq!(decode_eq_status(&[cmd::EQEBB_RET_STATUS, eqebb_type::PRESET_EQ, 0]), Some(true));
        assert_eq!(decode_eq_status(&[cmd::EQEBB_RET_STATUS, eqebb_type::PRESET_EQ, 1]), Some(false));
    }

    #[test]
    fn eq_capability_lists_presets_with_names() {
        let mut p = vec![
            cmd::EQEBB_RET_CAPABILITY,
            eqebb_type::PRESET_EQ,
            10,   // bands
            1,    // step
            2,    // preset count
            eq_preset::OFF,
            3,
        ];
        p.extend_from_slice(b"Off");
        p.push(eq_preset::ROCK);
        p.push(4);
        p.extend_from_slice(b"Rock");

        let (bands, step, presets) = decode_eq_capability(&p).expect("valid capability");
        assert_eq!((bands, step), (10, 1));
        assert_eq!(presets, vec![(eq_preset::OFF, "Off".into()), (eq_preset::ROCK, "Rock".into())]);
    }

    #[test]
    fn preset_ids_match_the_protocol_enum() {
        assert_eq!(eq_preset::OFF, 0x00);
        assert_eq!(eq_preset::ROCK, 0x01);
        assert_eq!(eq_preset::ACOUSTIC, 0x07);
        assert_eq!(eq_preset::BRIGHT, 0x10);
        assert_eq!(eq_preset::SPEECH, 0x17);
        assert_eq!(eq_preset::GAMING_EQ, 0x20);
        assert_eq!(eq_preset::HEAVY, 0x30);
        assert_eq!(eq_preset::CUSTOM, 0xA0);
        assert_eq!(eq_preset::USER_SETTING1, 0xA1);
        assert_eq!(eq_preset::ARTIST_COLLAB1, 0xB0);
        assert_eq!(eq_preset::UNSPECIFIED, 0xFF);
        assert_eq!(eq_preset_name(0x01), Some("Rock"));
        assert_eq!(eq_preset_name(0x09), None); // reserved
    }
}
