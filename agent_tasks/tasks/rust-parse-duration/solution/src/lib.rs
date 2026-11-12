//! Parse compact durations such as `1h30m`, `90s` or `1s250ms`.

use std::error::Error;
use std::fmt;
use std::time::Duration;

/// Why a duration string was rejected. `at` is a byte offset into the input.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ParseError {
    /// The input was empty.
    Empty,
    /// A unit or other character appeared where a number was expected, as in `"h"`.
    MissingNumber { at: usize },
    /// A number had no unit or an unknown one, as in `"10"` or `"10x"`.
    UnknownUnit { at: usize },
    /// A unit was repeated or came after a smaller one, as in `"5m1h"`.
    OutOfOrder { unit: &'static str },
    /// The value does not fit in a `Duration` of milliseconds held in a `u64`.
    Overflow,
}

impl fmt::Display for ParseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Empty => f.write_str("empty duration"),
            Self::MissingNumber { at } => write!(f, "expected a number at byte {at}"),
            Self::UnknownUnit { at } => write!(f, "expected a unit (h, m, s, ms) at byte {at}"),
            Self::OutOfOrder { unit } => {
                write!(f, "unit `{unit}` is repeated or comes after a smaller unit")
            }
            Self::Overflow => f.write_str("duration is too large"),
        }
    }
}

impl Error for ParseError {}

/// Units in the order they must appear, with their size in milliseconds.
const UNITS: [(&str, u64); 4] = [("h", 3_600_000), ("m", 60_000), ("s", 1_000), ("ms", 1)];

/// Parse `"1h30m"`, `"90s"`, `"250ms"`, `"2h5m10s"`.
pub fn parse_duration(input: &str) -> Result<Duration, ParseError> {
    if input.is_empty() {
        return Err(ParseError::Empty);
    }
    let mut total_ms = 0u64;
    let mut next_rank = 0;
    let mut rest = input;
    while !rest.is_empty() {
        let at = input.len() - rest.len();
        let digits = rest.bytes().take_while(u8::is_ascii_digit).count();
        if digits == 0 {
            return Err(ParseError::MissingNumber { at });
        }
        let (number, tail) = rest.split_at(digits);
        let value: u64 = number.parse().map_err(|_| ParseError::Overflow)?;
        // Longest match first, so "ms" is not read as "m" followed by "s".
        let (rank, &(unit, scale)) = UNITS
            .iter()
            .enumerate()
            .filter(|(_, (unit, _))| tail.starts_with(unit))
            .max_by_key(|(_, (unit, _))| unit.len())
            .ok_or(ParseError::UnknownUnit { at: at + digits })?;
        if rank < next_rank {
            return Err(ParseError::OutOfOrder { unit });
        }
        next_rank = rank + 1;
        total_ms = value
            .checked_mul(scale)
            .and_then(|ms| total_ms.checked_add(ms))
            .ok_or(ParseError::Overflow)?;
        rest = &tail[unit.len()..];
    }
    Ok(Duration::from_millis(total_ms))
}
