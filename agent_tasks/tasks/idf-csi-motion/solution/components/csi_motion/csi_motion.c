#include "csi_motion.h"

#include <math.h>
#include <string.h>

esp_err_t csi_motion_init(csi_motion_t *m, const csi_motion_config_t *cfg)
{
    if (m == NULL || cfg == NULL || cfg->window < 2 || cfg->window > CSI_MOTION_MAX_WINDOW ||
        cfg->exit_threshold > cfg->enter_threshold) {
        return ESP_ERR_INVALID_ARG;
    }
    memset(m, 0, sizeof(*m));
    m->cfg = *cfg;
    return ESP_OK;
}

float csi_motion_amplitude(const int8_t *buf, size_t len)
{
    float total = 0;
    size_t used = 0;
    for (size_t i = 0; i + 1 < len; i += 2) {
        const int32_t im = buf[i];
        const int32_t re = buf[i + 1];
        if (im == 0 && re == 0) {
            continue; /* null or guard subcarrier */
        }
        total += sqrtf((float)(im * im + re * re));
        used++;
    }
    return used ? total / (float)used : 0.0f;
}

float csi_motion_score(const csi_motion_t *m)
{
    if (m->count < 2) {
        return 0.0f;
    }
    /* Two-pass variance over at most 64 values: simple and numerically stable. */
    float mean = 0;
    for (uint16_t i = 0; i < m->count; i++) {
        mean += m->ring[i];
    }
    mean /= (float)m->count;
    float var = 0;
    for (uint16_t i = 0; i < m->count; i++) {
        const float d = m->ring[i] - mean;
        var += d * d;
    }
    return var / (float)m->count;
}

bool csi_motion_feed(csi_motion_t *m, const int8_t *buf, size_t len)
{
    m->ring[m->next] = csi_motion_amplitude(buf, len);
    m->next = (uint16_t)((m->next + 1) % m->cfg.window);
    if (m->count < m->cfg.window) {
        m->count++;
    }
    const float score = csi_motion_score(m);
    if (!m->active) {
        if (score > m->cfg.enter_threshold) {
            m->active = true;
            m->quiet_frames = 0;
        }
    } else if (score < m->cfg.exit_threshold) {
        if (++m->quiet_frames >= m->cfg.exit_frames) {
            m->active = false;
        }
    } else {
        m->quiet_frames = 0;
    }
    return m->active;
}
