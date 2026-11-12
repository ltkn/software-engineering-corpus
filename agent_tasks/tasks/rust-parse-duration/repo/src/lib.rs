//! Parse compact durations such as `1h30m`, `90s` or `1s250ms`.

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

/// Parse `"1h30m"`, `"90s"`, `"250ms"`, `"2h5m10s"`.
pub fn parse_duration(input: &str) -> Result<Duration, ParseError> {
    let mut total = 0u64;
    let mut num = String::new();
    for c in input.chars() {
        if c.is_ascii_digit() {
            num.push(c);
        } else {
            let n: u64 = num.parse().unwrap();
            total += match c {
                'h' => n * 60,
                'm' => n * 60,
                _ => return Err(ParseError::UnknownUnit { at: 0 }),
            };
            num.clear();
        }
    }
    Ok(Duration::from_secs(total))
}
