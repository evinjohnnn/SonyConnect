//! Session state machine and command scheduling.
//!
//! One `Session` owns one control channel. It is synchronous and time-injected
//! (`now_ms` is passed in), so the whole handshake can be replayed deterministically
//! in tests and driven by a real clock on device without hidden threads.
//!
//! # The link is stop-and-wait with a one-bit sequence number
//!
//! * The ACK for a frame carries the *reciprocal* of that frame's sequence
//!   number (`1 - seq`).
//! * There are only two ACK forms, one per sequence number, so the sequence
//!   space is 0/1.
//! * A sender writes a frame, then waits for its ACK before the next command.
//!   It resends with the *same* sequence number, so a retry is a
//!   retransmission rather than a new message.
//!
//! Consequence: exactly one command may be outstanding at a time, and every
//! data frame we receive must be acknowledged — including retransmissions.

use std::collections::{HashSet, VecDeque};

use crate::framing::{self, DataType, Frame, MdrTable, StreamDecoder};
use crate::protocol::{self, cmd};
use crate::state::{DeviceState, EqualizerUpdate};

/// Connection lifecycle. Mirrors the states the UI renders.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SessionState {
    Disconnected,
    Connecting,
    Handshaking,
    DiscoveringCapabilities,
    Syncing,
    Ready,
    Reconnecting,
    Suspended,
    Unsupported,
    Error,
}

impl SessionState {
    pub fn is_ready(self) -> bool {
        matches!(self, SessionState::Ready)
    }

    pub fn label(self) -> &'static str {
        match self {
            SessionState::Disconnected => "Not connected",
            SessionState::Connecting => "Connecting",
            SessionState::Handshaking => "Handshaking",
            SessionState::DiscoveringCapabilities => "Reading capabilities",
            SessionState::Syncing => "Syncing settings",
            SessionState::Ready => "Ready",
            SessionState::Reconnecting => "Reconnecting",
            SessionState::Suspended => "Suspended",
            SessionState::Unsupported => "Unsupported device",
            SessionState::Error => "Error",
        }
    }
}

/// What the caller should do next after feeding bytes in.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SessionEvent {
    /// Write these bytes to the control channel.
    Send(Vec<u8>),
    /// State changed in a way the UI should repaint.
    StateChanged(SessionState),
    /// A frame was accepted but produced no state change.
    Ignored,
    /// A frame failed validation.
    Malformed(framing::FrameError),
    /// Command timed out; the caller may retry within its own budget.
    Timeout(u8),
}

/// The command currently awaiting its ACK.
#[derive(Debug, Clone)]
struct InFlight {
    seq: u8,
    payload: Vec<u8>,
    table: MdrTable,
    sent_at_ms: u64,
    retries: u32,
    /// User writes fail the session on timeout; best-effort reads are skipped.
    is_write: bool,
}

/// Timeouts and retry policy. Conservative on purpose: we never hammer a
/// headphone that another controller may own.
#[derive(Debug, Clone, Copy)]
pub struct Policy {
    pub command_timeout_ms: u64,
    pub max_retries: u32,
    pub handshake_timeout_ms: u64,
}

impl Default for Policy {
    fn default() -> Self {
        Policy { command_timeout_ms: 3_000, max_retries: 2, handshake_timeout_ms: 8_000 }
    }
}

pub struct Session {
    state: SessionState,
    table: MdrTable,
    /// Sequence number for the next command we send.
    tx_seq: u8,
    /// Sequence number of the last data frame we accepted, for duplicate
    /// detection. The device retransmits until it is acknowledged.
    rx_last_seq: Option<u8>,
    decoder: StreamDecoder,
    /// Payloads waiting for their turn on the wire, with the table they
    /// belong to. Table 1 and table 2 share one channel but use different
    /// data-type bytes.
    outbox: VecDeque<(MdrTable, Vec<u8>)>,
    /// User writes jump ahead of queued sync reads.
    priority: VecDeque<(MdrTable, Vec<u8>)>,
    /// Reads that may be silently unsupported. A timeout is skipped in any
    /// state instead of failing the handshake.
    optional_reads: HashSet<Vec<u8>>,
    inflight: Option<InFlight>,
    policy: Policy,
    pub device: DeviceState,
    /// Filled in from `CONNECT_RET_PROTOCOL_INFO`.
    pub protocol_info: Option<protocol::ProtocolInfo>,
    /// Identity fields already received.
    model_received: bool,
    firmware_received: bool,
    /// When the on-head state was last asked for. The headphones do not
    /// notify when they are taken off (HW, 3.1.5), so it is re-read while
    /// the link is idle.
    last_wear_poll_ms: u64,
}

/// How often the on-head state is re-read while idle.
const WEAR_POLL_MS: u64 = 3_000;

impl Session {
    pub fn new(policy: Policy) -> Self {
        Session {
            state: SessionState::Disconnected,
            table: MdrTable::Table1,
            tx_seq: 0,
            rx_last_seq: None,
            decoder: StreamDecoder::new(),
            outbox: VecDeque::new(),
            priority: VecDeque::new(),
            optional_reads: HashSet::new(),
            inflight: None,
            policy,
            device: DeviceState::new(),
            protocol_info: None,
            model_received: false,
            firmware_received: false,
            last_wear_poll_ms: 0,
        }
    }

    /// Speak table 2 instead of table 1.
    pub fn with_table(mut self, table: MdrTable) -> Self {
        self.table = table;
        self
    }

    pub fn state(&self) -> SessionState {
        self.state
    }

    pub fn table(&self) -> MdrTable {
        self.table
    }

    /// The sequence number of the command awaiting acknowledgement, if any.
    ///
    /// Exposed for diagnostics and for the test harness that has to ACK
    /// commands the way a real device does.
    pub fn outstanding_seq(&self) -> Option<u8> {
        self.inflight.as_ref().map(|i| i.seq)
    }

    /// Begin the session: queue the first handshake request.
    pub fn connect(&mut self, now_ms: u64) -> Vec<SessionEvent> {
        self.state = SessionState::Handshaking;
        self.decoder = StreamDecoder::new();
        self.tx_seq = 0;
        self.rx_last_seq = None;
        self.outbox.clear();
        self.inflight = None;
        self.model_received = false;
        self.firmware_received = false;

        self.enqueue(protocol::get_protocol_info());
        let mut events = vec![SessionEvent::StateChanged(self.state)];
        events.extend(self.pump(now_ms));
        events
    }

    /// Queue a payload for this session's table.
    fn enqueue(&mut self, payload: Vec<u8>) {
        self.outbox.push_back((self.table, payload));
    }

    /// Queue a user write ahead of the sync reads.
    fn enqueue_write(&mut self, payload: Vec<u8>) {
        self.priority.push_back((self.table, payload));
    }

    /// Queue a write, dropping any unsent write for the same setting (the
    /// first `key_len` payload bytes). A slider dragged across many steps
    /// then leaves only its newest value waiting behind the in-flight one,
    /// instead of a backlog the device works through after the drag ends.
    fn enqueue_latest_write(&mut self, key_len: usize, payload: Vec<u8>) {
        let table = self.table;
        let key = payload[..key_len.min(payload.len())].to_vec();
        self.priority.retain(|(t, p)| !(*t == table && p.starts_with(&key)));
        self.priority.push_back((table, payload));
    }

    /// Frame the next queued payload, if the link is free.
    ///
    /// Exactly one command may be outstanding: the device will not answer a
    /// second one until it has acknowledged the first.
    fn pump(&mut self, now_ms: u64) -> Vec<SessionEvent> {
        let mut events = Vec::new();
        if self.inflight.is_some() {
            return events;
        }
        let next = if let Some(item) = self.priority.pop_front() {
            (item.0, item.1, true)
        } else if let Some(item) = self.outbox.pop_front() {
            (item.0, item.1, false)
        } else {
            return events;
        };
        let (table, payload, is_write) = next;
        let seq = self.tx_seq;
        let bytes = framing::pack(table.data_type(), seq, &payload);
        self.inflight = Some(InFlight {
            seq,
            payload,
            table,
            sent_at_ms: now_ms,
            retries: 0,
            is_write,
        });
        events.push(SessionEvent::Send(bytes));
        events
    }

    /// Feed raw bytes received from the control channel.
    pub fn receive(&mut self, bytes: &[u8], now_ms: u64) -> Vec<SessionEvent> {
        self.decoder.push(bytes);
        let mut events = Vec::new();
        loop {
            match self.decoder.next_frame() {
                Ok(Some(frame)) => {
                    events.extend(self.handle_frame(frame, now_ms));
                }
                Ok(None) => break,
                Err(err) => {
                    events.push(SessionEvent::Malformed(err));
                    // The decoder already dropped the bad frame and advanced,
                    // so keep draining: one corrupt frame must not stall the
                    // frames queued behind it.
                    continue;
                }
            }
        }
        events
    }

    fn handle_frame(&mut self, frame: Frame, now_ms: u64) -> Vec<SessionEvent> {
        let mut events = Vec::new();
        match frame.kind() {
            DataType::Ack => {
                // Only the reciprocal of the outstanding sequence number counts;
                // anything else is a stale ACK from a retransmission.
                let Some(inf) = self.inflight.as_ref() else { return events };
                if frame.seq != MdrTable::reciprocal(inf.seq) {
                    return events;
                }
                self.inflight = None;
                self.tx_seq = frame.seq;
                events.extend(self.pump(now_ms));
            }
            DataType::DataMdr | DataType::DataMdrNo2 => {
                // Acknowledge first, always — a retransmission is re-acked but
                // not re-processed.
                let ack = framing::pack(DataType::Ack, MdrTable::reciprocal(frame.seq), &[]);
                events.push(SessionEvent::Send(ack));

                if self.rx_last_seq == Some(frame.seq) {
                    return events;
                }
                self.rx_last_seq = Some(frame.seq);
                let table = match frame.kind() {
                    DataType::DataMdrNo2 => MdrTable::Table2,
                    _ => MdrTable::Table1,
                };
                events.extend(self.handle_payload(&frame.payload, table, now_ms));
            }
            _ => {
                // Frames for another data type are not ours to interpret.
            }
        }
        events
    }

