#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

#define FACE_DB_DIM 128
#define FACE_DB_MAX 16
#define FACE_DB_NAME_LEN 32

typedef struct {
    bool used;
    char name[FACE_DB_NAME_LEN];
    uint16_t samples;
    float embedding[FACE_DB_DIM]; /* unit length */
} face_db_entry_t;

typedef struct {
    float threshold; /* cosine similarity needed to accept a match */
    face_db_entry_t entries[FACE_DB_MAX];
} face_db_t;

typedef struct {
    const char *name; /* NULL when unknown */
    float similarity;
} face_match_t;

void face_db_init(face_db_t *db, float threshold);

/* Add a sample for `name` (new person, or another sample of an existing one). */
esp_err_t face_db_enroll(face_db_t *db, const char *name, const float *embedding);

/* Best match above the threshold; returns false (and out->name NULL) when unknown. */
bool face_db_identify(const face_db_t *db, const float *embedding, face_match_t *out);

esp_err_t face_db_remove(face_db_t *db, const char *name);

size_t face_db_count(const face_db_t *db);

/* Bytes needed by face_db_serialize for the current contents. */
size_t face_db_serialized_size(const face_db_t *db);
esp_err_t face_db_serialize(const face_db_t *db, uint8_t *buf, size_t cap, size_t *out_len);
esp_err_t face_db_deserialize(face_db_t *db, const uint8_t *buf, size_t len);

#ifdef __cplusplus
}
#endif
