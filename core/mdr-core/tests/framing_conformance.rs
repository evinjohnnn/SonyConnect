//! Framing conformance against the wire format the headphones expect.
//!
//! ACK frames come in exactly two forms, one per sequence number, and payload
//! bytes are escaped through a table of two-byte sequences. Those exact bytes
//! are asserted here, so a refactor of the framing layer cannot silently
//! diverge from the wire format.

use mdr_core::framing::{self, DataType, FrameError, MdrTable, StreamDecoder};

#[test]
fn ack_templates_match_the_shipped_application() {
    // {62, ACK, 0, 0,0,0,0, 1, 60} and {62, ACK, 1, 0,0,0,0, 2, 60},
    // i.e. START, type, seq, payloadLen(4 BE bytes), checksum, END — with the
    // checksum being the wrapping sum of type+seq+len+payload.
    assert_eq!(
        framing::pack(DataType::Ack, 0, &[]),
        vec![62, 1, 0, 0, 0, 0, 0, 1, 60],
        "empty ACK with seq 0"
    );
    assert_eq!(
        framing::pack(DataType::Ack, 1, &[]),
        vec![62, 1, 1, 0, 0, 0, 0, 2, 60],
        "empty ACK with seq 1"
    );
}

#[test]
fn escape_table_matches_the_wire_format() {
    // Escapes:
    //   '>' -> '=' '.'   {61, 46}
    //   '<' -> '=' ','   {61, 44}
    //   '=' -> '=' '-'   {61, 45}
    let packed = framing::pack(DataType::Data, 0, &[0x3E, 0x3C, 0x3D]);
    // START, then escaped body, then END.
    assert_eq!(packed.first(), Some(&62u8));
    assert_eq!(packed.last(), Some(&60u8));
    let body = &packed[1..packed.len() - 1];
    // The three payload bytes must appear as the six escape bytes, in order.
    assert!(
        body.windows(6).any(|w| w == [61, 46, 61, 44, 61, 45]),
        "expected escaped >, <, = sequence in {body:02X?}"
    );
}

#[test]
fn decoder_rejects_the_same_frame_a_checksum_mismatch() {
    // A frame whose checksum does not match is ignored.
    let mut packed = framing::pack(DataType::Data, 0, &[0x00, 0x01]);
    let n = packed.len();
    packed[n - 2] ^= 0xFF; // corrupt the checksum byte before END
    assert_eq!(framing::unpack(&packed), Err(FrameError::BadChecksum));
}

#[test]
fn decoder_rejects_negative_length_like_the_application() {
    // A length with the high bit set is refused. We express that as a length
    // that overruns the buffer.
    let mut body = vec![DataType::Data as u8, 0u8];
    body.extend_from_slice(&0xFFFF_FFFFu32.to_be_bytes());
    let mut packed = vec![62u8];
    packed.extend_from_slice(&body);
    packed.push(0u8);
    packed.push(60);
    assert_eq!(framing::unpack(&packed), Err(FrameError::TooLarge));
}

#[test]
fn stream_decoder_recovers_after_a_corrupt_frame() {
    // The app drops a bad frame and keeps reading. Our decoder must do the same
    // rather than wedging the connection.
    let good = framing::pack(DataType::Data, 7, &[0x66, 0x17]);
    let mut corrupt = framing::pack(DataType::Data, 8, &[0xAA]);
    let n = corrupt.len();
    corrupt[n - 2] ^= 0xFF;

    let mut joined = Vec::new();
    joined.extend_from_slice(&corrupt);
    joined.extend_from_slice(&good);

    let mut dec = StreamDecoder::new();
    dec.push(&joined);

    let first = dec.next_frame();
    assert!(matches!(first, Err(FrameError::BadChecksum)), "got {first:?}");

    let second = dec.next_frame().expect("recovered").expect("frame");
    assert_eq!(second.seq, 7);
    assert_eq!(second.payload, vec![0x66, 0x17]);
}

// ---------------------------------------------------------------------------
// Link layer: sequence numbers and the data type that carries MDR traffic.
// ---------------------------------------------------------------------------

#[test]
fn mdr_table_data_types_match_the_shipped_data_type_enum() {
    // Table 1 travels as data type 12 (DATA_MDR), table 2 as 14 (DATA_MDR_NO2).
    assert_eq!(MdrTable::Table1.data_type() as u8, 12);
    assert_eq!(MdrTable::Table2.data_type() as u8, 14);
    assert_eq!(MdrTable::Table1.data_type(), DataType::DataMdr);
    assert_eq!(MdrTable::Table2.data_type(), DataType::DataMdrNo2);
}

#[test]
fn the_acknowledgement_sequence_is_the_reciprocal() {
    // The ACK for a frame carries 1 - seq.
    assert_eq!(MdrTable::reciprocal(0), 1);
    assert_eq!(MdrTable::reciprocal(1), 0);
}

#[test]
fn the_two_ack_templates_are_the_only_sequence_numbers_the_app_can_send() {
    // There are exactly two ACK forms, one per sequence number: a one-bit
    // sequence space.
    for seq in 0..=1u8 {
        let ack = framing::pack(DataType::Ack, seq, &[]);
        assert!(ack.starts_with(&[62, 1, seq]), "unexpected ACK shape for seq {seq}");
    }
}
