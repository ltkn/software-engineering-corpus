//! Driver for the Sensirion SHT4x temperature and humidity sensor.

#![cfg_attr(not(test), no_std)]
#![forbid(unsafe_code)]

use embedded_hal::delay::DelayNs;
use embedded_hal::i2c::I2c;

/// Default I2C address of the SHT40/41/45.
pub const ADDRESS: u8 = 0x44;

const MEASURE_HIGH_PRECISION: u8 = 0xFD;
const READ_SERIAL: u8 = 0x89;
/// Datasheet maximum for a high-precision measurement is 8.3 ms.
const MEASURE_WAIT_US: u32 = 8_300;
const SERIAL_WAIT_US: u32 = 1_000;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Measurement {
    pub temperature_milli_c: i32,
    pub humidity_milli_percent: i32,
}

#[derive(Debug, PartialEq, Eq)]
pub enum Error<E> {
    /// The I2C bus reported an error.
    I2c(E),
    /// A word's checksum did not match: the data is corrupt.
    Crc,
}

/// CRC-8 used by Sensirion sensors: polynomial 0x31, init 0xFF, no reflection.
pub fn crc8(data: &[u8]) -> u8 {
    data.iter().fold(0xFF, |crc, &byte| {
        (0..8).fold(crc ^ byte, |c, _| {
            if c & 0x80 != 0 {
                (c << 1) ^ 0x31
            } else {
                c << 1
            }
        })
    })
}

/// Two 16-bit words, each followed by its CRC.
fn words<E>(buf: &[u8; 6]) -> Result<[u16; 2], Error<E>> {
    let word = |chunk: &[u8]| {
        if crc8(&chunk[..2]) == chunk[2] {
            Ok(u16::from_be_bytes([chunk[0], chunk[1]]))
        } else {
            Err(Error::Crc)
        }
    };
    Ok([word(&buf[..3])?, word(&buf[3..])?])
}

/// `offset + span * raw / 65535`, in thousandths, with 64-bit intermediate math.
fn scale(raw: u16, offset: i32, span: i64) -> i32 {
    let scaled = span * i64::from(raw) / 65_535;
    offset + i32::try_from(scaled).expect("span * raw / 65535 fits in i32")
}

pub struct Sht4x<I2C, D> {
    i2c: I2C,
    delay: D,
}

impl<I2C: I2c, D: DelayNs> Sht4x<I2C, D> {
    pub fn new(i2c: I2C, delay: D) -> Self {
        Self { i2c, delay }
    }

    fn command(&mut self, command: u8, wait_us: u32) -> Result<[u16; 2], Error<I2C::Error>> {
        self.i2c.write(ADDRESS, &[command]).map_err(Error::I2c)?;
        self.delay.delay_us(wait_us);
        let mut buf = [0u8; 6];
        self.i2c.read(ADDRESS, &mut buf).map_err(Error::I2c)?;
        words(&buf)
    }

    pub fn measure(&mut self) -> Result<Measurement, Error<I2C::Error>> {
        let [t, h] = self.command(MEASURE_HIGH_PRECISION, MEASURE_WAIT_US)?;
        Ok(Measurement {
            temperature_milli_c: scale(t, -45_000, 175_000),
            humidity_milli_percent: scale(h, -6_000, 125_000).clamp(0, 100_000),
        })
    }

    pub fn serial_number(&mut self) -> Result<u32, Error<I2C::Error>> {
        let [hi, lo] = self.command(READ_SERIAL, SERIAL_WAIT_US)?;
        Ok((u32::from(hi) << 16) | u32::from(lo))
    }

    /// Give the bus and the delay back.
    pub fn release(self) -> (I2C, D) {
        (self.i2c, self.delay)
    }
}
