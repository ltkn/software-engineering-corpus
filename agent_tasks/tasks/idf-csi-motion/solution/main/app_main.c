#include <string.h>
#include "csi_motion.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_netif.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"
#include "nvs_flash.h"

static const char *TAG = "csi";

#define CSI_MAX_LEN 384 /* bytes per frame we keep; longer frames are truncated */

typedef struct {
    uint16_t len;
    int8_t buf[CSI_MAX_LEN];
} csi_frame_t;

static QueueHandle_t s_frames;

/* Runs in the Wi-Fi task: copy and return, never block or log here. */
static void on_csi(void *ctx, wifi_csi_info_t *info)
{
    if (info == NULL || info->buf == NULL) {
        return;
    }
    csi_frame_t frame;
    frame.len = info->len > CSI_MAX_LEN ? CSI_MAX_LEN : info->len;
    memcpy(frame.buf, info->buf, frame.len);
    (void)xQueueSend(s_frames, &frame, 0); /* drop the frame if the queue is full */
}

static void detect_task(void *arg)
{
    csi_motion_t motion;
    const csi_motion_config_t cfg = {.window = 32, .enter_threshold = 4.0f, .exit_threshold = 2.0f,
                                     .exit_frames = 20};
    ESP_ERROR_CHECK(csi_motion_init(&motion, &cfg));
    bool was_active = false;
    csi_frame_t frame;
    for (;;) {
        if (xQueueReceive(s_frames, &frame, portMAX_DELAY) != pdTRUE) {
            continue;
        }
        const bool active = csi_motion_feed(&motion, frame.buf, frame.len);
        if (active != was_active) {
            ESP_LOGI(TAG, "motion %s (score %.2f)", active ? "started" : "stopped", csi_motion_score(&motion));
            was_active = active;
        }
    }
}

void app_main(void)
{
    ESP_ERROR_CHECK(nvs_flash_init());
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    esp_netif_create_default_wifi_sta();
    wifi_init_config_t init = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&init));
    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
    ESP_ERROR_CHECK(esp_wifi_start());

    s_frames = xQueueCreate(16, sizeof(csi_frame_t));
    configASSERT(s_frames != NULL);
    xTaskCreate(detect_task, "csi_detect", 4096, NULL, 5, NULL);

    /* ESP32-C5/C6 use the acquire-style config (wifi_csi_acquire_config_t). */
    wifi_csi_config_t csi = {
        .enable = 1,
        .acquire_csi_legacy = 1,
        .acquire_csi_ht20 = 1,
        .acquire_csi_ht40 = 1,
        .acquire_csi_su = 1,
        .acquire_csi_mu = 1,
        .acquire_csi_dcm = 1,
        .acquire_csi_beamformed = 1,
    };
    ESP_ERROR_CHECK(esp_wifi_set_csi_config(&csi));
    ESP_ERROR_CHECK(esp_wifi_set_csi_rx_cb(on_csi, NULL));
    ESP_ERROR_CHECK(esp_wifi_set_csi(true));
}
