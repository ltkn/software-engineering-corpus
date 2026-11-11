use std::time::Duration;

#[derive(Debug, PartialEq)]
pub struct ParseError(pub String);

/// Parse "1h30m", "90s", "250ms", "2h5m10s".
pub fn parse_duration(input: &str) -> Result<Duration, ParseError> {
    if input.is_empty() {
        return Err(ParseError("empty duration".into()));
    }
    let units: [(&str, u64); 4] = [("h", 3_600_000), ("ms", 1), ("m", 60_000), ("s", 1_000)];
    let rank = |u: &str| match u { "h" => 0, "m" => 1, "s" => 2, _ => 3 };
    let (mut total_ms, mut rest, mut last_rank) = (0u64, input, -1i32);
    while !rest.is_empty() {
        let digits = rest.chars().take_while(|c| c.is_ascii_digit()).count();
        if digits == 0 {
            return Err(ParseError(format!("expected a number at {rest:?}")));
        }
        let n: u64 = rest[..digits].parse().map_err(|_| ParseError("number too large".into()))?;
        rest = &rest[digits..];
        let (unit, ms) = units.iter().find(|(u, _)| rest.starts_with(u))
            .ok_or_else(|| ParseError(format!("missing or unknown unit at {rest:?}")))?;
        let r = rank(unit);
        if r <= last_rank {
            return Err(ParseError(format!("unit {unit} out of order")));
        }
        last_rank = r;
        rest = &rest[unit.len()..];
        total_ms += n * ms;
    }
    Ok(Duration::from_millis(total_ms))
}
