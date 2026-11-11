FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential cmake bats shellcheck jq ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /work