    fn handle_payload(
        &mut self,
        payload: &[u8],
        table: MdrTable,
        now_ms: u64,
    ) -> Vec<SessionEvent> {
        let mut events = Vec::new();
        let Some(&command) = payload.first() else { return events };

        match command {
            cmd::CONNECT_RET_PROTOCOL_INFO => {
                self.protocol_info = protocol::decode_protocol_info(payload);
                self.state = SessionState::DiscoveringCapabilities;
                events.push(SessionEvent::StateChanged(self.state));

                // Identity first, so the UI can name the device even if the
                // capability read is slow.
                self.enqueue(protocol::get_capability_info());
                self.enqueue(protocol::get_device_info(protocol::device_info_type::FW_VERSION));
                self.enqueue(protocol::get_device_info(protocol::device_info_type::MODEL_NAME));
                // Colour picks the product picture; a model that stays silent
                // must not hold up the handshake.
                self.queue_optional_read(
                    self.table,
                    protocol::get_device_info(protocol::device_info_type::SERIES_AND_COLOR_INFO),
                );
                events.extend(self.pump(now_ms));
            }
            cmd::CONNECT_RET_DEVICE_INFO
                if payload.get(1) == Some(&protocol::device_info_type::SERIES_AND_COLOR_INFO) =>
            {
                // Two raw bytes, not a length-prefixed string.
                if let Some((series, color)) = protocol::decode_series_and_color(payload) {
                    self.device.identity.model_series = Some(series);
                    self.device.identity.model_color = Some(color);
                    self.device.revision += 1;
                }
            }
            cmd::CONNECT_RET_DEVICE_INFO => {
                if let Some((info_type, text)) = protocol::decode_device_info(payload) {
                    match info_type {
                        protocol::device_info_type::MODEL_NAME => {
                            self.device.identity.model = text;
                            self.model_received = true;
                        }
                        protocol::device_info_type::FW_VERSION => {
                            self.device.identity.firmware = text;
                            self.firmware_received = true;
                        }
                        _ => {}
                    }
                }
                if self.model_received && self.firmware_received && self.state != SessionState::Ready {
                    self.state = SessionState::Syncing;
                    events.push(SessionEvent::StateChanged(self.state));
                    self.enqueue(protocol::get_battery());
                    events.extend(self.pump(now_ms));
                }
            }
            cmd::COMMON_RET_CAPABILITY => {
                if let Some((addr, id)) = protocol::decode_ble_setup(payload) {
                    self.device.apply_ble_setup(addr, id, now_ms);
                }
            }
            cmd::LEA_RET_CAPABILITY if table == MdrTable::Table2 => {
                if let Some(version) = protocol::decode_le_audio_switch_compat(payload) {
                    self.device.apply_le_audio_switch_compat(version, now_ms);
                }
            }
            cmd::VOICE_GUIDANCE_RET_STATUS | cmd::VOICE_GUIDANCE_NTFY_STATUS
                if table == MdrTable::Table2 =>
            {
                if let Some(enabled) = protocol::decode_voice_guidance_status(payload) {
                    self.device.apply_voice_guidance(enabled, now_ms);
                } else if let Some(language) = protocol::decode_voice_guidance_language(payload) {
                    self.device.apply_voice_guidance_language(language, now_ms);
                } else if let Some(pair) = protocol::decode_voice_guidance_status_raw(payload) {
                    self.device.apply_voice_guidance_status_raw(pair, now_ms);
                }
            }
            cmd::VOICE_GUIDANCE_RET_PARAM | cmd::VOICE_GUIDANCE_NTFY_PARAM
                if table == MdrTable::Table2 =>
            {
                if let Some(enabled) = protocol::decode_voice_guidance_param(payload) {
                    self.device.apply_voice_guidance(enabled, now_ms);
                } else if let Some(volume) = protocol::decode_voice_guidance_volume(payload) {
                    self.device.apply_voice_guidance_volume(volume, now_ms);
                }
            }
            cmd::SAFE_LISTENING_RET_PARAM | cmd::SAFE_LISTENING_NTFY_PARAM
                if table == MdrTable::Table2 =>
            {
                if let Some(level) = protocol::decode_safe_volume_level(payload) {
                    self.device.apply_safe_volume_level(level, now_ms);
                }
            }
            cmd::SAR_RET_CAPABILITY => {
                match payload.get(1).copied() {
                    Some(protocol::sar_type::SAR) if payload.len() == 3 => {
                        self.device.apply_sar_capability(payload[2], now_ms);
                    }
                    Some(protocol::sar_type::AUTO_PLAY) => {
                        if let Some(value) = protocol::decode_auto_play_capability(payload) {
                            self.device.apply_auto_play_capability(value, now_ms);
                        }
                    }
                    _ => {}
                }
            }
            cmd::SAR_RET_STATUS => {
                if let Some(enabled) = protocol::decode_gatt_status(payload) {
                    self.device.apply_gatt_connectable(enabled, now_ms);
                } else if let Some((enabled, status)) =
                    protocol::decode_sar_optimization_status(payload)
                {
                    self.device.apply_sar_optimization(enabled, status, now_ms);
                }
            }
            cmd::POWER_RET_CAPABILITY if table == MdrTable::Table2 => {
                if let Some(available) = protocol::decode_auto_standby(payload) {
                    self.device.apply_auto_standby(available, now_ms);
                }
            }
            cmd::POWER_RET_STATUS | cmd::POWER_NTFY_STATUS => {
                if table == MdrTable::Table1 {
                    if let Some(status) = protocol::decode_battery(payload) {
                        self.device.apply_battery(status, now_ms);
                    }
                    if let Some(on) = protocol::decode_auto_power_off(payload) {
                        self.device.apply_auto_power_off(on, now_ms);
                    }
                    if let Some(on) = protocol::decode_auto_power_off_wearing_status(payload) {
                        self.device.apply_auto_power_off_wearing_enabled(on, now_ms);
                    }
                }
                if table == MdrTable::Table2 {
                    if let Some(submerged) = protocol::decode_usb_submersion(payload) {
                        self.device.apply_usb_submersion(submerged, now_ms);
                    }
                    if let Some(enabled) = protocol::decode_auto_standby_status(payload) {
                        self.device.apply_auto_standby_enabled(enabled, now_ms);
                    }
                }
                if self.state == SessionState::Syncing {
                    self.state = SessionState::Ready;
                    events.push(SessionEvent::StateChanged(self.state));
                    // Ask for the current noise-control state. A device that
                    // does not implement this shape simply does not answer,
                    // which must not derail the session.
                    self.enqueue(protocol::get_noise_control_active());
                    // Equaliser: capability first, so the UI knows which presets
                    // exist, then the current values. A model without an
                    // equaliser answers none of these, which is harmless.
                    self.enqueue(protocol::get_eq_capability());
                    self.enqueue(protocol::get_clear_bass_capability());
                    self.enqueue(protocol::get_eq_status());
                    self.enqueue(protocol::get_eq_param());
                    self.enqueue(protocol::get_clear_bass());
                    // Audio upscaling is a separate family; the XM6 answers it.
                    self.enqueue(protocol::get_audio_upscaling());
                    // Audio upscaling is a separate family; the XM6 answers it.
                    self.enqueue(protocol::get_support_function());
                    self.outbox
                        .push_back((MdrTable::Table2, protocol::get_support_function()));
                    self.enqueue(protocol::get_auto_power_off());
                    self.enqueue(protocol::get_connection_mode());
                    // The capability reply carries the volume range; the
                    // volume itself is a separate param read.
                    self.enqueue(protocol::get_playback_capability());
                    self.enqueue(protocol::get_playback_status());
                    // Listening mode: the status byte only says whether the
                    // shortcut is usable, so the settings are read as params.
                    self.enqueue(protocol::get_bgm_mode());
                    self.enqueue(protocol::get_cinema_mode());
                    // Table-2 reads: the outbox carries its own table.
                    self.outbox.push_back((MdrTable::Table2, protocol::get_music_hand_over()));
                    self.outbox.push_back((MdrTable::Table2, protocol::get_source_switch()));
                    // Paired-device management is advertised by the XM6. A
                    // model without it stays silent; optional reads do not
                    // consume retries.
                    self.queue_optional_read(
                        MdrTable::Table2,
                        protocol::get_pairing_capability(),
                    );
                    self.queue_optional_read(MdrTable::Table2, protocol::get_pairing_devices());
                    self.queue_optional_read(MdrTable::Table2, protocol::get_pairing_status());
                    self.outbox.push_back((MdrTable::Table2, protocol::get_usb_submersion()));
                    self.outbox.push_back((MdrTable::Table2, protocol::get_auto_volume()));
                    self.outbox.push_back((MdrTable::Table2, protocol::get_auto_standby()));
                    self.outbox.push_back((MdrTable::Table2, protocol::get_auto_standby_status()));
                    self.outbox.push_back((MdrTable::Table2, protocol::get_auto_standby_param()));
                    self.enqueue(protocol::get_wearing_status());
                    self.enqueue(protocol::get_auto_power_off_wearing_status());
                    self.enqueue(protocol::get_auto_power_off_wearing());
                    // General-setting slots: the device names them in the
                    // capability reply, then reports a boolean per slot.
                    self.enqueue(protocol::get_common_status());
                    self.enqueue(protocol::get_voice_assistant_capability());
                    self.enqueue(protocol::get_voice_assistant());
                    // Speak-to-Chat (table-1 SYSTEM type 0x0C).
                    self.enqueue(protocol::get_smart_talking_status());
                    self.enqueue(protocol::get_smart_talking_param());
                    self.enqueue(protocol::get_smart_talking_ext());
                    self.enqueue(protocol::get_head_gesture());
                    self.enqueue(protocol::get_quick_access());
                    // Diagnostics: BLE setup, SAR/GATT/auto-play, repeat-tap.
                    self.enqueue(protocol::get_ble_setup());
                    self.enqueue(protocol::get_sar_capability());
                    self.enqueue(protocol::get_gatt_capability());
                    self.enqueue(protocol::get_gatt_status());
                    self.enqueue(protocol::get_sar_optimization_capability());
                    self.enqueue(protocol::get_sar_optimization_status());
                    self.enqueue(protocol::get_auto_play_capability());
                    self.outbox
                        .push_back((MdrTable::Table2, protocol::get_repeat_tap_status()));
                    self.queue_optional_read(MdrTable::Table2, protocol::get_wearing_checker());
                    self.queue_optional_read(MdrTable::Table2, protocol::get_safe_volume_level());
                    self.queue_optional_read(
                        MdrTable::Table2,
                        protocol::get_voice_guidance_param(),
                    );
                    self.queue_optional_read(
                        MdrTable::Table2,
                        protocol::get_voice_guidance_language(),
                    );
                    self.queue_optional_read(
                        MdrTable::Table2,
                        protocol::get_voice_guidance_volume(),
                    );
                    self.queue_optional_read(
                        MdrTable::Table2,
                        protocol::get_sony_voice_assistant_status(),
                    );
                    self.queue_optional_read(
                        MdrTable::Table2,
                        protocol::get_sony_voice_assistant_language(),
                    );
                    self.queue_optional_read(
                        MdrTable::Table2,
                        protocol::get_link_auto_switch_status(),
                    );
                    self.queue_optional_read(
                        MdrTable::Table2,
                        protocol::get_link_auto_switch_param(),
                    );
                    self.queue_optional_read(
                        MdrTable::Table2,
                        protocol::get_le_audio_switch_compat(),
                    );
                    self.queue_optional_read(MdrTable::Table1, protocol::get_sense_capability());
                    self.queue_optional_read(
                        MdrTable::Table1,
                        protocol::get_control_by_wearing(),
                    );
                    self.queue_optional_read(
                        MdrTable::Table1,
                        protocol::get_control_by_wearing_status(),
                    );
                    self.queue_optional_read(MdrTable::Table2, protocol::get_mic_on_off());
                    self.queue_optional_read(MdrTable::Table2, protocol::get_mic_capability());
                    for gs in [0xD1u8, 0xD2, 0xD3, 0xD4] {
                        self.enqueue(protocol::get_gs_capability(gs));
                        self.enqueue(protocol::get_gs_param(gs));
                    }
                    events.extend(self.pump(now_ms));
                }
            }
            cmd::POWER_RET_PARAM | cmd::POWER_NTFY_PARAM if table == MdrTable::Table1 => {
                if let Some(elements) = protocol::decode_auto_power_off_wearing(payload) {
                    self.device.apply_auto_power_off_wearing(elements, now_ms);
                }
            }
            cmd::POWER_RET_PARAM | cmd::POWER_NTFY_PARAM if table == MdrTable::Table2 => {
                if let Some(enabled) = protocol::decode_auto_standby_param(payload) {
                    self.device.apply_auto_standby_enabled(enabled, now_ms);
                }
            }
            cmd::NCASM_RET_PARAM | cmd::NCASM_NTFY_PARAM => {
                if let Some(nc) = protocol::decode_noise_control(payload) {
                    self.device.apply_noise_control(nc, now_ms);
                }
            }
            cmd::EQEBB_RET_CAPABILITY
                if table == MdrTable::Table1 =>
            {
                let update = match payload.get(1).copied() {
                    // The device may answer a PRESET_EQ request with any of the
                    // multiplexed preset shapes; all decode through the same
                    // function, which picks the right layout by type.
                    Some(
                        protocol::eqebb_type::PRESET_EQ
                        | protocol::eqebb_type::PRESET_EQ_AND_ULT_MODE
                        | protocol::eqebb_type::PRESET_EQ_AND_ERRORCODE,
                    ) => protocol::decode_eq_capability(payload).map(|(bands, step, presets)| {
                        EqualizerUpdate {
                            capability: Some((bands, step, presets)),
                            ..Default::default()
                        }
                    }),
                    Some(protocol::eqebb_type::EBB) => {
                        protocol::decode_clear_bass_capability(payload).map(|(min, max)| {
                            EqualizerUpdate {
                                clear_bass_range: Some((min, max)),
                                ..Default::default()
                            }
                        })
                    }
                    _ => None,
                };
                if let Some(u) = update {
                    self.device.apply_equalizer(u, now_ms);
                }
                // Ask for on/off in the shape the device answered in; the
                // XM6 ignores the plain PRESET_EQ status read.
                if let Some(
                    t @ (protocol::eqebb_type::PRESET_EQ_AND_ULT_MODE
                    | protocol::eqebb_type::PRESET_EQ_AND_ERRORCODE),
                ) = payload.get(1).copied()
                {
                    self.queue_optional_read(MdrTable::Table1, protocol::get_eq_status_of(t));
                }
            }
            cmd::EQEBB_RET_STATUS | cmd::EQEBB_NTFY_STATUS
                if table == MdrTable::Table1 =>
            {
                if let Some((enabled, codes)) = protocol::decode_eq_status_detail(payload) {
                    self.device.apply_equalizer(
                        EqualizerUpdate {
                            enabled: Some(enabled),
                            error_codes: Some(if enabled { Vec::new() } else { codes }),
                            ..Default::default()
                        },
                        now_ms,
                    );
                }
            }
            cmd::CONNECT_RET_SUPPORT_FUNCTION => {
                if let Some(functions) = protocol::decode_support_function(payload) {
                    if table == MdrTable::Table1 {
                        self.device.apply_supported_functions(functions, now_ms);
                    } else {
                        self.device.supported_functions_table2 = functions;
                        self.device.revision += 1;
                    }
                }
            }
            cmd::SYSTEM_RET_CAPABILITY if table == MdrTable::Table2 => {
                if let Some(key_type) = protocol::decode_mic_capability(payload) {
                    self.device.apply_mic_key_type(key_type, now_ms);
                }
            }
            cmd::ALERT_NTFY_PARAM if table == MdrTable::Table1 => {
                if let Some(alert) = protocol::decode_alert_param(payload) {
                    self.device.apply_alert(alert, now_ms);
                }
            }
            cmd::SENSE_NTFY_STATUS if table == MdrTable::Table1 => {
                if let Some(started) = protocol::decode_sense_control(payload) {
                    self.device.apply_sense_control(started, now_ms);
                }
            }
            cmd::SENSE_NTFY_PARAM | cmd::SENSE_RET_PARAM if table == MdrTable::Table1 => {
                if let Some(parameter) = protocol::decode_sense_parameter(payload) {
                    self.device.apply_sense_parameter(parameter, now_ms);
                }
            }
            cmd::SENSE_RET_CAPABILITY if table == MdrTable::Table1 => {
                if let Some(bytes) = protocol::decode_sense_capability(payload) {
                    self.device.apply_sense_capability(bytes, now_ms);
                }
            }
            cmd::SYSTEM_RET_CAPABILITY if table == MdrTable::Table1 => {
                if let Some(supported) = protocol::decode_voice_assistant_capability(payload) {
                    self.device.apply_voice_assistant_capability(supported, now_ms);
                }
            }
            cmd::SYSTEM_RET_PARAM | cmd::SYSTEM_NTFY_PARAM if table == MdrTable::Table1 => {
                if let Some(current) = protocol::decode_voice_assistant(payload) {
                    self.device.apply_voice_assistant(current, now_ms);
                }
                if let Some((enabled, _preview)) =
                    protocol::decode_smart_talking_param(payload)
                {
                    self.device.apply_smart_talking_param(enabled, now_ms);
                }
                if let Some(functions) = protocol::decode_quick_access(payload) {
                    self.device.apply_quick_access(functions, now_ms);
                }
                if let Some(action) = protocol::decode_head_gesture_action(payload) {
                    self.device.apply_head_gesture_action(action, now_ms);
                }
                if let Some(enabled) = protocol::decode_control_by_wearing(payload) {
                    self.device.apply_control_by_wearing(enabled, now_ms);
                }
            }
            cmd::SYSTEM_RET_PARAM | cmd::SYSTEM_NTFY_PARAM if table == MdrTable::Table2 => {
                if let Some(language) = protocol::decode_sony_voice_assistant_language(payload) {
                    self.device.apply_sony_voice_assistant_language(language, now_ms);
                }
                if let Some((enabled, speaker, address)) =
                    protocol::decode_link_auto_switch_param(payload)
                {
                    self.device.apply_link_auto_switch((enabled, speaker, address), now_ms);
                }
                if let Some((enabled, sound_effect)) = protocol::decode_mic_notify(payload) {
                    self.device.apply_mic_on_off(enabled, sound_effect, now_ms);
                }
                if let Some(result) = protocol::decode_quick_access_result(payload) {
                    self.device.apply_quick_access_result(result, now_ms);
                }
            }
            cmd::SYSTEM_RET_EXT_PARAM | cmd::SYSTEM_NTFY_EXT_PARAM if table == MdrTable::Table1 => {
                if let Some((sensitivity, mode_out)) =
                    protocol::decode_smart_talking_ext(payload)
                {
                    self.device.apply_smart_talking_ext(sensitivity, mode_out, now_ms);
                }
            }
            cmd::PERI_NTFY_EX_PARAM => {
                if let Some(event) = protocol::decode_pairing_connection_event(payload) {
                    self.device.apply_pairing_event(event, now_ms);
                }
            }
            cmd::PERI_RET_PARAM | cmd::PERI_NTFY_PARAM => {
                if let Some(list) = protocol::decode_pairing_devices(payload) {
                    self.device.apply_paired_devices(list, now_ms);
                } else if let Some(on) = protocol::decode_music_hand_over(payload) {
                    self.device.apply_music_hand_over(on, now_ms);
                } else if let Some(value) = protocol::decode_source_switch(payload) {
                    self.device.apply_source_switch(value, now_ms);
                }
            }
            cmd::PERI_RET_CAPABILITY => {
                if let Some(capability) = protocol::decode_pairing_capability(payload) {
                    self.device.apply_pairing_capability(capability, now_ms);
                }
            }
            cmd::PERI_RET_STATUS | cmd::PERI_NTFY_STATUS if table == MdrTable::Table2 => {
                if let Some(status) = protocol::decode_pairing_status(payload) {
                    self.device.apply_pairing_mode(status, now_ms);
                }
            }
            cmd::PLAY_RET_CAPABILITY => {
                if let Some((music, call)) = protocol::decode_playback_volume_capability(payload)
                {
                    self.device.apply_playback_volume_steps(music, call, now_ms);
                    if music > 0 {
                        self.enqueue(protocol::get_music_volume());
                    }
                    if call > 0 {
                        self.enqueue(protocol::get_call_volume());
                    }
                }
            }
            cmd::PLAY_RET_STATUS | cmd::PLAY_NTFY_STATUS => {
                if let Some(playback) = protocol::decode_playback_status(payload) {
                    self.device.apply_playback(playback, now_ms);
                }
            }
            cmd::PLAY_RET_PARAM | cmd::PLAY_NTFY_PARAM => {
                if let Some(volume) = protocol::decode_music_volume(payload) {
                    self.device.apply_music_volume(volume, now_ms);
                } else if let Some(volume) = protocol::decode_call_volume(payload) {
                    self.device.apply_call_volume(volume, now_ms);
                }
            }
            cmd::SYSTEM_RET_STATUS | cmd::SYSTEM_NTFY_STATUS => {
                if table == MdrTable::Table2 {
                    if let Some(code) = protocol::decode_wearing_checker(payload) {
                        self.device.apply_wearing_code(code, now_ms);
                    }
                }
                if table == MdrTable::Table1 {
                    if let Some(status) = protocol::decode_wearing_status(payload) {
                        self.device.apply_wearing_status(status, now_ms);
                    }
                    if let Some((enabled, effect)) = protocol::decode_smart_talking_status(payload)
                    {
                        self.device.apply_smart_talking_status(enabled, effect, now_ms);
                    }
                    if let Some(enabled) = protocol::decode_head_gesture(payload) {
                        self.device.apply_head_gesture(enabled, now_ms);
                    }
                    if let Some(available) = protocol::decode_control_by_wearing_status(payload) {
                        self.device.apply_control_by_wearing_available(available, now_ms);
                    }
                    if let Some((status, enabled)) =
                        protocol::decode_head_gesture_training_status(payload)
                    {
                        self.device.apply_head_gesture_training(status, enabled, now_ms);
                    }
                }
                if table == MdrTable::Table2 {
                    if let Some(on) = protocol::decode_auto_volume(payload) {
                        self.device.apply_auto_volume(on, now_ms);
                    }
                    if let Some(status) = protocol::decode_repeat_tap_status(payload) {
                        self.device.apply_repeat_tap_status(status, now_ms);
                    }
                    if let Some(enabled) = protocol::decode_sony_voice_assistant_status(payload) {
                        self.device.apply_sony_voice_assistant(enabled, now_ms);
                    }
                    if let Some(enabled) = protocol::decode_link_auto_switch_status(payload) {
                        self.device.apply_link_auto_switch((enabled, 0, String::new()), now_ms);
                    }
                    if let Some(enabled) = protocol::decode_mic_on_off(payload) {
                        self.device.apply_mic_on_off(enabled, true, now_ms);
                    }
                }
            }
            cmd::COMMON_RET_STATUS | cmd::COMMON_NTFY_STATUS => {
                if let Some(codec) = protocol::decode_common_codec(payload) {
                    self.device.apply_codec(codec.to_string(), now_ms);
                }
            }
            cmd::GENERAL_SETTING_RET_CAPABILITY => {
                if let Some(setting) = protocol::decode_gs_capability(payload) {
                    self.device.apply_gs_capability(setting, now_ms);
                }
            }
            cmd::GENERAL_SETTING_RET_PARAM | cmd::GENERAL_SETTING_NTFY_PARAM => {
                if let Some((gs_type, on)) = protocol::decode_gs_param(payload) {
                    self.device.apply_gs_value(gs_type, on, now_ms);
                }
            }
            cmd::AUDIO_RET_STATUS | cmd::AUDIO_NTFY_STATUS => {
                if let Some(enabled) = protocol::decode_audio_upscaling(payload) {
                    self.device.apply_upscaling(enabled, now_ms);
                }
                if let Some(mode) = protocol::decode_connection_mode(payload) {
                    self.device.apply_connection_mode(mode, now_ms);
                }
            }
            cmd::AUDIO_RET_PARAM | cmd::AUDIO_NTFY_PARAM => {
                if let Some((on, room)) = protocol::decode_bgm_mode(payload) {
                    self.device.apply_bgm_mode(on, room, now_ms);
                } else if let Some(on) = protocol::decode_cinema_mode(payload) {
                    self.device.apply_cinema_mode(on, now_ms);
                }
            }
            cmd::EQEBB_RET_PARAM | cmd::EQEBB_NTFY_PARAM
                if table == MdrTable::Table1 =>
            {
                let update = match payload.get(1).copied() {
                    // The XM6 confirms writes in the error-code type.
                    Some(
                        protocol::eqebb_type::PRESET_EQ
                        | protocol::eqebb_type::PRESET_EQ_AND_ERRORCODE,
                    ) => {
                        protocol::decode_eq_param(payload).map(|(preset, steps)| {
                            EqualizerUpdate {
                                preset: Some(preset),
                                band_steps: Some(steps),
                                ..Default::default()
                            }
                        })
                    }
                    Some(protocol::eqebb_type::EBB) => protocol::decode_clear_bass(payload)
                        .map(|level| EqualizerUpdate {
                            clear_bass: Some(level),
                            ..Default::default()
                        }),
                    _ => None,
                };
                if let Some(u) = update {
                    self.device.apply_equalizer(u, now_ms);
                }
            }
            _ => {}
        }
        events
    }

