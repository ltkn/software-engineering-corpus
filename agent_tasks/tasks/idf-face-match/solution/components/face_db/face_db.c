#include "face_db.h"

#include <math.h>
#include <string.h>

/* Stored format, little-endian:
 *   u32 magic 'FDB1', u16 version, u16 count, f32 threshold,
 *   count x { char name[FACE_DB_NAME_LEN], u16 samples, f32 embedding[FACE_DB_DIM] } */
#define FACE_DB_MAGIC 0x31424446u
#define FACE_DB_VERSION 1
#define HEADER_SIZE 12
#define ENTRY_SIZE (FACE_DB_NAME_LEN + 2 + 4 * FACE_DB_DIM)

static float norm(const float *v)
{
    float s = 0;
    for (int k = 0; k < FACE_DB_DIM; k++) {
        s += v[k] * v[k];
    }
    return sqrtf(s);
}

static face_db_entry_t *find(face_db_t *db, const char *name)
{
    for (int i = 0; i < FACE_DB_MAX; i++) {
        if (db->entries[i].used && strcmp(db->entries[i].name, name) == 0) {
            return &db->entries[i];
        }
    }
    return NULL;
}

void face_db_init(face_db_t *db, float threshold)
{
    memset(db, 0, sizeof(*db));
    db->threshold = threshold;
}

esp_err_t face_db_enroll(face_db_t *db, const char *name, const float *embedding)
{
    if (db == NULL || name == NULL || embedding == NULL || name[0] == '\0' ||
        strlen(name) >= FACE_DB_NAME_LEN) {
        return ESP_ERR_INVALID_ARG;
    }
    const float n = norm(embedding);
    if (!(n > 1e-6f) || !isfinite(n)) {
        return ESP_ERR_INVALID_ARG;
    }
    face_db_entry_t *e = find(db, name);
    if (e == NULL) {
        for (int i = 0; i < FACE_DB_MAX && e == NULL; i++) {
            if (!db->entries[i].used) {
                e = &db->entries[i];
            }
        }
        if (e == NULL) {
            return ESP_ERR_NO_MEM;
        }
        memset(e, 0, sizeof(*e));
        e->used = true;
        memcpy(e->name, name, strlen(name) + 1);
    }
    /* Running mean of unit vectors, renormalized: each sample counts equally. */
    const float w = (float)e->samples;
    for (int k = 0; k < FACE_DB_DIM; k++) {
        e->embedding[k] = (e->embedding[k] * w + embedding[k] / n) / (w + 1.0f);
    }
    const float m = norm(e->embedding);
    for (int k = 0; k < FACE_DB_DIM; k++) {
        e->embedding[k] /= m;
    }
    if (e->samples < UINT16_MAX) {
        e->samples++;
    }
    return ESP_OK;
}

bool face_db_identify(const face_db_t *db, const float *embedding, face_match_t *out)
{
    out->name = NULL;
    out->similarity = 0.0f;
    const float n = norm(embedding);
    if (!(n > 1e-6f)) {
        return false;
    }
    const face_db_entry_t *best = NULL;
    float best_sim = -2.0f;
    for (int i = 0; i < FACE_DB_MAX; i++) {
        const face_db_entry_t *e = &db->entries[i];
        if (!e->used) {
            continue;
        }
        float dot = 0;
        for (int k = 0; k < FACE_DB_DIM; k++) {
            dot += e->embedding[k] * embedding[k];
        }
        const float sim = dot / n; /* stored embeddings are unit length */
        if (sim > best_sim) {
            best_sim = sim;
            best = e;
        }
    }
    if (best == NULL) {
        return false;
    }
    out->similarity = best_sim;
    if (best_sim < db->threshold) {
        return false;
    }
    out->name = best->name;
    return true;
}

esp_err_t face_db_remove(face_db_t *db, const char *name)
{
    face_db_entry_t *e = find(db, name);
    if (e == NULL) {
        return ESP_ERR_NOT_FOUND;
    }
    memset(e, 0, sizeof(*e)); /* wipe the embedding, not just the flag */
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
    return HEADER_SIZE + face_db_count(db) * ENTRY_SIZE;
}

static uint8_t *put_u16(uint8_t *p, uint16_t v)
{
    p[0] = (uint8_t)v;
    p[1] = (uint8_t)(v >> 8);
    return p + 2;
}

static uint8_t *put_u32(uint8_t *p, uint32_t v)
{
    for (int i = 0; i < 4; i++) {
        p[i] = (uint8_t)(v >> (8 * i));
    }
    return p + 4;
}

static uint8_t *put_f32(uint8_t *p, float f)
{
    uint32_t v;
    memcpy(&v, &f, sizeof v);
    return put_u32(p, v);
}

static uint16_t get_u16(const uint8_t *p)
{
    return (uint16_t)(p[0] | (p[1] << 8));
}

static uint32_t get_u32(const uint8_t *p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static float get_f32(const uint8_t *p)
{
    const uint32_t v = get_u32(p);
    float f;
    memcpy(&f, &v, sizeof f);
    return f;
}

esp_err_t face_db_serialize(const face_db_t *db, uint8_t *buf, size_t cap, size_t *out_len)
{
    const size_t need = face_db_serialized_size(db);
    if (buf == NULL || cap < need) {
        return ESP_ERR_INVALID_SIZE;
    }
    uint8_t *p = put_u32(buf, FACE_DB_MAGIC);
    p = put_u16(p, FACE_DB_VERSION);
    p = put_u16(p, (uint16_t)face_db_count(db));
    p = put_f32(p, db->threshold);
    for (int i = 0; i < FACE_DB_MAX; i++) {
        const face_db_entry_t *e = &db->entries[i];
        if (!e->used) {
            continue;
        }
        memcpy(p, e->name, FACE_DB_NAME_LEN);
        p = put_u16(p + FACE_DB_NAME_LEN, e->samples);
        for (int k = 0; k < FACE_DB_DIM; k++) {
            p = put_f32(p, e->embedding[k]);
        }
    }
    *out_len = (size_t)(p - buf);
    return ESP_OK;
}

esp_err_t face_db_deserialize(face_db_t *db, const uint8_t *buf, size_t len)
{
    if (buf == NULL || len < HEADER_SIZE || get_u32(buf) != FACE_DB_MAGIC) {
        return ESP_ERR_INVALID_ARG;
    }
    if (get_u16(buf + 4) != FACE_DB_VERSION) {
        return ESP_ERR_INVALID_VERSION;
    }
    const uint16_t count = get_u16(buf + 6);
    if (count > FACE_DB_MAX || len != HEADER_SIZE + (size_t)count * ENTRY_SIZE) {
        return ESP_ERR_INVALID_SIZE;
    }
    face_db_t loaded;
    face_db_init(&loaded, get_f32(buf + 8));
    const uint8_t *p = buf + HEADER_SIZE;
    for (uint16_t i = 0; i < count; i++) {
        face_db_entry_t *e = &loaded.entries[i];
        e->used = true;
        memcpy(e->name, p, FACE_DB_NAME_LEN);
        e->name[FACE_DB_NAME_LEN - 1] = '\0';
        e->samples = get_u16(p + FACE_DB_NAME_LEN);
        p += FACE_DB_NAME_LEN + 2;
        for (int k = 0; k < FACE_DB_DIM; k++, p += 4) {
            e->embedding[k] = get_f32(p);
        }
    }
    *db = loaded; /* only replace the live database once everything validated */
    return ESP_OK;
}
