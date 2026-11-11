pub struct RingBuffer<T> {
    _marker: std::marker::PhantomData<T>,
}

impl<T> RingBuffer<T> {
    pub fn with_capacity(capacity: usize) -> Self {
        todo!()
    }
    /// Append; if full, overwrite and return the oldest element.
    pub fn push(&mut self, value: T) -> Option<T> {
        todo!()
    }
    pub fn pop(&mut self) -> Option<T> {
        todo!()
    }
    pub fn len(&self) -> usize {
        todo!()
    }
    pub fn iter(&self) -> impl Iterator<Item = &T> {
        std::iter::empty()
    }
}
