//! C ABI for the MDR engine.
//!
//! The ABI is deliberately tiny and handle-based so Swift, Kotlin/JNI and C#
//! can all drive the same core without embedding Rust types. All functions are
//! panic-free (the crate forbids `unsafe` and every entry point validates its
//! inputs), but callers must still treat every pointer argument as nullable.

use std::ffi::c_void;
use std::os::raw::c_char;

use mdr_core::{Policy, Session, SessionEvent, SessionState};

/// Opaque session handle.
pub struct MdrSession {
    inner: Session,
}

/// Result codes shared with every binding.
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MdrStatus {
    Ok = 0,
    NullHandle = 1,
    NotReady = 2,
    NoData = 3,
}

/// Flat view of engine state, read by the UI after each step.
///
/// Negative values mean "not known" — the distinction between "the device says
/// noise cancelling is off" and "we have not heard about noise control yet"
/// must survive the boundary, or the UI will show a confident wrong value.
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct MdrSnapshot {
    pub state: u8,
    pub battery_level: i16,
    pub battery_charging: i16,
    pub nc_enabled: i16,
    pub nc_mode: i16,
    pub ambient_mode: i16,
    pub ambient_level: i16,
    pub revision: u64,
    /// 1 when a local write is still unconfirmed.
    pub pending_write: u8,
    /// 1 when noise-control state has actually been received.
    pub nc_known: u8,
    /// Noise adaptation (auto ambient) on/off.
    pub nc_adaptation: u8,
    /// Noise-adaptation sensitivity step.
    pub nc_sensitivity: u8,
    /// Negotiated protocol version, or 0 when unknown.
    pub protocol_version: u32,
    /// 1 when the device reports support for each table.
    pub supports_table1: u8,
    pub supports_table2: u8,
    /// Model name reported by the device.
    pub model: [c_char; 48],
    /// Firmware version reported by the device.
    pub firmware: [c_char; 48],
    /// 1 when equaliser state has actually been received.
    pub eq_known: u8,
    /// 1 when the equaliser is on.
    pub eq_enabled: u8,
    /// Current `EqPresetId` wire value.
    pub eq_preset: u8,
    /// Number of bands the device advertises.
    pub eq_band_count: u8,
    /// Step granularity per band.
    pub eq_band_step: u8,
    /// Length of `eq_bands`.
    pub eq_band_len: u8,
    /// Per-band step values, in device order.
    pub eq_bands: [u8; 16],
    /// Clear Bass level and the range the device reported.
    pub clear_bass: i16,
    pub clear_bass_min: i16,
    pub clear_bass_max: i16,
    /// Number of presets the device offers; read each with `mdr_eq_preset_at`.
    pub eq_preset_count: u16,
    /// 1 when the device has reported audio upscaling support/state.
    pub upscaling_known: u8,
    /// 1 when upscaling is on.
    pub upscaling_enabled: u8,
    /// Negotiated codec name, NUL-terminated.
    pub codec: [c_char; 16],
    /// Auto power off (read-only) and connection mode flags.
    pub apo_known: u8,
    pub apo_enabled: u8,
    pub conn_known: u8,
    pub conn_classic: u8,
    pub conn_le: u8,
    /// Table-2 peripheral/power reads.
    pub mho_known: u8,
    pub mho_enabled: u8,
    pub usb_known: u8,
    pub usb_submerged: u8,
    /// Playback controller state.
    pub play_known: u8,
    pub play_enabled: u8,
    pub play_state: u8,
    pub play_source: u8,
    /// Wearing detection (SYSTEM 0x06): known flag and decoded fields.
    pub wear_known: u8,
    pub wear_detection_enabled: u8,
    pub wear_worn: u8,
    pub wear_selected_earpieces: u8,
    pub wear_result_code: u8,
    /// Auto power off with wearing detection: (current, last) element.
    pub apow_known: u8,
    pub apow_current: u8,
    pub apow_last: u8,
    pub apow_enabled_known: u8,
    pub apow_enabled: u8,
    /// Listening mode: 1 when both BGM and Cinema settings have been read.
    /// `listen_mode` is 0 standard, 1 BGM, 2 cinema; `listen_room` is the
    /// last `RoomSize`.
    pub listen_known: u8,
    pub listen_mode: u8,
    pub listen_room: u8,
    /// Music volume: 1 when both the step count and current value are known.
    pub volume_known: u8,
    pub volume_steps: u8,
    pub volume: u8,
    /// Call volume, same gating.
    pub call_volume_known: u8,
    pub call_volume_steps: u8,
    pub call_volume: u8,
    /// Auto volume with limitation (read-only).
    pub auto_volume_known: u8,
    pub auto_volume_enabled: u8,
    /// Auto standby candidate.
    pub auto_standby_known: u8,
    pub auto_standby_available: u8,
    /// Auto-standby on/off setting.
    pub auto_standby_setting_known: u8,
    pub auto_standby_setting: u8,
    /// Speak-to-Chat: known, enabled, effect, sensitivity, auto-off time.
    pub st_known: u8,
    pub st_enabled: u8,
    pub st_effect: u8,
    pub st_sensitivity: u8,
    pub st_mode_out: u8,
    /// Head gesture on/off.
    pub hg_known: u8,
    pub hg_enabled: u8,
    /// Safe-volume WHO level.
    pub safe_volume_known: u8,
    pub safe_volume_level: u8,
    /// Adaptive control started.
    pub ac_known: u8,
    pub ac_started: u8,
    /// Quick Access function ids.
    pub qa_known: u8,
    pub qa_count: u8,
    pub qa0: u8,
    pub qa1: u8,
    /// Control by wearing.
    pub cbw_known: u8,
    pub cbw_enabled: u8,
    /// Mic on/off.
    pub mic_known: u8,
    pub mic_enabled: u8,
    /// Sony Voice Assistant.
    pub sva_known: u8,
    pub sva_enabled: u8,
    pub sval_known: u8,
    pub sval_language: u8,
    /// Voice guidance.
    pub vg_known: u8,
    pub vg_enabled: u8,
    pub vgv_known: u8,
    pub vgv_volume: i8,
    /// Head gesture training.
    pub hgt_known: u8,
    pub hgt_in_test: u8,
    pub hgt_enabled: u8,
    pub hga_known: u8,
    pub hga_action: u8,
    /// Paired-device management (table-2 PERI type 0x00/0x02).
    pub pair_known: u8,
    pub pair_count: u8,
    pub pair_connected_count: u8,
    pub pair_playback_device: u8,
}

impl Default for MdrSnapshot {
    fn default() -> Self {
        MdrSnapshot {
            state: 0,
            battery_level: -1,
            battery_charging: -1,
            nc_enabled: -1,
            nc_mode: -1,
            ambient_mode: -1,
            ambient_level: -1,
            revision: 0,
            pending_write: 0,
            nc_known: 0,
            nc_adaptation: 0,
            nc_sensitivity: 0,
            protocol_version: 0,
            supports_table1: 0,
            supports_table2: 0,
            model: [0; 48],
            firmware: [0; 48],
            eq_known: 0,
            eq_enabled: 0,
            eq_preset: 0,
            eq_band_count: 0,
            eq_band_step: 0,
            eq_band_len: 0,
            eq_bands: [0; 16],
            clear_bass: 0,
            clear_bass_min: 0,
            clear_bass_max: 0,
            eq_preset_count: 0,
            upscaling_known: 0,
            upscaling_enabled: 0,
            codec: [0; 16],
            apo_known: 0,
            apo_enabled: 0,
            conn_known: 0,
            conn_classic: 0,
            conn_le: 0,
            mho_known: 0,
            mho_enabled: 0,
            usb_known: 0,
            usb_submerged: 0,
            play_known: 0,
            play_enabled: 0,
            play_state: 0,
            play_source: 0,
            wear_known: 0,
            wear_detection_enabled: 0,
            wear_worn: 0,
            wear_selected_earpieces: 0,
            wear_result_code: 0,
            apow_known: 0,
            apow_current: 0,
            apow_last: 0,
            apow_enabled_known: 0,
            apow_enabled: 0,
            listen_known: 0,
            listen_mode: 0,
            listen_room: 0,
            volume_known: 0,
            volume_steps: 0,
            volume: 0,
            call_volume_known: 0,
            call_volume_steps: 0,
            call_volume: 0,
            auto_volume_known: 0,
            auto_volume_enabled: 0,
            auto_standby_known: 0,
            auto_standby_available: 0,
            auto_standby_setting_known: 0,
            auto_standby_setting: 0,
            st_known: 0,
            st_enabled: 0,
            st_effect: 0,
            st_sensitivity: 0,
            st_mode_out: 0,
            hg_known: 0,
            hg_enabled: 0,
            safe_volume_known: 0,
            safe_volume_level: 0,
            ac_known: 0,
            ac_started: 0,
            qa_known: 0,
            qa_count: 0,
            qa0: 0,
            qa1: 0,
            cbw_known: 0,
            cbw_enabled: 0,
            mic_known: 0,
            mic_enabled: 0,
            sva_known: 0,
            sva_enabled: 0,
            sval_known: 0,
            sval_language: 0,
            vg_known: 0,
            vg_enabled: 0,
            vgv_known: 0,
            vgv_volume: 0,
            hgt_known: 0,
            hgt_in_test: 0,
            hgt_enabled: 0,
            hga_known: 0,
            hga_action: 0,
            pair_known: 0,
            pair_count: 0,
            pair_connected_count: 0,
            pair_playback_device: 0,
        }
    }
}

/// Copy a Rust string into a fixed C buffer, NUL-terminated and truncated.
fn copy_str(dst: &mut [c_char], src: &str) {
    for (slot, byte) in dst.iter_mut().zip(src.as_bytes().iter()) {
        *slot = *byte as c_char;
    }
}

fn state_code(s: SessionState) -> u8 {
    match s {
        SessionState::Disconnected => 0,
        SessionState::Connecting => 1,
        SessionState::Handshaking => 2,
        SessionState::DiscoveringCapabilities => 3,
        SessionState::Syncing => 4,
        SessionState::Ready => 5,
        SessionState::Reconnecting => 6,
        SessionState::Suspended => 7,
        SessionState::Unsupported => 8,
        SessionState::Error => 9,
    }
}

/// Create a session with the default policy.
#[no_mangle]
pub extern "C" fn mdr_session_new() -> *mut c_void {
    let session = Session::new(Policy::default());
    let boxed = Box::new(MdrSession { inner: session });
    Box::into_raw(boxed) as *mut c_void
}

