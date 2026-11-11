#include "stats.h"
#include <cassert>
#include <cmath>
#include <cstdio>

static bool near(double a, double b) { return std::fabs(a - b) < 1e-9; }

int main() {
    const double s[] = {2, 4, 6, 8, 10};
    auto out = moving_average(s, 3);
    const double want[] = {2, 3, 4, 6, 8};
    for (int i = 0; i < 5; ++i) assert(near(out[i], want[i]));
    assert(moving_average(std::span<const double>{}, 3).empty());
    auto one = moving_average(s, 1);
    assert(near(one[4], 10));
    std::puts("ok");
}
