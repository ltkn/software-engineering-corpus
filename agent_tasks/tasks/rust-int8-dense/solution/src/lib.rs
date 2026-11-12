//! int8 inference kernels for microcontrollers.

#![cfg_attr(not(test), no_std)]
#![forbid(unsafe_code)]

/// A real multiplier as `q * 2^(shift - 31)` with `q` in Q31, like TFLite's QuantizeMultiplier.
///
/// Uses the bits of the `f64` directly (frexp and round), so it needs no float library in `no_std`.
pub fn quantize_multiplier(real: f64) -> (i32, i32) {
    assert!(
        real >= 0.0 && real.is_finite(),
        "multiplier must be finite and non-negative"
    );
    let bits = real.to_bits();
    let exponent_field = ((bits >> 52) & 0x7FF) as i32;
    if exponent_field == 0 {
        return (0, 0); // zero or subnormal: far below what Q31 with shift >= -31 can hold
    }
    // real = mantissa * 2^shift with mantissa in [0.5, 1); mantissa * 2^53 is this integer.
    let mantissa = (bits & ((1 << 52) - 1)) | (1 << 52);
    let mut shift = exponent_field - 1022;
    // round(mantissa * 2^31), half away from zero.
    let mut q = (mantissa + (1 << 21)) >> 22;
    if q == 1 << 31 {
        q /= 2;
        shift += 1;
    }
    if shift < -31 {
        return (0, 0);
    }
    (i32::try_from(q).expect("q < 2^31"), shift)
}

/// High 32 bits of `2 * a * b`, rounded, saturating the single overflow case.
fn saturating_rounding_doubling_high_mul(a: i32, b: i32) -> i32 {
    if a == i32::MIN && b == i32::MIN {
        return i32::MAX;
    }
    let ab = i64::from(a) * i64::from(b);
    let nudge = if ab >= 0 { 1 << 30 } else { 1 - (1 << 30) };
    // Integer division truncates toward zero, as in the reference implementation.
    ((ab + nudge) / (1i64 << 31)) as i32
}

/// `x / 2^exponent`, rounded half away from zero.
fn rounding_divide_by_pot(x: i32, exponent: i32) -> i32 {
    let mask = ((1i64 << exponent) - 1) as i32;
    let remainder = x & mask;
    let threshold = (mask >> 1) + i32::from(x < 0);
    (x >> exponent) + i32::from(remainder > threshold)
}

/// `x * q * 2^(shift - 31)`, rounded like TFLite.
pub fn multiply_by_quantized_multiplier(x: i32, q: i32, shift: i32) -> i32 {
    let (left, right) = if shift > 0 { (shift, 0) } else { (0, -shift) };
    rounding_divide_by_pot(
        saturating_rounding_doubling_high_mul(x * (1 << left), q),
        right,
    )
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
        assert_eq!(input.len(), self.inputs, "input length");
        assert_eq!(
            self.weights.len(),
            self.inputs * output.len(),
            "weights shape"
        );
        assert_eq!(self.bias.len(), output.len(), "bias length");
        let rows = self.weights.chunks_exact(self.inputs);
        for ((out, row), &bias) in output.iter_mut().zip(rows).zip(self.bias) {
            let acc = row.iter().zip(input).fold(bias, |acc, (&w, &x)| {
                acc + (i32::from(x) + self.input_offset) * i32::from(w)
            });
            let scaled = multiply_by_quantized_multiplier(acc, self.multiplier, self.shift);
            let clamped = (scaled + self.output_offset)
                .clamp(i32::from(self.act_min), i32::from(self.act_max));
            *out = i8::try_from(clamped).expect("clamped to the i8 activation range");
        }
    }
}