/// Destroy a session. Passing null is a no-op.
///
/// # Safety
/// `handle` must come from [`mdr_session_new`] and must not be used afterwards.
#[no_mangle]
pub unsafe extern "C" fn mdr_session_free(handle: *mut c_void) {
    if handle.is_null() {
        return;
    }
    drop(Box::from_raw(handle as *mut MdrSession));
}

fn with<T>(handle: *mut c_void, f: impl FnOnce(&mut Session) -> T) -> Option<T> {
    if handle.is_null() {
        return None;
    }
    // SAFETY: caller contract documented on each exported function.
    let s = unsafe { &mut *(handle as *mut MdrSession) };
    Some(f(&mut s.inner))
}

/// Collect the bytes the session wants written.
///
/// A single inbound frame can produce more than one outbound frame — an
/// acknowledgement plus the next command, for example — so the events are
/// concatenated into one buffer. The control channel is a byte stream, so the
/// caller can write the buffer as-is.
fn collect_sends(events: Vec<SessionEvent>) -> Option<Vec<u8>> {
    let mut out: Vec<u8> = Vec::new();
    for event in events {
        if let SessionEvent::Send(bytes) = event {
            out.extend_from_slice(&bytes);
        }
    }
    if out.is_empty() {
        None
    } else {
        Some(out)
    }
}

/// Begin the handshake. Returns the bytes to write; caller frees with
/// [`mdr_bytes_free`].
/// # Safety
/// `handle` must be a live session from [`mdr_session_new`]; `out` must be writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_connect(handle: *mut c_void, now_ms: u64, out: *mut MdrBuffer) -> MdrStatus {
    if out.is_null() {
        return MdrStatus::NullHandle;
    }
    let Some(bytes) = with(handle, |s| collect_sends(s.connect(now_ms))) else {
        return MdrStatus::NullHandle;
    };
    match bytes {
        Some(b) => {
            unsafe { *out = MdrBuffer::from_vec(b) };
            MdrStatus::Ok
        }
        None => MdrStatus::NoData,
    }
}

/// Feed received bytes. Writes produced by the session are returned via `out`.
/// # Safety
/// `handle` must be live; `data` must point to `len` readable bytes; `out` must be writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_receive(
    handle: *mut c_void,
    data: *const u8,
    len: usize,
    now_ms: u64,
    out: *mut MdrBuffer,
) -> MdrStatus {
    if handle.is_null() || data.is_null() || out.is_null() {
        return MdrStatus::NullHandle;
    }
    let slice = unsafe { std::slice::from_raw_parts(data, len) };
    let produced = with(handle, |s| collect_sends(s.receive(slice, now_ms)));
    match produced {
        Some(Some(b)) => {
            unsafe { *out = MdrBuffer::from_vec(b) };
            MdrStatus::Ok
        }
        Some(None) => MdrStatus::NoData,
        None => MdrStatus::NullHandle,
    }
}

/// Request a battery refresh. Refused unless ready.
///
/// Returns `NoData` when the write was queued behind an outstanding command;
/// it will be sent as soon as that command is acknowledged.
/// # Safety
/// `handle` must be live and `out` must be writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_request_battery(
    handle: *mut c_void,
    now_ms: u64,
    out: *mut MdrBuffer,
) -> MdrStatus {
    if out.is_null() {
        return MdrStatus::NullHandle;
    }
    let result = with(handle, |s| match s.request_battery(now_ms) {
        None => MdrStatus::NotReady,
        Some(events) => match collect_sends(events) {
            Some(bytes) => {
                unsafe { *out = MdrBuffer::from_vec(bytes) };
                MdrStatus::Ok
            }
            None => MdrStatus::NoData,
        },
    });
    result.unwrap_or(MdrStatus::NullHandle)
}

/// Write noise-control state.
///
/// Returns `NoData` when the write was queued behind an outstanding command.
/// # Safety
/// `handle` must be live and `out` must be writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_set_noise_control(
    handle: *mut c_void,
    enabled: bool,
    mode: u8,
    ambient_mode: u8,
    ambient_level: u8,
    now_ms: u64,
    out: *mut MdrBuffer,
) -> MdrStatus {
    if out.is_null() {
        return MdrStatus::NullHandle;
    }
    let result = with(handle, |s| {
        match s.set_noise_control(enabled, mode, ambient_mode, ambient_level, now_ms) {
            None => MdrStatus::NotReady,
            Some(events) => match collect_sends(events) {
                Some(bytes) => {
                    unsafe { *out = MdrBuffer::from_vec(bytes) };
                    MdrStatus::Ok
                }
                None => MdrStatus::NoData,
            },
        }
    });
    result.unwrap_or(MdrStatus::NullHandle)
}

/// Number of equaliser presets the device reported.
///
/// # Safety
/// `handle` must be live and `out_count` writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_eq_preset_count(handle: *mut c_void, out_count: *mut usize) -> MdrStatus {
    if out_count.is_null() {
        return MdrStatus::NullHandle;
    }
    let Some(n) = with(handle, |s| {
        s.device.equalizer.as_ref().map(|v| v.value.presets.len()).unwrap_or(0)
    }) else {
        return MdrStatus::NullHandle;
    };
    unsafe { *out_count = n };
    MdrStatus::Ok
}

/// Read one reported preset by index: its wire id and its product name.
///
/// Returns `NoData` when the index is past the end. The name is truncated to
/// `name_cap - 1` bytes and NUL-terminated.
///
/// # Safety
/// `handle` must be live; `out_id` and `name` must be writable for their stated sizes.
#[no_mangle]
pub unsafe extern "C" fn mdr_eq_preset_at(
    handle: *mut c_void,
    index: usize,
    out_id: *mut u8,
    name: *mut c_char,
    name_cap: usize,
) -> MdrStatus {
    if out_id.is_null() || name.is_null() || name_cap == 0 {
        return MdrStatus::NullHandle;
    }
    let Some(entry) = with(handle, |s| {
        s.device
            .equalizer
            .as_ref()
            .and_then(|v| v.value.presets.get(index).cloned())
    }) else {
        return MdrStatus::NullHandle;
    };
    let Some((id, text)) = entry else {
        return MdrStatus::NoData;
    };
    unsafe {
        *out_id = id;
        let dst = std::slice::from_raw_parts_mut(name as *mut u8, name_cap);
        for slot in dst.iter_mut() {
            *slot = 0;
        }
        let bytes = text.as_bytes();
        let n = bytes.len().min(name_cap - 1);
        dst[..n].copy_from_slice(&bytes[..n]);
    }
    MdrStatus::Ok
}

/// Choose an equaliser preset, with optional per-band gains.
///
/// Refused with `NotReady` when the session is not ready, or when the preset
/// was not one the device advertised.
///
/// # Safety
/// `handle` must be live; `bands` must point to `band_count` readable bytes.
#[no_mangle]
pub unsafe extern "C" fn mdr_eq_set_preset(
    handle: *mut c_void,
    preset: u8,
    bands: *const u8,
    band_count: usize,
    now_ms: u64,
    out: *mut MdrBuffer,
) -> MdrStatus {
    if out.is_null() {
        return MdrStatus::NullHandle;
    }
    let slice: &[u8] = if band_count == 0 {
        &[]
    } else if bands.is_null() {
        return MdrStatus::NullHandle;
    } else {
        unsafe { std::slice::from_raw_parts(bands, band_count) }
    };
    let result = with(handle, |s| match s.set_eq_preset(preset, slice, now_ms) {
        None => MdrStatus::NotReady,
        Some(events) => match collect_sends(events) {
            Some(bytes) => {
                unsafe { *out = MdrBuffer::from_vec(bytes) };
                MdrStatus::Ok
            }
            None => MdrStatus::NoData,
        },
    });
    result.unwrap_or(MdrStatus::NullHandle)
}

/// Set the Clear Bass level, clamped to the range the device reported.
///
/// # Safety
/// `handle` must be live and `out` writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_eq_set_clear_bass(
    handle: *mut c_void,
    level: i8,
    now_ms: u64,
    out: *mut MdrBuffer,
) -> MdrStatus {
    if out.is_null() {
        return MdrStatus::NullHandle;
    }
    let result = with(handle, |s| match s.set_clear_bass(level, now_ms) {
        None => MdrStatus::NotReady,
        Some(events) => match collect_sends(events) {
            Some(bytes) => {
                unsafe { *out = MdrBuffer::from_vec(bytes) };
                MdrStatus::Ok
            }
            None => MdrStatus::NoData,
        },
    });
    result.unwrap_or(MdrStatus::NullHandle)
}

/// Queue an arbitrary payload on a ready session.
///
/// This exists for the diagnostic harness: it lets the supported capability
/// families be probed on real hardware instead of guessed at.
///
/// # Safety
/// `handle` must be live; `data` must point to `len` readable bytes.
#[no_mangle]
pub unsafe extern "C" fn mdr_send_raw(
    handle: *mut c_void,
    data: *const u8,
    len: usize,
    now_ms: u64,
    out: *mut MdrBuffer,
) -> MdrStatus {
    if out.is_null() || data.is_null() || len == 0 {
        return MdrStatus::NullHandle;
    }
    let slice = unsafe { std::slice::from_raw_parts(data, len) };
    let result = with(handle, |s| match s.send_raw(slice.to_vec(), now_ms) {
        None => MdrStatus::NotReady,
        Some(events) => {
            // An empty buffer means the payload was queued behind an in-flight
            // command; it will be flushed by the next receive/ack callback.
            let bytes = collect_sends(events).unwrap_or_default();
            unsafe { *out = MdrBuffer::from_vec(bytes) };
            MdrStatus::Ok
        }
    });
    result.unwrap_or(MdrStatus::NullHandle)
}

/// Turn noise adaptation (auto ambient) on or off.
///
/// # Safety
/// `handle` must be live and `out` writable.
/// Queue an arbitrary payload for a specific table (1 or 2).
///
/// Table 2 carries families such as voice guidance. Diagnostic use.
///
/// # Safety
/// `data` must point to `len` readable bytes; `out` must be writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_send_raw_table(
    handle: *mut c_void,
    table: u8,
    data: *const u8,
    len: usize,
    now_ms: u64,
    out: *mut MdrBuffer,
) -> MdrStatus {
    if out.is_null() || data.is_null() || len == 0 {
        return MdrStatus::NullHandle;
    }
    let slice = unsafe { std::slice::from_raw_parts(data, len) };
    let which = if table == 2 { mdr_core::MdrTable::Table2 } else { mdr_core::MdrTable::Table1 };
    let result = with(handle, |s| match s.send_raw_table(slice.to_vec(), which, now_ms) {
        None => MdrStatus::NotReady,
        Some(events) => {
            let bytes = collect_sends(events).unwrap_or_default();
            unsafe { *out = MdrBuffer::from_vec(bytes) };
            MdrStatus::Ok
        }
    });
    result.unwrap_or(MdrStatus::NullHandle)
}

