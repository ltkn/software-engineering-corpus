#include "face_db.h"

#include <string.h>

void face_db_init(face_db_t *db, float threshold)
{
    memset(db, 0, sizeof(*db));
    db->threshold = threshold;
}

esp_err_t face_db_enroll(face_db_t *db, const char *name, const float *embedding)
{
    for (int i = 0; i < FACE_DB_MAX; i++) {
        face_db_entry_t *e = &db->entries[i];
        if (!e->used) {
            e->used = true;
            strcpy(e->name, name);
            memcpy(e->embedding, embedding, sizeof(e->embedding));
            e->samples = 1;
            return ESP_OK;
        }
    }
    return ESP_FAIL;
}

bool face_db_identify(const face_db_t *db, const float *embedding, face_match_t *out)
{
    float best = -1e30f;
    out->name = NULL;
    for (int i = 0; i < FACE_DB_MAX; i++) {
        const face_db_entry_t *e = &db->entries[i];
        if (!e->used) {
            continue;
        }
        float dot = 0;
        for (int k = 0; k < FACE_DB_DIM; k++) {
            dot += e->embedding[k] * embedding[k];
        }
        if (dot > best) {
            best = dot;
            out->name = e->name;
        }
    }
    out->similarity = best;
    return out->name != NULL;
}

esp_err_t face_db_remove(face_db_t *db, const char *name)
{
    return ESP_OK;
}

size_t face_db_count(const face_db_t *db)
{
    size_t n = 0;
    for (int i = 0; i < FACE_DB_MAX; i++) {
        n += db->entries[i].used;
    }
    return n;
}

size_t face_db_serialized_size(const face_db_t *db)
{
    return sizeof(*db);
}

esp_err_t face_db_serialize(const face_db_t *db, uint8_t *buf, size_t cap, size_t *out_len)
{
    memcpy(buf, db, sizeof(*db));
    *out_len = sizeof(*db);
    return ESP_OK;
}

esp_err_t face_db_deserialize(face_db_t *db, const uint8_t *buf, size_t len)
{
    memcpy(db, buf, sizeof(*db));
    return ESP_OK;
}
