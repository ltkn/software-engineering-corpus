#include "face_db.h"
#include "esp_log.h"
#include "nvs_flash.h"

static const char *TAG = "faces";
static face_db_t s_db;

/* TODO: load the database from NVS at boot and save it after every change. */

void app_main(void)
{
    ESP_ERROR_CHECK(nvs_flash_init());
    face_db_init(&s_db, 0.6f);
    ESP_LOGI(TAG, "%u people enrolled", (unsigned)face_db_count(&s_db));
}
