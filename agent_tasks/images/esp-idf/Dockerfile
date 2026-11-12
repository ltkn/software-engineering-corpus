# ESP-IDF tasks: host unit tests (linux target, Unity) and a firmware build for the ESP32-C6.
FROM espressif/idf:v6.1
# docker exec does not run the image entrypoint, so idf.py sets up its environment itself.
COPY idf.py /usr/local/bin/idf.py
ENV CCACHE_DIR=/opt/ccache CCACHE_BASEDIR=/work IDF_CCACHE_ENABLE=1
# Warm ccache with the same layout and sdkconfig the tasks use.
COPY warmup /work
RUN chmod 755 /usr/local/bin/idf.py \
    && cd /work/test/host && idf.py --preview set-target linux build >/dev/null \
    && cd /work && idf.py set-target esp32c6 build >/dev/null \
    && rm -rf /work/* /work/.[!.]* ; true
WORKDIR /work