/// Turn noise adaptation (auto ambient) on or off.
///
/// # Safety
/// `handle` must be live and `out` writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_set_nc_adaptation(
    handle: *mut c_void,
    enabled: bool,
    now_ms: u64,
    out: *mut MdrBuffer,
) -> MdrStatus {
    if out.is_null() {
        return MdrStatus::NullHandle;
    }
    let result = with(handle, |s| match s.set_noise_adaptation(enabled, now_ms) {
        None => MdrStatus::NotReady,
        Some(events) => match collect_sends(events) {
            Some(bytes) => {
                unsafe { *out = MdrBuffer::from_vec(bytes) };
                MdrStatus::Ok
            }
            None => MdrStatus::NoData,
        },
    });
    result.unwrap_or(MdrStatus::NullHandle)
}

/// Number of queued or in-flight commands.
///
/// # Safety
/// `handle` must be live.
#[no_mangle]
pub unsafe extern "C" fn mdr_pending_count(handle: *mut c_void) -> usize {
    with(handle, |s| s.pending()).unwrap_or(0)
}

/// Number of supported functions the device advertised.
///
/// # Safety
/// `out_count` must be writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_supported_count(handle: *mut c_void, out_count: *mut usize) -> MdrStatus {
    if out_count.is_null() {
        return MdrStatus::NullHandle;
    }
    let Some(n) = with(handle, |s| s.device.supported_functions.len()) else {
        return MdrStatus::NullHandle;
    };
    unsafe { *out_count = n };
    MdrStatus::Ok
}

/// Read one supported function by index: its byte and human name.
///
/// # Safety
/// `name` must be writable for `cap` bytes.
#[no_mangle]
pub unsafe extern "C" fn mdr_supported_at(
    handle: *mut c_void,
    index: usize,
    out_value: *mut u8,
    name: *mut c_char,
    name_cap: usize,
) -> MdrStatus {
    if out_value.is_null() || name.is_null() {
        return MdrStatus::NullHandle;
    }
    let Some(entry) = with(handle, |s| s.device.supported_functions.get(index).copied()) else {
        return MdrStatus::NullHandle;
    };
    let Some(value) = entry else { return MdrStatus::NoData };
    let label = mdr_core::function_types::name(value).unwrap_or("UNKNOWN");
    unsafe {
        *out_value = value;
        write_c_str(name, name_cap, label);
    }
    MdrStatus::Ok
}

/// First `PresetEqErrorCodeType` the device gave for an equaliser that is
/// off (2 = listening mode), or `-1` when it is on or gave no reason.
///
/// # Safety
/// `handle` must come from `mdr_session_new`; `out_code` must be writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_eq_error_code(handle: *mut c_void, out_code: *mut i32) -> MdrStatus {
    if out_code.is_null() {
        return MdrStatus::NullHandle;
    }
    let Some(code) = with(handle, |s| {
        s.device.equalizer.as_ref().and_then(|e| e.value.error_codes.first().copied())
    }) else {
        return MdrStatus::NullHandle;
    };
    unsafe { *out_code = code.map_or(-1, i32::from) };
    MdrStatus::Ok
}

/// `ModelSeries` and `ModelColor` bytes from `SERIES_AND_COLOR_INFO`,
/// each `-1` until the device has answered.
///
/// # Safety
/// `handle` must come from `mdr_session_new`; both out pointers writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_model_color(
    handle: *mut c_void,
    out_series: *mut i32,
    out_color: *mut i32,
) -> MdrStatus {
    if out_series.is_null() || out_color.is_null() {
        return MdrStatus::NullHandle;
    }
    let Some((series, color)) = with(handle, |s| {
        (s.device.identity.model_series, s.device.identity.model_color)
    }) else {
        return MdrStatus::NullHandle;
    };
    unsafe {
        *out_series = series.map_or(-1, i32::from);
        *out_color = color.map_or(-1, i32::from);
    }
    MdrStatus::Ok
}

/// Number of table-2 functions the device advertised (`06 00` on table 2).
///
/// # Safety
/// `out_count` must be writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_supported_count_table2(
    handle: *mut c_void,
    out_count: *mut usize,
) -> MdrStatus {
    if out_count.is_null() {
        return MdrStatus::NullHandle;
    }
    let Some(n) = with(handle, |s| s.device.supported_functions_table2.len()) else {
        return MdrStatus::NullHandle;
    };
    unsafe { *out_count = n };
    MdrStatus::Ok
}

/// Read one table-2 function by index, named with the table-2 enum.
///
/// # Safety
/// `name` must be writable for `cap` bytes.
#[no_mangle]
pub unsafe extern "C" fn mdr_supported_at_table2(
    handle: *mut c_void,
    index: usize,
    out_value: *mut u8,
    name: *mut c_char,
    name_cap: usize,
) -> MdrStatus {
    if out_value.is_null() || name.is_null() {
        return MdrStatus::NullHandle;
    }
    let Some(entry) = with(handle, |s| s.device.supported_functions_table2.get(index).copied()) else {
        return MdrStatus::NullHandle;
    };
    let Some(value) = entry else { return MdrStatus::NoData };
    let label = mdr_core::function_types_table2::name(value).unwrap_or("UNKNOWN");
    unsafe {
        *out_value = value;
        write_c_str(name, name_cap, label);
    }
    MdrStatus::Ok
}

/// Number of paired devices the headset reported, or `NoData` before a read.
///
/// # Safety
/// `out_count` must be writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_paired_count(
    handle: *mut c_void,
    out_count: *mut usize,
) -> MdrStatus {
    if out_count.is_null() {
        return MdrStatus::NullHandle;
    }
    let Some(count) = with(handle, |s| {
        s.device.paired_devices.as_ref().map(|v| v.value.devices.len())
    }) else {
        return MdrStatus::NullHandle;
    };
    let Some(count) = count else { return MdrStatus::NoData };
    unsafe { *out_count = count };
    MdrStatus::Ok
}

/// Read one paired device by index.
///
/// # Safety
/// `address` and `name` must be writable for their stated capacities; the
/// scalar out-pointers must be writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_paired_at(
    handle: *mut c_void,
    index: usize,
    out_connected: *mut u8,
    out_cod_known: *mut u8,
    out_cod: *mut u32,
    address: *mut c_char,
    address_cap: usize,
    name: *mut c_char,
    name_cap: usize,
) -> MdrStatus {
    if out_connected.is_null()
        || out_cod_known.is_null()
        || out_cod.is_null()
        || address.is_null()
        || name.is_null()
    {
        return MdrStatus::NullHandle;
    }
    let Some(entry) = with(handle, |s| {
        s.device
            .paired_devices
            .as_ref()
            .and_then(|v| v.value.devices.get(index).cloned())
    }) else {
        return MdrStatus::NullHandle;
    };
    let Some(device) = entry else { return MdrStatus::NoData };
    unsafe {
        *out_connected = device.connected as u8;
        *out_cod_known = device.class_of_device.is_some() as u8;
        *out_cod = device.class_of_device.unwrap_or(0);
        write_c_str(address, address_cap, &device.address);
        write_c_str(name, name_cap, &device.name);
    }
    MdrStatus::Ok
}

/// Advertised pairing limits.
///
/// # Safety
/// The out-pointers must be writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_pairing_capability(
    handle: *mut c_void,
    out_max_paired: *mut u8,
    out_max_connected: *mut u8,
    out_file_transfer: *mut u8,
) -> MdrStatus {
    if out_max_paired.is_null() || out_max_connected.is_null() || out_file_transfer.is_null() {
        return MdrStatus::NullHandle;
    }
    let Some(capability) =
        with(handle, |s| s.device.pairing_capability.as_ref().map(|v| v.value))
    else {
        return MdrStatus::NullHandle;
    };
    let Some(capability) = capability else { return MdrStatus::NoData };
    unsafe {
        *out_max_paired = capability.max_paired;
        *out_max_connected = capability.max_connected;
        *out_file_transfer = capability.file_transfer;
    }
    MdrStatus::Ok
}

/// Connect to a paired device by index in the last reported list.
///
/// # Safety
/// `handle` must be live and `out` must be writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_pairing_connect(
    handle: *mut c_void,
    index: usize,
    now_ms: u64,
    out: *mut MdrBuffer,
) -> MdrStatus {
    if out.is_null() {
        return MdrStatus::NullHandle;
    }
    with(handle, |s| match s.pairing_connect(index, now_ms) {
        None => MdrStatus::NoData,
        Some(events) => match collect_sends(events) {
            Some(bytes) => {
                unsafe { *out = MdrBuffer::from_vec(bytes) };
                MdrStatus::Ok
            }
            None => MdrStatus::NoData,
        },
    })
    .unwrap_or(MdrStatus::NullHandle)
}

/// Disconnect a paired device by index in the last reported list.
///
/// # Safety
/// `handle` must be live and `out` must be writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_pairing_disconnect(
    handle: *mut c_void,
    index: usize,
    now_ms: u64,
    out: *mut MdrBuffer,
) -> MdrStatus {
    if out.is_null() {
        return MdrStatus::NullHandle;
    }
    with(handle, |s| match s.pairing_disconnect(index, now_ms) {
        None => MdrStatus::NoData,
        Some(events) => match collect_sends(events) {
            Some(bytes) => {
                unsafe { *out = MdrBuffer::from_vec(bytes) };
                MdrStatus::Ok
            }
            None => MdrStatus::NoData,
        },
    })
    .unwrap_or(MdrStatus::NullHandle)
}

/// Enter or leave pairing (inquiry-scan) mode.
///
/// # Safety
/// `handle` must be live and `out` must be writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_pairing_set_mode(
    handle: *mut c_void,
    pairing: bool,
    now_ms: u64,
    out: *mut MdrBuffer,
) -> MdrStatus {
    if out.is_null() {
        return MdrStatus::NullHandle;
    }
    with(handle, |s| match s.pairing_set_mode(pairing, now_ms) {
        None => MdrStatus::NotReady,
        Some(events) => match collect_sends(events) {
            Some(bytes) => {
                unsafe { *out = MdrBuffer::from_vec(bytes) };
                MdrStatus::Ok
            }
            None => MdrStatus::NoData,
        },
    })
    .unwrap_or(MdrStatus::NullHandle)
}

