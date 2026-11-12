# Arduino tasks: arduino-cli with the ESP32 core 3.x (compile for ESP32-C6) and g++ for host tests of the logic.
FROM debian:trixie-slim
ARG CLI_VERSION=1.6.0
ARG ESP32_CORE=3.3.12
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl g++ make python3 \
    && case "$(uname -m)" in aarch64|arm64) A=ARM64 ;; *) A=64bit ;; esac \
    && curl -fsSL "https://github.com/arduino/arduino-cli/releases/download/v${CLI_VERSION}/arduino-cli_${CLI_VERSION}_Linux_${A}.tar.gz" | tar -xz -C /usr/local/bin arduino-cli \
    && rm -rf /var/lib/apt/lists/*
RUN arduino-cli config init \
    && arduino-cli config set board_manager.additional_urls https://espressif.github.io/arduino-esp32/package_esp32_index.json \
    && arduino-cli core update-index && arduino-cli core install "esp32:esp32@${ESP32_CORE}" \
    && cd /root/.arduino15 && rm -rf staging \
    && find packages/esp32/tools -maxdepth 1 -name 'esp32*-libs' ! -name esp32c6-libs -exec rm -rf {} + \
    && rm -rf packages/esp32/tools/esp-x32
# Only the ESP32-C6 (RISC-V) libraries and toolchain are kept: the tasks target the C6.
# Compile once so the core is cached and task builds are fast.
COPY warmup /tmp/warmup
RUN arduino-cli compile --fqbn esp32:esp32:esp32c6 /tmp/warmup/warmup && rm -rf /tmp/warmup
WORKDIR /work
