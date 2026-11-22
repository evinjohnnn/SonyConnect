//! Deterministic application-protocol simulator.
//!
//! This is a test double, not a claim about hardware. It speaks the same wire
//! format the engine produces — including the alternating sequence numbers and
//! the mandatory acknowledgements — so framing, sequencing and state
//! reconciliation can be exercised without a headphone. Simulator success is
//! never reported as hardware success.

use std::collections::VecDeque;

use crate::framing::{self, DataType, Frame, MdrTable};
use crate::protocol::{self, cmd, charging, nc_mode};

/// A scriptable fake headphone.
pub struct SimDevice {
    pub model: String,
    pub firmware: String,
    pub battery: u8,
    pub charging: u8,
    pub nc_enabled: bool,
    pub nc_mode: u8,
    pub ambient_mode: u8,
    pub ambient_level: u8,
    /// Preferred `NcAsmInquiredType` this fake device reports.
    pub ncasma_type: u8,
    /// General-setting slots the fake device describes: (type, label, value).
    pub gs_settings: Vec<(u8, &'static str, bool)>,
    /// Voice-assistant assignment and the assistants it offers.
    pub va_current: u8,
    pub va_supported: Vec<u8>,
    /// Negotiated codec letter.
    pub codec: &'static str,
    /// Table-2 peripheral / power reads.
    pub music_hand_over: bool,
    pub usb_submersion: bool,
    /// Paired-device management: address, name, connected, Class of Device.
    pub paired_devices: Vec<(String, String, bool, u32)>,
    /// Whether the fake device is in inquiry-scan (pairing) mode.
    pub pairing_mode: bool,
    /// Playback controller: state (0 unsettled, 1 play, 2 pause, 3 stop) and
    /// source (0 music, 1 call).
    pub playback: u8,
    pub play_source: u8,
    /// Volume steps advertised for music/calls, and the current music volume.
    pub volume_steps: u8,
    pub music_volume: u8,
    pub call_volume: u8,
    /// Wearing detection: detector enabled, headset currently worn.
    pub wearing_detection_enabled: bool,
    pub wearing: bool,
    /// Auto power off.
    pub auto_power_off: bool,
    /// Auto volume with limitation (table-2 SYSTEM status type 0x04).
    pub auto_volume: bool,
    /// Auto standby on/off (table-2 POWER type 0x00).
    pub auto_standby_enabled: bool,
    /// Speak-to-Chat.
    pub smart_talking_enabled: bool,
    pub head_gesture_enabled: bool,
    pub head_gesture_training: bool,
    pub voice_guidance: bool,
    pub sony_voice_assistant: bool,
    pub link_auto_switch: bool,
    pub quick_access: Vec<u8>,
    pub adaptive_control: bool,
    pub control_by_wearing: bool,
    pub control_by_wearing_available: bool,
    pub mic_on_off: bool,
    pub mic_sound_effect: bool,
    pub voice_guidance_volume: i8,
    pub smart_talking_sensitivity: u8,
    pub smart_talking_mode_out: u8,
    /// Wearing-detection auto-off: current and last selected elements.
    pub apow_current: u8,
    pub apow_last: u8,
    pub apow_enabled: bool,
    /// Connection mode flags: classic, LE.
    pub conn_classic: bool,
    pub conn_le: bool,
    /// Listening modes: BGM on/off with a room size, Cinema on/off.
    pub bgm_on: bool,
    pub bgm_room: u8,
    pub cinema_on: bool,
    /// Equaliser state.
    pub eq_enabled: bool,
    pub eq_preset: u8,
    pub eq_bands: Vec<u8>,
    pub clear_bass: i8,
    /// Sequence number for the next frame this device sends.
    tx_seq: u8,
    /// Sequence number of the last frame this device accepted.
    rx_last_seq: Option<u8>,
    /// When true, the next response is emitted with a broken checksum.
    pub corrupt_next: bool,
    /// When true, the device stops answering (models a dropped link).
    pub mute: bool,
    /// Frames received, for assertions.
    pub received: Vec<Vec<u8>>,
}

impl Default for SimDevice {
    fn default() -> Self {
        SimDevice {
            model: "SIM-WH".into(),
            firmware: "0.0.1".into(),
            battery: 64,
            charging: charging::NOT_CHARGING,
            nc_enabled: true,
            nc_mode: nc_mode::NC,
            ambient_mode: 0,
            ambient_level: 8,
            ncasma_type: 0x17,
            gs_settings: vec![
                (0xD1, "SIDETONE_SETTING", true),
                (0xD2, "MULTIPOINT_SETTING", true),
                (0xD3, "TOUCH_PANEL_SETTING", true),
            ],
            va_current: 0xFF,
            va_supported: vec![0x34, 0x30, 0x31],
            codec: "A",
            music_hand_over: false,
            usb_submersion: false,
            paired_devices: vec![
                (
                    "2C:CA:16:75:76:32".into(),
                    "Sim Laptop".into(),
                    true,
                    0x38_01_0C,
                ),
                ("C0:47:54:5B:98:70".into(), "Sim Phone".into(), false, 0xFF_FF_FF),
            ],
            pairing_mode: false,
            playback: 2,
            play_source: 0,
            volume_steps: 30,
            music_volume: 15,
            call_volume: 12,
            wearing_detection_enabled: true,
            wearing: false,
            auto_power_off: true,
            auto_volume: false,
            auto_standby_enabled: true,
            smart_talking_enabled: false,
            head_gesture_enabled: true,
            head_gesture_training: false,
            voice_guidance: true,
            sony_voice_assistant: false,
            link_auto_switch: false,
            quick_access: vec![0x01, 0x0A],
            adaptive_control: false,
            control_by_wearing: true,
            control_by_wearing_available: true,
            mic_on_off: true,
            mic_sound_effect: true,
            voice_guidance_volume: 5,
            smart_talking_sensitivity: 0,
            smart_talking_mode_out: 1,
            apow_current: 0x10,
            apow_last: 0x00,
            apow_enabled: true,
            conn_classic: true,
            conn_le: true,
            bgm_on: false,
            bgm_room: protocol::room_size::MIDDLE,
            cinema_on: false,
            eq_enabled: true,
            eq_preset: protocol::eq_preset::ROCK,
            eq_bands: vec![3, 3, 2, 1, 2, 3, 3, 2, 1, 0],
            clear_bass: 0,
            tx_seq: 0,
            rx_last_seq: None,
            corrupt_next: false,
            mute: false,
            received: Vec::new(),
        }
    }
}

impl SimDevice {
    pub fn new() -> Self {
        Self::default()
    }

    /// Build a `PERI_RET_PARAM` pairing list in either supported shape.
    fn pairing_payload(&self, with_cod: bool) -> Vec<u8> {
        let mut out = vec![
            cmd::PERI_RET_PARAM,
            if with_cod {
                protocol::peri_type::PAIRING_DEVICE_MANAGEMENT_WITH_COD
            } else {
                protocol::peri_type::PAIRING_DEVICE_MANAGEMENT
            },
            self.paired_devices.len() as u8,
        ];
        for (address, name, connected, cod) in &self.paired_devices {
            let addr = address.as_bytes();
            let mut padded = [b'0'; 17];
            let n = addr.len().min(17);
            padded[..n].copy_from_slice(&addr[..n]);
            out.extend_from_slice(&padded);
            out.push(if *connected { 0x02 } else { 0x00 });
            if with_cod {
                out.extend_from_slice(&cod.to_be_bytes()[1..]);
            }
            let bytes = name.as_bytes();
            let n = bytes.len().min(128);
            out.push(n as u8);
            out.extend_from_slice(&bytes[..n]);
        }
        // The app calls this the "playback right device" index.
        out.push(0x01);
        out
    }

