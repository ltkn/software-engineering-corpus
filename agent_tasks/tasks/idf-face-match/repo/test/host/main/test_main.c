#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "face_db.h"
#include "unity.h"

/* Deterministic pseudo-random embedding for person `id`, with optional variation. */
static void embedding(float *out, int id, float scale, int variant)
{
    uint32_t s = 2166136261u ^ (uint32_t)id;
    for (int k = 0; k < FACE_DB_DIM; k++) {
        s = s * 16777619u + 12345u;
        float base = ((s >> 8) & 0xFFFF) / 32768.0f - 1.0f;
        float jitter = variant ? 0.15f * sinf((float)(k * variant)) : 0.0f;
        out[k] = scale * (base + jitter);
    }
}

static face_db_t db;
static float e[FACE_DB_DIM];

static void test_cosine_not_dot_product(void)
{
    face_db_init(&db, 0.6f);
    embedding(e, 1, 1.0f, 0);
    TEST_ASSERT_EQUAL(ESP_OK, face_db_enroll(&db, "ana", e));
    embedding(e, 2, 9.0f, 0); /* someone else with a large-norm embedding */
    TEST_ASSERT_EQUAL(ESP_OK, face_db_enroll(&db, "ben", e));
    face_match_t m;
    embedding(e, 1, 0.2f, 1); /* ana, small norm, slight variation */
    TEST_ASSERT_TRUE(face_db_identify(&db, e, &m));
    TEST_ASSERT_EQUAL_STRING("ana", m.name);
    TEST_ASSERT_TRUE(m.similarity > 0.9f && m.similarity <= 1.0001f);
}

static void test_unknown_below_threshold(void)
{
    face_db_init(&db, 0.6f);
    embedding(e, 1, 1.0f, 0);
    face_db_enroll(&db, "ana", e);
    face_match_t m;
    embedding(e, 3, 1.0f, 0);
    TEST_ASSERT_FALSE(face_db_identify(&db, e, &m));
    TEST_ASSERT_NULL(m.name);
    face_db_init(&db, 0.6f);
    TEST_ASSERT_FALSE(face_db_identify(&db, e, &m));
}

static void test_enrolling_again_updates_the_person(void)
{
    face_db_init(&db, 0.6f);
    for (int v = 0; v < 3; v++) {
        embedding(e, 1, 1.0f + v, v);
        TEST_ASSERT_EQUAL(ESP_OK, face_db_enroll(&db, "ana", e));
    }
    TEST_ASSERT_EQUAL(1, face_db_count(&db));
    TEST_ASSERT_EQUAL(3, db.entries[0].samples);
    float norm = 0;
    for (int k = 0; k < FACE_DB_DIM; k++) {
        norm += db.entries[0].embedding[k] * db.entries[0].embedding[k];
    }
    TEST_ASSERT_FLOAT_WITHIN(1e-3f, 1.0f, sqrtf(norm));
}

static void test_remove_full_and_bad_input(void)
{
    face_db_init(&db, 0.6f);
    char name[16];
    for (int i = 0; i < FACE_DB_MAX; i++) {
        snprintf(name, sizeof name, "p%d", i);
        embedding(e, 100 + i, 1.0f, 0);
        TEST_ASSERT_EQUAL(ESP_OK, face_db_enroll(&db, name, e));
    }
    embedding(e, 999, 1.0f, 0);
    TEST_ASSERT_EQUAL(ESP_ERR_NO_MEM, face_db_enroll(&db, "extra", e));
    TEST_ASSERT_EQUAL(ESP_OK, face_db_remove(&db, "p3"));
    TEST_ASSERT_EQUAL(ESP_ERR_NOT_FOUND, face_db_remove(&db, "p3"));
    TEST_ASSERT_EQUAL(ESP_OK, face_db_enroll(&db, "extra", e));
    TEST_ASSERT_EQUAL(FACE_DB_MAX, face_db_count(&db));
    face_match_t m;
    embedding(e, 103, 1.0f, 0);
    TEST_ASSERT_FALSE_MESSAGE(face_db_identify(&db, e, &m), "removed person is no longer recognised");

    memset(e, 0, sizeof e);
    TEST_ASSERT_EQUAL(ESP_ERR_INVALID_ARG, face_db_enroll(&db, "zero", e));
    embedding(e, 5, 1.0f, 0);
    TEST_ASSERT_EQUAL(ESP_ERR_INVALID_ARG, face_db_enroll(&db, "", e));
    TEST_ASSERT_EQUAL(ESP_ERR_INVALID_ARG,
                      face_db_enroll(&db, "a-name-that-is-far-too-long-for-the-db", e));
}

static void test_serialize_round_trip_and_validation(void)
{
    face_db_init(&db, 0.6f);
    embedding(e, 1, 1.0f, 0);
    face_db_enroll(&db, "ana", e);
    embedding(e, 2, 1.0f, 0);
    face_db_enroll(&db, "ben", e);
    face_db_enroll(&db, "ben", e);

    size_t need = face_db_serialized_size(&db);
    TEST_ASSERT_TRUE_MESSAGE(need < 2 * (FACE_DB_NAME_LEN + 4 * FACE_DB_DIM + 16) + 64,
                             "only enrolled people are written");
    uint8_t *buf = malloc(need);
    size_t len = 0;
    TEST_ASSERT_EQUAL(ESP_ERR_INVALID_SIZE, face_db_serialize(&db, buf, need - 1, &len));
    TEST_ASSERT_EQUAL(ESP_OK, face_db_serialize(&db, buf, need, &len));
    TEST_ASSERT_EQUAL(need, len);

    face_db_t copy;
    face_db_init(&copy, 0.6f);
    TEST_ASSERT_EQUAL(ESP_OK, face_db_deserialize(&copy, buf, len));
    TEST_ASSERT_EQUAL(2, face_db_count(&copy));
    face_match_t m;
    TEST_ASSERT_TRUE(face_db_identify(&copy, e, &m));
    TEST_ASSERT_EQUAL_STRING("ben", m.name);

    TEST_ASSERT_NOT_EQUAL(ESP_OK, face_db_deserialize(&copy, buf, len - 3));
    buf[0] ^= 0xFF;
    TEST_ASSERT_NOT_EQUAL(ESP_OK, face_db_deserialize(&copy, buf, len));
    TEST_ASSERT_NOT_EQUAL(ESP_OK, face_db_deserialize(&copy, buf, 2));
    free(buf);
}

void app_main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_cosine_not_dot_product);
    RUN_TEST(test_unknown_below_threshold);
    RUN_TEST(test_enrolling_again_updates_the_person);
    RUN_TEST(test_remove_full_and_bad_input);
    RUN_TEST(test_serialize_round_trip_and_validation);
    exit(UNITY_END());
}