/// Last connect/disconnect result pushed by the headset.
///
/// # Safety
/// Out-pointers must be writable for their stated sizes.
#[no_mangle]
pub unsafe extern "C" fn mdr_pairing_event(
    handle: *mut c_void,
    out_action: *mut u8,
    out_result: *mut u8,
    address: *mut c_char,
    address_cap: usize,
) -> MdrStatus {
    if out_action.is_null() || out_result.is_null() || address.is_null() {
        return MdrStatus::NullHandle;
    }
    let Some(event) = with(handle, |s| {
        s.device.last_pairing_event.as_ref().map(|v| v.value.clone())
    }) else {
        return MdrStatus::NullHandle;
    };
    let Some(event) = event else { return MdrStatus::NoData };
    unsafe {
        *out_action = event.action;
        *out_result = event.result;
        write_c_str(address, address_cap, &event.address);
    }
    MdrStatus::Ok
}

/// Current Bluetooth mode (`PERI_RET_STATUS` type 0x00).
///
/// # Safety
/// Out-pointers must be writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_pairing_mode(
    handle: *mut c_void,
    out_mode: *mut u8,
    out_enabled: *mut u8,
) -> MdrStatus {
    if out_mode.is_null() || out_enabled.is_null() {
        return MdrStatus::NullHandle;
    }
    let Some(status) = with(handle, |s| s.device.pairing_mode.as_ref().map(|v| v.value)) else {
        return MdrStatus::NullHandle;
    };
    let Some(status) = status else { return MdrStatus::NoData };
    unsafe {
        *out_mode = status.mode;
        *out_enabled = status.enabled as u8;
    }
    MdrStatus::Ok
}

/// Voice-assistant state: current assignment and how many are supported.
///
/// # Safety
/// Out-pointers must be writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_va_state(
    handle: *mut c_void,
    out_current: *mut u8,
    out_count: *mut usize,
) -> MdrStatus {
    if out_current.is_null() || out_count.is_null() {
        return MdrStatus::NullHandle;
    }
    let Some(state) = with(handle, |s| {
        s.device.voice_assistant.as_ref().map(|v| (v.value.current, v.value.supported.len()))
    }) else {
        return MdrStatus::NullHandle;
    };
    let Some((current, count)) = state else { return MdrStatus::NoData };
    unsafe {
        *out_current = current;
        *out_count = count;
    }
    MdrStatus::Ok
}

/// Read one supported voice assistant by index.
///
/// # Safety
/// `name` must be writable for `cap` bytes.
#[no_mangle]
pub unsafe extern "C" fn mdr_va_at(
    handle: *mut c_void,
    index: usize,
    out_value: *mut u8,
    name: *mut c_char,
    name_cap: usize,
) -> MdrStatus {
    if out_value.is_null() || name.is_null() {
        return MdrStatus::NullHandle;
    }
    let Some(entry) = with(handle, |s| {
        s.device
            .voice_assistant
            .as_ref()
            .and_then(|v| v.value.supported.get(index).copied())
    }) else {
        return MdrStatus::NullHandle;
    };
    let Some(value) = entry else { return MdrStatus::NoData };
    unsafe {
        *out_value = value;
        write_c_str(name, name_cap, mdr_core::protocol::voice_assistant::name(value));
    }
    MdrStatus::Ok
}

/// Choose the voice assistant.
///
/// # Safety
/// `handle` must be live and `out` writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_set_voice_assistant(
    handle: *mut c_void,
    value: u8,
    now_ms: u64,
    out: *mut MdrBuffer,
) -> MdrStatus {
    if out.is_null() {
        return MdrStatus::NullHandle;
    }
    let result = with(handle, |s| match s.set_voice_assistant(value, now_ms) {
        None => MdrStatus::NotReady,
        Some(events) => match collect_sends(events) {
            Some(bytes) => {
                unsafe { *out = MdrBuffer::from_vec(bytes) };
                MdrStatus::Ok
            }
            None => MdrStatus::NoData,
        },
    });
    result.unwrap_or(MdrStatus::NullHandle)
}

/// Number of general-setting slots the device described.
///
/// # Safety
/// `handle` must be live and `out_count` writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_gs_count(handle: *mut c_void, out_count: *mut usize) -> MdrStatus {
    if out_count.is_null() {
        return MdrStatus::NullHandle;
    }
    let Some(n) = with(handle, |s| s.device.general_settings.len()) else {
        return MdrStatus::NullHandle;
    };
    unsafe { *out_count = n };
    MdrStatus::Ok
}

/// Read one general-setting slot by index.
///
/// Writes its wire type, whether a value is known, the value, and its title and
/// detail strings. Returns `NoData` when the index is past the end.
///
/// # Safety
/// All out-pointers must be writable for their stated sizes.
#[no_mangle]
pub unsafe extern "C" fn mdr_gs_at(
    handle: *mut c_void,
    index: usize,
    out_type: *mut u8,
    out_known: *mut u8,
    out_value: *mut u8,
    title: *mut c_char,
    title_cap: usize,
    detail: *mut c_char,
    detail_cap: usize,
) -> MdrStatus {
    if out_type.is_null() || out_known.is_null() || out_value.is_null() || title.is_null() || detail.is_null() {
        return MdrStatus::NullHandle;
    }
    let Some(entry) = with(handle, |s| s.device.general_settings.get(index).cloned()) else {
        return MdrStatus::NullHandle;
    };
    let Some(gs) = entry else { return MdrStatus::NoData };

    unsafe {
        *out_type = gs.gs_type;
        *out_known = gs.value.is_some() as u8;
        *out_value = gs.value.unwrap_or(false) as u8;
        write_c_str(title, title_cap, &gs.title());
        write_c_str(detail, detail_cap, gs.detail());
    }
    MdrStatus::Ok
}

/// Copy `text` into a fixed buffer, NUL-terminated and truncated.
///
/// # Safety
/// `dst` must be writable for `cap` bytes.
unsafe fn write_c_str(dst: *mut c_char, cap: usize, text: &str) {
    if cap == 0 {
        return;
    }
    let buf = std::slice::from_raw_parts_mut(dst as *mut u8, cap);
    for slot in buf.iter_mut() {
        *slot = 0;
    }
    let bytes = text.as_bytes();
    let n = bytes.len().min(cap - 1);
    buf[..n].copy_from_slice(&bytes[..n]);
}

/// Set one general-setting slot (sidetone, multipoint, touch panel…).
///
/// Refused with `NotReady` when the device has not described that slot.
///
/// # Safety
/// `handle` must be live and `out` writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_set_gs_setting(
    handle: *mut c_void,
    gs_type: u8,
    enabled: bool,
    now_ms: u64,
    out: *mut MdrBuffer,
) -> MdrStatus {
    if out.is_null() {
        return MdrStatus::NullHandle;
    }
    let result = with(handle, |s| match s.set_gs_boolean(gs_type, enabled, now_ms) {
        None => MdrStatus::NotReady,
        Some(events) => match collect_sends(events) {
            Some(bytes) => {
                unsafe { *out = MdrBuffer::from_vec(bytes) };
                MdrStatus::Ok
            }
            None => MdrStatus::NoData,
        },
    });
    result.unwrap_or(MdrStatus::NullHandle)
}

/// Toggle audio upscaling.
///
/// Refused with `NotReady` unless the device has reported the feature.
///
/// # Safety
/// `handle` must be live and `out` writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_set_upscaling(
    handle: *mut c_void,
    enabled: bool,
    now_ms: u64,
    out: *mut MdrBuffer,
) -> MdrStatus {
    if out.is_null() {
        return MdrStatus::NullHandle;
    }
    let result = with(handle, |s| match s.set_upscaling(enabled, now_ms) {
        None => MdrStatus::NotReady,
        Some(events) => match collect_sends(events) {
            Some(bytes) => {
                unsafe { *out = MdrBuffer::from_vec(bytes) };
                MdrStatus::Ok
            }
            None => MdrStatus::NoData,
        },
    });
    result.unwrap_or(MdrStatus::NullHandle)
}

/// Send a playback control action (play, pause, next, previous, stop).
///
/// # Safety
/// `handle` must be live and `out` must be writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_playback_control(
    handle: *mut c_void,
    control: u8,
    now_ms: u64,
    out: *mut MdrBuffer,
) -> MdrStatus {
    if out.is_null() {
        return MdrStatus::NullHandle;
    }
    let result = with(handle, |s| match s.set_playback_control(control, now_ms) {
        None => MdrStatus::NotReady,
        Some(events) => match collect_sends(events) {
            Some(bytes) => {
                unsafe { *out = MdrBuffer::from_vec(bytes) };
                MdrStatus::Ok
            }
            None => MdrStatus::NoData,
        },
    });
    result.unwrap_or(MdrStatus::NullHandle)
}

/// Switch the listening mode (0 standard, 1 BGM, 2 cinema).
///
/// # Safety
/// `handle` must be live and `out` must be writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_set_listening_mode(
    handle: *mut c_void,
    mode: u8,
    now_ms: u64,
    out: *mut MdrBuffer,
) -> MdrStatus {
    if out.is_null() {
        return MdrStatus::NullHandle;
    }
    let Some(mode) = mdr_core::protocol::ListeningMode::from_code(mode) else {
        return MdrStatus::NoData;
    };
    let result = with(handle, |s| match s.set_listening_mode(mode, now_ms) {
        None => MdrStatus::NotReady,
        Some(events) => match collect_sends(events) {
            Some(bytes) => {
                unsafe { *out = MdrBuffer::from_vec(bytes) };
                MdrStatus::Ok
            }
            None => MdrStatus::NoData,
        },
    });
    result.unwrap_or(MdrStatus::NullHandle)
}

