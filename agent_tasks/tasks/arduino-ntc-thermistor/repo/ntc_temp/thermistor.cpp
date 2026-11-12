#include "thermistor.h"

#include <cmath>

NtcReading ntcFromMillivolts(float mv, const NtcConfig& cfg) {
    float r = cfg.seriesOhms * (cfg.supplyMv - mv) / mv;
    float invT = 1.0f / cfg.t0C + std::log(r / cfg.r0Ohms) / cfg.beta;
    return {NtcStatus::Ok, 1.0f / invT};
}

float TempFilter::update(float celsius) {
    if (!started_) {
        ema_ = celsius;
        started_ = true;
    }
    ema_ = alpha_ * celsius + (1.0f - alpha_) * ema_;
    return ema_;
}
