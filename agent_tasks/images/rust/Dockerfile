FROM rust:1.99-slim-trixie
# clippy and rustfmt are part of the checks: the tasks must be idiomatic, not just pass.
RUN rustup component add clippy rustfmt
WORKDIR /work
