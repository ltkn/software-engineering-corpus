//! Driver for the Sensirion SHT4x temperature and humidity sensor.

#![cfg_attr(not(test), no_std)]
#![forbid(unsafe_code)]

use embedded_hal::delay::DelayNs;
use embedded_hal::i2c::I2c;

/// Default I2C address of the SHT40/41/45.
pub const ADDRESS: u8 = 0x44;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Measurement {
    pub temperature_milli_c: i32,
    pub humidity_milli_percent: i32,
}

#[derive(Debug, PartialEq, Eq)]
pub enum Error<E> {
    I2c(E),
    Crc,
}

/// CRC-8 used by Sensirion sensors.
pub fn crc8(data: &[u8]) -> u8 {
    todo!()
}

pub struct Sht4x<I2C, D> {
    i2c: I2C,
    delay: D,
}

impl<I2C: I2c, D: DelayNs> Sht4x<I2C, D> {
    pub fn new(i2c: I2C, delay: D) -> Self {
        Self { i2c, delay }
    }

    pub fn measure(&mut self) -> Result<Measurement, Error<I2C::Error>> {
        let mut buf = [0u8; 6];
        self.i2c.write(ADDRESS, &[0xFD]).unwrap();
        self.i2c.read(ADDRESS, &mut buf).unwrap();
        let t = u16::from_be_bytes([buf[0], buf[1]]) as i32;
        let h = u16::from_be_bytes([buf[3], buf[4]]) as i32;
        Ok(Measurement {
            temperature_milli_c: -45 + 175 * t / 65535,
            humidity_milli_percent: -6 + 125 * h / 65535,
        })
    }

    pub fn serial_number(&mut self) -> Result<u32, Error<I2C::Error>> {
        todo!()
    }

    /// Give the bus and the delay back.
    pub fn release(self) -> (I2C, D) {
        (self.i2c, self.delay)
    }
}
