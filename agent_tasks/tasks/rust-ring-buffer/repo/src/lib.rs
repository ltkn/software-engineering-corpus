//! A fixed-capacity FIFO buffer that overwrites its oldest element when full.

#![forbid(unsafe_code)]

#[derive(Debug, Clone)]
pub struct RingBuffer<T> {
    _marker: std::marker::PhantomData<T>,
}

impl<T> RingBuffer<T> {
    /// Create an empty buffer. Panics if `capacity` is zero.
    pub fn with_capacity(capacity: usize) -> Self {
        todo!()
    }

    /// Append; if full, overwrite and return the oldest element.
    pub fn push(&mut self, value: T) -> Option<T> {
        todo!()
    }

    /// Remove and return the oldest element.
    pub fn pop(&mut self) -> Option<T> {
        todo!()
    }

    pub fn len(&self) -> usize {
        todo!()
    }

    pub fn is_empty(&self) -> bool {
        todo!()
    }

    pub fn capacity(&self) -> usize {
        todo!()
    }

    /// Iterate from oldest to newest.
    pub fn iter(&self) -> impl Iterator<Item = &T> {
        std::iter::empty()
    }
}