    #[cfg(test)]
    pub(crate) fn queue_optional_read_for_test(&mut self, payload: Vec<u8>) {
        self.queue_optional_read(MdrTable::Table2, payload);
    }

    #[cfg(test)]
    pub(crate) fn pump_for_test(&mut self, now_ms: u64) -> Vec<SessionEvent> {
        self.pump(now_ms)
    }

    #[cfg(test)]
    pub(crate) fn handle_payload_for_test(
        &mut self,
        payload: &[u8],
        table: MdrTable,
        now_ms: u64,
    ) -> Vec<SessionEvent> {
        self.handle_payload(payload, table, now_ms)
    }

    /// Queue a read whose silence must not fail the session.
    /// Re-read the on-head state when the link is idle and the model has
    /// answered it before. Never ahead of anything else.
    fn queue_wear_poll(&mut self, now_ms: u64) {
        let idle = self.inflight.is_none() && self.outbox.is_empty() && self.priority.is_empty();
        if self.state != SessionState::Ready || !idle || self.device.wearing_code.is_none() {
            return;
        }
        if now_ms.saturating_sub(self.last_wear_poll_ms) < WEAR_POLL_MS {
            return;
        }
        self.last_wear_poll_ms = now_ms;
        self.queue_optional_read(MdrTable::Table2, protocol::get_wearing_checker());
    }

