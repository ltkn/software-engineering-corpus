// Tiny test helpers for host tests (no framework needed).
#pragma once
#include <cmath>
#include <cstdio>

inline int g_failures = 0;
inline int g_checks = 0;

#define CHECK(cond)                                                              \
    do {                                                                         \
        ++g_checks;                                                              \
        if (!(cond)) {                                                           \
            ++g_failures;                                                        \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);          \
        }                                                                        \
    } while (0)

#define CHECK_NEAR(actual, expected, tol)                                        \
    do {                                                                         \
        ++g_checks;                                                              \
        double a_ = (actual), e_ = (expected);                                   \
        if (!(std::fabs(a_ - e_) <= (tol))) {                                    \
            ++g_failures;                                                        \
            std::printf("FAIL %s:%d: %s = %g, expected %g +- %g\n", __FILE__,    \
                        __LINE__, #actual, a_, e_, (double)(tol));               \
        }                                                                        \
    } while (0)

inline int test_summary() {
    std::printf("%d checks, %d failed\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}
