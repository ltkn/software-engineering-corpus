use duration::{ParseError, parse_duration};
use std::time::Duration;

#[test]
fn combinations() {
    assert_eq!(parse_duration("1h30m"), Ok(Duration::from_secs(5400)));
    assert_eq!(parse_duration("90s"), Ok(Duration::from_secs(90)));
    assert_eq!(parse_duration("2h5m10s"), Ok(Duration::from_secs(7510)));
    assert_eq!(parse_duration("1s250ms"), Ok(Duration::from_millis(1250)));
    assert_eq!(parse_duration("1m250ms"), Ok(Duration::from_millis(60_250)));
    assert_eq!(parse_duration("0s"), Ok(Duration::ZERO));
}

#[test]
fn errors_name_the_problem() {
    use ParseError::*;
    let cases = [
        ("", Empty),
        ("h", MissingNumber { at: 0 }),
        ("1h-5m", MissingNumber { at: 2 }),
        ("10", UnknownUnit { at: 2 }),
        ("10x", UnknownUnit { at: 2 }),
        ("1.5h", UnknownUnit { at: 1 }),
        ("5m1h", OutOfOrder { unit: "h" }),
        ("1m1m", OutOfOrder { unit: "m" }),
        ("1ms1s", OutOfOrder { unit: "s" }),
        ("99999999999999999999h", Overflow),
        ("5124095576030432h", Overflow),
    ];
    for (input, expected) in cases {
        assert_eq!(parse_duration(input), Err(expected), "input {input:?}");
    }
}

#[test]
fn error_is_a_std_error_with_a_message() {
    let err: Box<dyn std::error::Error> = Box::new(parse_duration("10x").unwrap_err());
    assert!(!err.to_string().is_empty());
    assert_ne!(
        err.to_string(),
        format!("{err:?}"),
        "Display should be written for humans"
    );
}