/// Set the music volume, clamped by the engine to the advertised steps.
///
/// # Safety
/// `handle` must be live and `out` must be writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_set_music_volume(
    handle: *mut c_void,
    volume: u8,
    now_ms: u64,
    out: *mut MdrBuffer,
) -> MdrStatus {
    if out.is_null() {
        return MdrStatus::NullHandle;
    }
    let result = with(handle, |s| match s.set_music_volume(volume, now_ms) {
        None => MdrStatus::NotReady,
        Some(events) => match collect_sends(events) {
            Some(bytes) => {
                unsafe { *out = MdrBuffer::from_vec(bytes) };
                MdrStatus::Ok
            }
            None => MdrStatus::NoData,
        },
    });
    result.unwrap_or(MdrStatus::NullHandle)
}

/// Set the call volume, clamped by the engine to the advertised steps.
///
/// # Safety
/// `handle` must be live and `out` must be writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_set_call_volume(
    handle: *mut c_void,
    volume: u8,
    now_ms: u64,
    out: *mut MdrBuffer,
) -> MdrStatus {
    if out.is_null() {
        return MdrStatus::NullHandle;
    }
    let result = with(handle, |s| match s.set_call_volume(volume, now_ms) {
        None => MdrStatus::NotReady,
        Some(events) => match collect_sends(events) {
            Some(bytes) => {
                unsafe { *out = MdrBuffer::from_vec(bytes) };
                MdrStatus::Ok
            }
            None => MdrStatus::NoData,
        },
    });
    result.unwrap_or(MdrStatus::NullHandle)
}

/// Set the safe-volume WHO standard level (0 normal, 1 sensitive).
///
/// # Safety
/// `handle` must be live and `out` must be writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_set_safe_volume(
    handle: *mut c_void,
    level: u8,
    now_ms: u64,
    out: *mut MdrBuffer,
) -> MdrStatus {
    if out.is_null() {
        return MdrStatus::NullHandle;
    }
    let result = with(handle, |s| match s.set_safe_volume_level(level, now_ms) {
        None => MdrStatus::NotReady,
        Some(events) => match collect_sends(events) {
            Some(bytes) => {
                unsafe { *out = MdrBuffer::from_vec(bytes) };
                MdrStatus::Ok
            }
            None => MdrStatus::NoData,
        },
    });
    result.unwrap_or(MdrStatus::NullHandle)
}

/// Set one general-setting boolean slot.
///
/// # Safety
/// `handle` must be live and `out` must be writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_set_gs_boolean(
    handle: *mut c_void,
    gs_type: u8,
    on: bool,
    now_ms: u64,
    out: *mut MdrBuffer,
) -> MdrStatus {
    if out.is_null() {
        return MdrStatus::NullHandle;
    }
    let result = with(handle, |s| match s.set_gs_boolean(gs_type, on, now_ms) {
        None => MdrStatus::NotReady,
        Some(events) => match collect_sends(events) {
            Some(bytes) => {
                unsafe { *out = MdrBuffer::from_vec(bytes) };
                MdrStatus::Ok
            }
            None => MdrStatus::NoData,
        },
    });
    result.unwrap_or(MdrStatus::NullHandle)
}

/// Start or stop adaptive control.
///
/// # Safety
/// `handle` must be live and `out` must be writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_set_adaptive_control(
    handle: *mut c_void,
    start: bool,
    now_ms: u64,
    out: *mut MdrBuffer,
) -> MdrStatus {
    if out.is_null() {
        return MdrStatus::NullHandle;
    }
    let result = with(handle, |s| match s.set_adaptive_control(start, now_ms) {
        None => MdrStatus::NotReady,
        Some(events) => match collect_sends(events) {
            Some(bytes) => {
                unsafe { *out = MdrBuffer::from_vec(bytes) };
                MdrStatus::Ok
            }
            None => MdrStatus::NoData,
        },
    });
    result.unwrap_or(MdrStatus::NullHandle)
}

/// Replace the Quick Access function list.
///
/// # Safety
/// `handle` must be live, `data` must point to `len` bytes and `out` must be writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_set_quick_access_functions(
    handle: *mut c_void,
    data: *const u8,
    len: usize,
    now_ms: u64,
    out: *mut MdrBuffer,
) -> MdrStatus {
    if out.is_null() || data.is_null() || len == 0 {
        return MdrStatus::NullHandle;
    }
    let slice = unsafe { std::slice::from_raw_parts(data, len) };
    let result = with(handle, |s| match s.set_quick_access_functions(slice, now_ms) {
        None => MdrStatus::NotReady,
        Some(events) => match collect_sends(events) {
            Some(bytes) => {
                unsafe { *out = MdrBuffer::from_vec(bytes) };
                MdrStatus::Ok
            }
            None => MdrStatus::NoData,
        },
    });
    result.unwrap_or(MdrStatus::NullHandle)
}

/// Toggle playback control by wearing/removing the headphones.
///
/// # Safety
/// `handle` must be live and `out` must be writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_set_control_by_wearing(
    handle: *mut c_void,
    enabled: bool,
    now_ms: u64,
    out: *mut MdrBuffer,
) -> MdrStatus {
    if out.is_null() {
        return MdrStatus::NullHandle;
    }
    let result = with(handle, |s| match s.set_control_by_wearing(enabled, now_ms) {
        None => MdrStatus::NotReady,
        Some(events) => match collect_sends(events) {
            Some(bytes) => {
                unsafe { *out = MdrBuffer::from_vec(bytes) };
                MdrStatus::Ok
            }
            None => MdrStatus::NoData,
        },
    });
    result.unwrap_or(MdrStatus::NullHandle)
}

/// Toggle mic on/off by headphone operation.
///
/// # Safety
/// `handle` must be live and `out` must be writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_set_mic_on_off(
    handle: *mut c_void,
    enabled: bool,
    now_ms: u64,
    out: *mut MdrBuffer,
) -> MdrStatus {
    if out.is_null() {
        return MdrStatus::NullHandle;
    }
    let result = with(handle, |s| match s.set_mic_on_off(enabled, now_ms) {
        None => MdrStatus::NotReady,
        Some(events) => match collect_sends(events) {
            Some(bytes) => {
                unsafe { *out = MdrBuffer::from_vec(bytes) };
                MdrStatus::Ok
            }
            None => MdrStatus::NoData,
        },
    });
    result.unwrap_or(MdrStatus::NullHandle)
}

/// Toggle Sony Voice Assistant.
///
/// # Safety
/// `handle` must be live and `out` must be writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_set_sony_voice_assistant(
    handle: *mut c_void,
    enabled: bool,
    now_ms: u64,
    out: *mut MdrBuffer,
) -> MdrStatus {
    if out.is_null() {
        return MdrStatus::NullHandle;
    }
    let result = with(handle, |s| match s.set_sony_voice_assistant(enabled, now_ms) {
        None => MdrStatus::NotReady,
        Some(events) => match collect_sends(events) {
            Some(bytes) => {
                unsafe { *out = MdrBuffer::from_vec(bytes) };
                MdrStatus::Ok
            }
            None => MdrStatus::NoData,
        },
    });
    result.unwrap_or(MdrStatus::NullHandle)
}

/// Toggle voice guidance.
///
/// # Safety
/// `handle` must be live and `out` must be writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_set_voice_guidance(
    handle: *mut c_void,
    enabled: bool,
    now_ms: u64,
    out: *mut MdrBuffer,
) -> MdrStatus {
    if out.is_null() {
        return MdrStatus::NullHandle;
    }
    let result = with(handle, |s| match s.set_voice_guidance(enabled, now_ms) {
        None => MdrStatus::NotReady,
        Some(events) => match collect_sends(events) {
            Some(bytes) => {
                unsafe { *out = MdrBuffer::from_vec(bytes) };
                MdrStatus::Ok
            }
            None => MdrStatus::NoData,
        },
    });
    result.unwrap_or(MdrStatus::NullHandle)
}

/// Set the voice guidance volume.
///
/// # Safety
/// `handle` must be live and `out` must be writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_set_voice_guidance_volume(
    handle: *mut c_void,
    volume: i8,
    now_ms: u64,
    out: *mut MdrBuffer,
) -> MdrStatus {
    if out.is_null() {
        return MdrStatus::NullHandle;
    }
    let result = with(handle, |s| match s.set_voice_guidance_volume(volume, now_ms) {
        None => MdrStatus::NotReady,
        Some(events) => match collect_sends(events) {
            Some(bytes) => {
                unsafe { *out = MdrBuffer::from_vec(bytes) };
                MdrStatus::Ok
            }
            None => MdrStatus::NoData,
        },
    });
    result.unwrap_or(MdrStatus::NullHandle)
}

/// Toggle head gesture control.
///
/// # Safety
/// `handle` must be live and `out` must be writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_set_head_gesture(
    handle: *mut c_void,
    enabled: bool,
    now_ms: u64,
    out: *mut MdrBuffer,
) -> MdrStatus {
    if out.is_null() {
        return MdrStatus::NullHandle;
    }
    let result = with(handle, |s| match s.set_head_gesture(enabled, now_ms) {
        None => MdrStatus::NotReady,
        Some(events) => match collect_sends(events) {
            Some(bytes) => {
                unsafe { *out = MdrBuffer::from_vec(bytes) };
                MdrStatus::Ok
            }
            None => MdrStatus::NoData,
        },
    });
    result.unwrap_or(MdrStatus::NullHandle)
}

/// Start or finish head gesture training.
///
/// # Safety
/// `handle` must be live and `out` must be writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_set_head_gesture_training(
    handle: *mut c_void,
    start: bool,
    now_ms: u64,
    out: *mut MdrBuffer,
) -> MdrStatus {
    if out.is_null() {
        return MdrStatus::NullHandle;
    }
    let result = with(handle, |s| match s.set_head_gesture_training(start, now_ms) {
        None => MdrStatus::NotReady,
        Some(events) => match collect_sends(events) {
            Some(bytes) => {
                unsafe { *out = MdrBuffer::from_vec(bytes) };
                MdrStatus::Ok
            }
            None => MdrStatus::NoData,
        },
    });
    result.unwrap_or(MdrStatus::NullHandle)
}

/// Ask the headphones to power off.
///
/// # Safety
/// `handle` must be live and `out` must be writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_power_off(
    handle: *mut c_void,
    now_ms: u64,
    out: *mut MdrBuffer,
) -> MdrStatus {
    if out.is_null() {
        return MdrStatus::NullHandle;
    }
    let result = with(handle, |s| match s.power_off(now_ms) {
        None => MdrStatus::NotReady,
        Some(events) => match collect_sends(events) {
            Some(bytes) => {
                unsafe { *out = MdrBuffer::from_vec(bytes) };
                MdrStatus::Ok
            }
            None => MdrStatus::NoData,
        },
    });
    result.unwrap_or(MdrStatus::NullHandle)
}

