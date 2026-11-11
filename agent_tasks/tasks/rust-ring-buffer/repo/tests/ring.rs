use ring::RingBuffer;

#[test]
fn fifo_and_overwrite() {
    let mut r = RingBuffer::with_capacity(3);
    assert_eq!(r.push(1), None);
    assert_eq!(r.push(2), None);
    assert_eq!(r.push(3), None);
    assert_eq!(r.push(4), Some(1));
    assert_eq!(r.iter().copied().collect::<Vec<_>>(), vec![2, 3, 4]);
    assert_eq!(r.pop(), Some(2));
    assert_eq!(r.len(), 2);
}

#[test]
fn wraps_many_times() {
    let mut r = RingBuffer::with_capacity(4);
    for i in 0..1000 { r.push(i); }
    assert_eq!(r.iter().copied().collect::<Vec<_>>(), vec![996, 997, 998, 999]);
    while r.pop().is_some() {}
    assert_eq!(r.len(), 0);
}

#[test]
#[should_panic]
fn zero_capacity_panics() {
    let _ = RingBuffer::<u8>::with_capacity(0);
}
