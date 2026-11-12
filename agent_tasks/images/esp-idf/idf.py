#!/bin/bash
# idf.py with the ESP-IDF environment loaded (docker exec skips the image entrypoint).
. /opt/esp/idf/export.sh >/dev/null 2>&1
exec python "$IDF_PATH/tools/idf.py" "$@"
