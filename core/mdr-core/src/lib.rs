//! `mdr-core` — an independent, interoperable engine for the Sony MDR control
//! protocol used by headphones such as the WH-1000XM series.
//!
//! Scope, stated plainly:
//!
//! * Implements the framing layer and a curated V2 table-1 command surface.
//! * Never claims a capability the device has not reported.
//! * Contains no Sony code, assets, or credentials. Protocol constants were
//!   cross-checked against the MIT-licensed `libmdr` project (see `NOTICE.md`).
//!
//! The crate is `no_std`-friendly in spirit (no threads, no clock, no I/O) so
//! every platform adapter can drive it synchronously from its own event loop.

#![forbid(unsafe_code)]

pub mod devices;
pub mod framing;
pub mod protocol;
pub mod session;
pub mod simulator;
pub mod state;

/// Generated wire values. Kept separate from the
/// hand-written, curated constants in [`protocol::cmd`] so a conformance test
/// can prove the two agree.
#[path = "generated/function_types.rs"]
pub mod function_types;

/// Table-2 names: the same byte means a different function on table 2.
#[path = "generated/function_types_table2.rs"]
pub mod function_types_table2;

#[path = "generated/command_table_v2t1.rs"]
pub mod command_table_v2t1;

pub use framing::{DataType, Frame, FrameError, MdrTable, StreamDecoder};
pub use protocol::{BatteryStatus, NoiseControl, ProtocolInfo};
pub use session::{Policy, Session, SessionEvent, SessionState};
pub use state::{DeviceState, Provenance, Value};

/// Protocol generation negotiated with a device.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProtocolVersion {
    V1,
    V2,
}

/// Crate version, for the About screen and diagnostics headers.
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

#[cfg(test)]
mod integration {
    use super::*;

    /// End-to-end: framing → simulator → session → state, with the sequence
    /// numbers the real channel uses.
    #[test]
    fn handshake_then_write_then_read() {
        let mut session = Session::new(Policy::default());
        let mut sim = simulator::SimDevice::new();
        sim.battery = 42;
        let mut now = 0u64;
        simulator::drive(&mut session, &mut sim, &mut now);

        assert_eq!(session.state(), SessionState::Ready);
        assert_eq!(session.device.battery.as_ref().unwrap().value.level, 42);

        let events = session
            .set_noise_control(false, 0, 0, 0, now)
            .expect("ready session accepts writes");
        let write = events
            .iter()
            .find_map(|e| match e {
                SessionEvent::Send(b) => Some(b.clone()),
                _ => None,
            })
            .expect("a frame to write");

        let mut decoder = StreamDecoder::new();
        decoder.push(&write);
        let frame = decoder.next_frame().unwrap().unwrap();
        // Table-1 traffic travels as DATA_MDR, never as plain DATA.
        assert_eq!(frame.kind(), DataType::DataMdr);
        assert_eq!(frame.payload[0], protocol::cmd::NCASM_SET_PARAM);

        for reply in sim.handle(&frame) {
            session.receive(&reply, now + 1);
        }
        let nc = session.device.noise_control.as_ref().unwrap().value;
        assert!(!nc.enabled);
        assert_eq!(session.device.noise_control.as_ref().unwrap().provenance, Provenance::Device);
    }

    #[test]
    fn every_frame_round_trips_through_the_decoder() {
        for len in 0..40usize {
            let payload: Vec<u8> = (0..len).map(|i| (i * 7 % 256) as u8).collect();
            let packed = framing::pack(DataType::Data, 3, &payload);
            let (frame, used) = framing::unpack(&packed).unwrap();
            assert_eq!(used, packed.len());
            assert_eq!(frame.payload, payload);
        }
    }
}
