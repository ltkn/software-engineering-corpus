#include <cmath>
#include <cstdint>
#include <vector>

#include "check.h"
#include "doppler.h"

namespace {
constexpr double kPi = 3.14159265358979323846;

// Deterministic noise in [-1, 1].
struct Lcg {
    uint32_t s = 12345;
    double next() {
        s = s * 1664525u + 1013904223u;
        return (s >> 8) / double(1u << 24) * 2.0 - 1.0;
    }
};

std::vector<uint16_t> make_signal(size_t n, double fs, std::vector<std::pair<double, double>> tones, double noise) {
    std::vector<uint16_t> out(n);
    Lcg rng;
    for (size_t i = 0; i < n; ++i) {
        double v = 2048.0 + noise * rng.next();
        for (auto [hz, amp] : tones) v += amp * std::sin(2 * kPi * hz * i / fs + 0.3);
        out[i] = static_cast<uint16_t>(std::lround(std::fmin(4095.0, std::fmax(0.0, v))));
    }
    return out;
}
}  // namespace

int main() {
    DopplerConfig cfg;  // 5 kHz, 24.125 GHz
    CHECK_NEAR(dopplerSpeedKmh(447.068544f, 24.125e9f), 10.0, 0.01);

    // 10 km/h is about 447.1 Hz at 24.125 GHz.
    auto s10 = make_signal(512, 5000, {{447.068544, 300}}, 40);
    DopplerResult r = analyze(s10.data(), s10.size(), cfg);
    CHECK(r.target);
    CHECK_NEAR(r.speedKmh, 10.0, 0.15);
    CHECK_NEAR(r.frequencyHz, 447.069, 6.0);

    // The strongest of two targets wins.
    auto two = make_signal(1024, 5000, {{1341.205633, 500}, {536.482253, 150}}, 40);
    r = analyze(two.data(), two.size(), cfg);
    CHECK(r.target);
    CHECK_NEAR(r.speedKmh, 30.0, 0.15);

    // Slow drift below minHz is ignored; the real target is found.
    auto drift = make_signal(512, 5000, {{8.0, 900}, {894.137089, 200}}, 30);
    r = analyze(drift.data(), drift.size(), cfg);
    CHECK(r.target);
    CHECK_NEAR(r.speedKmh, 20.0, 0.2);

    // Only noise around mid-scale: no target.
    auto quiet = make_signal(512, 5000, {}, 60);
    r = analyze(quiet.data(), quiet.size(), cfg);
    CHECK(!r.target);

    // Off-bin frequency is refined by interpolation (bin width here is ~9.8 Hz).
    auto off = make_signal(512, 5000, {{326.360037, 400}}, 20);
    r = analyze(off.data(), off.size(), cfg);
    CHECK(r.target);
    CHECK_NEAR(r.speedKmh, 7.3, 0.1);

    return test_summary();
}