    /// Handle one inbound frame.
    ///
    /// Returns the bytes to write back: always an acknowledgement, plus a
    /// response frame when the command warrants one.
    pub fn handle(&mut self, frame: &Frame) -> Vec<Vec<u8>> {
        self.received.push(frame.payload.clone());

        // An acknowledgement is never acknowledged, and it lives outside the
        // data-frame sequence space. Treating it as data corrupts the duplicate
        // detection, which then silently drops real replies.
        if frame.kind() == DataType::Ack {
            return Vec::new();
        }

        // Every data frame must be acknowledged, even a retransmission.
        let mut out = vec![framing::pack(DataType::Ack, MdrTable::reciprocal(frame.seq), &[])];

        if self.mute {
            return out;
        }
        // A repeated sequence number is a retransmission: acknowledge it, but
        // do not answer twice.
        if self.rx_last_seq == Some(frame.seq) {
            return out;
        }
        self.rx_last_seq = Some(frame.seq);

        let payload = &frame.payload;
        let table2 = frame.kind() == DataType::DataMdrNo2;
        let Some(&command) = payload.first() else { return out };
        let reply: Option<Vec<u8>> = match command {
            cmd::CONNECT_GET_PROTOCOL_INFO => Some(vec![
                cmd::CONNECT_RET_PROTOCOL_INFO,
                0x00,
                0x00,
                0x00,
                0x02,
                0x00,
                protocol::ENABLE,
                protocol::ENABLE,
            ]),
            cmd::CONNECT_GET_CAPABILITY_INFO => Some(vec![cmd::CONNECT_RET_CAPABILITY_INFO, 0x00, 0x00]),
            cmd::COMMON_GET_CAPABILITY if payload.get(1) == Some(&0x04) => {
                let mut v = vec![cmd::COMMON_RET_CAPABILITY, 0x04];
                v.extend_from_slice(b"2C:CA:16:75:76:32");
                v.extend_from_slice(b"4C78CDDC");
                Some(v)
            }
            cmd::SAR_GET_CAPABILITY if payload.get(1) == Some(&0x00) => {
                Some(vec![cmd::SAR_RET_CAPABILITY, 0x00, 0x00])
            }
            cmd::SAR_GET_CAPABILITY if payload.get(1) == Some(&0x10) => {
                Some(vec![cmd::SAR_RET_CAPABILITY, 0x10, 0x00])
            }
            cmd::SAR_GET_STATUS if payload.get(1) == Some(&0x10) => {
                Some(vec![cmd::SAR_RET_STATUS, 0x10, 0x00])
            }
            cmd::SAR_GET_CAPABILITY if payload.get(1) == Some(&0x21) => {
                Some(vec![cmd::SAR_RET_CAPABILITY, 0x21, 0x00])
            }
            cmd::SAR_GET_STATUS if payload.get(1) == Some(&0x21) => {
                Some(vec![cmd::SAR_RET_STATUS, 0x21, 0x00, 0x00])
            }
            cmd::SAR_GET_CAPABILITY if payload.get(1) == Some(&0x02) => {
                Some(vec![cmd::SAR_RET_CAPABILITY, 0x02, 0x4B, 0xEC])
            }
            cmd::SYSTEM_GET_STATUS if table2 && payload.get(1) == Some(&0x01) => {
                Some(vec![cmd::SYSTEM_RET_STATUS, 0x01, 0x01])
            }
            cmd::CONNECT_GET_SUPPORT_FUNCTION => {
                let list: &[u8] = if table2 {
                    &[0x34, 0x23, 0xF1, 0xF4, 0x20]
                } else {
                    &[0x12, 0x13, 0x20, 0x25, 0xFC]
                };
                let mut v = vec![
                    cmd::CONNECT_RET_SUPPORT_FUNCTION,
                    0x00,
                    list.len() as u8,
                ];
                for &f in list {
                    v.push(f);
                    v.push(0xFF);
                }
                Some(v)
            }
            cmd::CONNECT_GET_DEVICE_INFO => {
                let info_type = payload.get(1).copied().unwrap_or(0);
                if info_type == protocol::device_info_type::SERIES_AND_COLOR_INFO {
                    // Simulated: series 0, colour Black (`ModelColor` 0x01).
                    Some(vec![cmd::CONNECT_RET_DEVICE_INFO, info_type, 0x00, 0x01])
                } else {
                    let text = match info_type {
                        protocol::device_info_type::MODEL_NAME => self.model.clone(),
                        protocol::device_info_type::FW_VERSION => self.firmware.clone(),
                        _ => String::new(),
                    };
                    let bytes = text.as_bytes();
                    let mut v = vec![cmd::CONNECT_RET_DEVICE_INFO, info_type, bytes.len() as u8];
                    v.extend_from_slice(bytes);
                    Some(v)
                }
            }
            cmd::POWER_GET_STATUS => {
                let inquired = payload.get(1).copied().unwrap_or(0);
                if inquired == 0x04 {
                    Some(vec![
                        cmd::POWER_RET_STATUS,
                        0x04,
                        if self.auto_power_off { 0x00 } else { 0x01 },
                    ])
                } else if inquired == 0x05 {
                    Some(vec![
                        cmd::POWER_RET_STATUS,
                        0x05,
                        if self.apow_enabled { 0x00 } else { 0x01 },
                    ])
                } else if table2 && inquired == 0x00 {
                    Some(vec![
                        cmd::POWER_RET_STATUS,
                        0x00,
                        if self.auto_standby_enabled { 0x00 } else { 0x01 },
                    ])
                } else if inquired == 0x02 {
                    Some(vec![
                        cmd::POWER_RET_STATUS,
                        0x02,
                        if self.usb_submersion { 0x00 } else { 0x01 },
                    ])
                } else {
                    Some(vec![cmd::POWER_RET_STATUS, inquired, self.battery, self.charging])
                }
            }
            cmd::NCASM_GET_PARAM => Some(vec![
                cmd::NCASM_RET_PARAM,
                self.ncasma_type,
                protocol::value_change::CHANGED,
                if self.nc_enabled { 1 } else { 0 },
                self.nc_mode,
                self.ambient_mode,
                self.ambient_level,
                1,
                0,
            ]),
            cmd::NCASM_SET_PARAM => {
                if payload.len() >= 7 {
                    self.nc_enabled = payload[3] == 1;
                    self.nc_mode = payload[4];
                    self.ambient_mode = payload[5];
                    self.ambient_level = payload[6].min(20);
                }
                Some(vec![
                    cmd::NCASM_NTFY_PARAM,
                    self.ncasma_type,
                    protocol::value_change::CHANGED,
                    if self.nc_enabled { 1 } else { 0 },
                    self.nc_mode,
                    self.ambient_mode,
                    self.ambient_level,
                    1,
                    0,
                ])
            }
            cmd::EQEBB_GET_PARAM if !table2 => {
                let inquired = payload.get(1).copied().unwrap_or(0);
                match inquired {
                    protocol::eqebb_type::PRESET_EQ => {
                        let mut v = vec![
                            cmd::EQEBB_RET_PARAM,
                            protocol::eqebb_type::PRESET_EQ,
                            self.eq_preset,
                            self.eq_bands.len() as u8,
                        ];
                        v.extend_from_slice(&self.eq_bands);
                        Some(v)
                    }
                    protocol::eqebb_type::EBB => Some(vec![
                        cmd::EQEBB_RET_PARAM,
                        protocol::eqebb_type::EBB,
                        self.clear_bass as u8,
                    ]),
                    _ => None,
                }
            }
            cmd::EQEBB_GET_STATUS => Some(vec![
                cmd::EQEBB_RET_STATUS,
                protocol::eqebb_type::PRESET_EQ,
                protocol::ENABLE,
            ]),
            cmd::GENERAL_SETTING_GET_CAPABILITY => {
                let gs = payload.get(1).copied().unwrap_or(0);
                self.gs_settings.iter().find(|(t, _, _)| *t == gs).map(|(t, label, _)| {
                    let mut v = vec![cmd::GENERAL_SETTING_RET_CAPABILITY, *t, 0x00, 0x01];
                    v.push(label.len() as u8);
                    v.extend_from_slice(label.as_bytes());
                    v.push(0x00); // empty summary
                    v
                })
            }
            cmd::GENERAL_SETTING_GET_PARAM => {
                let gs = payload.get(1).copied().unwrap_or(0);
                self.gs_settings.iter().find(|(t, _, _)| *t == gs).map(|(t, _, on)| {
                    vec![cmd::GENERAL_SETTING_RET_PARAM, *t, 0x00, if *on { 0x00 } else { 0x01 }]
                })
            }
            cmd::GENERAL_SETTING_SET_PARAM => {
                let gs = payload.get(1).copied().unwrap_or(0);
                let value = payload.get(3).copied().unwrap_or(0x01);
                for entry in self.gs_settings.iter_mut() {
                    if entry.0 == gs {
                        entry.2 = value == 0x00;
                    }
                }
                self.gs_settings.iter().find(|(t, _, _)| *t == gs).map(|(t, _, on)| {
                    vec![cmd::GENERAL_SETTING_RET_PARAM, *t, 0x00, if *on { 0x00 } else { 0x01 }]
                })
            }
            cmd::SYSTEM_GET_CAPABILITY if payload.get(1) == Some(&0x04) => {
                let mut v = vec![cmd::SYSTEM_RET_CAPABILITY, 0x04, 0x01, self.va_supported.len() as u8];
                v.extend_from_slice(&self.va_supported);
                Some(v)
            }
            cmd::PERI_GET_STATUS
                if payload.get(1) == Some(&protocol::peri_type::PAIRING_DEVICE_MANAGEMENT) =>
            {
                Some(vec![
                    cmd::PERI_RET_STATUS,
                    protocol::peri_type::PAIRING_DEVICE_MANAGEMENT,
                    if self.pairing_mode {
                        protocol::pairing_mode::INQUIRY_SCAN
                    } else {
                        protocol::pairing_mode::NORMAL
                    },
                    0x00,
                ])
            }
            cmd::PERI_GET_CAPABILITY
                if payload.get(1) == Some(&protocol::peri_type::PAIRING_DEVICE_MANAGEMENT) =>
            {
                Some(vec![
                    cmd::PERI_RET_CAPABILITY,
                    protocol::peri_type::PAIRING_DEVICE_MANAGEMENT,
                    0x08,
                    0x02,
                    0x00,
                ])
            }
            cmd::PERI_GET_PARAM
                if payload.get(1) == Some(&protocol::peri_type::PAIRING_DEVICE_MANAGEMENT) =>
            {
                Some(self.pairing_payload(false))
            }
            cmd::PERI_GET_PARAM
                if payload.get(1) == Some(&protocol::peri_type::PAIRING_DEVICE_MANAGEMENT_WITH_COD) =>
            {
                Some(self.pairing_payload(true))
            }
            cmd::PERI_SET_STATUS
                if payload.len() == 4
                    && payload.get(1) == Some(&protocol::peri_type::PAIRING_DEVICE_MANAGEMENT) =>
            {
                self.pairing_mode = payload[2] == protocol::pairing_mode::INQUIRY_SCAN;
                // The XM6 notifies with the Class-of-Device inquired type
                // (`35 02 <mode> 00`), not the 0x00 the write used.
                Some(vec![
                    cmd::PERI_NTFY_STATUS,
                    protocol::peri_type::PAIRING_DEVICE_MANAGEMENT_WITH_COD,
                    payload[2],
                    0x00,
                ])
            }
            cmd::PERI_SET_EX_PARAM
                if payload.len() == 20
                    && matches!(
                        payload.get(1),
                        Some(&protocol::peri_type::PAIRING_DEVICE_MANAGEMENT)
                            | Some(&protocol::peri_type::PAIRING_DEVICE_MANAGEMENT_WITH_COD)
                    ) =>
            {
                let action = payload[2];
                let address = String::from_utf8_lossy(&payload[3..20]).into_owned();
                if let Some(entry) = self
                    .paired_devices
                    .iter_mut()
                    .find(|(candidate, _, _, _)| *candidate == address)
                {
                    if action == protocol::pairing_action::CONNECT {
                        entry.2 = true;
                    } else if action == protocol::pairing_action::DISCONNECT {
                        entry.2 = false;
                    }
                }
                let mut reply = vec![
                    cmd::PERI_NTFY_EX_PARAM,
                    protocol::peri_type::PAIRING_DEVICE_MANAGEMENT_WITH_COD,
                    action,
                    protocol::pairing_result::CONNECTION_SUCCESS,
                ];
                if action == protocol::pairing_action::DISCONNECT {
                    reply[3] = protocol::pairing_result::DISCONNECTION_SUCCESS;
                }
                reply.extend_from_slice(address.as_bytes());
                Some(reply)
            }
            cmd::PERI_GET_PARAM if payload.get(1) == Some(&protocol::peri_type::SOURCE_SWITCH_CONTROL) => {
                Some(vec![cmd::PERI_RET_PARAM, protocol::peri_type::SOURCE_SWITCH_CONTROL, 0x01])
            }
            cmd::PERI_GET_PARAM if payload.get(1) == Some(&protocol::peri_type::MUSIC_HAND_OVER_SETTING) => {
                Some(vec![
                    cmd::PERI_RET_PARAM,
                    protocol::peri_type::MUSIC_HAND_OVER_SETTING,
                    if self.music_hand_over { 0x00 } else { 0x01 },
                ])
            }
            cmd::PERI_SET_PARAM if payload.get(1) == Some(&protocol::peri_type::MUSIC_HAND_OVER_SETTING) => {
                self.music_hand_over = payload.get(2) == Some(&protocol::ENABLE);
                None
            }
            cmd::PLAY_GET_CAPABILITY if payload.get(1) == Some(&0x01) => Some(vec![
                cmd::PLAY_RET_CAPABILITY,
                0x01,
                self.volume_steps,
                self.volume_steps,
            ]),
            cmd::PLAY_GET_PARAM if payload.get(1) == Some(&protocol::play_type::MUSIC_VOLUME) => {
                Some(vec![cmd::PLAY_RET_PARAM, protocol::play_type::MUSIC_VOLUME, self.music_volume])
            }
            cmd::PLAY_GET_PARAM if payload.get(1) == Some(&protocol::play_type::CALL_VOLUME) => {
                Some(vec![cmd::PLAY_RET_PARAM, protocol::play_type::CALL_VOLUME, self.call_volume])
            }
            cmd::PLAY_SET_PARAM
                if payload.get(1) == Some(&protocol::play_type::MUSIC_VOLUME) =>
            {
                // The WH-1000XM6 confirms with a notify carrying the new
                // value (HW, 2026-11-21: A8 20 0B -> ACK, A9 20 0B).
                payload.get(2).map(|&volume| {
                    self.music_volume = volume;
                    vec![cmd::PLAY_NTFY_PARAM, protocol::play_type::MUSIC_VOLUME, volume]
                })
            }
            cmd::PLAY_SET_PARAM
                if payload.get(1) == Some(&protocol::play_type::CALL_VOLUME) =>
            {
                if let Some(&volume) = payload.get(2) {
                    self.call_volume = volume;
                }
                None
            }
            cmd::PLAY_GET_STATUS if payload.get(1) == Some(&0x01) => Some(vec![
                cmd::PLAY_RET_STATUS,
                0x01,
                0x00,
                self.playback,
                self.play_source,
            ]),
            cmd::PLAY_SET_STATUS if payload.get(1) == Some(&0x01) => {
                let control = payload.get(3).copied().unwrap_or(0);
                self.playback = match control {
                    0x01 => 2, // pause
                    0x07 => 1, // play
                    0x06 => 3, // stop
                    _ => self.playback,
                };
                Some(vec![
                    cmd::PLAY_RET_STATUS, 0x01, 0x00, self.playback, self.play_source,
                ])
            }
            cmd::POWER_GET_PARAM if table2 && payload.get(1) == Some(&0x00) => Some(vec![
                cmd::POWER_RET_PARAM,
                0x00,
                if self.auto_standby_enabled { 0x00 } else { 0x01 },
            ]),
            cmd::POWER_SET_PARAM if table2 && payload.get(1) == Some(&0x00) => {
                self.auto_standby_enabled = payload.get(2) == Some(&0x00);
                Some(vec![
                    cmd::POWER_RET_PARAM,
                    0x00,
                    if self.auto_standby_enabled { 0x00 } else { 0x01 },
                ])
            }
            cmd::POWER_GET_PARAM if payload.get(1) == Some(&0x05) => Some(vec![
                cmd::POWER_RET_PARAM,
                0x05,
                self.apow_current,
                self.apow_last,
            ]),
            cmd::POWER_SET_PARAM if payload.get(1) == Some(&0x05) => {
                if let Some(&current) = payload.get(2) {
                    self.apow_last = self.apow_current;
                    self.apow_current = current;
                }
                Some(vec![cmd::POWER_RET_PARAM, 0x05, self.apow_current, self.apow_last])
            }
            cmd::POWER_GET_CAPABILITY if table2 && payload.get(1) == Some(&0x00) => {
                Some(vec![cmd::POWER_RET_CAPABILITY, 0x00, 0x00])
            }
            cmd::SYSTEM_GET_STATUS if payload.get(1) == Some(&0x0F) => Some(vec![
                cmd::SYSTEM_RET_STATUS,
                0x0F,
                if self.head_gesture_enabled { 0x00 } else { 0x01 },
            ]),
            cmd::SYSTEM_SET_STATUS if payload.get(1) == Some(&0x0F) => {
                self.head_gesture_enabled = payload.get(2) == Some(&0x00);
                Some(vec![
                    cmd::SYSTEM_RET_STATUS,
                    0x0F,
                    if self.head_gesture_enabled { 0x00 } else { 0x01 },
                ])
            }
            cmd::SENSE_SET_STATUS if !table2 && payload.get(1) == Some(&0x01) => {
                self.adaptive_control = payload.get(2) == Some(&0x01);
                Some(vec![
                    cmd::SENSE_NTFY_STATUS,
                    0x01,
                    if self.adaptive_control { 0x01 } else { 0x00 },
                ])
            }
            cmd::SENSE_GET_CAPABILITY if !table2 && payload.get(1) == Some(&0x01) => {
                Some(vec![cmd::SENSE_RET_CAPABILITY, 0x01, 0x03, 0x08, 0x10, 0x20])
            }
            cmd::SYSTEM_GET_PARAM if !table2 && payload.get(1) == Some(&0x01) => Some(vec![
                cmd::SYSTEM_RET_PARAM,
                0x01,
                if self.control_by_wearing { 0x00 } else { 0x01 },
            ]),
            cmd::SYSTEM_GET_STATUS if !table2 && payload.get(1) == Some(&0x01) => Some(vec![
                cmd::SYSTEM_RET_STATUS,
                0x01,
                if self.control_by_wearing_available { 0x00 } else { 0x01 },
            ]),
            cmd::SYSTEM_SET_PARAM if !table2 && payload.get(1) == Some(&0x01) => {
                self.control_by_wearing = payload.get(2) == Some(&0x00);
                Some(vec![
                    cmd::SYSTEM_NTFY_PARAM,
                    0x01,
                    if self.control_by_wearing { 0x00 } else { 0x01 },
                ])
            }
            cmd::SYSTEM_SET_STATUS if payload.get(1) == Some(&0x10) => {
                self.head_gesture_training = payload.get(2) == Some(&0x00);
                Some(vec![
                    cmd::SYSTEM_NTFY_STATUS,
                    0x10,
                    if self.head_gesture_training { 0x00 } else { 0x01 },
                    0x00,
                ])
            }
            cmd::SYSTEM_GET_STATUS if payload.get(1) == Some(&0x0C) => Some(vec![
                cmd::SYSTEM_RET_STATUS,
                0x0C,
                if self.smart_talking_enabled { 0x00 } else { 0x01 },
                0x00,
            ]),
            cmd::SYSTEM_GET_STATUS if payload.get(1) == Some(&0x04) => Some(vec![
                cmd::SYSTEM_RET_STATUS,
                0x04,
                if self.auto_volume { 0x00 } else { 0x01 },
            ]),
            cmd::SYSTEM_GET_STATUS if payload.get(1) == Some(&0x06) => Some(vec![
                cmd::SYSTEM_RET_STATUS,
                0x06,
                if self.wearing_detection_enabled { 0x00 } else { 0x01 },
                if self.wearing { 0x01 } else { 0x00 },
                0xF0,
                0x00,
            ]),
            cmd::LEA_GET_CAPABILITY if table2 && payload.get(1) == Some(&0x01) => {
                Some(vec![cmd::LEA_RET_CAPABILITY, 0x01, 0x03])
            }
            cmd::SYSTEM_GET_STATUS if table2 && payload.get(1) == Some(&0x0B) => Some(vec![
                cmd::SYSTEM_RET_STATUS,
                0x0B,
                if self.mic_on_off { 0x00 } else { 0x01 },
            ]),
            cmd::SYSTEM_GET_CAPABILITY if table2 && payload.get(1) == Some(&0x0B) => {
                Some(vec![cmd::SYSTEM_RET_CAPABILITY, 0x0B, 0x01])
            }
            cmd::SYSTEM_SET_PARAM if table2 && payload.get(1) == Some(&0x0B) => {
                self.mic_on_off = payload.get(2) == Some(&0x00);
                Some(vec![
                    cmd::SYSTEM_NTFY_PARAM,
                    0x0B,
                    if self.mic_on_off { 0x00 } else { 0x01 },
                    if self.mic_sound_effect { 0x00 } else { 0x01 },
                ])
            }
            cmd::SYSTEM_GET_STATUS if table2 && payload.get(1) == Some(&0x05) => Some(vec![
                cmd::SYSTEM_RET_STATUS,
                0x05,
                if self.sony_voice_assistant { 0x00 } else { 0x01 },
            ]),
            cmd::SYSTEM_SET_STATUS if table2 && payload.get(1) == Some(&0x05) => {
                self.sony_voice_assistant = payload.get(2) == Some(&0x00);
                Some(vec![
                    cmd::SYSTEM_RET_STATUS,
                    0x05,
                    if self.sony_voice_assistant { 0x00 } else { 0x01 },
                ])
            }
            cmd::SYSTEM_GET_PARAM if table2 && payload.get(1) == Some(&0x05) => {
                Some(vec![cmd::SYSTEM_RET_PARAM, 0x05, 0x00])
            }
            cmd::SYSTEM_GET_STATUS if table2 && payload.get(1) == Some(&0x0A) => Some(vec![
                cmd::SYSTEM_RET_STATUS,
                0x0A,
                if self.link_auto_switch { 0x00 } else { 0x01 },
            ]),
            cmd::SYSTEM_GET_PARAM if table2 && payload.get(1) == Some(&0x0A) => {
                let mut v = vec![cmd::SYSTEM_RET_PARAM, 0x0A, 0x01, 0x00, 0x01];
                v.extend_from_slice(b"00:00:00:00:00:00");
                Some(v)
            }
            cmd::VOICE_GUIDANCE_GET_STATUS
                if table2 && payload.get(1) == Some(&0x01) && payload.get(2) == Some(&0x00) =>
            {
                Some(vec![
                    cmd::VOICE_GUIDANCE_RET_STATUS,
                    0x01,
                    0x00,
                    if self.voice_guidance { 0x00 } else { 0x01 },
                ])
            }
            cmd::VOICE_GUIDANCE_GET_STATUS
                if table2 && payload.get(1) == Some(&0x01) && payload.get(2) == Some(&0x01) =>
            {
                Some(vec![cmd::VOICE_GUIDANCE_RET_STATUS, 0x01, 0x01, 0x01])
            }
            cmd::VOICE_GUIDANCE_SET_STATUS if table2 && payload.get(1) == Some(&0x01) => {
                self.voice_guidance = payload.get(3) == Some(&0x00);
                Some(vec![
                    cmd::VOICE_GUIDANCE_NTFY_STATUS,
                    0x01,
                    0x00,
                    if self.voice_guidance { 0x00 } else { 0x01 },
                ])
            }
            cmd::VOICE_GUIDANCE_GET_PARAM if table2 && payload.get(1) == Some(&0x01) => {
                Some(vec![
                    cmd::VOICE_GUIDANCE_RET_PARAM,
                    0x01,
                    if self.voice_guidance { 0x00 } else { 0x01 },
                    0x01,
                ])
            }
            cmd::VOICE_GUIDANCE_SET_PARAM if table2 && payload.get(1) == Some(&0x01) => {
                self.voice_guidance = payload.get(2) == Some(&0x00);
                Some(vec![
                    cmd::VOICE_GUIDANCE_NTFY_PARAM,
                    0x01,
                    if self.voice_guidance { 0x00 } else { 0x01 },
                ])
            }
            cmd::VOICE_GUIDANCE_GET_PARAM if table2 && payload.get(1) == Some(&0x20) => {
                Some(vec![
                    cmd::VOICE_GUIDANCE_RET_PARAM,
                    0x20,
                    self.voice_guidance_volume as u8,
                ])
            }
            cmd::VOICE_GUIDANCE_SET_PARAM if table2 && payload.get(1) == Some(&0x20) => {
                self.voice_guidance_volume = payload.get(2).copied().unwrap_or(5) as i8;
                Some(vec![
                    cmd::VOICE_GUIDANCE_RET_PARAM,
                    0x20,
                    self.voice_guidance_volume as u8,
                ])
            }
            cmd::SAFE_LISTENING_GET_PARAM if payload.get(1) == Some(&0x04) => {
                Some(vec![cmd::SAFE_LISTENING_RET_PARAM, 0x04, 0x00])
            }
            cmd::SAFE_LISTENING_SET_STATUS if payload.get(1) == Some(&0x04) => {
                Some(vec![
                    cmd::SAFE_LISTENING_RET_PARAM,
                    0x04,
                    payload.get(2).copied().unwrap_or(0),
                ])
            }
            cmd::SYSTEM_GET_PARAM if payload.get(1) == Some(&0x0D) => {
                let mut reply = vec![
                    cmd::SYSTEM_RET_PARAM,
                    0x0D,
                    self.quick_access.len() as u8,
                ];
                reply.extend_from_slice(&self.quick_access);
                Some(reply)
            }
            cmd::SYSTEM_SET_PARAM if table2 && payload.get(1) == Some(&0x02) => {
                let count = payload.get(4).copied().unwrap_or(0) as usize;
                self.quick_access = payload.get(5..5 + count).unwrap_or(&[]).to_vec();
                Some(vec![cmd::SYSTEM_NTFY_PARAM, 0x02, 0x00])
            }
            cmd::SYSTEM_GET_PARAM if payload.get(1) == Some(&0x0C) => Some(vec![
                cmd::SYSTEM_RET_PARAM,
                0x0C,
                if self.smart_talking_enabled { 0x00 } else { 0x01 },
                0x01,
            ]),
            cmd::SYSTEM_SET_PARAM if payload.get(1) == Some(&0x0C) => {
                self.smart_talking_enabled = payload.get(2) == Some(&0x00);
                Some(vec![
                    cmd::SYSTEM_RET_PARAM,
                    0x0C,
                    if self.smart_talking_enabled { 0x00 } else { 0x01 },
                    payload.get(3).copied().unwrap_or(0x01),
                ])
            }
            cmd::SYSTEM_GET_EXT_PARAM if payload.get(1) == Some(&0x0C) => Some(vec![
                cmd::SYSTEM_RET_EXT_PARAM,
                0x0C,
                self.smart_talking_sensitivity,
                self.smart_talking_mode_out,
            ]),
            cmd::SYSTEM_SET_EXT_PARAM if payload.get(1) == Some(&0x0C) => {
                if let Some(&s) = payload.get(2) {
                    self.smart_talking_sensitivity = s;
                }
                if let Some(&t) = payload.get(3) {
                    self.smart_talking_mode_out = t;
                }
                Some(vec![
                    cmd::SYSTEM_RET_EXT_PARAM,
                    0x0C,
                    self.smart_talking_sensitivity,
                    self.smart_talking_mode_out,
                ])
            }
            cmd::SYSTEM_GET_PARAM if payload.get(1) == Some(&0x04) => {
                Some(vec![cmd::SYSTEM_RET_PARAM, 0x04, self.va_current])
            }
            cmd::SYSTEM_SET_PARAM if payload.get(1) == Some(&0x04) => {
                self.va_current = payload.get(2).copied().unwrap_or(0xFF);
                Some(vec![cmd::SYSTEM_RET_PARAM, 0x04, self.va_current])
            }
            cmd::COMMON_GET_STATUS => {
                let json = format!(
                    "{{\"type\":\"CS\",\"dInfo\":{{\"model\":\"SIM-WH\"}},\"btInfo\":{{\"codec\":\"{}\"}}}}",
                    self.codec
                );
                let mut v = vec![cmd::COMMON_RET_STATUS, 0x00];
                v.extend_from_slice(json.as_bytes());
                Some(v)
            }
            cmd::AUDIO_GET_STATUS if payload.get(1) == Some(&0x05) => Some(vec![
                cmd::AUDIO_RET_STATUS,
                0x05,
                if self.conn_classic { 0x00 } else { 0x01 },
                if self.conn_le { 0x00 } else { 0x01 },
            ]),
            cmd::AUDIO_GET_PARAM => {
                let inquired = payload.get(1).copied().unwrap_or(0xFF);
                match inquired {
                    protocol::audio_type::BGM_MODE
                    | protocol::audio_type::BGM_MODE_AND_ERRORCODE => Some(vec![
                        cmd::AUDIO_RET_PARAM,
                        inquired,
                        if self.bgm_on { protocol::ENABLE } else { protocol::DISABLE },
                        self.bgm_room,
                    ]),
                    protocol::audio_type::UPMIX_CINEMA => Some(vec![
                        cmd::AUDIO_RET_PARAM,
                        protocol::audio_type::UPMIX_CINEMA,
                        if self.cinema_on { protocol::ENABLE } else { protocol::DISABLE },
                    ]),
                    _ => None,
                }
            }
            cmd::AUDIO_SET_PARAM => {
                let inquired = payload.get(1).copied().unwrap_or(0xFF);
                let on = payload.get(2) == Some(&protocol::ENABLE);
                match inquired {
                    protocol::audio_type::BGM_MODE
                    | protocol::audio_type::BGM_MODE_AND_ERRORCODE => {
                        self.bgm_on = on;
                        if let Some(&room) = payload.get(3) {
                            self.bgm_room = room;
                        }
                    }
                    protocol::audio_type::UPMIX_CINEMA => self.cinema_on = on,
                    _ => {}
                }
                None
            }
            cmd::EQEBB_GET_CAPABILITY => {
                let inquired = payload.get(1).copied().unwrap_or(0);
                match inquired {
                    protocol::eqebb_type::PRESET_EQ => {
                        // band count, step, preset count, then id/len/name triples.
                        let presets: [(u8, &str); 3] = [
                            (protocol::eq_preset::OFF, "Off"),
                            (protocol::eq_preset::ROCK, "Rock"),
                            (protocol::eq_preset::POP, "Pop"),
                        ];
                        let mut v = vec![
                            cmd::EQEBB_RET_CAPABILITY,
                            protocol::eqebb_type::PRESET_EQ,
                            self.eq_bands.len() as u8,
                            1,
                            presets.len() as u8,
                        ];
                        for (id, name) in presets {
                            v.push(id);
                            v.push(name.len() as u8);
                            v.extend_from_slice(name.as_bytes());
                        }
                        Some(v)
                    }
                    protocol::eqebb_type::EBB => Some(vec![
                        cmd::EQEBB_RET_CAPABILITY,
                        protocol::eqebb_type::EBB,
                        (-10i8) as u8,
                        10,
                    ]),
                    _ => None,
                }
            }
            cmd::EQEBB_SET_PARAM => {
                let inquired = payload.get(1).copied().unwrap_or(0);
                match inquired {
                    protocol::eqebb_type::PRESET_EQ
                        if payload.len() >= 4 && payload.len() >= 4 + payload[3] as usize =>
                    {
                        self.eq_preset = payload[2];
                        self.eq_bands = payload[4..4 + payload[3] as usize].to_vec();
                        let mut v = vec![
                            cmd::EQEBB_NTFY_PARAM,
                            protocol::eqebb_type::PRESET_EQ,
                            self.eq_preset,
                            self.eq_bands.len() as u8,
                        ];
                        v.extend_from_slice(&self.eq_bands);
                        Some(v)
                    }
                    protocol::eqebb_type::EBB if payload.len() >= 3 => {
                        self.clear_bass = payload[2] as i8;
                        Some(vec![
                            cmd::EQEBB_NTFY_PARAM,
                            protocol::eqebb_type::EBB,
                            self.clear_bass as u8,
                        ])
                    }
                    _ => None,
                }
            }
            _ => None,
        };

        let Some(mut p) = reply else { return out };
        let seq = self.tx_seq;
        self.tx_seq = MdrTable::reciprocal(seq);

        let reply_type = frame.kind();
        if self.corrupt_next {
            self.corrupt_next = false;
            let mut bytes = framing::pack(reply_type, seq, &p);
            // Flip the checksum byte (always the last byte before '<').
            let idx = bytes.len().saturating_sub(2);
            bytes[idx] ^= 0xFF;
            p.clear();
            out.push(bytes);
            return out;
        }
        out.push(framing::pack(reply_type, seq, &p));
        out
    }
}

/// Convenience: drive a session against a simulator until it goes quiet.
pub fn drive(
    session: &mut crate::session::Session,
    sim: &mut SimDevice,
    now: &mut u64,
) -> Vec<crate::session::SessionEvent> {
    let mut all = Vec::new();
    let mut queue: VecDeque<Vec<u8>> = VecDeque::new();
    for ev in session.connect(*now) {
        if let crate::session::SessionEvent::Send(b) = &ev {
            queue.push_back(b.clone());
        }
        all.push(ev);
    }
    let mut decoder = framing::StreamDecoder::new();
    let mut guard = 0;
    while let Some(bytes) = queue.pop_front() {
        guard += 1;
        if guard > 2048 {
            break;
        }
        decoder.push(&bytes);
        while let Ok(Some(frame)) = decoder.next_frame() {
            let replies = sim.handle(&frame);
            for reply in replies {
                *now += 1;
                for ev in session.receive(&reply, *now) {
                    if let crate::session::SessionEvent::Send(b) = &ev {
                        queue.push_back(b.clone());
                    }
                    all.push(ev);
                }
            }
        }
    }
    all
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::session::{Policy, Session, SessionState};

    #[test]
    fn simulator_drives_session_to_ready() {
        let mut s = Session::new(Policy::default());
        let mut sim = SimDevice::new();
        let mut now = 0u64;
        drive(&mut s, &mut sim, &mut now);
        assert_eq!(s.state(), SessionState::Ready);
        assert_eq!(s.device.battery.as_ref().unwrap().value.level, 64);
        assert_eq!(s.device.identity.model, "SIM-WH");
        assert!(s.device.noise_control.is_some());
    }

    #[test]
    fn simulator_applies_noise_control_write() {
        let mut s = Session::new(Policy::default());
        let mut sim = SimDevice::new();
        let mut now = 0u64;
        drive(&mut s, &mut sim, &mut now);
        let events = s
            .set_noise_control(true, nc_mode::ASM, crate::protocol::asm_mode::VOICE, 15, now)
            .expect("ready session");
        let bytes = events
            .iter()
            .find_map(|e| match e {
                crate::session::SessionEvent::Send(b) => Some(b.clone()),
                _ => None,
            })
            .expect("a frame to write");
        let mut dec = framing::StreamDecoder::new();
        dec.push(&bytes);
        let frame = dec.next_frame().unwrap().unwrap();
        let replies = sim.handle(&frame);
        for reply in replies {
            s.receive(&reply, now + 5);
        }
        let nc = s.device.noise_control.as_ref().unwrap().value;
        assert!(nc.is_ambient());
        assert!(nc.focus_on_voice());
        assert_eq!(nc.ambient_level, 15);
    }

    #[test]
    fn mute_device_stalls_without_panicking() {
        let mut s = Session::new(Policy::default());
        let mut sim = SimDevice::new();
        sim.mute = true;
        let mut now = 0u64;
        drive(&mut s, &mut sim, &mut now);
        assert_eq!(s.state(), SessionState::Handshaking);
    }

    #[test]
    fn corrupt_response_is_reported() {
        let mut s = Session::new(Policy::default());
        let mut sim = SimDevice::new();
        sim.corrupt_next = true;
        let mut now = 0u64;
        let events = drive(&mut s, &mut sim, &mut now);
        assert!(events
            .iter()
            .any(|e| matches!(e, crate::session::SessionEvent::Malformed(_))));
    }

    #[test]
    fn the_device_acknowledges_every_frame() {
        let mut sim = SimDevice::new();
        let frame = Frame {
            data_type: DataType::DataMdr as u8,
            seq: 0,
            payload: vec![cmd::CONNECT_GET_PROTOCOL_INFO, 0x00],
        };
        let replies = sim.handle(&frame);
        assert_eq!(replies.len(), 2);
        let mut dec = framing::StreamDecoder::new();
        dec.push(&replies[0]);
        let ack = dec.next_frame().unwrap().unwrap();
        assert_eq!(ack.kind(), DataType::Ack);
        assert_eq!(ack.seq, 1);
    }

    /// Drive one request through the simulator and feed every reply back.
    fn round_trip(
        s: &mut Session,
        sim: &mut SimDevice,
        now: &mut u64,
        events: Vec<crate::session::SessionEvent>,
    ) {
        let mut decoder = framing::StreamDecoder::new();
        let mut pending: std::collections::VecDeque<crate::session::SessionEvent> =
            events.into();
        while let Some(ev) = pending.pop_front() {
            if let crate::session::SessionEvent::Send(bytes) = ev {
                decoder.push(&bytes);
                while let Ok(Some(frame)) = decoder.next_frame() {
                    for reply in sim.handle(&frame) {
                        *now += 1;
                        for follow_up in s.receive(&reply, *now) {
                            pending.push_back(follow_up);
                        }
                    }
                }
            }
        }
    }

    #[test]
    fn new_families_are_read_during_handshake() {
        let mut s = Session::new(Policy::default());
        let mut sim = SimDevice::new();
        let mut now = 0u64;
        drive(&mut s, &mut sim, &mut now);

        // General settings are named by the device.
        let titles: Vec<String> = s
            .device
            .general_settings
            .iter()
            .map(|g| g.title())
            .collect();
        assert_eq!(titles, vec!["Sidetone", "Multipoint", "Touch panel"]);
        assert!(s.device.general_settings.iter().all(|g| g.value == Some(true)));

        // Voice assistant list and current value.
        let va = s.device.voice_assistant.as_ref().expect("voice assistant");
        assert_eq!(va.value.current, 0xFF);
        assert_eq!(va.value.supported.len(), 3);
        assert_eq!(va.value.current_name(), "Not set");

        // Table-2 reads arrive during sync too.
        assert!(!s.device.music_hand_over.as_ref().unwrap().value);
        assert!(!s.device.usb_submersion.as_ref().unwrap().value);
        let pairing = s.device.paired_devices.as_ref().expect("paired devices");
        assert_eq!(pairing.value.devices.len(), 2);
        assert_eq!(pairing.value.devices[0].name, "Sim Laptop");
        assert!(pairing.value.devices[0].connected);
        assert_eq!(pairing.value.devices[0].class_of_device, Some(0x38_01_0C));
        assert_eq!(pairing.value.playback_device, 1);
        let cap = s.device.pairing_capability.as_ref().expect("pairing capability");
        assert_eq!(cap.value.max_paired, 8);
        assert_eq!(cap.value.max_connected, 2);
        assert!(!s.device.auto_volume.as_ref().unwrap().value);
        assert!(s.device.auto_standby.as_ref().unwrap().value);
        assert!(s.device.auto_standby_enabled.as_ref().unwrap().value);
        let st = s.device.smart_talking.as_ref().unwrap().value;
        assert!(!st.enabled);
        assert_eq!(st.sensitivity, 0);
        assert_eq!(st.mode_out, 1);
        assert!(s.device.head_gesture.as_ref().unwrap().value);
        assert_eq!(
            s.device.ble_setup.as_ref().unwrap().value,
            ("2C:CA:16:75:76:32".to_string(), "4C78CDDC".to_string())
        );
        assert_eq!(s.device.repeat_tap_status.as_ref().unwrap().value, 1);
        assert_eq!(s.device.sar_capability.as_ref().unwrap().value, 0);
        assert!(s.device.gatt_connectable.as_ref().unwrap().value);
        assert_eq!(s.device.sar_optimization.as_ref().unwrap().value, (true, 0));
        assert_eq!(s.device.auto_play_capability.as_ref().unwrap().value, 0x4BEC);
        assert_eq!(s.device.quick_access.as_ref().unwrap().value, vec![0x01, 0x0A]);
        assert!(
            sim.received.iter().any(|p| p == &[0x56, 0x04]),
            "safe volume request not sent: {:?}",
            sim.received
        );
        assert_eq!(s.device.safe_volume_level.as_ref().unwrap().value, 0);
        assert!(s.device.voice_guidance.as_ref().unwrap().value);
        assert_eq!(s.device.voice_guidance_volume.as_ref().unwrap().value, 5);
        assert!(!s.device.sony_voice_assistant.as_ref().unwrap().value);
        assert!(!s.device.link_auto_switch.as_ref().unwrap().value.0);
        assert_eq!(s.device.le_audio_switch_compat.as_ref().unwrap().value, 3);
        assert!(s.device.mic_on_off.as_ref().unwrap().value);
        assert_eq!(s.device.mic_key_type.as_ref().unwrap().value, 1);
        assert!(s.device.control_by_wearing.as_ref().unwrap().value);
        assert!(s.device.control_by_wearing_available.as_ref().unwrap().value);
        assert_eq!(
            s.device.adaptive_control_capability.as_ref().unwrap().value,
            vec![0x03, 0x08, 0x10, 0x20]
        );
        assert_eq!(s.device.source_switch.as_ref().unwrap().value, 1);

        // Both support lists are read; table 2 is a separate list.
        assert_eq!(s.device.supported_functions, vec![0x12, 0x13, 0x20, 0x25, 0xFC]);
        assert_eq!(s.device.supported_functions_table2, vec![0x34, 0x23, 0xF1, 0xF4, 0x20]);

        // Playback state is read during sync.
        let play = s.device.playback.as_ref().expect("playback");
        assert!(play.value.enabled);
        assert_eq!(play.value.playback, 2);
        assert_eq!(play.value.source, 0);

        // Wearing-detection auto-off reads the current/last pair.
        let apow = s.device.auto_power_off_wearing.as_ref().expect("auto-off wearing");
        assert_eq!(apow.value, (0x10, 0x00));
        assert!(s.device.auto_power_off_wearing_enabled.as_ref().unwrap().value);

        // Wearing detection decodes the captured six-byte shape.
        let wear = s.device.wearing_status.as_ref().expect("wearing status");
        assert!(wear.value.detection_enabled);
        assert!(!wear.value.worn);
        assert_eq!(wear.value.selected_earpieces, 0xF0);
        assert_eq!(wear.value.result_code, 0);

        // Codec, auto power off, connection mode.
        assert_eq!(s.device.codec.as_ref().unwrap().value, "AAC");
        assert!(s.device.auto_power_off.as_ref().unwrap().value);
        let cm = s.device.connection_mode.as_ref().unwrap().value;
        assert!(cm.0 && cm.1);
    }

    #[test]
    fn general_setting_write_is_confirmed() {
        let mut s = Session::new(Policy::default());
        let mut sim = SimDevice::new();
        let mut now = 0u64;
        drive(&mut s, &mut sim, &mut now);

        let events = s.set_gs_boolean(0xD1, false, now).expect("ready session");
        round_trip(&mut s, &mut sim, &mut now, events);
        assert!(!sim.gs_settings[0].2, "simulator applied the write");
        let gs = s.device.general_settings.iter().find(|g| g.gs_type == 0xD1).unwrap();
        assert_eq!(gs.value, Some(false));
    }

    #[test]
    fn playback_control_is_confirmed() {
        let mut s = Session::new(Policy::default());
        let mut sim = SimDevice::new();
        let mut now = 0u64;
        drive(&mut s, &mut sim, &mut now);

        let events = s.set_playback_control(0x07, now).expect("ready session");
        round_trip(&mut s, &mut sim, &mut now, events);
        assert_eq!(sim.playback, 1, "play");
        assert_eq!(s.device.playback.as_ref().unwrap().value.playback, 1);
    }

    #[test]
    fn music_volume_is_read_and_written() {
        let mut s = Session::new(Policy::default());
        let mut sim = SimDevice::new();
        let mut now = 0u64;
        drive(&mut s, &mut sim, &mut now);
        assert_eq!(s.device.playback_volume_steps.as_ref().unwrap().value, (30, 30));
        assert_eq!(s.device.music_volume.as_ref().unwrap().value, 15);

        let events = s.set_music_volume(40, now).expect("ready session");
        round_trip(&mut s, &mut sim, &mut now, events);
        assert_eq!(sim.music_volume, 30, "clamped to the advertised steps");
        assert_eq!(s.device.music_volume.as_ref().unwrap().value, 30);

        assert_eq!(s.device.call_volume.as_ref().unwrap().value, 12);
        let events = s.set_call_volume(40, now).expect("ready session");
        round_trip(&mut s, &mut sim, &mut now, events);
        assert_eq!(sim.call_volume, 30);
        assert_eq!(s.device.call_volume.as_ref().unwrap().value, 30);
    }

    #[test]
    fn a_volume_drag_sends_only_the_newest_unsent_value() {
        let mut s = Session::new(Policy::default());
        let mut sim = SimDevice::new();
        let mut now = 0u64;
        drive(&mut s, &mut sim, &mut now);
        let before = sim.received.len();

        // 20 goes out at once; 21..=24 arrive while it is in flight.
        let mut events = s.set_music_volume(20, now).expect("ready session");
        for v in 21..=24 {
            events.extend(s.set_music_volume(v, now).expect("ready session"));
        }
        round_trip(&mut s, &mut sim, &mut now, events);

        let writes: Vec<u8> = sim.received[before..]
            .iter()
            .filter(|p| p.starts_with(&[0xA8, 0x20]))
            .map(|p| p[2])
            .collect();
        assert_eq!(writes, vec![20, 24], "intermediate steps are dropped");
        assert_eq!(sim.music_volume, 24);
        assert_eq!(s.device.music_volume.as_ref().unwrap().value, 24);
        assert!(!s.device.has_pending_write());
    }

    #[test]
    fn smart_talking_write_updates_device_and_state() {
        let mut s = Session::new(Policy::default());
        let mut sim = SimDevice::new();
        let mut now = 0u64;
        drive(&mut s, &mut sim, &mut now);
        assert!(!s.device.smart_talking.as_ref().unwrap().value.enabled);

        let events = s.set_smart_talking(true, now).expect("ready session");
        round_trip(&mut s, &mut sim, &mut now, events);
        assert!(sim.smart_talking_enabled);
        assert!(s.device.smart_talking.as_ref().unwrap().value.enabled);

        let events = s
            .set_smart_talking_detail(2, 3, now)
            .expect("ready session");
        round_trip(&mut s, &mut sim, &mut now, events);
        let st = s.device.smart_talking.as_ref().unwrap().value;
        assert_eq!(st.sensitivity, 2);
        assert_eq!(st.mode_out, 3);

        let events = s.set_head_gesture(false, now).expect("ready session");
        round_trip(&mut s, &mut sim, &mut now, events);
        assert!(!sim.head_gesture_enabled);
        assert!(!s.device.head_gesture.as_ref().unwrap().value);
    }


    #[test]
    fn adaptive_control_round_trip() {
        let mut s = Session::new(Policy::default());
        let mut sim = SimDevice::new();
        let mut now = 0u64;
        drive(&mut s, &mut sim, &mut now);
        let events = s.set_adaptive_control(true, now).expect("ready session");
        round_trip(&mut s, &mut sim, &mut now, events);
        assert!(sim.adaptive_control);
        assert!(s.device.adaptive_control_started.as_ref().unwrap().value);
        let events = s.set_adaptive_control(false, now).expect("ready session");
        round_trip(&mut s, &mut sim, &mut now, events);
        assert!(!sim.adaptive_control);
    }

    #[test]
    fn quick_access_functions_round_trip() {
        let mut s = Session::new(Policy::default());
        let mut sim = SimDevice::new();
        let mut now = 0u64;
        drive(&mut s, &mut sim, &mut now);
        let events = s
            .set_quick_access_functions(&[0x01, 0x01], now)
            .expect("ready session");
        round_trip(&mut s, &mut sim, &mut now, events);
        assert_eq!(sim.quick_access, vec![0x01, 0x01]);
        assert_eq!(s.device.quick_access_result.as_ref().unwrap().value, 0);
    }

    #[test]
    fn control_by_wearing_write_round_trip() {
        let mut s = Session::new(Policy::default());
        let mut sim = SimDevice::new();
        let mut now = 0u64;
        drive(&mut s, &mut sim, &mut now);
        let events = s.set_control_by_wearing(false, now).expect("ready session");
        round_trip(&mut s, &mut sim, &mut now, events);
        assert!(!sim.control_by_wearing);
        assert!(!s.device.control_by_wearing.as_ref().unwrap().value);
    }

    #[test]
    fn mic_on_off_write_round_trip() {
        let mut s = Session::new(Policy::default());
        let mut sim = SimDevice::new();
        let mut now = 0u64;
        drive(&mut s, &mut sim, &mut now);
        let events = s.set_mic_on_off(false, now).expect("ready session");
        round_trip(&mut s, &mut sim, &mut now, events);
        assert!(!sim.mic_on_off);
        assert!(!s.device.mic_on_off.as_ref().unwrap().value);
    }

    #[test]
    fn optional_read_timeout_does_not_fail_ready_session() {
        let mut s = Session::new(Policy::default());
        let mut sim = SimDevice::new();
        let mut now = 0u64;
        drive(&mut s, &mut sim, &mut now);
        s.queue_optional_read_for_test(vec![0x60, 0x99]);
        let events = s.pump_for_test(now);
        assert!(events.iter().any(|e| matches!(e, crate::session::SessionEvent::Send(_))));
        now += Policy::default().command_timeout_ms + 1;
        let events = s.poll_timeout(now);
        assert!(events.iter().any(|e| matches!(e, crate::session::SessionEvent::Timeout(0x60))));
        assert_eq!(s.state(), SessionState::Ready);
    }

    #[test]
    fn sony_voice_assistant_write_round_trip() {
        let mut s = Session::new(Policy::default());
        let mut sim = SimDevice::new();
        let mut now = 0u64;
        drive(&mut s, &mut sim, &mut now);
        let events = s.set_sony_voice_assistant(true, now).expect("ready session");
        round_trip(&mut s, &mut sim, &mut now, events);
        assert!(sim.sony_voice_assistant);
        assert!(s.device.sony_voice_assistant.as_ref().unwrap().value);
    }

    #[test]
    fn voice_guidance_round_trip() {
        let mut s = Session::new(Policy::default());
        let mut sim = SimDevice::new();
        let mut now = 0u64;
        drive(&mut s, &mut sim, &mut now);
        let events = s.set_voice_guidance(false, now).expect("ready session");
        round_trip(&mut s, &mut sim, &mut now, events);
        assert!(!sim.voice_guidance);
        assert!(!s.device.voice_guidance.as_ref().unwrap().value);
        assert!(!s.device.has_pending_write());

        let events = s.set_voice_guidance_volume(3, now).expect("ready session");
        round_trip(&mut s, &mut sim, &mut now, events);
        assert_eq!(sim.voice_guidance_volume, 3);
        assert_eq!(s.device.voice_guidance_volume.as_ref().unwrap().value, 3);
    }

    #[test]
    fn head_gesture_training_round_trip() {
        let mut s = Session::new(Policy::default());
        let mut sim = SimDevice::new();
        let mut now = 0u64;
        drive(&mut s, &mut sim, &mut now);
        let events = s.set_head_gesture_training(true, now).expect("ready session");
        round_trip(&mut s, &mut sim, &mut now, events);
        assert!(sim.head_gesture_training);
        assert_eq!(
            s.device.head_gesture_training.as_ref().unwrap().value,
            (0, true)
        );
        let events = s.set_head_gesture_training(false, now).expect("ready session");
        round_trip(&mut s, &mut sim, &mut now, events);
        assert!(!sim.head_gesture_training);
        assert_eq!(
            s.device.head_gesture_training.as_ref().unwrap().value,
            (1, true)
        );
    }

    #[test]
    fn safe_volume_reply_is_applied_directly() {
        let mut s = Session::new(Policy::default());
        let mut sim = SimDevice::new();
        let mut now = 0u64;
        drive(&mut s, &mut sim, &mut now);
        let frame = framing::pack(DataType::DataMdrNo2, 99, &[0x57, 0x04, 0x01]);
        s.receive(&frame, 999);
        assert_eq!(s.device.safe_volume_level.as_ref().unwrap().value, 1);
    }

    #[test]
    fn auto_standby_write_updates_device_and_state() {
        let mut s = Session::new(Policy::default());
        let mut sim = SimDevice::new();
        let mut now = 0u64;
        drive(&mut s, &mut sim, &mut now);
        assert!(s.device.auto_standby_enabled.as_ref().unwrap().value);

        let events = s.set_auto_standby(false, now).expect("ready session");
        round_trip(&mut s, &mut sim, &mut now, events);
        assert!(!sim.auto_standby_enabled);
        assert!(!s.device.auto_standby_enabled.as_ref().unwrap().value);
    }

    #[test]
    fn music_hand_over_write_updates_device_and_state() {
        let mut s = Session::new(Policy::default());
        let mut sim = SimDevice::new();
        let mut now = 0u64;
        drive(&mut s, &mut sim, &mut now);
        assert!(!s.device.music_hand_over.as_ref().unwrap().value);

        let events = s.set_music_hand_over(true, now).expect("ready session");
        round_trip(&mut s, &mut sim, &mut now, events);
        assert!(sim.music_hand_over);
        assert!(s.device.music_hand_over.as_ref().unwrap().value);
    }

    #[test]
    fn pairing_connect_and_disconnect_round_trip() {
        let mut s = Session::new(Policy::default());
        let mut sim = SimDevice::new();
        let mut now = 0u64;
        drive(&mut s, &mut sim, &mut now);

        let list = s.device.paired_devices.as_ref().expect("pairing list").value.clone();
        assert!(list.devices[0].connected);
        assert!(!list.devices[1].connected);

        // Connect the second device; the follow-up list read must confirm it.
        let events = s.pairing_connect(1, now).expect("ready session");
        round_trip(&mut s, &mut sim, &mut now, events);
        assert!(sim.paired_devices[1].2);
        assert!(s.device.paired_devices.as_ref().unwrap().value.devices[1].connected);
        assert_eq!(
            s.device.last_pairing_event.as_ref().unwrap().value.result,
            protocol::pairing_result::CONNECTION_SUCCESS
        );

        // Disconnect it again.
        let events = s.pairing_disconnect(1, now).expect("ready session");
        round_trip(&mut s, &mut sim, &mut now, events);
        assert!(!sim.paired_devices[1].2);
        assert!(!s.device.paired_devices.as_ref().unwrap().value.devices[1].connected);

        // Already-disconnected is a no-op, and an out-of-range index is None.
        let events = s.pairing_disconnect(1, now).expect("ready session");
        assert!(events.is_empty());
        assert!(s.pairing_connect(99, now).is_none());
    }

    #[test]
    fn pairing_mode_write_reaches_the_device() {
        let mut s = Session::new(Policy::default());
        let mut sim = SimDevice::new();
        let mut now = 0u64;
        drive(&mut s, &mut sim, &mut now);

        let events = s.pairing_set_mode(true, now).expect("ready session");
        round_trip(&mut s, &mut sim, &mut now, events);
        assert!(sim.pairing_mode);
        let mode = s.device.pairing_mode.as_ref().expect("pairing mode");
        assert_eq!(mode.value.mode, protocol::pairing_mode::INQUIRY_SCAN);

        let events = s.pairing_set_mode(false, now).expect("ready session");
        round_trip(&mut s, &mut sim, &mut now, events);
        assert!(!sim.pairing_mode);
        let mode = s.device.pairing_mode.as_ref().expect("pairing mode");
        assert_eq!(mode.value.mode, protocol::pairing_mode::NORMAL);
    }

    #[test]
    fn adaptive_parameter_notification_reaches_state() {
        let mut s = Session::new(Policy::default());
        let mut sim = SimDevice::new();
        let mut now = 0u64;
        drive(&mut s, &mut sim, &mut now);

        let payload = [
            protocol::cmd::SENSE_NTFY_PARAM,
            0x01,
            0x02,
            0x00, 0x10, 0x02,
            0x00, 0x20, 0x00,
        ];
        s.handle_payload_for_test(&payload, crate::MdrTable::Table1, now);
        let parameter = s
            .device
            .adaptive_parameter
            .as_ref()
            .expect("adaptive parameter");
        assert_eq!(parameter.value.functions.len(), 2);
        assert_eq!(parameter.value.functions[0].function, 0x10);
        assert_eq!(parameter.value.functions[1].function, 0x20);
    }

    #[test]
    fn listening_mode_is_read_and_switched() {
        let mut s = Session::new(Policy::default());
        let mut sim = SimDevice::new();
        let mut now = 0u64;
        drive(&mut s, &mut sim, &mut now);

        // Both params are read during the ready transition.
        let listen = s.device.listening().expect("BGM and Cinema read");
        assert_eq!(listen.mode(), protocol::ListeningMode::Normal);
        assert_eq!(listen.room, protocol::room_size::MIDDLE);

        let events = s
            .set_listening_mode(protocol::ListeningMode::Cinema, now)
            .expect("ready session");
        round_trip(&mut s, &mut sim, &mut now, events);
        assert!(sim.cinema_on);
        assert!(!sim.bgm_on);
        assert_eq!(
            s.device.listening().expect("still known").mode(),
            protocol::ListeningMode::Cinema
        );
    }

    #[test]
    fn auto_power_off_wearing_write_is_confirmed() {
        let mut s = Session::new(Policy::default());
        let mut sim = SimDevice::new();
        let mut now = 0u64;
        drive(&mut s, &mut sim, &mut now);

        let events = s.set_auto_power_off_wearing(0x11, 0x10, now).expect("ready session");
        round_trip(&mut s, &mut sim, &mut now, events);
        assert_eq!(sim.apow_current, 0x11);
        assert_eq!(sim.apow_last, 0x10);
        let apow = s.device.auto_power_off_wearing.as_ref().unwrap();
        assert_eq!(apow.value, (0x11, 0x10));
    }

    #[test]
    fn voice_assistant_write_is_confirmed() {
        let mut s = Session::new(Policy::default());
        let mut sim = SimDevice::new();
        let mut now = 0u64;
        drive(&mut s, &mut sim, &mut now);

        let events = s.set_voice_assistant(0x31, now).expect("ready session");
        round_trip(&mut s, &mut sim, &mut now, events);
        assert_eq!(sim.va_current, 0x31);
        let va = s.device.voice_assistant.as_ref().unwrap();
        assert_eq!(va.value.current_name(), "Google Assistant");
    }

    #[test]
    fn equalizer_is_read_during_the_handshake() {
        let mut s = Session::new(Policy::default());
        let mut sim = SimDevice::new();
        let mut now = 0u64;
        drive(&mut s, &mut sim, &mut now);

        let eq = s.device.equalizer.as_ref().expect("equaliser reported");
        assert!(eq.value.enabled);
        assert_eq!(eq.value.preset, protocol::eq_preset::ROCK);
        assert_eq!(eq.value.band_count, sim.eq_bands.len() as u8);
        assert!(!eq.value.presets.is_empty(), "device advertised no presets");
        assert_eq!(eq.value.clear_bass_min, -10);
        assert_eq!(eq.value.clear_bass_max, 10);
    }

    #[test]
    fn equalizer_preset_write_is_confirmed_by_the_device() {
        let mut s = Session::new(Policy::default());
        let mut sim = SimDevice::new();
        let mut now = 0u64;
        drive(&mut s, &mut sim, &mut now);

        let bands = sim.eq_bands.clone();
        let events = s
            .set_eq_preset(protocol::eq_preset::POP, &bands, now)
            .expect("ready session accepts a preset the device listed");
        round_trip(&mut s, &mut sim, &mut now, events);

        assert_eq!(sim.eq_preset, protocol::eq_preset::POP);
        assert_eq!(
            s.device.equalizer.as_ref().unwrap().value.preset,
            protocol::eq_preset::POP
        );
    }

    #[test]
    fn a_preset_the_device_never_advertised_is_refused() {
        let mut s = Session::new(Policy::default());
        let mut sim = SimDevice::new();
        let mut now = 0u64;
        drive(&mut s, &mut sim, &mut now);
        // 0x33 is a real protocol preset but this fake device only lists three.
        assert!(s.set_eq_preset(protocol::eq_preset::SOFT, &[], now).is_none());
    }

    #[test]
    fn clear_bass_write_is_clamped_and_confirmed() {
        let mut s = Session::new(Policy::default());
        let mut sim = SimDevice::new();
        let mut now = 0u64;
        drive(&mut s, &mut sim, &mut now);

        let events = s.set_clear_bass(-99, now).expect("ready session");
        round_trip(&mut s, &mut sim, &mut now, events);
        assert_eq!(sim.clear_bass, -10, "clamped to the reported minimum");
        assert_eq!(s.device.equalizer.as_ref().unwrap().value.clear_bass, -10);
    }
}

