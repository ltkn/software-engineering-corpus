// 10k NTC thermistor on an ESP32-C6 ADC pin, printed once a second.
#include "thermistor.h"

constexpr int NTC_PIN = 1;
NtcConfig config;
TempFilter filter(0.2f);

void setup() {
    Serial.begin(115200);
    analogReadResolution(12);
}

void loop() {
    const float mv = analogReadMilliVolts(NTC_PIN);
    const NtcReading r = ntcFromMillivolts(mv, config);
    switch (r.status) {
        case NtcStatus::Open:  Serial.println("sensor open"); break;
        case NtcStatus::Short: Serial.println("sensor shorted"); break;
        case NtcStatus::Ok:    Serial.printf("%.2f C\n", filter.update(r.celsius)); break;
    }
    delay(1000);
}
