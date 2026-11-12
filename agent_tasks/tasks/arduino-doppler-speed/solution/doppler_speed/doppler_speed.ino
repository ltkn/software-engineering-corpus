// Speed from a 24 GHz Doppler radar IF output on an ESP32-C6 ADC pin.
#include "doppler.h"

constexpr int IF_PIN = 2;
constexpr size_t N = 512;
constexpr uint32_t SAMPLE_RATE = 5000;

hw_timer_t* timer = nullptr;
// The ISR only flags that a sample is due; reading the ADC happens in loop(),
// because analogRead is not safe to call from an interrupt.
volatile uint32_t due = 0;
uint16_t samples[N];
size_t filled = 0;

void ARDUINO_ISR_ATTR onTimer() { due = due + 1; }

void setup() {
    Serial.begin(115200);
    analogReadResolution(12);
    timer = timerBegin(1000000);                        // core 3.x: frequency in Hz
    timerAttachInterrupt(timer, &onTimer);
    timerAlarm(timer, 1000000 / SAMPLE_RATE, true, 0);  // autoreload, unlimited
}

void loop() {
    while (due > 0 && filled < N) {
        noInterrupts();
        due = due - 1;
        interrupts();
        samples[filled++] = analogRead(IF_PIN);
    }
    if (filled < N) return;
    filled = 0;
    DopplerConfig cfg;
    cfg.sampleRateHz = SAMPLE_RATE;
    const DopplerResult r = analyze(samples, N, cfg);
    if (r.target) Serial.printf("%.1f km/h (%.0f Hz)\n", r.speedKmh, r.frequencyHz);
}
