use std::time::Duration;

#[derive(Debug, PartialEq)]
pub struct ParseError(pub String);

/// Parse "1h30m", "90s", "250ms", "2h5m10s".
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
                _ => return Err(ParseError(format!("bad unit {c}"))),
            };
            num.clear();
        }
    }
    Ok(Duration::from_secs(total))
}
