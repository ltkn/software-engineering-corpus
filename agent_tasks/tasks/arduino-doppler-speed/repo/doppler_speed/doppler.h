#pragma once
#include <cstddef>
#include <cstdint>

struct DopplerConfig {
    float sampleRateHz = 5000.0f;
    float carrierHz = 24.125e9f;
    float minHz = 30.0f;   // ignore bins below this frequency
    float snr = 6.0f;      // peak must be this many times the median magnitude
};

struct DopplerResult {
    bool target;
    float frequencyHz;
    float speedKmh;
};

float dopplerSpeedKmh(float dopplerHz, float carrierHz);

// samples: raw ADC readings (12-bit); n: power of two, at most 1024.
DopplerResult analyze(const uint16_t* samples, size_t n, const DopplerConfig& cfg);
