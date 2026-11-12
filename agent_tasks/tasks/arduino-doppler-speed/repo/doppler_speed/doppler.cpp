#include "doppler.h"

float dopplerSpeedKmh(float dopplerHz, float carrierHz) {
    return dopplerHz * 3e8f / carrierHz;
}

DopplerResult analyze(const uint16_t* samples, size_t n, const DopplerConfig& cfg) {
    // Count zero crossings.
    size_t crossings = 0;
    for (size_t i = 1; i < n; ++i) {
        if ((samples[i - 1] < 0) != (samples[i] < 0)) ++crossings;
    }
    float hz = crossings * cfg.sampleRateHz / (2.0f * n);
    return {hz > 0, hz, dopplerSpeedKmh(hz, cfg.carrierHz)};
}
