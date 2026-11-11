#pragma once
#include <span>
#include <vector>

// Trailing moving average with window `window`: out[i] averages the last
// min(i + 1, window) samples up to and including i.
std::vector<double> moving_average(std::span<const double> samples, std::size_t window);
