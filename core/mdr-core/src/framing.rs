//! Frame layer for the Sony MDR control channel.
//!
//! Wire form (cross-checked against the MIT-licensed `libmdr` project):
//!
//! ```text
//! '>'  <escaped body>  '<'
//!
//! body := data_type:u8  seq:u8  len:u32be  payload[len]  checksum:u8
//! checksum := wrapping sum of every body byte except the checksum itself
//! ```
//!
//! Escaping applies to the whole body (including the checksum):
//! `0x3C -> 0x3D 0x2C`, `0x3D -> 0x3D 0x2D`, `0x3E -> 0x3D 0x2E`.
//!
//! Parsing is deliberately defensive: every length is validated against the
//! bytes actually present, escaping is checked, and no allocation is driven by
//! a length field before that length is proven to exist.

/// Start-of-frame marker `>`.
pub const START: u8 = 0x3E;
/// End-of-frame marker `<`.
pub const END: u8 = 0x3C;
/// Escape sentinel `=`.
pub const ESC: u8 = 0x3D;

const ESC_END: u8 = 0x2C; // escaped '<'
const ESC_ESC: u8 = 0x2D; // escaped '='
const ESC_START: u8 = 0x2E; // escaped '>'

/// Largest body we will accept. The reference client fragments above 2048.
pub const MAX_BODY: usize = 4096;

/// MDR data-type byte.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum DataType {
    Data = 0,
    Ack = 1,
    DataMcNo1 = 2,
    DataIcd = 9,
    DataEv = 10,
    DataMdr = 12,
    DataCommon = 13,
    DataMdrNo2 = 14,
    Shot = 16,
    ShotMcNo1 = 18,
    ShotIcd = 25,
    ShotEv = 26,
    ShotMdr = 28,
    ShotCommon = 29,
    ShotMdrNo2 = 30,
    LargeDataCommon = 45,
    Unknown = 0xFF,
}

impl DataType {
    pub fn from_byte(b: u8) -> DataType {
        match b {
            0 => DataType::Data,
            1 => DataType::Ack,
            2 => DataType::DataMcNo1,
            9 => DataType::DataIcd,
            10 => DataType::DataEv,
            12 => DataType::DataMdr,
            13 => DataType::DataCommon,
            14 => DataType::DataMdrNo2,
            16 => DataType::Shot,
            18 => DataType::ShotMcNo1,
            25 => DataType::ShotIcd,
            26 => DataType::ShotEv,
            28 => DataType::ShotMdr,
            29 => DataType::ShotCommon,
            30 => DataType::ShotMdrNo2,
            45 => DataType::LargeDataCommon,
            _ => DataType::Unknown,
        }
    }
}

/// Which command table a session speaks.
///
/// Both tables share one RFCOMM channel but announce themselves with different
/// data-type bytes, so a frame's table is unambiguous from its header.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum MdrTable {
    #[default]
    Table1,
    Table2,
}

impl MdrTable {
    /// Table 1 travels as
    /// `DATA_MDR` (12), table 2 as `DATA_MDR_NO2` (14).
    pub fn data_type(self) -> DataType {
        match self {
            MdrTable::Table1 => DataType::DataMdr,
            MdrTable::Table2 => DataType::DataMdrNo2,
        }
    }

    /// Sequence numbers on this link are a single alternating bit, so the
    /// reciprocal is `1 - seq`.
    pub fn reciprocal(seq: u8) -> u8 {
        1u8.wrapping_sub(seq)
    }
}

/// A decoded frame.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Frame {
    pub data_type: u8,
    pub seq: u8,
    pub payload: Vec<u8>,
}

impl Frame {
    pub fn new(data_type: DataType, seq: u8, payload: impl Into<Vec<u8>>) -> Self {
        Frame { data_type: data_type as u8, seq, payload: payload.into() }
    }

    pub fn kind(&self) -> DataType {
        DataType::from_byte(self.data_type)
    }
}

/// Every way a frame can fail to decode. Distinguishing these matters: a
/// `BadChecksum` from real hardware is a different signal from an `Incomplete`
/// read that simply needs more bytes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FrameError {
    /// Not enough bytes yet; caller should read more and retry.
    Incomplete,
    /// No start marker where one was required.
    BadStartMarker,
    /// No end marker inside the scanned window.
    BadEndMarker,
    /// Trailing escape sentinel, or escape followed by an unknown byte.
    BadEscape,
    /// Declared length does not match the bytes carried.
    BadLength,
    /// Checksum mismatch.
    BadChecksum,
    /// Declared length exceeds `MAX_BODY`.
    TooLarge,
    /// Body shorter than the fixed 6-byte header (type, seq, len).
    ShortBody,
}

impl core::fmt::Display for FrameError {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        let s = match self {
            FrameError::Incomplete => "incomplete frame",
            FrameError::BadStartMarker => "missing start marker",
            FrameError::BadEndMarker => "missing end marker",
            FrameError::BadEscape => "invalid escape sequence",
            FrameError::BadLength => "declared length does not match payload",
            FrameError::BadChecksum => "checksum mismatch",
            FrameError::TooLarge => "frame exceeds maximum body size",
            FrameError::ShortBody => "body shorter than header",
        };
        f.write_str(s)
    }
}

