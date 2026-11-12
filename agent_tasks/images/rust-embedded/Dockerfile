# Embedded Rust tasks: no_std crates tested on the host and built for the ESP32-C6
# (riscv32imac) and Cortex-M4F targets. Crates are fetched once for offline builds.
FROM rust:1.99-slim-trixie
RUN rustup component add clippy rustfmt \
    && rustup target add riscv32imac-unknown-none-elf thumbv7em-none-eabihf
COPY warmup /tmp/warmup
RUN cd /tmp/warmup && cargo fetch && cargo test -q && cargo build -q --target riscv32imac-unknown-none-elf \
    && rm -rf /tmp/warmup
WORKDIR /work
