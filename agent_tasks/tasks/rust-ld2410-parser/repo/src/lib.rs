//! Parse HLK-LD2410 radar report frames from a UART byte stream.

#![cfg_attr(not(test), no_std)]
#![forbid(unsafe_code)]

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TargetState {
    None,
    Moving,
    Stationary,
    MovingAndStationary,
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

#[derive(Default)]
pub struct Parser {
    buf: heapless::Vec<u8, 23>,
}

impl Parser {
    pub fn new() -> Self {
        Self::default()
    }

    /// Feed one byte; returns a report when a complete, valid frame ends with it.
    pub fn push(&mut self, byte: u8) -> Option<Report> {
        if self.buf.is_empty() && byte != 0xF4 {
            return None;
        }
        let _ = self.buf.push(byte);
        if self.buf.len() < 23 {
            return None;
        }
        let f = core::mem::take(&mut self.buf);
        let state = match f[8] {
            1 => TargetState::Moving,
            2 => TargetState::Stationary,
            3 => TargetState::MovingAndStationary,
            _ => TargetState::None,
        };
        Some(Report {
            state,
            moving_cm: u16::from_le_bytes([f[9], f[10]]),
            moving_energy: f[11],
            stationary_cm: u16::from_le_bytes([f[12], f[13]]),
            stationary_energy: f[14],
            detection_cm: u16::from_le_bytes([f[15], f[16]]),
        })
    }
}
