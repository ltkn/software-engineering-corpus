#include "thermistor.h"

#include <algorithm>
#include <cmath>

namespace {
constexpr float kKelvin = 273.15f;
constexpr float kRailFraction = 0.01f;
}  // namespace

NtcReading ntcFromMillivolts(float mv, const NtcConfig& cfg) {
    const float margin = cfg.supplyMv * kRailFraction;
    const bool nearSupply = mv >= cfg.supplyMv - margin;
    const bool nearGround = mv <= margin;
    if (nearSupply || nearGround) {
        // Low side: an open NTC pulls the pin up to the supply. High side: the opposite.
        const bool open = cfg.ntcOnLowSide ? nearSupply : nearGround;
        return {open ? NtcStatus::Open : NtcStatus::Short, NAN};
    }
    // Divider: V = Vs * R_low / (R_high + R_low).
    const float ntcOhms = cfg.ntcOnLowSide ? cfg.seriesOhms * mv / (cfg.supplyMv - mv)
                                           : cfg.seriesOhms * (cfg.supplyMv - mv) / mv;
    // Beta equation, in kelvin: 1/T = 1/T0 + ln(R/R0) / B.
    const float invT = 1.0f / (cfg.t0C + kKelvin) + std::log(ntcOhms / cfg.r0Ohms) / cfg.beta;
    return {NtcStatus::Ok, 1.0f / invT - kKelvin};
}

float TempFilter::update(float celsius) {
    window_[next_] = celsius;
    next_ = (next_ + 1) % 5;
    count_ = std::min<size_t>(count_ + 1, 5);
    float sorted[5];
    std::copy(window_, window_ + count_, sorted);
    std::sort(sorted, sorted + count_);
    const float median = sorted[count_ / 2];
    if (!started_) {
        ema_ = median;
        started_ = true;
    } else {
        ema_ = alpha_ * median + (1.0f - alpha_) * ema_;
    }
    return ema_;
}
