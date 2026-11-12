# Godot 4.7 headless: GDScript tasks run their tests with the engine, no display.
FROM debian:trixie-slim
ARG GODOT_VERSION=4.7.2
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl unzip libfontconfig1 \
    && case "$(uname -m)" in aarch64|arm64) A=arm64 ;; *) A=x86_64 ;; esac \
    && curl -fsSL -o /tmp/godot.zip "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.${A}.zip" \
    && unzip -q /tmp/godot.zip -d /opt/godot && ln -s "/opt/godot/Godot_v${GODOT_VERSION}-stable_linux.${A}" /usr/local/bin/godot \
    && rm /tmp/godot.zip && apt-get purge -y curl unzip && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*
ENV HOME=/root
WORKDIR /work