/// Toggle Speak-to-Chat.
///
/// # Safety
/// `handle` must be live and `out` must be writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_set_smart_talking(
    handle: *mut c_void,
    enabled: bool,
    now_ms: u64,
    out: *mut MdrBuffer,
) -> MdrStatus {
    if out.is_null() {
        return MdrStatus::NullHandle;
    }
    let result = with(handle, |s| match s.set_smart_talking(enabled, now_ms) {
        None => MdrStatus::NotReady,
        Some(events) => match collect_sends(events) {
            Some(bytes) => {
                unsafe { *out = MdrBuffer::from_vec(bytes) };
                MdrStatus::Ok
            }
            None => MdrStatus::NoData,
        },
    });
    result.unwrap_or(MdrStatus::NullHandle)
}

/// Set Speak-to-Chat sensitivity and auto-off time.
///
/// # Safety
/// `handle` must be live and `out` must be writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_set_smart_talking_detail(
    handle: *mut c_void,
    sensitivity: u8,
    mode_out: u8,
    now_ms: u64,
    out: *mut MdrBuffer,
) -> MdrStatus {
    if out.is_null() {
        return MdrStatus::NullHandle;
    }
    let result = with(handle, |s| {
        match s.set_smart_talking_detail(sensitivity, mode_out, now_ms) {
            None => MdrStatus::NotReady,
            Some(events) => match collect_sends(events) {
                Some(bytes) => {
                    unsafe { *out = MdrBuffer::from_vec(bytes) };
                    MdrStatus::Ok
                }
                None => MdrStatus::NoData,
            },
        }
    });
    result.unwrap_or(MdrStatus::NullHandle)
}

/// Toggle auto standby.
///
/// # Safety
/// `handle` must be live and `out` must be writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_set_auto_standby(
    handle: *mut c_void,
    enabled: bool,
    now_ms: u64,
    out: *mut MdrBuffer,
) -> MdrStatus {
    if out.is_null() {
        return MdrStatus::NullHandle;
    }
    let result = with(handle, |s| match s.set_auto_standby(enabled, now_ms) {
        None => MdrStatus::NotReady,
        Some(events) => match collect_sends(events) {
            Some(bytes) => {
                unsafe { *out = MdrBuffer::from_vec(bytes) };
                MdrStatus::Ok
            }
            None => MdrStatus::NoData,
        },
    });
    result.unwrap_or(MdrStatus::NullHandle)
}

/// Toggle music hand-over.
///
/// # Safety
/// `handle` must be live and `out` must be writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_set_music_hand_over(
    handle: *mut c_void,
    enabled: bool,
    now_ms: u64,
    out: *mut MdrBuffer,
) -> MdrStatus {
    if out.is_null() {
        return MdrStatus::NullHandle;
    }
    let result = with(handle, |s| match s.set_music_hand_over(enabled, now_ms) {
        None => MdrStatus::NotReady,
        Some(events) => match collect_sends(events) {
            Some(bytes) => {
                unsafe { *out = MdrBuffer::from_vec(bytes) };
                MdrStatus::Ok
            }
            None => MdrStatus::NoData,
        },
    });
    result.unwrap_or(MdrStatus::NullHandle)
}

/// Set the wearing-detection auto-power-off element.
///
/// # Safety
/// `handle` must be live and `out` must be writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_set_auto_power_off_wearing(
    handle: *mut c_void,
    current: u8,
    last: u8,
    now_ms: u64,
    out: *mut MdrBuffer,
) -> MdrStatus {
    if out.is_null() {
        return MdrStatus::NullHandle;
    }
    let result = with(handle, |s| {
        match s.set_auto_power_off_wearing(current, last, now_ms) {
            None => MdrStatus::NotReady,
            Some(events) => match collect_sends(events) {
                Some(bytes) => {
                    unsafe { *out = MdrBuffer::from_vec(bytes) };
                    MdrStatus::Ok
                }
                None => MdrStatus::NoData,
            },
        }
    });
    result.unwrap_or(MdrStatus::NullHandle)
}

/// Drive the engine's timeout/retry clock. Returns retry bytes in `out` when a
/// command has gone unanswered and policy still allows another attempt.
/// # Safety
/// `handle` must be live and `out` must be writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_poll(handle: *mut c_void, now_ms: u64, out: *mut MdrBuffer) -> MdrStatus {
    if out.is_null() {
        return MdrStatus::NullHandle;
    }
    let produced = with(handle, |s| collect_sends(s.poll_timeout(now_ms)));
    match produced {
        Some(Some(b)) => {
            unsafe { *out = MdrBuffer::from_vec(b) };
            MdrStatus::Ok
        }
        Some(None) => MdrStatus::NoData,
        None => MdrStatus::NullHandle,
    }
}

/// Read the current state snapshot.
/// # Safety
/// `handle` must be live and `out` must be writable.
#[no_mangle]
pub unsafe extern "C" fn mdr_snapshot(handle: *mut c_void, out: *mut MdrSnapshot) -> MdrStatus {
    if out.is_null() {
        return MdrStatus::NullHandle;
    }
    let Some(snap) = with(handle, |s| {
        let mut snap = MdrSnapshot { state: state_code(s.state()), ..Default::default() };
        if let Some(b) = &s.device.battery {
            snap.battery_level = b.value.level as i16;
            snap.battery_charging = b.value.charging as i16;
        }
        if let Some(nc) = &s.device.noise_control {
            snap.nc_enabled = nc.value.enabled as i16;
            snap.nc_mode = nc.value.mode as i16;
            snap.ambient_mode = nc.value.ambient_mode as i16;
            snap.ambient_level = nc.value.ambient_level as i16;
            snap.nc_known = 1;
            snap.nc_adaptation = nc.value.adaptation_on as u8;
            snap.nc_sensitivity = nc.value.sensitivity;
        }
        snap.revision = s.device.revision;
        snap.pending_write = s.device.has_pending_write() as u8;
        if let Some(info) = &s.protocol_info {
            snap.protocol_version = info.version;
            snap.supports_table1 = info.supports_table1 as u8;
            snap.supports_table2 = info.supports_table2 as u8;
        }
        copy_str(&mut snap.model, &s.device.identity.model);
        copy_str(&mut snap.firmware, &s.device.identity.firmware);
        if let Some(eq) = &s.device.equalizer {
            let v = &eq.value;
            snap.eq_known = 1;
            // Report off only when the device said so; unreported is on.
            snap.eq_enabled = (!v.status_known || v.enabled) as u8;
            snap.eq_preset = v.preset;
            snap.eq_band_count = v.band_count;
            snap.eq_band_step = v.band_step;
            let n = v.band_steps.len().min(snap.eq_bands.len());
            snap.eq_band_len = n as u8;
            snap.eq_bands[..n].copy_from_slice(&v.band_steps[..n]);
            snap.clear_bass = v.clear_bass as i16;
            snap.clear_bass_min = v.clear_bass_min as i16;
            snap.clear_bass_max = v.clear_bass_max as i16;
            snap.eq_preset_count = v.presets.len().min(u16::MAX as usize) as u16;
        }
        if let Some(up) = &s.device.upscaling {
            snap.upscaling_known = 1;
            snap.upscaling_enabled = up.value as u8;
        }
        if let Some(codec) = &s.device.codec {
            copy_str(&mut snap.codec, &codec.value);
        }
        if let Some(apo) = &s.device.auto_power_off {
            snap.apo_known = 1;
            snap.apo_enabled = apo.value as u8;
        }
        if let Some(cm) = &s.device.connection_mode {
            snap.conn_known = 1;
            snap.conn_classic = cm.value.0 as u8;
            snap.conn_le = cm.value.1 as u8;
        }
        if let Some(mho) = &s.device.music_hand_over {
            snap.mho_known = 1;
            snap.mho_enabled = mho.value as u8;
        }
        if let Some(usb) = &s.device.usb_submersion {
            snap.usb_known = 1;
            snap.usb_submerged = usb.value as u8;
        }
        if let Some(play) = &s.device.playback {
            snap.play_known = 1;
            snap.play_enabled = play.value.enabled as u8;
            snap.play_state = play.value.playback;
            snap.play_source = play.value.source;
        }
        if let Some(w) = &s.device.wearing_status {
            // Earpiece fitting detection; kept for its own fields.
            snap.wear_detection_enabled = w.value.detection_enabled as u8;
            snap.wear_selected_earpieces = w.value.selected_earpieces;
            snap.wear_result_code = w.value.result_code;
        }
        // Worn means the table-2 wearing checker says both sides are on
        // (code 0). The fitting detector's byte is not an on-head signal.
        if let Some(code) = &s.device.wearing_code {
            snap.wear_known = 1;
            snap.wear_worn = (code.value == 0) as u8;
        }
        if let Some(apow) = &s.device.auto_power_off_wearing {
            snap.apow_known = 1;
            snap.apow_current = apow.value.0;
            snap.apow_last = apow.value.1;
        }
        if let Some(on) = &s.device.auto_power_off_wearing_enabled {
            snap.apow_enabled_known = 1;
            snap.apow_enabled = on.value as u8;
        }
        if let Some(listen) = s.device.listening() {
            snap.listen_known = 1;
            snap.listen_mode = listen.mode().code();
            snap.listen_room = listen.room;
        }
        if let (Some(steps), Some(volume)) =
            (&s.device.playback_volume_steps, &s.device.music_volume)
        {
            snap.volume_known = 1;
            snap.volume_steps = steps.value.0;
            snap.volume = volume.value;
        }
        if let (Some(steps), Some(volume)) =
            (&s.device.playback_volume_steps, &s.device.call_volume)
        {
            snap.call_volume_known = 1;
            snap.call_volume_steps = steps.value.1;
            snap.call_volume = volume.value;
        }
        if let Some(on) = &s.device.auto_volume {
            snap.auto_volume_known = 1;
            snap.auto_volume_enabled = on.value as u8;
        }
        if let Some(available) = &s.device.auto_standby {
            snap.auto_standby_known = 1;
            snap.auto_standby_available = available.value as u8;
        }
        if let Some(enabled) = &s.device.auto_standby_enabled {
            snap.auto_standby_setting_known = 1;
            snap.auto_standby_setting = enabled.value as u8;
        }
        if let Some(st) = &s.device.smart_talking {
            snap.st_known = 1;
            snap.st_enabled = st.value.enabled as u8;
            snap.st_effect = st.value.effect;
            snap.st_sensitivity = st.value.sensitivity;
            snap.st_mode_out = st.value.mode_out;
        }
        if let Some(enabled) = &s.device.head_gesture {
            snap.hg_known = 1;
            snap.hg_enabled = enabled.value as u8;
        }
        if let Some(level) = &s.device.safe_volume_level {
            snap.safe_volume_known = 1;
            snap.safe_volume_level = level.value;
        }
        if let Some(started) = &s.device.adaptive_control_started {
            snap.ac_known = 1;
            snap.ac_started = started.value as u8;
        }
        if let Some(functions) = &s.device.quick_access {
            snap.qa_known = 1;
            snap.qa_count = functions.value.len().min(2) as u8;
            snap.qa0 = functions.value.first().copied().unwrap_or(0);
            snap.qa1 = functions.value.get(1).copied().unwrap_or(0);
        }
        if let Some(enabled) = &s.device.control_by_wearing {
            snap.cbw_known = 1;
            snap.cbw_enabled = enabled.value as u8;
        }
        if let Some(enabled) = &s.device.mic_on_off {
            snap.mic_known = 1;
            snap.mic_enabled = enabled.value as u8;
        }
        if let Some(enabled) = &s.device.sony_voice_assistant {
            snap.sva_known = 1;
            snap.sva_enabled = enabled.value as u8;
        }
        if let Some(language) = &s.device.sony_voice_assistant_language {
            snap.sval_known = 1;
            snap.sval_language = language.value;
        }
        if let Some(enabled) = &s.device.voice_guidance {
            snap.vg_known = 1;
            snap.vg_enabled = enabled.value as u8;
        }
        if let Some(volume) = &s.device.voice_guidance_volume {
            snap.vgv_known = 1;
            snap.vgv_volume = volume.value;
        }
        if let Some(training) = &s.device.head_gesture_training {
            snap.hgt_known = 1;
            snap.hgt_in_test = training.value.0;
            snap.hgt_enabled = training.value.1 as u8;
        }
        if let Some(action) = &s.device.head_gesture_action {
            snap.hga_known = 1;
            snap.hga_action = action.value;
        }
        if let Some(list) = &s.device.paired_devices {
            snap.pair_known = 1;
            snap.pair_count = list.value.devices.len().min(255) as u8;
            snap.pair_connected_count = list
                .value
                .devices
                .iter()
                .filter(|device| device.connected)
                .count()
                .min(255) as u8;
            snap.pair_playback_device = list.value.playback_device;
        }
        snap
    }) else {
        return MdrStatus::NullHandle;
    };
    unsafe { *out = snap };
    MdrStatus::Ok
}

