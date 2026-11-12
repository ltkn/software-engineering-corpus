#include <initializer_list>

#include "check.h"
#include "thermistor.h"

int main() {
    NtcConfig low;
    NtcConfig high;
    high.ntcOnLowSide = false;
    struct Case { float c, lowMv, highMv; };
    const Case cases[] = {{-10.0f, 2816.453f, 483.547f}, {0.0f, 2543.477f, 756.523f}, {25.0f, 1650.000f, 1650.000f}, {40.0f, 1143.344f, 2156.656f}, {85.0f, 323.453f, 2976.547f}};
    for (const Case& k : cases) {
        NtcReading a = ntcFromMillivolts(k.lowMv, low);
        CHECK(a.status == NtcStatus::Ok);
        CHECK_NEAR(a.celsius, k.c, 0.05);
        NtcReading b = ntcFromMillivolts(k.highMv, high);
        CHECK(b.status == NtcStatus::Ok);
        CHECK_NEAR(b.celsius, k.c, 0.05);
    }

    // Faults: low side, NTC open pulls the pin to the supply; shorted pulls it to ground.
    CHECK(ntcFromMillivolts(3299.0f, low).status == NtcStatus::Open);
    CHECK(ntcFromMillivolts(5.0f, low).status == NtcStatus::Short);
    CHECK(ntcFromMillivolts(3299.0f, high).status == NtcStatus::Short);
    CHECK(ntcFromMillivolts(5.0f, high).status == NtcStatus::Open);
    CHECK(ntcFromMillivolts(0.0f, low).status == NtcStatus::Short);

    // A single spike does not move the output.
    TempFilter f(0.3f);
    float out = 0;
    for (float v : {25.0f, 25.0f, 25.0f, 25.0f, 80.0f, 25.0f, 25.0f}) out = f.update(v);
    CHECK_NEAR(out, 25.0, 0.01);

    // A real step is followed, smoothly.
    TempFilter g(0.5f);
    for (int i = 0; i < 5; ++i) g.update(20.0f);
    float first = g.update(30.0f);
    CHECK_NEAR(first, 20.0, 0.01);  // median still 20
    float after = 0;
    for (int i = 0; i < 20; ++i) after = g.update(30.0f);
    CHECK_NEAR(after, 30.0, 0.05);
    return test_summary();
}
