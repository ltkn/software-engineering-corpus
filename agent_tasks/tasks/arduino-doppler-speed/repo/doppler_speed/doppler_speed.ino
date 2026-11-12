// Speed from a 24 GHz Doppler radar IF output on an ESP32-C6 ADC pin.
#include "doppler.h"

constexpr int IF_PIN = 2;
constexpr size_t N = 512;
constexpr uint32_t SAMPLE_RATE = 5000;

hw_timer_t* timer = nullptr;
volatile uint16_t buffer[N];
volatile size_t filled = 0;

void IRAM_ATTR onTimer() {
    if (filled < N) buffer[filled++] = analogRead(IF_PIN);
}

void setup() {
    Serial.begin(115200);
    analogReadResolution(12);
    timer = timerBegin(0, 80, true);                      // 1 MHz tick
    timerAttachInterrupt(timer, &onTimer, true);
    timerAlarmWrite(timer, 1000000 / SAMPLE_RATE, true);
    timerAlarmEnable(timer);
}

void loop() {
    if (filled < N) return;
    uint16_t copy[N];
    for (size_t i = 0; i < N; ++i) copy[i] = buffer[i];
    filled = 0;
    DopplerConfig cfg;
    cfg.sampleRateHz = SAMPLE_RATE;
    DopplerResult r = analyze(copy, N, cfg);
    if (r.target) Serial.printf("%.1f km/h (%.0f Hz)\n", r.speedKmh, r.frequencyHz);
}
