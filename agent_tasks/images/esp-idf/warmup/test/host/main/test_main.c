#include <stdlib.h>
#include "unity.h"
#include "warm.h"
static void test_warm(void) { TEST_ASSERT_EQUAL(2, warm(1)); }
void app_main(void) { UNITY_BEGIN(); RUN_TEST(test_warm); exit(UNITY_END()); }