    fn queue_optional_read(&mut self, table: MdrTable, payload: Vec<u8>) {
        self.optional_reads.insert(payload.clone());
        self.outbox.push_back((table, payload));
    }

    /// Check for a timed-out command. Returns the payload to retry, if allowed.
    ///
    /// This is also the periodic tick, so it drains anything queued while the
    /// link was busy. Without that, a user action taken during a command would
    /// sit in the outbox forever, because the stop-and-wait link only advances
    /// when an acknowledgement arrives.
    pub fn poll_timeout(&mut self, now_ms: u64) -> Vec<SessionEvent> {
        self.queue_wear_poll(now_ms);
        if self.inflight.is_none() {
            let events = self.pump(now_ms);
            if !events.is_empty() {
                return events;
            }
        }
        let mut events = Vec::new();
        let Some(inf) = self.inflight.as_ref() else { return events };
        if now_ms.saturating_sub(inf.sent_at_ms) < self.policy.command_timeout_ms {
            return events;
        }
        let command = inf.payload.first().copied().unwrap_or(0);
        // Best-effort reads are not retried: a silent model must not spend
        // three timeouts on each optional capability.
        let optional = self.optional_reads.contains(&inf.payload);
        let max_retries = if inf.is_write || (self.state != SessionState::Ready && !optional) {
            self.policy.max_retries
        } else {
            0
        };
        if inf.retries < max_retries {
            // A retry is a retransmission: same sequence number, same payload.
            let seq = inf.seq;
            let payload = inf.payload.clone();
            let table = inf.table;
            let retries = inf.retries + 1;
            let is_write = inf.is_write;
            self.inflight = Some(InFlight {
                seq, payload: payload.clone(), table, sent_at_ms: now_ms, retries, is_write,
            });
            let bytes = framing::pack(table.data_type(), seq, &payload);
            events.push(SessionEvent::Send(bytes));
            return events;
        }
        let is_write = self.inflight.as_ref().map(|i| i.is_write).unwrap_or(true);
        let payload_key = inf.payload.clone();
        self.inflight = None;
        if optional {
            self.optional_reads.remove(&payload_key);
        }
        if !is_write && (self.state == SessionState::Ready || optional) {
            // A best-effort read that the model does not serve must not kill
            // the session; report it and move on to the next command.
            events.push(SessionEvent::Timeout(command));
            events.extend(self.pump(now_ms));
            return events;
        }
        self.state = SessionState::Error;
        events.push(SessionEvent::StateChanged(self.state));
        events.push(SessionEvent::Timeout(command));
        events
    }

    /// Number of commands still queued or in flight.
    pub fn pending(&self) -> usize {
        self.outbox.len() + self.priority.len() + usize::from(self.inflight.is_some())
    }

    /// Choose the voice assistant. Refused unless the device has reported one.
    pub fn set_voice_assistant(&mut self, value: u8, now_ms: u64) -> Option<Vec<SessionEvent>> {
        if !self.state.is_ready() || self.device.voice_assistant.is_none() {
            return None;
        }
        self.enqueue_write(protocol::set_voice_assistant(value));
        Some(self.pump(now_ms))
    }

    /// Set one general-setting slot, if the device described it.
    pub fn set_gs_boolean(
        &mut self,
        gs_type: u8,
        on: bool,
        now_ms: u64,
    ) -> Option<Vec<SessionEvent>> {
        if !self.state.is_ready()
            || !self.device.general_settings.iter().any(|s| s.gs_type == gs_type)
        {
            return None;
        }
        self.enqueue_write(protocol::set_gs_boolean(gs_type, on));
        Some(self.pump(now_ms))
    }

