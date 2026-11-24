// Step 2: dots -> mask -> letter, shown on the Serial Monitor (no Bluetooth yet).
//
// Button logic on this device:
//  - Dots 1-6 are LATCHING buttons with REVERSED logic:
//      pushed down (locked) = default = pin LOW
//      up                   = active dot = pin HIGH
//  - Submit (V) and Reset (X) are normal momentary push buttons:
//      pressed = pin LOW (button to GND, internal pull-up)
//
// Flow:
//  READY            -> user raises dots, presses V -> mask + letter printed
//  WAITING_ANSWER   -> the app will answer later over Bluetooth. For now YOU are
//                      the app: type 1 (correct) or 2 (incorrect) in the Serial Monitor.
//  WAITING_DOTS_DOWN-> device ignores Submit until all 6 dots are pushed down again,
//                      so an old letter can never be sent twice.
//  Reset (X) in READY: cancels the letter locally (nothing sent to the app) and goes
//                      to WAITING_DOTS_DOWN, the same wait as after an answer.

// --- Pins (as wired on the breadboard, 23 Nov 2026) ---
const int DOT_1_PIN = 13;
const int DOT_2_PIN = 14;
const int DOT_3_PIN = 27;
const int DOT_4_PIN = 26;
const int DOT_5_PIN = 33;
const int DOT_6_PIN = 32;
const int RESET_PIN = 18;    // X
const int SUBMIT_PIN = 19;   // V

const int NUM_DOTS = 6;
const int dotPins[NUM_DOTS] = {DOT_1_PIN, DOT_2_PIN, DOT_3_PIN, DOT_4_PIN, DOT_5_PIN, DOT_6_PIN};

// Reversed logic for the latching dots: a dot is active when its button is UP.
const int DOT_ACTIVE = HIGH;
// Normal logic for the momentary V and X buttons.
const int BUTTON_PRESSED = LOW;

// Contacts bounce for a few ms; accept a new state only after it is stable this long.
const unsigned long DEBOUNCE_MS = 30;

// Answer bytes, same values as Filip's BLE protocol (Control characteristic).
const char ANSWER_CORRECT = '1';    // will be 0x01 over Bluetooth
const char ANSWER_INCORRECT = '2';  // will be 0x02 over Bluetooth

// --- Braille table: same masks as Filip's handover document ---
// Mask bits: dot 1 = 1, dot 2 = 2, dot 3 = 4, dot 4 = 8, dot 5 = 16, dot 6 = 32.
const uint8_t LETTER_MASKS[26] = {
  1,  3,  9, 25, 17, 11, 27, 19, 10, 26,   // a-j
  5,  7, 13, 29, 21, 15, 31, 23, 14, 30,   // k-t
  37, 39, 58, 45, 61, 53                   // u-z
};

// --- Debounced input (one per pin) ---
struct DebouncedPin {
  int pin;
  int stableState;
  int lastRaw;
  unsigned long lastChangeMs;
};

DebouncedPin dots[NUM_DOTS];
DebouncedPin submitButton;
DebouncedPin resetButton;

void initPin(DebouncedPin &p, int pin) {
  pinMode(pin, INPUT_PULLUP);
  p.pin = pin;
  p.stableState = digitalRead(pin);
  p.lastRaw = p.stableState;
  p.lastChangeMs = 0;
}

// Updates the debounced state. Returns true only at the moment the state changes.
bool updatePin(DebouncedPin &p, unsigned long now) {
  int raw = digitalRead(p.pin);
  if (raw != p.lastRaw) {
    p.lastRaw = raw;
    p.lastChangeMs = now;
  }
  if (raw != p.stableState && (now - p.lastChangeMs) >= DEBOUNCE_MS) {
    p.stableState = raw;
    return true;
  }
  return false;
}

// --- Device states ---
enum DeviceState { READY, WAITING_ANSWER, WAITING_DOTS_DOWN };
DeviceState state = READY;