impl std::error::Error for FrameError {}

/// Wrapping byte sum, the MDR checksum.
#[inline]
pub fn checksum(bytes: &[u8]) -> u8 {
    bytes.iter().fold(0u8, |acc, b| acc.wrapping_add(*b))
}

#[inline]
fn escape_byte(out: &mut Vec<u8>, b: u8) {
    match b {
        END => {
            out.push(ESC);
            out.push(ESC_END);
        }
        ESC => {
            out.push(ESC);
            out.push(ESC_ESC);
        }
        START => {
            out.push(ESC);
            out.push(ESC_START);
        }
        other => out.push(other),
    }
}

/// Serialise one frame, escaping and checksumming.
pub fn pack(data_type: DataType, seq: u8, payload: &[u8]) -> Vec<u8> {
    let mut body = Vec::with_capacity(payload.len() + 7);
    body.push(data_type as u8);
    body.push(seq);
    body.extend_from_slice(&(payload.len() as u32).to_be_bytes());
    body.extend_from_slice(payload);
    let ck = checksum(&body);
    body.push(ck);

    let mut out = Vec::with_capacity(body.len() + 2);
    out.push(START);
    for b in body {
        escape_byte(&mut out, b);
    }
    out.push(END);
    out
}

/// Decode one frame from the front of `buf`.
///
/// On success returns the frame and how many bytes of `buf` it consumed, so a
/// stream reader can advance its buffer and keep any following frame.
pub fn unpack(buf: &[u8]) -> Result<(Frame, usize), FrameError> {
    if buf.is_empty() {
        return Err(FrameError::Incomplete);
    }
    if buf[0] != START {
        return Err(FrameError::BadStartMarker);
    }

    // Unescape until the terminating marker. The escaping guarantees the first
    // unescaped END is a real frame terminator.
    let mut body = Vec::with_capacity(buf.len().min(MAX_BODY));
    let mut i = 1usize;
    let mut terminated = false;
    while i < buf.len() {
        let b = buf[i];
        if b == END {
            terminated = true;
            i += 1;
            break;
        }
        if b == ESC {
            let Some(&next) = buf.get(i + 1) else {
                return Err(FrameError::Incomplete); // escape split across reads
            };
            let decoded = match next {
                ESC_END => END,
                ESC_ESC => ESC,
                ESC_START => START,
                _ => return Err(FrameError::BadEscape),
            };
            body.push(decoded);
            i += 2;
            continue;
        }
        body.push(b);
        i += 1;
        if body.len() > MAX_BODY + 2 {
            return Err(FrameError::TooLarge);
        }
    }
    if !terminated {
        // Distinguish "needs more bytes" from a protocol violation.
        return Err(if body.len() > MAX_BODY { FrameError::TooLarge } else { FrameError::Incomplete });
    }

    if body.len() < 7 {
        return Err(FrameError::ShortBody);
    }
    let data_type = body[0];
    let seq = body[1];
    let declared = u32::from_be_bytes([body[2], body[3], body[4], body[5]]) as usize;
    if declared > MAX_BODY {
        return Err(FrameError::TooLarge);
    }
    if body.len() != 6 + declared + 1 {
        return Err(FrameError::BadLength);
    }
    let (checked, ck) = body.split_at(body.len() - 1);
    if checksum(checked) != ck[0] {
        return Err(FrameError::BadChecksum);
    }
    let payload = checked[6..].to_vec();
    Ok((Frame { data_type, seq, payload }, i))
}

/// Incremental decoder for a byte stream (RFCOMM gives arbitrary chunking).
#[derive(Debug, Default)]
pub struct StreamDecoder {
    buf: Vec<u8>,
    /// Frames discarded because they failed validation; surfaced for diagnostics.
    pub error_count: u32,
}

impl StreamDecoder {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn push(&mut self, bytes: &[u8]) {
        self.buf.extend_from_slice(bytes);
    }

    /// Pull the next complete frame, if any.
    ///
    /// Resynchronises on the next start marker when the buffered data does not
    /// begin with one, and drops a corrupt frame rather than wedging the stream.
    pub fn next_frame(&mut self) -> Result<Option<Frame>, FrameError> {
        if self.buf.is_empty() {
            return Ok(None);
        }
        if self.buf[0] != START {
            match self.buf.iter().position(|b| *b == START) {
                Some(pos) => {
                    self.buf.drain(..pos);
                }
                None => {
                    self.buf.clear();
                    return Ok(None);
                }
            }
        }
        match unpack(&self.buf) {
            Ok((frame, used)) => {
                self.buf.drain(..used);
                Ok(Some(frame))
            }
            Err(FrameError::Incomplete) => Ok(None),
            Err(err) => {
                self.error_count = self.error_count.saturating_add(1);
                // Drop the leading marker, then skip to the next one. This
                // always consumes at least one byte, so the scan makes
                // progress, and the error is still reported — a silently
                // dropped frame would make a bug in the field invisible.
                self.buf.drain(..1);
                match self.buf.iter().position(|b| *b == START) {
                    Some(pos) => {
                        self.buf.drain(..pos);
                    }
                    None => self.buf.clear(),
                }
                Err(err)
            }
        }
    }

    pub fn buffered(&self) -> usize {
        self.buf.len()
    }
}
