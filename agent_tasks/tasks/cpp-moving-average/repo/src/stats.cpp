#include "stats.h"

std::vector<double> moving_average(std::span<const double> samples, std::size_t window) {
    std::vector<double> out(samples.size());
    double sum = 0;
    for (std::size_t i = 0; i < samples.size(); ++i) {
        sum += samples[i];
        sum -= samples[i - window];
        out[i] = sum / window;
    }
    return out;
}