uint8_t readMask() {
  uint8_t mask = 0;
  for (int i = 0; i < NUM_DOTS; i++) {
    if (dots[i].stableState == DOT_ACTIVE) {
      mask |= (1 << i);   // dot 1 -> bit 0 ... dot 6 -> bit 5
    }
  }
  return mask;
}

// Returns 'a'-'z', or '?' if the mask is not a letter (0 = empty cell).
char maskToLetter(uint8_t mask) {
  for (int i = 0; i < 26; i++) {
    if (LETTER_MASKS[i] == mask) {
      return 'a' + i;
    }
  }
  return '?';
}

void printDots(uint8_t mask) {
  Serial.print("dots up: ");
  bool any = false;
  for (int i = 0; i < NUM_DOTS; i++) {
    if (mask & (1 << i)) {
      Serial.print(i + 1);
      Serial.print(' ');
      any = true;
    }
  }
  if (!any) {
    Serial.print("none ");
  }
}

void setup() {
  Serial.begin(115200);
  for (int i = 0; i < NUM_DOTS; i++) {
    initPin(dots[i], dotPins[i]);
  }
  initPin(submitButton, SUBMIT_PIN);
  initPin(resetButton, RESET_PIN);

  Serial.println("Step 2: braille letter test");
  if (readMask() != 0) {
    // Start in the "wait" state so dots left up from before are not sent by accident.
    state = WAITING_DOTS_DOWN;
    Serial.println("Some dots are up. Push all dots down to start.");
  } else {
    Serial.println("READY: raise dots for a letter, then press V.");
  }
}

void loop() {
  unsigned long now = millis();

  // Report every dot change, so you can follow what the device sees.
  for (int i = 0; i < NUM_DOTS; i++) {
    if (updatePin(dots[i], now)) {
      Serial.print("Dot ");
      Serial.print(i + 1);
      Serial.println(dots[i].stableState == DOT_ACTIVE ? " UP (active)" : " DOWN (default)");
    }
  }

  bool submitPressed = updatePin(submitButton, now) && submitButton.stableState == BUTTON_PRESSED;
  bool resetPressed  = updatePin(resetButton, now)  && resetButton.stableState == BUTTON_PRESSED;

  switch (state) {
    case READY:
      if (resetPressed) {
        // Reset (X) is local only: nothing is sent to the app.
        // Like after an answer, the user must push all dots down before typing again.
        Serial.println("RESET: letter cancelled (nothing sent). Push all dots down to continue.");
        state = WAITING_DOTS_DOWN;
        break;
      }
      if (submitPressed) {
        uint8_t mask = readMask();
        Serial.print("SUBMIT  ");
        printDots(mask);
        Serial.print(" mask = ");
        Serial.print(mask);
        Serial.print("  letter = ");
        Serial.println(maskToLetter(mask));
        Serial.println("Waiting for answer: type 1 (correct) or 2 (incorrect)");
        state = WAITING_ANSWER;
      }
      break;

    case WAITING_ANSWER:
      if (submitPressed) {
        Serial.println("V ignored: still waiting for the answer");
      }
      if (resetPressed) {
        // The letter was already sent, so the app's answer must still arrive first.
        Serial.println("X ignored: still waiting for the answer");
      }
      if (Serial.available() > 0) {
        char c = Serial.read();
        if (c == ANSWER_CORRECT || c == ANSWER_INCORRECT) {
          Serial.println(c == ANSWER_CORRECT ? "Answer: CORRECT" : "Answer: INCORRECT");
          Serial.println("Push all dots down to continue.");
          state = WAITING_DOTS_DOWN;
        }
        // Other characters (like the newline from the Serial Monitor) are ignored.
      }
      break;

    case WAITING_DOTS_DOWN:
      if (submitPressed || resetPressed) {
        // Say which dots are still up, so a stuck dot or loose wire is easy to find.
        Serial.print("Ignored: push all dots down first. Still ");
        printDots(readMask());
        Serial.println();
      }
      if (readMask() == 0) {
        Serial.println("All dots down. READY for the next letter.");
        state = READY;
      }
      break;
  }
}
