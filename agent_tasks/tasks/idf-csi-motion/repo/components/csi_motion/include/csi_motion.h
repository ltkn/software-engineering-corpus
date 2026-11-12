#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

#define CSI_MOTION_MAX_WINDOW 64

typedef struct {
    uint16_t window;          /* frames in the variance window, 2..CSI_MOTION_MAX_WINDOW */
    float enter_threshold;    /* variance above this: motion */
    float exit_threshold;     /* variance below this for exit_frames: no motion (<= enter) */
    uint16_t exit_frames;
} csi_motion_config_t;

typedef struct {
    csi_motion_config_t cfg;
    float ring[CSI_MOTION_MAX_WINDOW];
    uint16_t count;
    uint16_t next;
    uint16_t quiet_frames;
    bool active;
} csi_motion_t;

esp_err_t csi_motion_init(csi_motion_t *m, const csi_motion_config_t *cfg);

/* Mean amplitude over subcarriers; buf holds len bytes as (imag, real) int8 pairs. */
float csi_motion_amplitude(const int8_t *buf, size_t len);

/* Add one CSI frame; returns whether motion is currently detected. */
bool csi_motion_feed(csi_motion_t *m, const int8_t *buf, size_t len);

/* Variance of the amplitude over the frames in the window. */
float csi_motion_score(const csi_motion_t *m);

#ifdef __cplusplus
}
#endif