/// A byte buffer returned across the ABI.
#[repr(C)]
pub struct MdrBuffer {
    pub data: *mut u8,
    pub len: usize,
    pub cap: usize,
}

impl MdrBuffer {
    fn from_vec(mut v: Vec<u8>) -> Self {
        let buf = MdrBuffer { data: v.as_mut_ptr(), len: v.len(), cap: v.capacity() };
        std::mem::forget(v);
        buf
    }
}

/// Free a buffer returned by this library.
///
/// # Safety
/// `buf` must point to a buffer this library returned, and must not be used
/// afterwards. Passing null is a no-op.
#[no_mangle]
pub unsafe extern "C" fn mdr_bytes_free(buf: *mut MdrBuffer) {
    if buf.is_null() {
        return;
    }
    let b = &mut *buf;
    if !b.data.is_null() {
        drop(Vec::from_raw_parts(b.data, b.len, b.cap));
    }
    b.data = std::ptr::null_mut();
    b.len = 0;
    b.cap = 0;
}

/// Engine version string, static and NUL-terminated.
#[no_mangle]
pub extern "C" fn mdr_version() -> *const c_char {
    concat!(env!("CARGO_PKG_VERSION"), "\0").as_ptr() as *const c_char
}

// ---------------------------------------------------------------------------
// JSON state export
// ---------------------------------------------------------------------------
//
// Language bindings that are not Swift would otherwise have to duplicate the
// exact layout of `MdrSnapshot`, and a single padding mistake there is a silent
// memory bug. Exporting one JSON document removes that whole class of error.

fn json_escape(out: &mut String, value: &str) {
    for ch in value.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04X}", c as u32)),
            c => out.push(c),
        }
    }
}

