#include <Wire.h>
void setup() { Serial.begin(115200); Wire.begin(); analogReadResolution(12); }
void loop() { Serial.println(analogReadMilliVolts(1)); delay(1000); }
