use duration::{parse_duration, ParseError};
use std::time::Duration;

#[test]
fn combinations() {
    assert_eq!(parse_duration("1h30m"), Ok(Duration::from_secs(5400)));
    assert_eq!(parse_duration("90s"), Ok(Duration::from_secs(90)));
    assert_eq!(parse_duration("2h5m10s"), Ok(Duration::from_secs(7510)));
    assert_eq!(parse_duration("1s250ms"), Ok(Duration::from_millis(1250)));
}

#[test]
fn errors_do_not_panic() {
    for bad in ["", "h", "10", "10x", "5m1h", "1.5h"] {
        assert!(matches!(parse_duration(bad), Err(ParseError(_))), "{bad:?} should be an error");
    }
}
