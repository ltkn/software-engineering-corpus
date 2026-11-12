#include <string.h>
#include "csi_motion.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_netif.h"
#include "esp_wifi.h"
#include "nvs_flash.h"

static const char *TAG = "csi";
static csi_motion_t s_motion;

static void on_csi(void *ctx, wifi_csi_info_t *info)
{
    bool active = csi_motion_feed(&s_motion, info->buf, info->len);
    ESP_LOGI(TAG, "len=%d rssi=%d motion=%d score=%.2f", info->len, info->rx_ctrl.rssi, active,
             csi_motion_score(&s_motion));
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

    const csi_motion_config_t cfg = {.window = 32, .enter_threshold = 4.0f, .exit_threshold = 2.0f,
                                     .exit_frames = 20};
    ESP_ERROR_CHECK(csi_motion_init(&s_motion, &cfg));

    wifi_csi_config_t csi = {
        .lltf_en = true,
        .htltf_en = true,
        .stbc_htltf2_en = true,
        .ltf_merge_en = true,
        .channel_filter_en = false,
        .manu_scale = false,
    };
    ESP_ERROR_CHECK(esp_wifi_set_csi_config(&csi));
    ESP_ERROR_CHECK(esp_wifi_set_csi_rx_cb(on_csi, NULL));
    ESP_ERROR_CHECK(esp_wifi_set_csi(true));
}
