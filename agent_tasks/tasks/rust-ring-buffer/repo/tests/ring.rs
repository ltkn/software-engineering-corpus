use ring::RingBuffer;

#[test]
fn fifo_and_overwrite() {
    let mut r = RingBuffer::with_capacity(3);
    assert!(r.is_empty());
    assert_eq!(r.push(1), None);
    assert_eq!(r.push(2), None);
    assert_eq!(r.push(3), None);
    assert_eq!(r.push(4), Some(1));
    assert_eq!(r.iter().copied().collect::<Vec<_>>(), vec![2, 3, 4]);
    assert_eq!(r.pop(), Some(2));
    assert_eq!(r.len(), 2);
    assert!(!r.is_empty());
}

#[test]
fn wraps_many_times_without_growing() {
    let mut r = RingBuffer::with_capacity(4);
    for i in 0..1000 {
        r.push(i);
    }
    assert_eq!(r.capacity(), 4);
    assert_eq!(
        r.iter().copied().collect::<Vec<_>>(),
        vec![996, 997, 998, 999]
    );
    while r.pop().is_some() {}
    assert!(r.is_empty());
}

#[test]
fn works_with_owned_values() {
    let mut r = RingBuffer::with_capacity(2);
    r.push(String::from("a"));
    r.push(String::from("b"));
    assert_eq!(r.push(String::from("c")).as_deref(), Some("a"));
}

#[test]
#[should_panic(expected = "capacity")]
fn zero_capacity_panics() {
    let _ = RingBuffer::<u8>::with_capacity(0);
}
