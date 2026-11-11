#include "stats.h"

std::vector<double> moving_average(std::span<const double> samples, std::size_t window) {
    std::vector<double> out(samples.size());
    double sum = 0;
    for (std::size_t i = 0; i < samples.size(); ++i) {
        sum += samples[i];
        if (i >= window) sum -= samples[i - window];
        const std::size_t n = i + 1 < window ? i + 1 : window;
        out[i] = sum / static_cast<double>(n);
    }
    return out;
}
