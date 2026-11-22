//! End-to-end FFI check: drive the simulator through the C ABI and verify the
//! JSON snapshot carries the newer state fields.

use std::ptr;

use mdr_core::framing::StreamDecoder;
use mdr_core::simulator::SimDevice;
use mdr_ffi::{mdr_bytes_free, mdr_connect, mdr_receive, mdr_session_free, mdr_session_new,
              mdr_state_json, mdr_supported_at, mdr_supported_at_table2, mdr_supported_count,
              mdr_supported_count_table2, MdrBuffer, MdrStatus};

unsafe fn take(buf: &mut MdrBuffer) -> Vec<u8> {
    if buf.data.is_null() || buf.len == 0 {
        return Vec::new();
    }
    let bytes = std::slice::from_raw_parts(buf.data, buf.len).to_vec();
    mdr_bytes_free(buf);
    bytes
}

#[test]
fn state_json_contains_new_fields() {
    unsafe {
        let handle = mdr_session_new();
        assert!(!handle.is_null());

        let mut out = MdrBuffer { data: ptr::null_mut(), len: 0, cap: 0 };
        assert_eq!(mdr_connect(handle, 0, &mut out), MdrStatus::Ok);

        let mut queue = vec![take(&mut out)];
        let mut sim = SimDevice::new();
        let mut now = 0u64;
        let mut decoder = StreamDecoder::new();

        while let Some(bytes) = queue.pop() {
            if bytes.is_empty() {
                continue;
            }
            decoder.push(&bytes);
            while let Ok(Some(frame)) = decoder.next_frame() {
                for reply in sim.handle(&frame) {
                    now += 1;
                    let mut response = MdrBuffer { data: ptr::null_mut(), len: 0, cap: 0 };
                    let status = mdr_receive(handle, reply.as_ptr(), reply.len(), now, &mut response);
                    if status == MdrStatus::Ok {
                        let sent = take(&mut response);
                        if !sent.is_empty() {
                            queue.push(sent);
                        }
                    }
                }
            }
        }

        let mut buf = vec![0i8; 16_384];
        let written = mdr_state_json(handle, buf.as_mut_ptr(), buf.len());
        assert!(written > 0, "state JSON failed: {written}");

        let bytes: Vec<u8> = buf[..written as usize].iter().map(|b| *b as u8).collect();
        let json = String::from_utf8(bytes).expect("valid UTF-8");
        for key in [
            "\"playback\"",
            "\"music_hand_over\"",
            "\"usb_submersion\"",
            "\"earpiece_fitting\"",
            "\"auto_power_off_wearing\"",
            "\"connection_mode\"",
            "\"listening\"",
            "\"volume\"",
            "\"call_volume\"",
            "\"auto_volume\"",
            "\"auto_standby\"",
            "\"auto_standby_enabled\"",
            "\"smart_talking\"",
            "\"head_gesture\"",
            "\"ble\"",
            "\"repeat_tap\"",
            "\"gatt_connectable\"",
            "\"sar_optimization\"",
            "\"auto_play_capability\"",
            "\"quick_access\"",
            "\"paired_devices\"",
            "\"pairing_capability\"",
            "\"pairing_playback_device\"",
        ] {
            assert!(json.contains(key), "missing {key} in {json}");
        }
        assert!(json.contains("Sim Laptop"), "paired device name missing in {json}");

        mdr_session_free(handle);
    }
}

/// Drive a fresh session through sync against the simulator.
unsafe fn synced_session() -> *mut std::ffi::c_void {
    let handle = mdr_session_new();
    assert!(!handle.is_null());
    let mut out = MdrBuffer { data: ptr::null_mut(), len: 0, cap: 0 };
    assert_eq!(mdr_connect(handle, 0, &mut out), MdrStatus::Ok);
    let mut queue = vec![take(&mut out)];
    let mut sim = SimDevice::new();
    let mut now = 0u64;
    let mut decoder = StreamDecoder::new();
    while let Some(bytes) = queue.pop() {
        if bytes.is_empty() {
            continue;
        }
        decoder.push(&bytes);
        while let Ok(Some(frame)) = decoder.next_frame() {
            for reply in sim.handle(&frame) {
                now += 1;
                let mut response = MdrBuffer { data: ptr::null_mut(), len: 0, cap: 0 };
                if mdr_receive(handle, reply.as_ptr(), reply.len(), now, &mut response) == MdrStatus::Ok {
                    let sent = take(&mut response);
                    if !sent.is_empty() {
                        queue.push(sent);
                    }
                }
            }
        }
    }
    handle
}

unsafe fn names(
    handle: *mut std::ffi::c_void,
    count: unsafe extern "C" fn(*mut std::ffi::c_void, *mut usize) -> MdrStatus,
    at: unsafe extern "C" fn(*mut std::ffi::c_void, usize, *mut u8, *mut std::ffi::c_char, usize) -> MdrStatus,
) -> Vec<(u8, String)> {
    let mut n = 0usize;
    assert_eq!(count(handle, &mut n), MdrStatus::Ok);
    (0..n)
        .filter_map(|i| {
            let mut value = 0u8;
            let mut name = vec![0 as std::ffi::c_char; 128];
            if at(handle, i, &mut value, name.as_mut_ptr(), name.len()) != MdrStatus::Ok {
                return None;
            }
            let label = std::ffi::CStr::from_ptr(name.as_ptr()).to_string_lossy().into_owned();
            Some((value, label))
        })
        .collect()
}

#[test]
fn supported_functions_are_named_per_table() {
    unsafe {
        let handle = synced_session();
        let table1 = names(handle, mdr_supported_count, mdr_supported_at);
        let table2 = names(handle, mdr_supported_count_table2, mdr_supported_at_table2);

        // 0x20 means different functions on each table.
        assert!(table1.contains(&(0x20, "BATTERY_LEVEL_INDICATOR".into())), "{table1:?}");
        assert!(table2.contains(&(0x20, "AUTO_STANDBY".into())), "{table2:?}");
        assert!(table2.contains(&(0x34, "MUSIC_HAND_OVER_SETTING".into())), "{table2:?}");
        assert_eq!(table2.len(), 5);

        mdr_session_free(handle);
    }
}
