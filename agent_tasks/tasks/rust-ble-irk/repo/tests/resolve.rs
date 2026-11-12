use irk::{BdAddr, Irk, ah, identify, resolves};

const IRK_A: Irk = Irk([
    0xec, 0x02, 0x34, 0xa3, 0x57, 0xc8, 0xad, 0x05, 0x34, 0x10, 0x10, 0xa6, 0x0a, 0x39, 0x7d, 0x9b,
]);
const IRK_B: Irk = Irk([
    0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff,
]);

fn reversed<const N: usize>(mut bytes: [u8; N]) -> [u8; N] {
    bytes.reverse();
    bytes
}

#[test]
fn spec_sample_data() {
    // Core spec, Vol 3, Part H, D.7: ah(IRK, 0x708194) = 0x0dfbaa
    assert_eq!(ah(&IRK_A, [0x70, 0x81, 0x94]), [0x0d, 0xfb, 0xaa]);
}

#[test]
fn resolves_its_own_addresses_only() {
    let addr = BdAddr([0x70, 0x81, 0x94, 0x0d, 0xfb, 0xaa]);
    assert!(addr.is_resolvable_private());
    assert!(resolves(&IRK_A, &addr));
    assert!(!resolves(&IRK_B, &addr));
    assert!(!resolves(
        &IRK_A,
        &BdAddr([0x70, 0x81, 0x94, 0x0d, 0xfb, 0xab])
    ));
    assert!(resolves(
        &IRK_A,
        &BdAddr([0x4a, 0x1b, 0x2c, 0xa4, 0x90, 0xbb])
    ));
    assert!(resolves(
        &IRK_B,
        &BdAddr([0x6f, 0x0e, 0x0d, 0x50, 0xbd, 0x91])
    ));
}

#[test]
fn only_resolvable_private_addresses_resolve() {
    // Same prand bits, but the two most significant bits are not 0b01.
    for msb in [0x30, 0xb0, 0xf0] {
        let addr = BdAddr([msb, 0x81, 0x94, 0x0d, 0xfb, 0xaa]);
        assert!(!addr.is_resolvable_private(), "{addr:?}");
        assert!(!resolves(&IRK_A, &addr), "{addr:?}");
    }
}

#[test]
fn little_endian_inputs() {
    let addr = BdAddr::from_le_bytes([0xaa, 0xfb, 0x0d, 0x94, 0x81, 0x70]);
    assert_eq!(addr, BdAddr([0x70, 0x81, 0x94, 0x0d, 0xfb, 0xaa]));
    assert!(resolves(&Irk::from_le_bytes(reversed(IRK_A.0)), &addr));
}

#[test]
fn identifies_the_right_device() {
    let bonded = [("alice-phone", IRK_B), ("bob-watch", IRK_A)];
    let a = BdAddr([0x4a, 0x1b, 0x2c, 0x83, 0xa6, 0x3e]);
    let b = BdAddr([0x4a, 0x1b, 0x2c, 0xa4, 0x90, 0xbb]);
    assert_eq!(identify(&a, &bonded), Some(&"alice-phone"));
    assert_eq!(identify(&b, &bonded), Some(&"bob-watch"));
    assert_eq!(identify(&BdAddr([0x55, 1, 2, 3, 4, 5]), &bonded), None);
    assert_eq!(identify::<&str>(&b, &[]), None);
}
