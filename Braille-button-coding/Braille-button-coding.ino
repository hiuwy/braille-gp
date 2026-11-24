// Test sketch: read all 8 latching buttons and print which are pressed.
// Wiring: each button between a GPIO pin and GND (pull-up).
// The internal pull-up holds the pin HIGH; pressing the button pulls it to GND (LOW).

// --- Pins (as wired on the breadboard, 23 Nov 2026) ---
// None of these are strapping pins (0, 2, 5, 12, 15) or input-only pins (34-39),
// so all have an internal pull-up and cannot stop the board from booting.
const int BUTTON_1_PIN = 13;
const int BUTTON_2_PIN = 14;
const int BUTTON_3_PIN = 27;
const int BUTTON_4_PIN = 26;
const int BUTTON_5_PIN = 33;
const int BUTTON_6_PIN = 32;
const int BUTTON_DELETE_PIN = 18;   // X
const int BUTTON_SUBMIT_PIN = 19;   // V

// Mechanical contacts "bounce" for a few ms when they change.
// We only accept a new state if it stays stable this long.
const unsigned long DEBOUNCE_MS = 30;

// With pull-up wiring, a pressed button reads LOW.
const int PRESSED = LOW;

const int NUM_BUTTONS = 8;
const int buttonPins[NUM_BUTTONS] = {
  BUTTON_1_PIN, BUTTON_2_PIN, BUTTON_3_PIN, BUTTON_4_PIN,
  BUTTON_5_PIN, BUTTON_6_PIN, BUTTON_DELETE_PIN, BUTTON_SUBMIT_PIN
};
const char* buttonNames[NUM_BUTTONS] = {
  "Button 1", "Button 2", "Button 3", "Button 4",
  "Button 5", "Button 6", "Delete (X)", "Submit (V)"
};

int stableState[NUM_BUTTONS];          // last accepted (debounced) state
int lastRawState[NUM_BUTTONS];         // last raw reading
unsigned long lastChangeMs[NUM_BUTTONS];

// Prints one line with every button that is pressed right now,
// so you can see the whole combination at a glance.
void printPressedList() {
  Serial.print("   Now pressed: ");
  bool any = false;
  for (int i = 0; i < NUM_BUTTONS; i++) {
    if (stableState[i] == PRESSED) {
      Serial.print(buttonNames[i]);
      Serial.print("  ");
      any = true;
    }
  }
  if (!any) {
    Serial.print("none");
  }
  Serial.println();
}

void setup() {
  Serial.begin(115200);
  for (int i = 0; i < NUM_BUTTONS; i++) {
    pinMode(buttonPins[i], INPUT_PULLUP);
    stableState[i] = digitalRead(buttonPins[i]);
    lastRawState[i] = stableState[i];
    lastChangeMs[i] = 0;

    // Print the start state, because a latching button may already be locked in
    Serial.print("Start: ");
    Serial.print(buttonNames[i]);
    Serial.print(" (GPIO ");
    Serial.print(buttonPins[i]);
    Serial.println(stableState[i] == PRESSED ? ") PRESSED (locked)" : ") RELEASED");
  }
  Serial.println("8-button test started");
}

void loop() {
  unsigned long now = millis();
  for (int i = 0; i < NUM_BUTTONS; i++) {
    int raw = digitalRead(buttonPins[i]);
    if (raw != lastRawState[i]) {       // contact moved (or bounced): restart timer
      lastRawState[i] = raw;
      lastChangeMs[i] = now;
    }
    if (raw != stableState[i] && (now - lastChangeMs[i]) >= DEBOUNCE_MS) {
      stableState[i] = raw;             // stable long enough: accept it
      Serial.print(now);
      Serial.print(" ms  ");
      Serial.print(buttonNames[i]);
      Serial.print(" (GPIO ");
      Serial.print(buttonPins[i]);
      Serial.println(raw == PRESSED ? ") PRESSED (locked)" : ") RELEASED");
      printPressedList();
    }
  }
}
