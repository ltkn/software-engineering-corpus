#include <math.h>
#include <stdlib.h>
#include <string.h>
#include "csi_motion.h"
#include "unity.h"

#define SUBCARRIERS 64

/* A frame where every used subcarrier has amplitude `amp` (I/Q = 0.6a, 0.8a);
 * subcarriers 0 and 32 are null (both zero), as on real hardware. */
static void frame(int8_t *buf, float amp)
{
    for (int k = 0; k < SUBCARRIERS; k++) {
        bool null = k == 0 || k == 32;
        buf[2 * k] = null ? 0 : (int8_t)lroundf(0.6f * amp);
        buf[2 * k + 1] = null ? 0 : (int8_t)lroundf(0.8f * amp);
    }
}

static const csi_motion_config_t CFG = {.window = 8, .enter_threshold = 4.0f, .exit_threshold = 1.0f,
                                        .exit_frames = 3};

static void test_amplitude_ignores_null_subcarriers(void)
{
    int8_t buf[2 * SUBCARRIERS];
    frame(buf, 50);
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 50.0f, csi_motion_amplitude(buf, sizeof buf));
}

static void test_amplitude_does_not_overflow(void)
{
    int8_t buf[2 * SUBCARRIERS];
    for (size_t i = 0; i < sizeof buf; i++) {
        buf[i] = -128;
    }
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 181.02f, csi_motion_amplitude(buf, sizeof buf));
    int8_t zeros[8] = {0};
    TEST_ASSERT_EQUAL_FLOAT(0.0f, csi_motion_amplitude(zeros, sizeof zeros));
}

static void test_score_uses_only_the_window(void)
{
    csi_motion_t m;
    int8_t buf[2 * SUBCARRIERS];
    TEST_ASSERT_EQUAL(ESP_OK, csi_motion_init(&m, &CFG));
    for (int i = 0; i < 20; i++) {
        frame(buf, (i % 2) ? 30 : 40);
        csi_motion_feed(&m, buf, sizeof buf);
    }
    TEST_ASSERT_FLOAT_WITHIN(0.5f, 25.0f, csi_motion_score(&m));
    for (int i = 0; i < CFG.window; i++) {
        frame(buf, 35);
        csi_motion_feed(&m, buf, sizeof buf);
    }
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 0.0f, csi_motion_score(&m));
}

static void test_hysteresis(void)
{
    csi_motion_t m;
    int8_t buf[2 * SUBCARRIERS];
    TEST_ASSERT_EQUAL(ESP_OK, csi_motion_init(&m, &CFG));
    for (int i = 0; i < 8; i++) {
        frame(buf, 35);
        TEST_ASSERT_FALSE(csi_motion_feed(&m, buf, sizeof buf));
    }
    bool active = false;
    for (int i = 0; i < 4; i++) {
        frame(buf, (i % 2) ? 25 : 45);
        active = csi_motion_feed(&m, buf, sizeof buf);
    }
    TEST_ASSERT_TRUE_MESSAGE(active, "strong variation starts motion");
    /* Back to still: stays active until the window has calmed for exit_frames frames. */
    int frames_until_clear = 0;
    while (active && frames_until_clear < 40) {
        frame(buf, 35);
        active = csi_motion_feed(&m, buf, sizeof buf);
        frames_until_clear++;
        if (frames_until_clear == 1) {
            TEST_ASSERT_TRUE_MESSAGE(active, "does not drop on the first quiet frame");
        }
    }
    TEST_ASSERT_FALSE(active);
    TEST_ASSERT_TRUE_MESSAGE(frames_until_clear >= CFG.exit_frames, "needs exit_frames quiet frames");
}

static void test_two_detectors_are_independent(void)
{
    csi_motion_t a, b;
    int8_t buf[2 * SUBCARRIERS];
    TEST_ASSERT_EQUAL(ESP_OK, csi_motion_init(&a, &CFG));
    TEST_ASSERT_EQUAL(ESP_OK, csi_motion_init(&b, &CFG));
    for (int i = 0; i < 8; i++) {
        frame(buf, (i % 2) ? 20 : 50);
        csi_motion_feed(&a, buf, sizeof buf);
        frame(buf, 35);
        csi_motion_feed(&b, buf, sizeof buf);
    }
    TEST_ASSERT_TRUE(a.active);
    TEST_ASSERT_FALSE(b.active);
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 0.0f, csi_motion_score(&b));
}

static void test_invalid_config(void)
{
    csi_motion_t m;
    csi_motion_config_t bad = CFG;
    bad.window = 0;
    TEST_ASSERT_EQUAL(ESP_ERR_INVALID_ARG, csi_motion_init(&m, &bad));
    bad = CFG;
    bad.window = CSI_MOTION_MAX_WINDOW + 1;
    TEST_ASSERT_EQUAL(ESP_ERR_INVALID_ARG, csi_motion_init(&m, &bad));
    bad = CFG;
    bad.exit_threshold = bad.enter_threshold + 1;
    TEST_ASSERT_EQUAL(ESP_ERR_INVALID_ARG, csi_motion_init(&m, &bad));
    TEST_ASSERT_EQUAL(ESP_ERR_INVALID_ARG, csi_motion_init(&m, NULL));
}

void app_main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_amplitude_ignores_null_subcarriers);
    RUN_TEST(test_amplitude_does_not_overflow);
    RUN_TEST(test_score_uses_only_the_window);
    RUN_TEST(test_hysteresis);
    RUN_TEST(test_two_detectors_are_independent);
    RUN_TEST(test_invalid_config);
    exit(UNITY_END());
}
