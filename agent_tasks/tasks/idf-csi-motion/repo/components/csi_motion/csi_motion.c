#include "csi_motion.h"

#include <math.h>
#include <string.h>

static float s_sum, s_sum_sq;
static uint32_t s_frames;

esp_err_t csi_motion_init(csi_motion_t *m, const csi_motion_config_t *cfg)
{
    memset(m, 0, sizeof(*m));
    m->cfg = *cfg;
    s_sum = s_sum_sq = 0;
    s_frames = 0;
    return ESP_OK;
}

float csi_motion_amplitude(const int8_t *buf, size_t len)
{
    int8_t total = 0;
    for (size_t i = 0; i + 1 < len; i += 2) {
        int8_t sq = buf[i] * buf[i] + buf[i + 1] * buf[i + 1];
        total += (int8_t)sqrtf(sq);
    }
    return len ? (float)total / (len / 2) : 0;
}

bool csi_motion_feed(csi_motion_t *m, const int8_t *buf, size_t len)
{
    float a = csi_motion_amplitude(buf, len);
    s_sum += a;
    s_sum_sq += a * a;
    s_frames++;
    m->active = csi_motion_score(m) > m->cfg.enter_threshold;
    return m->active;
}

float csi_motion_score(const csi_motion_t *m)
{
    if (s_frames < 2) {
        return 0;
    }
    float mean = s_sum / s_frames;
    return s_sum_sq / s_frames - mean * mean;
}
