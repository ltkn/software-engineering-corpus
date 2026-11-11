use std::collections::VecDeque;

pub struct RingBuffer<T> {
    buf: VecDeque<T>,
    cap: usize,
}

impl<T> RingBuffer<T> {
    pub fn with_capacity(capacity: usize) -> Self {
        assert!(capacity > 0, "capacity must be > 0");
        Self { buf: VecDeque::with_capacity(capacity), cap: capacity }
    }
    pub fn push(&mut self, value: T) -> Option<T> {
        let old = if self.buf.len() == self.cap { self.buf.pop_front() } else { None };
        self.buf.push_back(value);
        old
    }
    pub fn pop(&mut self) -> Option<T> {
        self.buf.pop_front()
    }
    pub fn len(&self) -> usize {
        self.buf.len()
    }
    pub fn iter(&self) -> impl Iterator<Item = &T> {
        self.buf.iter()
    }
}
