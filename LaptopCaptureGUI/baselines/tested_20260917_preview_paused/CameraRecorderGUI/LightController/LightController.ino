// Firmware for the Placido experiment's Arduino UNO light controller.
// Talks to ArduinoController.py over USB serial (9600 baud) using single
// ASCII-character commands:
//   'A' -- ARM:     light solid on
//   'Q' -- ACQUIRE: light flashes -- one 30fps frame on, one frame off
//                   (50% duty cycle relative to a 30fps frame period),
//                   i.e. an actual flash frequency of ~15Hz -- until 'S'
//   'S' -- SETTLE:  stop flashing, light goes solid on
//   'O' -- OFF:     light off
//
// The light isn't driven directly -- LIGHT_PIN drives a MOSFET gate that
// switches the actual light. If your wiring turns the light ON when the
// gate is LOW instead of HIGH, swap the HIGH/LOW in lightOn()/lightOff().
//
// Safety: any solid or flashing command expires after LIGHT_TIMEOUT_MS. This
// provides a hardware-side fallback if the laptop program stops responding.

const int LIGHT_PIN = 3;
const unsigned long LIGHT_TIMEOUT_MS = 15000;  // 15 seconds
// One 30fps frame period (1000ms/30fps ~= 33.3ms) per half-cycle: light
// held on for one whole frame, then off for one whole frame -- so each
// captured frame is fully lit or fully dark, not half-and-half. A full
// on+off cycle is therefore 2 frames (~66.7ms), i.e. ~15Hz actual flash
// frequency, not 30Hz -- 30fps/50%-duty describes the frame alignment,
// not the flash rate itself.
const unsigned long FLASH_HALF_PERIOD_MS = 33;

enum State { STATE_OFF, STATE_SOLID, STATE_FLASHING };
State state = STATE_OFF;

bool flashOn = false;
unsigned long lastToggle = 0;
unsigned long lightStateStartedAt = 0;

void lightOn() {
  digitalWrite(LIGHT_PIN, HIGH);
}

void lightOff() {
  digitalWrite(LIGHT_PIN, LOW);
}

void startLightState(State newState) {
  state = newState;
  lightStateStartedAt = millis();
}

void stopLight() {
  state = STATE_OFF;
  flashOn = false;
  lightStateStartedAt = 0;
  lightOff();
}

void setup() {
  pinMode(LIGHT_PIN, OUTPUT);
  lightOff();
  Serial.begin(9600);
}

void loop() {
  if (Serial.available()) {
    char c = Serial.read();
    switch (c) {
      case 'A':
        startLightState(STATE_SOLID);
        lightOn();
        break;
      case 'Q':
        startLightState(STATE_FLASHING);
        flashOn = false;
        lastToggle = millis();
        break;
      case 'S':
        startLightState(STATE_SOLID);
        lightOn();
        break;
      case 'O':
        stopLight();
        break;
      default:
        break;  // ignore anything else (e.g. stray newlines)
    }
  }

  if (state == STATE_FLASHING) {
    unsigned long now = millis();
    if (now - lastToggle >= FLASH_HALF_PERIOD_MS) {
      flashOn = !flashOn;
      flashOn ? lightOn() : lightOff();
      lastToggle = now;
    }
  }

  if (state != STATE_OFF &&
      millis() - lightStateStartedAt >= LIGHT_TIMEOUT_MS) {
    stopLight();
    Serial.println("SAFETY_OFF");
  }
}
