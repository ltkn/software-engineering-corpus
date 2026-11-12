#!/bin/sh
# Import (registers class_name scripts), then run the test suites headless.
set -e
godot --headless --path . --import >/dev/null 2>&1 || true
godot --headless --path . --script res://tests/run_tests.gd
