#pragma once
#include <cstddef>

struct NtcConfig {
    float seriesOhms = 10000.0f;
    float r0Ohms = 10000.0f;   // resistance at t0C
    float t0C = 25.0f;
    float beta = 3950.0f;
    float supplyMv = 3300.0f;
    bool ntcOnLowSide = true;  // NTC between the ADC pin and ground
};

enum class NtcStatus { Ok, Open, Short };

struct NtcReading {
    NtcStatus status;
    float celsius;
};

NtcReading ntcFromMillivolts(float mv, const NtcConfig& cfg);

// Median of the last five readings, then an exponential moving average.
class TempFilter {
public:
    explicit TempFilter(float alpha) : alpha_(alpha) {}
    float update(float celsius);

private:
    float alpha_;
    float window_[5] = {};
    size_t count_ = 0;
    size_t next_ = 0;
    float ema_ = 0.0f;
    bool started_ = false;
};
