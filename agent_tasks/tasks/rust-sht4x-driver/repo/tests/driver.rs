use embedded_hal::delay::DelayNs;
use embedded_hal::i2c::ErrorKind;
use embedded_hal_mock::eh1::i2c::{Mock, Transaction};
use sht4x::{ADDRESS, Error, Measurement, Sht4x, crc8};

/// Records how long the driver waited.
#[derive(Default)]
struct Waited(u64);

impl DelayNs for Waited {
    fn delay_ns(&mut self, ns: u32) {
        self.0 += u64::from(ns);
    }
}

fn word(value: u16) -> [u8; 3] {
    let [hi, lo] = value.to_be_bytes();
    [hi, lo, crc8(&[hi, lo])]
}

fn reading(t: u16, h: u16) -> Vec<u8> {
    [word(t), word(h)].concat()
}

#[test]
fn crc_matches_the_datasheet_example() {
    assert_eq!(crc8(&[0xBE, 0xEF]), 0x92);
    assert_eq!(crc8(&[0x00, 0x00]), 0x81);
}

#[test]
fn measures_with_integer_conversion() {
    let i2c = Mock::new(&[
        Transaction::write(ADDRESS, vec![0xFD]),
        Transaction::read(ADDRESS, reading(0x6666, 0x8000)),
    ]);
    let mut sensor = Sht4x::new(i2c, Waited::default());
    let m = sensor.measure().unwrap();
    assert!((m.temperature_milli_c - 24_999).abs() <= 1, "{m:?}");
    assert!((m.humidity_milli_percent - 56_500).abs() <= 1, "{m:?}");
    let (mut i2c, waited) = sensor.release();
    assert!(waited.0 >= 8_300_000, "waited only {} ns", waited.0);
    i2c.done();
}

#[test]
fn humidity_is_clamped() {
    let i2c = Mock::new(&[
        Transaction::write(ADDRESS, vec![0xFD]),
        Transaction::read(ADDRESS, reading(0x0000, 0xFFFF)),
        Transaction::write(ADDRESS, vec![0xFD]),
        Transaction::read(ADDRESS, reading(0xFFFF, 0x0000)),
    ]);
    let mut sensor = Sht4x::new(i2c, Waited::default());
    assert_eq!(
        sensor.measure().unwrap(),
        Measurement {
            temperature_milli_c: -45_000,
            humidity_milli_percent: 100_000
        }
    );
    assert_eq!(
        sensor.measure().unwrap(),
        Measurement {
            temperature_milli_c: 130_000,
            humidity_milli_percent: 0
        }
    );
    sensor.release().0.done();
}

#[test]
fn bad_crc_is_an_error() {
    let mut bytes = reading(0x6666, 0x8000);
    bytes[5] ^= 0xFF;
    let i2c = Mock::new(&[
        Transaction::write(ADDRESS, vec![0xFD]),
        Transaction::read(ADDRESS, bytes),
    ]);
    let mut sensor = Sht4x::new(i2c, Waited::default());
    assert_eq!(sensor.measure(), Err(Error::Crc));
    sensor.release().0.done();
}

#[test]
fn bus_errors_are_returned_not_panicked() {
    let i2c = Mock::new(&[Transaction::write(ADDRESS, vec![0xFD]).with_error(ErrorKind::Other)]);
    let mut sensor = Sht4x::new(i2c, Waited::default());
    assert_eq!(sensor.measure(), Err(Error::I2c(ErrorKind::Other)));
    sensor.release().0.done();
}

#[test]
fn reads_the_serial_number() {
    let i2c = Mock::new(&[
        Transaction::write(ADDRESS, vec![0x89]),
        Transaction::read(ADDRESS, [word(0x1234), word(0xABCD)].concat()),
    ]);
    let mut sensor = Sht4x::new(i2c, Waited::default());
    assert_eq!(sensor.serial_number(), Ok(0x1234_ABCD));
    sensor.release().0.done();
}