    /// Send a noise-control write. Refuses unless the session is ready, so a
    /// write can never race ahead of a completed handshake.
    ///
    /// Returns `None` when the session is not ready. The returned events
    /// contain the bytes to write; they may be empty when the link is busy,
    /// in which case the write is sent as soon as the outstanding command is
    /// acknowledged.
    pub fn set_noise_control(
        &mut self,
        enabled: bool,
        mode: u8,
        ambient_mode: u8,
        ambient_level: u8,
        now_ms: u64,
    ) -> Option<Vec<SessionEvent>> {
        if !self.state.is_ready() {
            return None;
        }
        let (adaptation, sensitivity) = self
            .device
            .noise_control
            .as_ref()
            .map(|v| (v.value.adaptation_on, v.value.sensitivity))
            .unwrap_or((false, 0));
        self.enqueue_write(protocol::set_noise_control_active(
            enabled,
            mode,
            ambient_mode,
            ambient_level,
            adaptation,
            sensitivity,
        ));
        Some(self.pump(now_ms))
    }

    /// Queue an arbitrary payload. Used by the diagnostic harness to probe
    /// capability families that the curated API does not cover yet.
    ///
    /// Refused unless the session is ready, so it cannot interleave with the
    /// handshake.
    pub fn send_raw(&mut self, payload: Vec<u8>, now_ms: u64) -> Option<Vec<SessionEvent>> {
        if !self.state.is_ready() || payload.is_empty() {
            return None;
        }
        self.priority.push_back((self.table, payload));
        Some(self.pump(now_ms))
    }

    /// Turn noise adaptation (auto ambient) on or off, keeping the rest of the
    /// noise-control state as it is.
    pub fn set_noise_adaptation(
        &mut self,
        enabled: bool,
        now_ms: u64,
    ) -> Option<Vec<SessionEvent>> {
        if !self.state.is_ready() {
            return None;
        }
        let (on, mode, ambient_mode, level, _, sensitivity) = self
            .device
            .noise_control
            .as_ref()
            .map(|v| {
                (
                    v.value.enabled,
                    v.value.mode,
                    v.value.ambient_mode,
                    v.value.ambient_level,
                    v.value.adaptation_on,
                    v.value.sensitivity,
                )
            })?;
        self.enqueue_write(protocol::set_noise_control_active(
            on, mode, ambient_mode, level, enabled, sensitivity,
        ));
        Some(self.pump(now_ms))
    }

    /// Queue a payload for an explicit table. Used by the diagnostic harness to
    /// reach table-2 families such as voice guidance.
    pub fn send_raw_table(
        &mut self,
        payload: Vec<u8>,
        table: MdrTable,
        now_ms: u64,
    ) -> Option<Vec<SessionEvent>> {
        if !self.state.is_ready() || payload.is_empty() {
            return None;
        }
        self.priority.push_back((table, payload));
        Some(self.pump(now_ms))
    }

    /// Request a battery refresh. Refused unless the session is ready.
    pub fn request_battery(&mut self, now_ms: u64) -> Option<Vec<SessionEvent>> {
        if !self.state.is_ready() {
            return None;
        }
        self.enqueue(protocol::get_battery());
        Some(self.pump(now_ms))
    }

    /// Choose an equaliser preset, optionally with per-band gains.
    ///
    /// Refused unless the session is ready and an equaliser has been reported,
    /// so the UI cannot write a preset the device never advertised.
    pub fn set_eq_preset(
        &mut self,
        preset: u8,
        band_steps: &[u8],
        now_ms: u64,
    ) -> Option<Vec<SessionEvent>> {
        if !self.state.is_ready() {
            return None;
        }
        let eq = self.device.equalizer.as_ref()?;
        if !eq.value.presets.is_empty() && !eq.value.presets.iter().any(|(id, _)| *id == preset) {
            // The device did not list this preset; refuse rather than send
            // something it will reject.
            return None;
        }
        // HW: the WH-1000XM6 (fw 3.1.5) acknowledges an EQEBB_SET_PARAM
        // but sends no EQEBB_NTFY_PARAM to the host that wrote it, so the
        // curve would stay pending and the UI would fall back to the old
        // one. Read it back right after the write; the reply is the
        // device's own account of what it applied.
        self.enqueue_latest_write(2, protocol::set_eq_preset(preset, band_steps));
        self.enqueue_latest_write(2, protocol::get_eq_param());
        self.device.mark_equalizer_pending(now_ms);
        Some(self.pump(now_ms))
    }

    /// Toggle audio upscaling. Refused unless the device has reported support.
    /// Send a playback control action (play, pause, next, previous, stop).
    pub fn set_playback_control(
        &mut self,
        control: u8,
        now_ms: u64,
    ) -> Option<Vec<SessionEvent>> {
        if !self.state.is_ready() {
            return None;
        }
        let payload = protocol::set_playback_control(control)?;
        self.enqueue_write(payload);
        Some(self.pump(now_ms))
    }

    /// Set the music volume, clamped to the step count the device advertised.
    ///
    /// Refused until the capability reply and the current volume have both
    /// arrived, so the UI cannot send a value outside the device's range.
    pub fn set_music_volume(&mut self, volume: u8, now_ms: u64) -> Option<Vec<SessionEvent>> {
        if !self.state.is_ready() {
            return None;
        }
        let (max, _) = self.device.playback_volume_steps.as_ref()?.value;
        if max == 0 {
            return None;
        }
        let volume = volume.min(max);
        if self.device.music_volume.as_ref().map(|v| v.value) == Some(volume) {
            return Some(Vec::new());
        }
        self.enqueue_latest_write(2, protocol::set_music_volume(volume));
        self.device.mark_music_volume_pending(volume, now_ms);
        Some(self.pump(now_ms))
    }

    /// Set the call volume, clamped to the advertised call step count.
    pub fn set_call_volume(&mut self, volume: u8, now_ms: u64) -> Option<Vec<SessionEvent>> {
        if !self.state.is_ready() {
            return None;
        }
        let (_, max) = self.device.playback_volume_steps.as_ref()?.value;
        if max == 0 {
            return None;
        }
        let volume = volume.min(max);
        if self.device.call_volume.as_ref().map(|v| v.value) == Some(volume) {
            return Some(Vec::new());
        }
        self.enqueue_latest_write(2, protocol::set_call_volume(volume));
        self.device.mark_call_volume_pending(volume, now_ms);
        Some(self.pump(now_ms))
    }

    /// Start or stop adaptive control.
    pub fn set_adaptive_control(
        &mut self,
        start: bool,
        now_ms: u64,
    ) -> Option<Vec<SessionEvent>> {
        if !self.state.is_ready() {
            return None;
        }
        self.priority
            .push_back((MdrTable::Table1, protocol::set_sense_control(start)));
        self.device.mark_sense_control_pending(start, now_ms);
        Some(self.pump(now_ms))
    }

    /// Replace the Quick Access function list (`F8 02`).
    pub fn set_quick_access_functions(
        &mut self,
        functions: &[u8],
        now_ms: u64,
    ) -> Option<Vec<SessionEvent>> {
        if !self.state.is_ready() || self.device.quick_access.is_none() {
            return None;
        }
        let payload = protocol::set_quick_access_functions(functions)?;
        self.priority.push_back((MdrTable::Table2, payload));
        self.outbox.push_back((MdrTable::Table1, protocol::get_quick_access()));
        Some(self.pump(now_ms))
    }

    /// Toggle playback control by wearing/removing the headphones.
    pub fn set_control_by_wearing(
        &mut self,
        enabled: bool,
        now_ms: u64,
    ) -> Option<Vec<SessionEvent>> {
        if !self.state.is_ready() || self.device.control_by_wearing.is_none() {
            return None;
        }
        if self.device.control_by_wearing.as_ref().map(|v| v.value) == Some(enabled) {
            return Some(Vec::new());
        }
        self.priority.push_back((
            MdrTable::Table1,
            protocol::set_control_by_wearing(enabled),
        ));
        self.device.mark_control_by_wearing_pending(enabled, now_ms);
        Some(self.pump(now_ms))
    }

    /// Toggle mic on/off by headphone operation.
    pub fn set_mic_on_off(&mut self, enabled: bool, now_ms: u64) -> Option<Vec<SessionEvent>> {
        if !self.state.is_ready() || self.device.mic_on_off.is_none() {
            return None;
        }
        if self.device.mic_on_off.as_ref().map(|v| v.value) == Some(enabled) {
            return Some(Vec::new());
        }
        self.priority
            .push_back((MdrTable::Table2, protocol::set_mic_on_off(enabled)));
        self.device.mark_mic_on_off_pending(enabled, now_ms);
        Some(self.pump(now_ms))
    }

    /// Toggle Sony Voice Assistant.
    pub fn set_sony_voice_assistant(
        &mut self,
        enabled: bool,
        now_ms: u64,
    ) -> Option<Vec<SessionEvent>> {
        if !self.state.is_ready() || self.device.sony_voice_assistant.is_none() {
            return None;
        }
        if self.device.sony_voice_assistant.as_ref().map(|v| v.value) == Some(enabled) {
            return Some(Vec::new());
        }
        self.priority.push_back((
            MdrTable::Table2,
            protocol::set_sony_voice_assistant_enabled(enabled),
        ));
        self.device.mark_sony_voice_assistant_pending(enabled, now_ms);
        Some(self.pump(now_ms))
    }

    /// Toggle voice guidance.
    pub fn set_voice_guidance(
        &mut self,
        enabled: bool,
        now_ms: u64,
    ) -> Option<Vec<SessionEvent>> {
        if !self.state.is_ready()
            || (self.device.voice_guidance.is_none()
                && self.device.voice_guidance_language.is_none()
                && self.device.voice_guidance_volume.is_none())
        {
            return None;
        }
        if self.device.voice_guidance.as_ref().map(|v| v.value) == Some(enabled) {
            return Some(Vec::new());
        }
        self.priority.push_back((
            MdrTable::Table2,
            protocol::set_voice_guidance_enabled(enabled),
        ));
        self.device.mark_voice_guidance_pending(enabled, now_ms);
        Some(self.pump(now_ms))
    }

    /// Set the voice guidance volume.
    pub fn set_voice_guidance_volume(
        &mut self,
        volume: i8,
        now_ms: u64,
    ) -> Option<Vec<SessionEvent>> {
        if !self.state.is_ready() || self.device.voice_guidance_volume.is_none() {
            return None;
        }
        self.priority.push_back((
            MdrTable::Table2,
            protocol::set_voice_guidance_volume(volume, true),
        ));
        self.device.mark_voice_guidance_volume_pending(volume, now_ms);
        Some(self.pump(now_ms))
    }

