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
    pub fn from_le_bytes(mut le: [u8; 6]) -> Self {
        le.reverse();
        BdAddr(le)
    }

    /// True for a resolvable private address: the two most significant bits are `0b01`.
    pub fn is_resolvable_private(&self) -> bool {
        self.0[0] >> 6 == 0b01
    }

    /// The 24-bit random part (`prand`), most significant byte first.
    fn prand(&self) -> [u8; 3] {
        [self.0[0], self.0[1], self.0[2]]
    }

    /// The 24-bit hash, most significant byte first.
    fn hash(&self) -> [u8; 3] {
        [self.0[3], self.0[4], self.0[5]]
    }
}

/// An Identity Resolving Key, most significant byte first (as printed in the spec).
#[derive(Clone, Copy, PartialEq, Eq)]
pub struct Irk(pub [u8; 16]);

impl Irk {
    /// From the little-endian order NimBLE stores keys in.
    pub fn from_le_bytes(mut le: [u8; 16]) -> Self {
        le.reverse();
        Irk(le)
    }
}

/// The random address hash function `ah(k, r) = e(k, padding || r) mod 2^24`.
///
/// `e` is AES-128 with the most significant octet first, so the 13 zero padding
/// octets come before `r` and the result is the last three octets.
pub fn ah(irk: &Irk, prand: [u8; 3]) -> [u8; 3] {
    let cipher = Aes128::new(&irk.0.into());
    let mut plaintext = [0u8; 16];
    plaintext[13..].copy_from_slice(&prand);
    let mut block = plaintext.into();
    cipher.encrypt_block(&mut block);
    [block[13], block[14], block[15]]
}

/// Does `addr` resolve with `irk`? Only resolvable private addresses can.
pub fn resolves(irk: &Irk, addr: &BdAddr) -> bool {
    addr.is_resolvable_private() && ah(irk, addr.prand()) == addr.hash()
}

/// The bonded device whose IRK resolves `addr`, if any.
pub fn identify<'a, T>(addr: &BdAddr, bonded: &'a [(T, Irk)]) -> Option<&'a T> {
    if !addr.is_resolvable_private() {
        return None;
    }
    bonded
        .iter()
        .find(|(_, irk)| resolves(irk, addr))
        .map(|(device, _)| device)
}
