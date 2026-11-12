#include "doppler.h"

#include <algorithm>
#include <cmath>
#include <complex>

namespace {

constexpr float kSpeedOfLight = 299792458.0f;
constexpr size_t kMaxN = 1024;
constexpr float kPi = 3.14159265358979f;

// In-place iterative radix-2 FFT.
void fft(std::complex<float>* x, size_t n) {
    for (size_t i = 1, j = 0; i < n; ++i) {
        size_t bit = n >> 1;
        for (; j & bit; bit >>= 1) j ^= bit;
        j ^= bit;
        if (i < j) std::swap(x[i], x[j]);
    }
    for (size_t len = 2; len <= n; len <<= 1) {
        const float angle = -2.0f * kPi / static_cast<float>(len);
        const std::complex<float> step(std::cos(angle), std::sin(angle));
        for (size_t start = 0; start < n; start += len) {
            std::complex<float> w(1.0f, 0.0f);
            for (size_t k = 0; k < len / 2; ++k) {
                const std::complex<float> even = x[start + k];
                const std::complex<float> odd = x[start + k + len / 2] * w;
                x[start + k] = even + odd;
                x[start + k + len / 2] = even - odd;
                w *= step;
            }
        }
    }
}

bool isPowerOfTwo(size_t n) { return n >= 2 && (n & (n - 1)) == 0; }

}  // namespace

float dopplerSpeedKmh(float dopplerHz, float carrierHz) {
    return dopplerHz * kSpeedOfLight / (2.0f * carrierHz) * 3.6f;
}

DopplerResult analyze(const uint16_t* samples, size_t n, const DopplerConfig& cfg) {
    const DopplerResult none{false, 0.0f, 0.0f};
    if (!isPowerOfTwo(n) || n > kMaxN) return none;

    // Static buffers: no heap use on the device, about 12 KB.
    static std::complex<float> spectrum[kMaxN];
    static float magnitude[kMaxN / 2];
    static float sorted[kMaxN / 2];

    float mean = 0.0f;
    for (size_t i = 0; i < n; ++i) mean += samples[i];
    mean /= static_cast<float>(n);
    for (size_t i = 0; i < n; ++i) {
        const float hann = 0.5f - 0.5f * std::cos(2.0f * kPi * i / static_cast<float>(n - 1));
        spectrum[i] = {(samples[i] - mean) * hann, 0.0f};
    }
    fft(spectrum, n);

    const size_t half = n / 2;
    const float binHz = cfg.sampleRateHz / static_cast<float>(n);
    const size_t first = std::max<size_t>(1, static_cast<size_t>(std::ceil(cfg.minHz / binHz)));
    if (first + 1 >= half) return none;

    size_t peak = first;
    for (size_t k = 0; k < half; ++k) magnitude[k] = std::abs(spectrum[k]);
    for (size_t k = first; k < half - 1; ++k) {
        if (magnitude[k] > magnitude[peak]) peak = k;
    }

    const size_t count = half - first;
    std::copy(magnitude + first, magnitude + half, sorted);
    std::nth_element(sorted, sorted + count / 2, sorted + count);
    const float median = sorted[count / 2];
    if (median <= 0.0f || magnitude[peak] < cfg.snr * median) return none;

    // Parabolic interpolation on log magnitudes (good for a Hann window).
    float offset = 0.0f;
    if (peak > first) {
        const float a = std::log(magnitude[peak - 1] + 1e-9f);
        const float b = std::log(magnitude[peak] + 1e-9f);
        const float c = std::log(magnitude[peak + 1] + 1e-9f);
        const float denom = a - 2.0f * b + c;
        if (denom != 0.0f) offset = 0.5f * (a - c) / denom;
    }
    const float hz = (static_cast<float>(peak) + offset) * binHz;
    return {true, hz, dopplerSpeedKmh(hz, cfg.carrierHz)};
}
