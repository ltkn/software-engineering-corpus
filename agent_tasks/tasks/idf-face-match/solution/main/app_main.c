#include <stdlib.h>
#include "esp_log.h"
#include "face_db.h"
#include "nvs.h"
#include "nvs_flash.h"

static const char *TAG = "faces";
static const char *NVS_NS = "faces";
static const char *NVS_KEY = "db";
static face_db_t s_db;

static esp_err_t load_db(void)
{
    nvs_handle_t h;
    esp_err_t err = nvs_open(NVS_NS, NVS_READONLY, &h);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        return ESP_OK; /* first boot: nothing stored yet */
    }
    if (err != ESP_OK) {
        return err;
    }
    size_t len = 0;
    err = nvs_get_blob(h, NVS_KEY, NULL, &len); /* size first */
    if (err == ESP_OK && len > 0) {
        uint8_t *buf = malloc(len);
        if (buf == NULL) {
            err = ESP_ERR_NO_MEM;
        } else {
            err = nvs_get_blob(h, NVS_KEY, buf, &len);
            if (err == ESP_OK) {
                err = face_db_deserialize(&s_db, buf, len);
            }
            free(buf);
        }
    } else if (err == ESP_ERR_NVS_NOT_FOUND) {
        err = ESP_OK;
    }
    nvs_close(h);
    return err;
}

/* Call after every enrol or remove. */
esp_err_t save_db(void)
{
    const size_t need = face_db_serialized_size(&s_db);
    uint8_t *buf = malloc(need);
    if (buf == NULL) {
        return ESP_ERR_NO_MEM;
    }
    size_t len = 0;
    esp_err_t err = face_db_serialize(&s_db, buf, need, &len);
    if (err == ESP_OK) {
        nvs_handle_t h;
        err = nvs_open(NVS_NS, NVS_READWRITE, &h);
        if (err == ESP_OK) {
            err = nvs_set_blob(h, NVS_KEY, buf, len);
            if (err == ESP_OK) {
                err = nvs_commit(h);
            }
            nvs_close(h);
        }
    }
    free(buf);
    return err;
}

void app_main(void)
{
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        err = nvs_flash_init();
    }
    ESP_ERROR_CHECK(err);
    face_db_init(&s_db, 0.6f);
    err = load_db();
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "stored face database unreadable (%s); starting empty", esp_err_to_name(err));
        face_db_init(&s_db, 0.6f);
    }
    ESP_LOGI(TAG, "%u people enrolled", (unsigned)face_db_count(&s_db));
}
