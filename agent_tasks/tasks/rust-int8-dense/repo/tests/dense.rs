use tinyml::{Dense, multiply_by_quantized_multiplier, quantize_multiplier};

const N_IN: usize = 16;
const N_OUT: usize = 4;
const WEIGHTS: [i8; N_IN * N_OUT] = [
    -45, 115, -89, -26, 39, -115, -109, 83, 10, -103, -34, 22, -113, 105, 2, -73, -118, -105, -16,
    -20, -110, -66, -104, 14, -19, -112, 84, 17, -96, 115, -70, 34, 33, 22, 115, -112, 20, 22, -26,
    -115, 122, -71, -116, 15, 92, -93, -53, -20, -91, 11, -97, 19, -49, 16, 81, 47, -81, -101, 21,
    19, 36, -79, -32, -103,
];
const BIAS: [i32; N_OUT] = [1487, 2833, -2486, 1623];

fn layer(act_min: i8) -> Dense<'static> {
    let (multiplier, shift) = quantize_multiplier(0.0071);
    Dense {
        weights: &WEIGHTS,
        bias: &BIAS,
        inputs: N_IN,
        input_offset: 5,
        output_offset: 3,
        multiplier,
        shift,
        act_min,
        act_max: 127,
    }
}

#[test]
fn quantized_multipliers_match_tflite() {
    for (real, q, shift) in [
        (0.5, 1073741824, 0),
        (1.0, 1073741824, 1),
        (0.0071, 1951633139, -7),
        (0.000123, 1081919442, -12),
        (1.5, 1610612736, 1),
        (0.99999999999, 1073741824, 1),
    ] {
        assert_eq!(quantize_multiplier(real), (q, shift), "real {real}");
    }
    assert_eq!(quantize_multiplier(0.0), (0, 0));
}

#[test]
fn fixed_point_multiply_rounds_like_tflite() {
    for (x, q, shift, expected) in [
        (1000, 1951633139, -7, 7),
        (-1000, 1951633139, -7, -7),
        (123456, 1073741824, 0, 61728),
        (-7, 1073741824, -1, -2),
        (-6, 1073741824, -1, -2),
        (5, 1073741824, -1, 2),
        (2000000000, 2000000000, 0, 1862645149),
        (-2147483648, -2147483648, 0, 2147483647),
        (300, 1073741824, 3, 1200),
    ] {
        assert_eq!(
            multiply_by_quantized_multiplier(x, q, shift),
            expected,
            "x={x} q={q} shift={shift}"
        );
    }
}

#[test]
fn dense_is_bit_exact() {
    let inputs: [[i8; N_IN]; 3] = [
        [
            -98, -23, 126, 90, 32, 110, 104, 57, 25, -1, -36, -4, -87, 25, 125, 47,
        ],
        [
            101, 19, -91, -68, 86, -44, 47, -51, 122, 87, -108, -89, 32, 46, 51, 126,
        ],
        [
            105, -93, -81, 10, 114, -95, -97, 30, 100, 17, 69, 49, -117, 108, 53, -42,
        ],
    ];
    let expected: [[i8; N_OUT]; 3] = [
        [-128, -68, -128, -51],
        [-50, -128, 119, -128],
        [127, 127, -128, -128],
    ];
    let relu: [[i8; N_OUT]; 3] = [[3, 3, 3, 3], [3, 3, 119, 3], [127, 127, 3, 3]];
    for i in 0..3 {
        let mut out = [0i8; N_OUT];
        layer(-128).forward(&inputs[i], &mut out);
        assert_eq!(out, expected[i], "input {i}");
        layer(3).forward(&inputs[i], &mut out);
        assert_eq!(out, relu[i], "input {i} with ReLU");
    }
}

#[test]
fn saturates_instead_of_wrapping() {
    let mut out = [0i8; N_OUT];
    layer(-128).forward(&[127; N_IN], &mut out);
    let expected: [i8; N_OUT] = [-128, -128, -128, -128];
    assert_eq!(out, expected);
}

#[test]
#[should_panic]
fn wrong_lengths_panic() {
    let mut out = [0i8; N_OUT];
    layer(-128).forward(&[0; N_IN - 1], &mut out);
}
