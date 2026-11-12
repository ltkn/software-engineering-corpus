//! Parse HLK-LD2410 radar report frames from a UART byte stream.

#![cfg_attr(not(test), no_std)]
#![forbid(unsafe_code)]

const HEADER: [u8; 4] = [0xF4, 0xF3, 0xF2, 0xF1];
const FOOTER: [u8; 4] = [0xF8, 0xF7, 0xF6, 0xF5];
const MAX_DATA: usize = 64;
/// Type, head, nine bytes of target data, tail, check.
const MIN_DATA: usize = 13;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TargetState {
    None,
    Moving,
    Stationary,
    MovingAndStationary,
}

impl TargetState {
    fn from_byte(byte: u8) -> Option<Self> {
        match byte {
            0 => Some(Self::None),
            1 => Some(Self::Moving),
            2 => Some(Self::Stationary),
            3 => Some(Self::MovingAndStationary),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Report {
    pub state: TargetState,
    pub moving_cm: u16,
    pub moving_energy: u8,
    pub stationary_cm: u16,
    pub stationary_energy: u8,
    pub detection_cm: u16,
}

impl Report {
    /// Decode the data section of a report frame (type .. check).
    fn decode(data: &[u8]) -> Option<Self> {
        let [kind, head, target @ .., tail, check] = data else {
            return None;
        };
        if !matches!(kind, 0x01 | 0x02) || *head != 0xAA || *tail != 0x55 || *check != 0x00 {
            return None;
        }
        let t = target.get(..9)?;
        let u16_at = |i: usize| u16::from_le_bytes([t[i], t[i + 1]]);
        Some(Self {
            state: TargetState::from_byte(t[0])?,
            moving_cm: u16_at(1),
            moving_energy: t[3],
            stationary_cm: u16_at(4),
            stationary_energy: t[6],
            detection_cm: u16_at(7),
        })
    }
}

#[derive(Debug, Default)]
enum State {
    /// Looking for the header (`Parser::matched` bytes matched so far).
    #[default]
    Header,
    Length,
    Data(usize),
    Footer(usize),
}

#[derive(Debug, Default)]
pub struct Parser {
    state: State,
    matched: usize,
    length: heapless::Vec<u8, 2>,
    data: heapless::Vec<u8, MAX_DATA>,
}

impl Parser {
    pub fn new() -> Self {
        Self::default()
    }

    fn reset(&mut self) {
        *self = Self::default();
    }

    /// Feed one byte; returns a report when a complete, valid frame ends with it.
    pub fn push(&mut self, byte: u8) -> Option<Report> {
        match self.state {
            State::Header => {
                if byte == HEADER[self.matched] {
                    self.matched += 1;
                } else {
                    // A mismatch may itself start a new header.
                    self.matched = usize::from(byte == HEADER[0]);
                }
                if self.matched == HEADER.len() {
                    self.matched = 0;
                    self.state = State::Length;
                }
            }
            State::Length => {
                let _ = self.length.push(byte);
                if let [lo, hi] = self.length[..] {
                    let len = usize::from(u16::from_le_bytes([lo, hi]));
                    if (MIN_DATA..=MAX_DATA).contains(&len) {
                        self.state = State::Data(len);
                    } else {
                        self.reset();
                    }
                }
            }
            State::Data(len) => {
                let _ = self.data.push(byte);
                if self.data.len() == len {
                    self.state = State::Footer(0);
                }
            }
            State::Footer(i) => {
                if byte != FOOTER[i] {
                    self.reset();
                    return self.push(byte);
                }
                if i + 1 < FOOTER.len() {
                    self.state = State::Footer(i + 1);
                } else {
                    let report = Report::decode(&self.data);
                    self.reset();
                    return report;
                }
            }
        }
        None
    }
}