/// Serialise the whole engine state as one JSON object.
///
/// Writes a NUL-terminated JSON document into `buf`. Returns the number of
/// bytes written (excluding the terminator), or a negative value when the
/// buffer is too small. Callers should size the buffer generously (4 KiB is
/// ample) and retry with the returned negative magnitude if it is not.
///
/// # Safety
/// `handle` must be live; `buf` must be writable for `cap` bytes.
#[no_mangle]
pub unsafe extern "C" fn mdr_state_json(
    handle: *mut c_void,
    buf: *mut c_char,
    cap: usize,
) -> isize {
    if buf.is_null() || cap == 0 {
        return -1;
    }
    let Some(doc) = with(handle, |s| {
        let mut out = String::with_capacity(1024);
        out.push('{');
        out.push_str(&format!("\"state\":\"{}\",", s.state().label()));
        out.push_str(&format!("\"state_code\":{},", state_code(s.state())));

        out.push_str("\"model\":\"");
        json_escape(&mut out, &s.device.identity.model);
        out.push_str("\",\"firmware\":\"");
        json_escape(&mut out, &s.device.identity.firmware);
        out.push('"');
        if let Some(color) = s.device.identity.model_color {
            out.push_str(&format!(",\"model_color\":{color}"));
        }

        if let Some(info) = &s.protocol_info {
            out.push_str(&format!(
                ",\"protocol\":{},\"table1\":{},\"table2\":{}",
                info.version, info.supports_table1 as u8, info.supports_table2 as u8
            ));
        }

        if let Some(b) = &s.device.battery {
            out.push_str(&format!(
                ",\"battery\":{},\"charging\":{}",
                b.value.level, b.value.charging
            ));
        }

        if let Some(nc) = &s.device.noise_control {
            out.push_str(&format!(
                ",\"nc\":{{\"enabled\":{},\"mode\":{},\"ambient_mode\":{},\"level\":{},\"adaptation\":{},\"sensitivity\":{}}}",
                nc.value.enabled as u8, nc.value.mode, nc.value.ambient_mode, nc.value.ambient_level,
                nc.value.adaptation_on as u8, nc.value.sensitivity
            ));
        }

        if let Some(eq) = &s.device.equalizer {
            let v = &eq.value;
            out.push_str(",\"eq\":{");
            out.push_str(&format!(
                "\"enabled\":{},\"preset\":{},\"band_count\":{},\"band_step\":{},\"clear_bass\":{},\"clear_bass_min\":{},\"clear_bass_max\":{},\"preset_name\":\"",
                v.enabled as u8, v.preset, v.band_count, v.band_step, v.clear_bass,
                v.clear_bass_min, v.clear_bass_max
            ));
            if let Some(name) = mdr_core::protocol::eq_preset_name(v.preset) {
                json_escape(&mut out, name);
            }
            out.push_str("\",\"bands\":[");
            for (i, b) in v.band_steps.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                out.push_str(&b.to_string());
            }
            out.push_str("],\"presets\":[");
            for (i, (id, name)) in v.presets.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                out.push_str(&format!("{{\"id\":{},\"name\":\"", id));
                json_escape(&mut out, name);
                out.push_str("\"}");
            }
            out.push_str("]}");
        }

        if let Some(up) = &s.device.upscaling {
            out.push_str(&format!(",\"upscaling\":{}", up.value as u8));
        }
        if let Some(codec) = &s.device.codec {
            out.push_str(",\"codec\":\"");
            json_escape(&mut out, &codec.value);
            out.push('"');
        }
        if let Some(apo) = &s.device.auto_power_off {
            out.push_str(&format!(",\"auto_power_off\":{}", apo.value as u8));
        }
        if let Some(cm) = &s.device.connection_mode {
            out.push_str(&format!(
                ",\"connection_mode\":{{\"classic\":{},\"le\":{}}}",
                cm.value.0 as u8, cm.value.1 as u8
            ));
        }
        if let Some(mho) = &s.device.music_hand_over {
            out.push_str(&format!(",\"music_hand_over\":{}", mho.value));
        }
        if let Some(usb) = &s.device.usb_submersion {
            out.push_str(&format!(",\"usb_submersion\":{}", usb.value));
        }
        if let Some(play) = &s.device.playback {
            out.push_str(&format!(
                ",\"playback\":{{\"enabled\":{},\"state\":\"{}\",\"source\":\"{}\"}}",
                play.value.enabled as u8,
                mdr_core::protocol::playback_label(play.value.playback),
                mdr_core::protocol::playback_source_label(play.value.source)
            ));
        }
        if let Some(listen) = s.device.listening() {
            out.push_str(&format!(
                ",\"listening\":{{\"mode\":\"{}\",\"mode_code\":{},\"room\":{},\"room_name\":\"{}\"}}",
                listen.mode().label(),
                listen.mode().code(),
                listen.room,
                mdr_core::protocol::room_size_label(listen.room)
            ));
        }
        if let (Some(steps), Some(volume)) =
            (&s.device.playback_volume_steps, &s.device.music_volume)
        {
            out.push_str(&format!(
                ",\"volume\":{{\"value\":{},\"max\":{}}}",
                volume.value, steps.value.0
            ));
        }
        if let (Some(steps), Some(volume)) =
            (&s.device.playback_volume_steps, &s.device.call_volume)
        {
            out.push_str(&format!(
                ",\"call_volume\":{{\"value\":{},\"max\":{}}}",
                volume.value, steps.value.1
            ));
        }
        if let Some(on) = &s.device.auto_volume {
            out.push_str(&format!(",\"auto_volume\":{}", on.value));
        }
        if let Some(available) = &s.device.auto_standby {
            out.push_str(&format!(",\"auto_standby\":{}", available.value));
        }
        if let Some(enabled) = &s.device.auto_standby_enabled {
            out.push_str(&format!(",\"auto_standby_enabled\":{}", enabled.value));
        }
        if let Some(st) = &s.device.smart_talking {
            out.push_str(&format!(
                ",\"smart_talking\":{{\"enabled\":{},\"effect\":{},\"sensitivity\":{},\"sensitivity_name\":\"{}\",\"mode_out\":{},\"mode_out_name\":\"{}\"}}",
                st.value.enabled,
                st.value.effect,
                st.value.sensitivity,
                mdr_core::protocol::smart_talking_sensitivity_label(st.value.sensitivity),
                st.value.mode_out,
                mdr_core::protocol::smart_talking_mode_out_label(st.value.mode_out)
            ));
        }
        if let Some(enabled) = &s.device.head_gesture {
            out.push_str(&format!(",\"head_gesture\":{}", enabled.value));
        }
        if let Some(version) = &s.device.le_audio_switch_compat {
            out.push_str(&format!(",\"le_audio_switch_compat\":{}", version.value));
        }
        if let Some(enabled) = &s.device.sony_voice_assistant {
            out.push_str(&format!(",\"sony_voice_assistant\":{}", enabled.value));
        }
        if let Some(language) = &s.device.sony_voice_assistant_language {
            out.push_str(&format!(",\"sony_voice_assistant_language\":{}", language.value));
        }
        if let Some(link) = &s.device.link_auto_switch {
            let (enabled, speaker, address) = &link.value;
            out.push_str(&format!(
                ",\"link_auto_switch\":{{\"enabled\":{},\"speaker\":{},\"address\":\"{}\"}}",
                enabled, speaker, address
            ));
        }
        if let Some(cap) = &s.device.pairing_capability {
            out.push_str(&format!(
                ",\"pairing_capability\":{{\"max_paired\":{},\"max_connected\":{},\"file_transfer\":{}}}",
                cap.value.max_paired, cap.value.max_connected, cap.value.file_transfer
            ));
        }
        if let Some(mode) = &s.device.pairing_mode {
            out.push_str(&format!(
                ",\"pairing_mode\":{{\"mode\":{},\"name\":\"{}\",\"enabled\":{}}}",
                mode.value.mode,
                mdr_core::protocol::pairing_mode_label(mode.value.mode),
                mode.value.enabled
            ));
        }
        if let Some(list) = &s.device.paired_devices {
            out.push_str(",\"paired_devices\":[");
            for (index, device) in list.value.devices.iter().enumerate() {
                if index > 0 {
                    out.push(',');
                }
                out.push_str("{\"address\":\"");
                json_escape(&mut out, &device.address);
                out.push_str("\",\"name\":\"");
                json_escape(&mut out, &device.name);
                out.push_str(&format!("\",\"connected\":{}", device.connected));
                if let Some(cod) = device.class_of_device {
                    out.push_str(&format!(",\"class_of_device\":{cod}"));
                }
                out.push('}');
            }
            out.push_str(&format!(
                "],\"pairing_playback_device\":{}",
                list.value.playback_device
            ));
        }
        if let Some(event) = &s.device.last_pairing_event {
            out.push_str(&format!(
                ",\"pairing_event\":{{\"action\":{},\"result\":{},\"result_name\":\"{}\",\"address\":\"{}\"}}",
                event.value.action,
                event.value.result,
                mdr_core::protocol::pairing_result_label(event.value.result),
                event.value.address
            ));
        }
        if let Some(enabled) = &s.device.control_by_wearing {
            out.push_str(&format!(",\"control_by_wearing\":{}", enabled.value));
        }
        if let Some(available) = &s.device.control_by_wearing_available {
            out.push_str(&format!(",\"control_by_wearing_available\":{}", available.value));
        }
        if let Some(enabled) = &s.device.mic_on_off {
            out.push_str(&format!(",\"mic_on_off\":{}", enabled.value));
        }
        if let Some(effect) = &s.device.mic_off_sound_effect {
            out.push_str(&format!(",\"mic_off_sound_effect\":{}", effect.value));
        }
        if let Some(key) = &s.device.mic_key_type {
            out.push_str(&format!(",\"mic_key_type\":{}", key.value));
        }
        if let Some(alert) = &s.device.last_alert {
            out.push_str(&format!(
                ",\"last_alert\":{{\"type\":{},\"name\":\"{}\",\"message\":{},\"action\":{}}}",
                alert.value.0,
                mdr_core::protocol::alert_type_name(alert.value.0),
                alert.value.1,
                alert.value.2
            ));
        }
        if let Some(started) = &s.device.adaptive_control_started {
            out.push_str(&format!(",\"adaptive_control_started\":{}", started.value));
        }
        if let Some(capability) = &s.device.adaptive_control_capability {
            let bytes: Vec<String> = capability.value.iter().map(|b| b.to_string()).collect();
            out.push_str(&format!(
                ",\"adaptive_control_capability\":[{}]",
                bytes.join(",")
            ));
        }
        if let Some(parameter) = &s.device.adaptive_parameter {
            out.push_str(",\"adaptive_parameter\":[");
            for (index, function) in parameter.value.functions.iter().enumerate() {
                if index > 0 {
                    out.push(',');
                }
                out.push_str(&format!(
                    "{{\"function\":{},\"name\":\"{}\",\"result\":{},\"data\":[{}]}}",
                    function.function,
                    mdr_core::protocol::sense_function_name(function.function),
                    function.result,
                    function
                        .data
                        .iter()
                        .map(|b| b.to_string())
                        .collect::<Vec<_>>()
                        .join(",")
                ));
            }
            out.push(']');
        }
        if let Some(enabled) = &s.device.voice_guidance {
            out.push_str(&format!(",\"voice_guidance\":{}", enabled.value));
        }
        if let Some(language) = &s.device.voice_guidance_language {
            out.push_str(&format!(",\"voice_guidance_language\":{}", language.value));
        }
        if let Some(status) = &s.device.voice_guidance_status_raw {
            out.push_str(&format!(
                ",\"voice_guidance_status_raw\":[{},{}]",
                status.value.0, status.value.1
            ));
        }
        if let Some(volume) = &s.device.voice_guidance_volume {
            out.push_str(&format!(",\"voice_guidance_volume\":{}", volume.value));
        }
        if let Some(training) = &s.device.head_gesture_training {
            out.push_str(&format!(
                ",\"head_gesture_training\":{{\"status\":{},\"enabled\":{}}}",
                training.value.0, training.value.1
            ));
        }
        if let Some(action) = &s.device.head_gesture_action {
            out.push_str(&format!(",\"head_gesture_action\":{}", action.value));
        }
        if let Some(ble) = &s.device.ble_setup {
            out.push_str(&format!(
                ",\"ble\":{{\"address\":\"{}\",\"id\":\"{}\"}}",
                ble.value.0, ble.value.1
            ));
        }
        if let Some(status) = &s.device.repeat_tap_status {
            out.push_str(&format!(",\"repeat_tap\":{}", status.value));
        }
        if let Some(count) = &s.device.sar_capability {
            out.push_str(&format!(",\"sar_capability\":{}", count.value));
        }
        if let Some(enabled) = &s.device.gatt_connectable {
            out.push_str(&format!(",\"gatt_connectable\":{}", enabled.value));
        }
        if let Some(opt) = &s.device.sar_optimization {
            out.push_str(&format!(
                ",\"sar_optimization\":{{\"enabled\":{},\"status\":{}}}",
                opt.value.0, opt.value.1
            ));
        }
        if let Some(value) = &s.device.auto_play_capability {
            out.push_str(&format!(",\"auto_play_capability\":{}", value.value));
        }
        if let Some(level) = &s.device.safe_volume_level {
            out.push_str(&format!(
                ",\"safe_volume\":{{\"level\":{},\"name\":\"{}\"}}",
                level.value,
                if level.value == 1 { "Sensitive" } else { "Normal" }
            ));
        }
        if let Some(result) = &s.device.quick_access_result {
            out.push_str(&format!(",\"quick_access_result\":{}", result.value));
        }
        if let Some(functions) = &s.device.quick_access {
            out.push_str(",\"quick_access\":[");
            for (i, f) in functions.value.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                out.push_str(&format!(
                    "{{\"value\":{},\"name\":\"{}\"}}",
                    f,
                    mdr_core::protocol::quick_access_name(*f)
                ));
            }
            out.push(']');
        }
        if let Some(w) = &s.device.wearing_status {
            out.push_str(&format!(
                ",\"earpiece_fitting\":{{\"in_ear\":{},\"detection_enabled\":{},\"selected_earpieces\":{},\"result_code\":{}}}",
                w.value.worn, w.value.detection_enabled, w.value.selected_earpieces, w.value.result_code
            ));
        }
        if let Some(apow) = &s.device.auto_power_off_wearing {
            out.push_str(&format!(
                ",\"auto_power_off_wearing\":{{\"current\":{},\"last\":{}",
                apow.value.0, apow.value.1
            ));
            if let Some(on) = &s.device.auto_power_off_wearing_enabled {
                out.push_str(&format!(",\"enabled\":{}", on.value as u8));
            }
            out.push('}');
        }

        if let Some(va) = &s.device.voice_assistant {
            out.push_str(&format!(
                ",\"voice_assistant\":{{\"current\":{},\"name\":\"",
                va.value.current
            ));
            json_escape(&mut out, va.value.current_name());
            out.push_str("\",\"supported\":[");
            for (i, v) in va.value.supported.iter().enumerate() {
                if i > 0 { out.push(','); }
                out.push_str(&format!("{{\"value\":{},\"name\":\"", v));
                json_escape(&mut out, mdr_core::protocol::voice_assistant::name(*v));
                out.push_str("\"}");
            }
            out.push_str("]}");
        }

        out.push_str(",\"gs\":[");
        for (i, gs) in s.device.general_settings.iter().enumerate() {
            if i > 0 {
                out.push(',');
            }
            out.push_str(&format!("{{\"type\":{},\"label\":\"", gs.gs_type));
            json_escape(&mut out, &gs.label);
            out.push_str("\",\"title\":\"");
            json_escape(&mut out, &gs.title());
            out.push_str("\",\"detail\":\"");
            json_escape(&mut out, gs.detail());
            out.push_str("\",\"value\":");
            match gs.value {
                Some(v) => out.push_str(if v { "1" } else { "0" }),
                None => out.push_str("null"),
            }
            out.push('}');
        }
        out.push(']');

        out.push_str(&format!(
            ",\"pending_write\":{},\"revision\":{}}}",
            s.device.has_pending_write() as u8,
            s.device.revision
        ));
        out
    }) else {
        return -1;
    };

    let bytes = doc.as_bytes();
    if bytes.len() + 1 > cap {
        return -((bytes.len() + 1) as isize);
    }
    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), buf as *mut u8, bytes.len());
        *buf.add(bytes.len()) = 0;
    }
    bytes.len() as isize
}