    /// Set the safe-volume WHO standard level.
    pub fn set_safe_volume_level(
        &mut self,
        level: u8,
        now_ms: u64,
    ) -> Option<Vec<SessionEvent>> {
        if !self.state.is_ready() || self.device.safe_volume_level.is_none() {
            return None;
        }
        let payload = protocol::set_safe_volume_level(level)?;
        self.priority.push_back((MdrTable::Table2, payload));
        self.device.mark_safe_volume_pending(level, now_ms);
        Some(self.pump(now_ms))
    }

    /// Toggle head gesture control.
    pub fn set_head_gesture(&mut self, enabled: bool, now_ms: u64) -> Option<Vec<SessionEvent>> {
        if !self.state.is_ready() || self.device.head_gesture.is_none() {
            return None;
        }
        if self.device.head_gesture.as_ref().map(|v| v.value) == Some(enabled) {
            return Some(Vec::new());
        }
        self.enqueue_write(protocol::set_head_gesture(enabled));
        self.device.mark_head_gesture_pending(enabled, now_ms);
        Some(self.pump(now_ms))
    }

    /// Enter or leave head gesture training mode.
    pub fn set_head_gesture_training(
        &mut self,
        start: bool,
        now_ms: u64,
    ) -> Option<Vec<SessionEvent>> {
        if !self.state.is_ready() {
            return None;
        }
        self.priority
            .push_back((MdrTable::Table1, protocol::set_head_gesture_training(start)));
        Some(self.pump(now_ms))
    }

    /// Ask the headphones to power off (`USER_POWER_OFF`).
    pub fn power_off(&mut self, now_ms: u64) -> Option<Vec<SessionEvent>> {
        if !self.state.is_ready() {
            return None;
        }
        self.enqueue_write(protocol::power_off());
        Some(self.pump(now_ms))
    }

    /// Toggle Speak-to-Chat. The preview flag is sent off; the app keeps it
    /// separate and it only matters for the on-headphone preview.
    pub fn set_smart_talking(
        &mut self,
        enabled: bool,
        now_ms: u64,
    ) -> Option<Vec<SessionEvent>> {
        if !self.state.is_ready() {
            return None;
        }
        self.device.smart_talking.as_ref()?;
        self.enqueue_write(protocol::set_smart_talking_enabled(enabled, false));
        self.device.mark_smart_talking_pending(enabled, now_ms);
        Some(self.pump(now_ms))
    }

    /// Set Speak-to-Chat sensitivity and auto-off time.
    pub fn set_smart_talking_detail(
        &mut self,
        sensitivity: u8,
        mode_out: u8,
        now_ms: u64,
    ) -> Option<Vec<SessionEvent>> {
        if !self.state.is_ready() {
            return None;
        }
        self.device.smart_talking.as_ref()?;
        let payload = protocol::set_smart_talking_detail(sensitivity, mode_out)?;
        self.enqueue_write(payload);
        self.device
            .mark_smart_talking_detail_pending(sensitivity, mode_out, now_ms);
        Some(self.pump(now_ms))
    }

    /// Toggle auto standby (table-2 POWER type 0x00).
    ///
    /// Refused until the current setting has been read.
    pub fn set_auto_standby(
        &mut self,
        enabled: bool,
        now_ms: u64,
    ) -> Option<Vec<SessionEvent>> {
        if !self.state.is_ready() {
            return None;
        }
        self.device.auto_standby_enabled.as_ref()?;
        if self.device.auto_standby_enabled.as_ref().map(|v| v.value) == Some(enabled) {
            return Some(Vec::new());
        }
        self.priority
            .push_back((MdrTable::Table2, protocol::set_auto_standby(enabled)));
        self.device.mark_auto_standby_pending(enabled, now_ms);
        Some(self.pump(now_ms))
    }

    /// Toggle music hand-over (table-2 PERI type 0x03).
    ///
    /// Refused until the device has reported the current value, so the UI
    /// cannot write a setting the model does not have.
    pub fn set_music_hand_over(
        &mut self,
        enabled: bool,
        now_ms: u64,
    ) -> Option<Vec<SessionEvent>> {
        if !self.state.is_ready() || self.device.music_hand_over.is_none() {
            return None;
        }
        if self.device.music_hand_over.as_ref().map(|v| v.value) == Some(enabled) {
            return Some(Vec::new());
        }
        self.priority
            .push_back((MdrTable::Table2, protocol::set_music_hand_over(enabled)));
        self.device.mark_music_hand_over_pending(enabled, now_ms);
        Some(self.pump(now_ms))
    }

    /// Connect to a paired device by its index in the last reported list.
    ///
    /// The write is followed by a list re-read so the state reflects what the
    /// headset actually did; notifications are not required for correctness.
    pub fn pairing_connect(
        &mut self,
        index: usize,
        now_ms: u64,
    ) -> Option<Vec<SessionEvent>> {
        self.pairing_connection(index, protocol::pairing_action::CONNECT, now_ms)
    }

    /// Disconnect a paired device by its index in the last reported list.
    ///
    /// Disconnecting the host closes the control channel; the frame is returned
    /// to the caller first, so the write still reaches the headset.
    pub fn pairing_disconnect(
        &mut self,
        index: usize,
        now_ms: u64,
    ) -> Option<Vec<SessionEvent>> {
        self.pairing_connection(index, protocol::pairing_action::DISCONNECT, now_ms)
    }

    fn pairing_connection(
        &mut self,
        index: usize,
        action: u8,
        now_ms: u64,
    ) -> Option<Vec<SessionEvent>> {
        if !self.state.is_ready() {
            return None;
        }
        let (address, connected) = {
            let list = self.device.paired_devices.as_ref()?;
            let device = list.value.devices.get(index)?;
            (device.address.clone(), device.connected)
        };
        let wants_connected = action == protocol::pairing_action::CONNECT;
        if connected == wants_connected {
            return Some(Vec::new());
        }
        let payload = protocol::set_pairing_connection(action, &address)?;
        self.priority.push_back((MdrTable::Table2, payload));
        self.outbox
            .push_front((MdrTable::Table2, protocol::get_pairing_devices()));
        Some(self.pump(now_ms))
    }

    /// Enter or leave pairing (inquiry-scan) mode.
    pub fn pairing_set_mode(
        &mut self,
        pairing: bool,
        now_ms: u64,
    ) -> Option<Vec<SessionEvent>> {
        if !self.state.is_ready() {
            return None;
        }
        self.priority
            .push_back((MdrTable::Table2, protocol::set_pairing_mode(pairing)));
        Some(self.pump(now_ms))
    }

    /// Switch the listening mode.
    ///
    /// Refused until both underlying settings have been read, because the
    /// current room size is part of the BGM setter and must be preserved.
    /// The device enforces exclusivity, but the previous mode is switched off
    /// explicitly so a lost reply cannot leave two modes enabled.
    pub fn set_listening_mode(
        &mut self,
        mode: protocol::ListeningMode,
        now_ms: u64,
    ) -> Option<Vec<SessionEvent>> {
        if !self.state.is_ready() {
            return None;
        }
        let current = self.device.listening()?;
        if current.mode() == mode {
            return Some(Vec::new());
        }
        match mode {
            protocol::ListeningMode::Normal => {
                if current.bgm_on {
                    self.enqueue_write(protocol::set_bgm_mode(false, current.room)?);
                }
                if current.cinema_on {
                    self.enqueue_write(protocol::set_cinema_mode(false));
                }
            }
            protocol::ListeningMode::Bgm => {
                if current.cinema_on {
                    self.enqueue_write(protocol::set_cinema_mode(false));
                }
                self.enqueue_write(protocol::set_bgm_mode(true, current.room)?);
            }
            protocol::ListeningMode::Cinema => {
                if current.bgm_on {
                    self.enqueue_write(protocol::set_bgm_mode(false, current.room)?);
                }
                self.enqueue_write(protocol::set_cinema_mode(true));
            }
        }
        self.device.mark_listening_pending(mode, now_ms);
        Some(self.pump(now_ms))
    }

    /// Set the wearing-detection auto-power-off element.
    pub fn set_auto_power_off_wearing(
        &mut self,
        current: u8,
        last: u8,
        now_ms: u64,
    ) -> Option<Vec<SessionEvent>> {
        if !self.state.is_ready() {
            return None;
        }
        let payload = protocol::set_auto_power_off_wearing(current, last)?;
        self.enqueue_write(payload);
        Some(self.pump(now_ms))
    }

    pub fn set_upscaling(&mut self, enabled: bool, now_ms: u64) -> Option<Vec<SessionEvent>> {
        if !self.state.is_ready() || self.device.upscaling.is_none() {
            return None;
        }
        self.enqueue_write(protocol::set_audio_upscaling(enabled));
        if let Some(v) = self.device.upscaling.as_mut() {
            v.provenance = crate::state::Provenance::PendingWrite;
            v.value = enabled;
            v.at_ms = now_ms;
        }
        Some(self.pump(now_ms))
    }

    /// Set the Clear Bass level. Clamped to the range the device reported.
    pub fn set_clear_bass(&mut self, level: i8, now_ms: u64) -> Option<Vec<SessionEvent>> {
        if !self.state.is_ready() {
            return None;
        }
        let (min, max) = self
            .device
            .equalizer
            .as_ref()
            .map(|v| (v.value.clear_bass_min, v.value.clear_bass_max))
            .unwrap_or((-10, 10));
        self.enqueue_write(protocol::set_clear_bass(level, min, max));
        self.device.mark_equalizer_pending(now_ms);
        Some(self.pump(now_ms))
    }

