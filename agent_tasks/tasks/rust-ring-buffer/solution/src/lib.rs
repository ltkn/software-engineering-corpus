//! A fixed-capacity FIFO buffer that overwrites its oldest element when full.

#![forbid(unsafe_code)]

use std::collections::VecDeque;

#[derive(Debug, Clone)]
pub struct RingBuffer<T> {
    items: VecDeque<T>,
    capacity: usize,
}

impl<T> RingBuffer<T> {
    /// Create an empty buffer. Panics if `capacity` is zero.
    pub fn with_capacity(capacity: usize) -> Self {
        assert!(capacity > 0, "capacity must be greater than zero");
        Self {
            items: VecDeque::with_capacity(capacity),
            capacity,
        }
    }

    /// Append; if full, overwrite and return the oldest element.
    pub fn push(&mut self, value: T) -> Option<T> {
        let evicted = if self.items.len() == self.capacity {
            self.items.pop_front()
        } else {
            None
        };
        self.items.push_back(value);
        evicted
    }

    /// Remove and return the oldest element.
    pub fn pop(&mut self) -> Option<T> {
        self.items.pop_front()
    }

    pub fn len(&self) -> usize {
        self.items.len()
    }

    pub fn is_empty(&self) -> bool {
        self.items.is_empty()
    }

    pub fn capacity(&self) -> usize {
        self.capacity
    }

    /// Iterate from oldest to newest.
    pub fn iter(&self) -> impl Iterator<Item = &T> {
        self.items.iter()
    }
}
