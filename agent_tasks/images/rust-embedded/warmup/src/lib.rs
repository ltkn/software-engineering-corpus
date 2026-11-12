#![cfg_attr(not(test), no_std)]
pub fn warm() -> heapless::Vec<u8, 4> {
    heapless::Vec::new()
}
#[cfg(test)]
mod tests {
    #[test]
    fn it_builds() {
        assert!(super::warm().is_empty());
    }
}