    /// Mark the session dead. `suspend` distinguishes OS sleep from a real loss.
    pub fn disconnect(&mut self, suspend: bool) {
        self.state = if suspend { SessionState::Suspended } else { SessionState::Disconnected };
        self.inflight = None;
        self.outbox.clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::framing;

    /// A stand-in for the device side of the link.
    ///
    /// It alternates sequence numbers exactly like the hardware and always
    /// acknowledges what it receives, so the session sees a faithful peer.
    struct FakeDevice {
        seq: u8,
    }

    impl FakeDevice {
        fn new() -> Self {
            FakeDevice { seq: 0 }
        }

        /// The next frame the device would send.
        fn frame(&mut self, payload: &[u8]) -> Vec<u8> {
            let seq = self.seq;
            self.seq = MdrTable::reciprocal(seq);
            framing::pack(DataType::DataMdr, seq, payload)
        }

        /// Acknowledge whatever the session has outstanding, then deliver a
        /// response — the order a real device uses.
        fn exchange(&mut self, session: &mut Session, now: u64, payload: &[u8]) -> Vec<SessionEvent> {
            let mut events = Vec::new();
            if let Some(seq) = session.outstanding_seq() {
                events.extend(session.receive(&framing::pack(DataType::Ack, MdrTable::reciprocal(seq), &[]), now));
            }
            events.extend(session.receive(&self.frame(payload), now));
            events
        }
    }

    fn sends(events: &[SessionEvent]) -> Vec<Vec<u8>> {
        events
            .iter()
            .filter_map(|e| match e {
                SessionEvent::Send(b) => Some(b.clone()),
                _ => None,
            })
            .collect()
    }

    fn payload_of(bytes: &[u8]) -> Vec<u8> {
        let mut dec = framing::StreamDecoder::new();
        dec.push(bytes);
        dec.next_frame().unwrap().unwrap().payload
    }

    fn frame_of(bytes: &[u8]) -> Frame {
        let mut dec = framing::StreamDecoder::new();
        dec.push(bytes);
        dec.next_frame().unwrap().unwrap()
    }

    /// `CONNECT_RET_PROTOCOL_INFO` with version 2 and both tables enabled.
    const PROTOCOL_INFO: [u8; 8] = [
        cmd::CONNECT_RET_PROTOCOL_INFO,
        0x00,
        0x00,
        0x00,
        0x00,
        0x02,
        protocol::ENABLE,
        protocol::ENABLE,
    ];

    #[test]
    fn handshake_uses_the_shipped_connect_payloads() {
        let mut s = Session::new(Policy::default());
        let events = s.connect(0);
        let out = sends(&events);
        assert_eq!(out.len(), 1);
        assert_eq!(payload_of(&out[0]), vec![cmd::CONNECT_GET_PROTOCOL_INFO, 0x00]);
        // The frame must travel as DATA_MDR (0x0C), not DATA (0x00).
        let frame = frame_of(&out[0]);
        assert_eq!(frame.kind(), DataType::DataMdr);
        assert_eq!(frame.seq, 0);
    }

    #[test]
    fn every_received_data_frame_is_acknowledged() {
        let mut s = Session::new(Policy::default());
        let mut dev = FakeDevice::new();
        s.connect(0);
        let events = dev.exchange(&mut s, 1, &PROTOCOL_INFO);
        let out = sends(&events);
        // The first outbound frame is the ACK for the device's frame.
        let ack = frame_of(&out[0]);
        assert_eq!(ack.kind(), DataType::Ack);
        assert_eq!(ack.seq, 1);
    }

    #[test]
    fn a_duplicate_frame_is_reacked_but_not_reprocessed() {
        let mut s = Session::new(Policy::default());
        let mut dev = FakeDevice::new();
        s.connect(0);
        let frame = dev.frame(&[cmd::POWER_NTFY_STATUS, 0x00, 90, 0x00]);
        let first = s.receive(&frame, 1);
        assert_eq!(sends(&first).len(), 1); // just the ACK
        let second = s.receive(&frame, 2);
        // Only the ACK: the duplicate must not be processed again.
        assert_eq!(sends(&second).len(), 1);
        assert_eq!(sends(&second)[0], sends(&first)[0]);
    }

    #[test]
    fn only_one_command_is_outstanding_at_a_time() {
        let mut s = Session::new(Policy::default());
        let mut dev = FakeDevice::new();
        s.connect(0);
        // The device answers before acknowledging, so the session must not
        // have queued a second command yet.
        let events = s.receive(&dev.frame(&PROTOCOL_INFO), 1);
        assert_eq!(sends(&events).len(), 1);
        assert_eq!(s.outstanding_seq(), Some(0));
    }

    #[test]
    fn full_handshake_reaches_ready() {
        let mut s = Session::new(Policy::default());
        let mut dev = FakeDevice::new();
        s.connect(0);

        dev.exchange(&mut s, 10, &PROTOCOL_INFO);
        assert_eq!(s.state(), SessionState::DiscoveringCapabilities);

        dev.exchange(&mut s, 20, &[cmd::CONNECT_RET_DEVICE_INFO, 0x02, 0x05, b'3', b'.', b'1', b'.', b'5']);
        dev.exchange(&mut s, 25, &[cmd::CONNECT_RET_DEVICE_INFO, 0x01, 0x0A, b'W', b'H', b'-', b'1', b'0', b'0', b'0', b'X', b'M', b'6']);
        assert_eq!(s.device.identity.model, "WH-1000XM6");
        assert_eq!(s.device.identity.firmware, "3.1.5");

        dev.exchange(&mut s, 30, &[cmd::POWER_RET_STATUS, 0x00, 77, 0x00]);
        assert_eq!(s.state(), SessionState::Ready);
        assert_eq!(s.device.battery.as_ref().unwrap().value.level, 77);
        assert!(s.protocol_info.is_some());
    }

    #[test]
    fn eq_status_is_read_in_the_type_the_capability_used() {
        let mut s = Session::new(Policy::default());
        // Shape of the XM6 reply: 10 bands, step 13, two presets.
        let cap = [cmd::EQEBB_RET_CAPABILITY, 0x04, 0x0A, 0x0D, 0x02, 0x00, 0x00, 0xA0, 0x00];
        s.handle_payload(&cap, MdrTable::Table1, 0);
        assert!(s.outbox.iter().any(|(t, p)| *t == MdrTable::Table1 && p == &vec![0x52, 0x04]));
        // Unreported status is unknown, not off.
        let eq = &s.device.equalizer.as_ref().unwrap().value;
        assert!(!eq.status_known);
        s.handle_payload(&[cmd::EQEBB_RET_STATUS, 0x04, 0x00, 0x00], MdrTable::Table1, 5);
        let eq = &s.device.equalizer.as_ref().unwrap().value;
        assert!(eq.status_known && eq.enabled);
    }

    #[test]
    fn wearing_checker_sets_the_worn_code_from_table_two() {
        let mut s = Session::new(Policy::default());
        // HW: F3 00 00 while worn (WH-1000XM6, fw 3.1.5).
        s.handle_payload(&[cmd::SYSTEM_RET_STATUS, 0x00, 0x00], MdrTable::Table2, 1);
        assert_eq!(s.device.wearing_code.as_ref().map(|v| v.value), Some(0));
        s.handle_payload(&[cmd::SYSTEM_NTFY_STATUS, 0x00, 0x04], MdrTable::Table2, 2);
        assert_eq!(s.device.wearing_code.as_ref().map(|v| v.value), Some(4));
        // Table 1 F3 00 … is something else; it must not touch the code.
        s.handle_payload(&[cmd::SYSTEM_RET_STATUS, 0x00, 0x00], MdrTable::Table1, 3);
        assert_eq!(s.device.wearing_code.as_ref().map(|v| v.value), Some(4));
        // ILLEGAL is ignored.
        s.handle_payload(&[cmd::SYSTEM_NTFY_STATUS, 0x00, 0x01], MdrTable::Table2, 4);
        assert_eq!(s.device.wearing_code.as_ref().map(|v| v.value), Some(4));
    }

    #[test]
    fn on_head_state_is_re_read_while_idle() {
        let mut s = Session::new(Policy::default());
        s.state = SessionState::Ready;
        // Never asked before the model has answered it once.
        assert!(s.poll_timeout(10_000).is_empty());
        s.handle_payload(&[cmd::SYSTEM_RET_STATUS, 0x00, 0x00], MdrTable::Table2, 10_000);
        let rev = s.device.revision;
        let sent = s.poll_timeout(20_000);
        assert!(matches!(sent.as_slice(), [SessionEvent::Send(_)]));
        // The same answer again is not a change.
        s.inflight = None;
        s.handle_payload(&[cmd::SYSTEM_RET_STATUS, 0x00, 0x00], MdrTable::Table2, 20_050);
        assert_eq!(s.device.revision, rev);
        // Not again within the interval.
        assert!(s.poll_timeout(21_000).is_empty());
        // Taken off: the next read says so.
        assert!(!s.poll_timeout(23_100).is_empty());
        s.inflight = None;
        s.handle_payload(&[cmd::SYSTEM_RET_STATUS, 0x00, 0x04], MdrTable::Table2, 23_150);
        assert_eq!(s.device.wearing_code.as_ref().map(|v| v.value), Some(4));
    }

    #[test]
    fn eq_write_is_followed_by_one_read_back() {
        let mut s = Session::new(Policy::default());
        s.state = SessionState::Ready;
        s.device.apply_equalizer(
            EqualizerUpdate {
                enabled: Some(true),
                preset: Some(0xA0),
                band_steps: Some(vec![6; 10]),
                capability: Some((10, 13, vec![(0xA0, "Custom".into())])),
                ..Default::default()
            },
            0,
        );
        // Something is on the wire, so both writes wait in the queue.
        s.inflight = Some(InFlight {
            seq: 0,
            payload: vec![0x00],
            table: MdrTable::Table1,
            sent_at_ms: 0,
            retries: 0,
            is_write: false,
        });
        s.set_eq_preset(0xA0, &[5; 10], 1);
        s.set_eq_preset(0xA0, &[4; 10], 2);
        let queued: Vec<&Vec<u8>> = s.priority.iter().map(|(_, p)| p).collect();
        assert_eq!(queued.len(), 2, "one write and one read, newest write only: {queued:?}");
        assert_eq!(queued[0][0], cmd::EQEBB_SET_PARAM);
        assert_eq!(queued[0][queued[0].len() - 1], 4);
        assert_eq!(queued[1], &protocol::get_eq_param());
    }

    #[test]
    fn error_code_eq_notifications_update_state_and_clear_pending() {
        let mut s = Session::new(Policy::default());
        s.device.apply_equalizer(
            EqualizerUpdate {
                enabled: Some(true),
                preset: Some(0xA0),
                band_steps: Some(vec![5; 10]),
                capability: Some((10, 21, vec![(0xA0, "Custom".into()), (0x30, "Bright".into())])),
                ..Default::default()
            },
            0,
        );
        s.device.mark_equalizer_pending(1);
        assert!(s.device.has_pending_write());

        let mut ntfy = vec![cmd::EQEBB_NTFY_PARAM, 0x04, 0x30, 0x0A];
        ntfy.extend([0x0A, 0x0A, 0x05, 0x05, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06]);
        s.handle_payload(&ntfy, MdrTable::Table1, 10);
        let eq = &s.device.equalizer.as_ref().unwrap().value;
        assert_eq!(eq.preset, 0x30);
        assert_eq!(eq.band_steps[0], 0x0A);
        assert!(!s.device.has_pending_write());

        s.handle_payload(&[cmd::EQEBB_NTFY_STATUS, 0x04, 0x01, 0x01, 0x02], MdrTable::Table1, 20);
        let eq = &s.device.equalizer.as_ref().unwrap().value;
        assert!(!eq.enabled);
        assert_eq!(eq.error_codes, vec![0x02]);

        s.handle_payload(&[cmd::EQEBB_NTFY_STATUS, 0x04, 0x00, 0x00], MdrTable::Table1, 30);
        let eq = &s.device.equalizer.as_ref().unwrap().value;
        assert!(eq.enabled);
        assert!(eq.error_codes.is_empty());

        // The same bytes on table 2 are a different family (safe listening
        // shares 0x5x ids there) and must not touch the equaliser.
        s.handle_payload(&[0x55, 0x04, 0x01, 0x01, 0x02], MdrTable::Table2, 40);
        s.handle_payload(&[0x59, 0x04, 0x33, 0x01, 0x00], MdrTable::Table2, 41);
        let eq = &s.device.equalizer.as_ref().unwrap().value;
        assert!(eq.enabled);
        assert_eq!(eq.preset, 0x30);
    }

    #[test]
    fn series_and_color_is_read_as_bytes_without_restarting_sync() {
        let mut s = Session::new(Policy::default());
        let mut dev = FakeDevice::new();
        s.connect(0);
        dev.exchange(&mut s, 10, &PROTOCOL_INFO);
        dev.exchange(&mut s, 20, &[cmd::CONNECT_RET_DEVICE_INFO, 0x02, 0x05, b'3', b'.', b'1', b'.', b'5']);
        dev.exchange(&mut s, 25, &[cmd::CONNECT_RET_DEVICE_INFO, 0x01, 0x02, b'W', b'H']);
        assert_eq!(s.state(), SessionState::Syncing);
        dev.exchange(&mut s, 28, &[cmd::CONNECT_RET_DEVICE_INFO, 0x03, 0x00, 0x05]);
        assert_eq!(s.device.identity.model_color, Some(0x05));
        assert_eq!(s.device.identity.model_series, Some(0x00));
        // Model name is untouched by the colour reply.
        assert_eq!(s.device.identity.model, "WH");
        assert_eq!(s.state(), SessionState::Syncing);
    }

    #[test]
    fn protocol_info_flags_are_decoded_with_the_inverted_enable_value() {
        let mut s = Session::new(Policy::default());
        let mut dev = FakeDevice::new();
        s.connect(0);
        // EnableDisable.ENABLE == 0, DISABLE == 1.
        dev.exchange(&mut s, 10, &[cmd::CONNECT_RET_PROTOCOL_INFO, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x01]);
        let info = s.protocol_info.expect("protocol info");
        assert!(info.supports_table1);
        assert!(!info.supports_table2);
        assert_eq!(info.version, 2);
    }

    #[test]
    fn write_refused_before_ready() {
        let mut s = Session::new(Policy::default());
        assert!(s.set_noise_control(true, 0, 0, 10, 0).is_none());
        assert!(s.request_battery(0).is_none());
    }

    #[test]
    fn timeout_retries_with_the_same_sequence_number() {
        let policy = Policy { command_timeout_ms: 100, max_retries: 1, ..Policy::default() };
        let mut s = Session::new(policy);
        s.connect(0);
        assert!(s.poll_timeout(50).is_empty());
        let first = s.poll_timeout(150);
        let out = sends(&first);
        assert_eq!(out.len(), 1);
        // Same sequence number: a retry is a retransmission.
        assert_eq!(frame_of(&out[0]).seq, 0);

        let second = s.poll_timeout(400);
        assert!(second.iter().any(|e| matches!(e, SessionEvent::Timeout(_))));
    }

    #[test]
    fn an_ack_advances_the_sequence_number() {
        let mut s = Session::new(Policy::default());
        let mut dev = FakeDevice::new();
        s.connect(0);
        // The device's answer queues the next commands, but our first command
        // is still outstanding until the device acknowledges it.
        s.receive(&dev.frame(&PROTOCOL_INFO), 1);
        assert_eq!(s.outstanding_seq(), Some(0));

        // We sent seq 0, so the ACK carries the reciprocal, 1.
        let events = s.receive(&framing::pack(DataType::Ack, 1, &[]), 5);
        let out = sends(&events);
        // The next queued command goes out with the next sequence number.
        assert_eq!(out.len(), 1);
        assert_eq!(frame_of(&out[0]).seq, 1);
    }

    #[test]
    fn a_stale_ack_is_ignored() {
        let mut s = Session::new(Policy::default());
        s.connect(0);
        // We sent seq 0, so seq 0 as an ACK is not the reciprocal (1).
        let events = s.receive(&framing::pack(DataType::Ack, 0, &[]), 5);
        assert!(sends(&events).is_empty());
    }

    #[test]
    fn listening_mode_needs_both_reads_before_a_write_is_allowed() {
        let mut s = Session::new(Policy::default());
        let mut dev = FakeDevice::new();
        s.connect(0);
        dev.exchange(&mut s, 1, &PROTOCOL_INFO);
        dev.exchange(&mut s, 2, &[cmd::CONNECT_RET_DEVICE_INFO, 0x02, 0x03, b'1', b'.', b'0']);
        dev.exchange(&mut s, 3, &[cmd::CONNECT_RET_DEVICE_INFO, 0x01, 0x02, b'W', b'H']);
        dev.exchange(&mut s, 4, &[cmd::POWER_RET_STATUS, 0x00, 50, 0]);
        assert!(s.state().is_ready());

        // Only BGM has arrived; the mode is still unknown and a write must be
        // refused rather than guessed.
        dev.exchange(&mut s, 5, &[cmd::AUDIO_RET_PARAM, 0x09, 0x01, 0x01]);
        assert!(s.device.listening().is_none());
        assert!(s.set_listening_mode(protocol::ListeningMode::Cinema, 6).is_none());

        dev.exchange(&mut s, 7, &[cmd::AUDIO_RET_PARAM, 0x04, 0x01]);
        let listen = s.device.listening().expect("both reads");
        assert_eq!(listen.mode(), protocol::ListeningMode::Normal);
        assert_eq!(listen.room, 1);
    }

    #[test]
    fn listening_mode_switch_turns_the_other_mode_off_first() {
        let mut s = Session::new(Policy::default());
        let mut dev = FakeDevice::new();
        s.connect(0);
        dev.exchange(&mut s, 1, &PROTOCOL_INFO);
        dev.exchange(&mut s, 2, &[cmd::CONNECT_RET_DEVICE_INFO, 0x02, 0x03, b'1', b'.', b'0']);
        dev.exchange(&mut s, 3, &[cmd::CONNECT_RET_DEVICE_INFO, 0x01, 0x02, b'W', b'H']);
        dev.exchange(&mut s, 4, &[cmd::POWER_RET_STATUS, 0x00, 50, 0]);
        // Drain the automatic read queue the ready transition enqueued, so the
        // write below is the next command on the wire.
        while let Some(seq) = s.outstanding_seq() {
            s.receive(&framing::pack(DataType::Ack, MdrTable::reciprocal(seq), &[]), 5);
        }
        dev.exchange(&mut s, 5, &[cmd::AUDIO_RET_PARAM, 0x09, 0x00, 0x02]);
        dev.exchange(&mut s, 6, &[cmd::AUDIO_RET_PARAM, 0x04, 0x01]);

        // BGM is on; choose Cinema. BGM must be switched off with its room
        // size preserved, then Cinema switched on.
        let events = s.set_listening_mode(protocol::ListeningMode::Cinema, 7).expect("ready");
        let first = sends(&events);
        assert_eq!(first.len(), 1, "stop-and-wait sends one command");
        assert_eq!(payload_of(&first[0]), vec![0xE8, 0x09, 0x01, 0x02]);

        let seq = s.outstanding_seq().expect("in flight");
        let events = s.receive(&framing::pack(DataType::Ack, MdrTable::reciprocal(seq), &[]), 8);
        let second = sends(&events);
        assert_eq!(second.len(), 1);
        assert_eq!(payload_of(&second[0]), vec![0xE8, 0x04, 0x00]);

        // Optimistic state: pending until the device confirms.
        let listen = s.device.listening().expect("both reads");
        assert_eq!(listen.mode(), protocol::ListeningMode::Cinema);
        assert!(s.device.has_pending_write());
    }

    #[test]
    fn noise_control_notification_updates_state() {
        let mut s = Session::new(Policy::default());
        let mut dev = FakeDevice::new();
        s.connect(0);
        dev.exchange(&mut s, 1, &PROTOCOL_INFO);
        dev.exchange(&mut s, 2, &[cmd::CONNECT_RET_DEVICE_INFO, 0x02, 0x03, b'1', b'.', b'0']);
        dev.exchange(&mut s, 3, &[cmd::CONNECT_RET_DEVICE_INFO, 0x01, 0x02, b'W', b'H']);
        dev.exchange(&mut s, 4, &[cmd::POWER_RET_STATUS, 0x00, 50, 0]);
        assert!(s.state().is_ready());
        dev.exchange(&mut s, 5, &[cmd::NCASM_NTFY_PARAM, 0x17, 0x01, 0x01, 0x00, 0x00, 0x0B]);
        let nc = s.device.noise_control.as_ref().unwrap();
        assert!(nc.value.is_noise_cancelling());
        assert_eq!(nc.value.ambient_level, 11);
    }
}
