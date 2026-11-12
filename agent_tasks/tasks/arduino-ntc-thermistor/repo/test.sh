#!/bin/sh
# Host tests of the logic, then a firmware build for the ESP32-C6 with the ESP32 Arduino core 3.x.
set -e
mkdir -p build
g++ -std=c++20 -Wall -Wextra -Werror -I ntc_temp test/*.cpp ntc_temp/*.cpp -o build/host_tests
./build/host_tests
arduino-cli compile --fqbn esp32:esp32:esp32c6 --warnings default ntc_temp >build/compile.log 2>&1 \
    || { grep -E "error|Error" build/compile.log | head -30; exit 1; }
echo "firmware build ok"
