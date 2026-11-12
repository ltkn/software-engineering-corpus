#include "warm.h"
#include "esp_wifi.h"
#include "nvs_flash.h"
void app_main(void) { nvs_flash_init(); (void)warm(1); }
