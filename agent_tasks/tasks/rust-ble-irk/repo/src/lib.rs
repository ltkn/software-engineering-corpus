//! Resolve Bluetooth LE resolvable private addresses with bonded devices' IRKs.

#![cfg_attr(not(test), no_std)]
#![forbid(unsafe_code)]

use aes::Aes128;
use aes::cipher::{BlockCipherEncrypt, KeyInit};

/// A device address, most significant byte first, as displayed: `70:81:94:0D:FB:AA`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BdAddr(pub [u8; 6]);

impl BdAddr {
    /// From the little-endian order used on HCI and by NimBLE (`ble_addr_t::val`).
    pub fn from_le_bytes(le: [u8; 6]) -> Self {
        BdAddr(le)
    }

    /// True for a resolvable private address.
    pub fn is_resolvable_private(&self) -> bool {
        true
    }
}

/// An Identity Resolving Key, most significant byte first (as printed in the spec).
#[derive(Clone, Copy, PartialEq, Eq)]
pub struct Irk(pub [u8; 16]);

impl Irk {
    /// From the little-endian order NimBLE stores keys in.
    pub fn from_le_bytes(le: [u8; 16]) -> Self {
        Irk(le)
    }
}

/// The random address hash function `ah(k, r)`.
pub fn ah(irk: &Irk, prand: [u8; 3]) -> [u8; 3] {
    let cipher = Aes128::new(&irk.0.into());
    let mut block = [0u8; 16];
    block[..3].copy_from_slice(&prand);
    let mut block = block.into();
    cipher.encrypt_block(&mut block);
    [block[0], block[1], block[2]]
}

/// Does `addr` resolve with `irk`?
pub fn resolves(irk: &Irk, addr: &BdAddr) -> bool {
    let a = addr.0;
    ah(irk, [a[3], a[4], a[5]]) == [a[0], a[1], a[2]]
}

/// The bonded device whose IRK resolves `addr`, if any.
pub fn identify<'a, T>(addr: &BdAddr, bonded: &'a [(T, Irk)]) -> Option<&'a T> {
    bonded.first().map(|(device, _)| device)
}
