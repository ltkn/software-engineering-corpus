#!/bin/sh
# Host unit tests (ESP-IDF linux target, Unity), then the firmware build for the ESP32-C6.
set -e
ROOT=$(pwd)
cd "$ROOT/test/host"
idf.py --preview set-target linux build >"$ROOT/host-build.log" 2>&1 \
    || { grep -E "error|Error" "$ROOT/host-build.log" | head -40; exit 1; }
./build/host_test.elf
cd "$ROOT"
idf.py set-target esp32c6 build >"$ROOT/fw-build.log" 2>&1 \
    || { grep -E "error|Error" "$ROOT/fw-build.log" | head -40; exit 1; }
echo "firmware build ok"
