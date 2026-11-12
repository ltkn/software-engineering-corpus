//! int8 inference kernels for microcontrollers.

#![cfg_attr(not(test), no_std)]
#![forbid(unsafe_code)]

/// A real multiplier as `q * 2^(shift - 31)` with `q` in Q31.
pub fn quantize_multiplier(real: f64) -> (i32, i32) {
    let mut shift = 0;
    let mut m = real;
    while m != 0.0 && m < 0.5 {
        m *= 2.0;
        shift -= 1;
    }
    ((m * 2147483648.0) as i32, shift)
}

/// `x * q * 2^(shift - 31)`, rounded like TFLite.
pub fn multiply_by_quantized_multiplier(x: i32, q: i32, shift: i32) -> i32 {
    ((x as f64) * (q as f64) * 2f64.powi(shift - 31)) as i32
}

/// A fully connected layer with per-tensor int8 quantization (symmetric weights).
pub struct Dense<'a> {
    /// `outputs x inputs`, row-major.
    pub weights: &'a [i8],
    pub bias: &'a [i32],
    pub inputs: usize,
    /// Minus the input zero point.
    pub input_offset: i32,
    /// The output zero point.
    pub output_offset: i32,
    pub multiplier: i32,
    pub shift: i32,
    pub act_min: i8,
    pub act_max: i8,
}

impl Dense<'_> {
    pub fn forward(&self, input: &[i8], output: &mut [i8]) {
        todo!()
    }
}
