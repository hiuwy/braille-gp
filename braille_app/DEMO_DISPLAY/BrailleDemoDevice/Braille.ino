#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <atomic>

const int DOT_1_PIN = 13;
const int DOT_2_PIN = 14;
const int DOT_3_PIN = 27;
const int DOT_4_PIN = 26;
const int DOT_5_PIN = 33;
const int DOT_6_PIN = 32;
const int RESET_PIN = 18;    // X
const int SUBMIT_PIN = 19;   // Y

//BLE
#define SERVICE_UUID "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define MASK_CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define CONTROL_CHARACTERISTIC_UUID "a0c14c2b-ce60-4e5e-9a25-946aa608cb37"
BLECharacteristic *maskCharacteristic = nullptr;
BLECharacteristic *controlCharacteristic = nullptr;

std::atomic<bool> deviceConnected{false};
std::atomic<uint8_t> receivedCommand{0x00};
std::atomic<bool> disconnectRequested{false};

const int NUM_DOTS = 6;
const int dotPins[NUM_DOTS] = {DOT_1_PIN, DOT_2_PIN, DOT_3_PIN, DOT_4_PIN, DOT_5_PIN, DOT_6_PIN};

const int DOT_ACTIVE = HIGH;
const int BUTTON_PRESSED = LOW;
const unsigned long DEBOUNCE_MS = 30;
const uint8_t ANSWER_CORRECT = 0x01;    
const uint8_t ANSWER_INCORRECT = 0x02; 

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

class BrailleServiceCallbacks : public BLEServerCallbacks
{
  public:
  void onConnect(BLEServer *pServer) override
  {
    deviceConnected.store(true);
    Serial.println("BLE Connected!");
  }
  void onDisconnect(BLEServer *pServer) override
  {
    deviceConnected.store(false);
    disconnectRequested.store(true);
    BLEDevice::startAdvertising();
    Serial.println("BLE disconnected!");
  }
};

class BrailleCharacteristicCallbacks : public BLECharacteristicCallbacks
{
  public:
  void onWrite(BLECharacteristic *pCharacteristic) override
  {
     String value = pCharacteristic->getValue();

     if (value.length() == 1)
     {
      uint8_t command = static_cast<uint8_t>(value[0]);
      if(command == 0x01)
      {
        receivedCommand.store(0x01);
        Serial.println("Correct!");
      }
      else if(command == 0x02)
      {
        receivedCommand.store(0x02);
        Serial.println("Incorrect!");
      }
      else
      {
        Serial.println("Unknown command!");
      }
     }
     Serial.println("BLE Received!");
  }
};

void setup() {
  Serial.begin(115200);
  BLEDevice::init("BrailleLearner");

  BLEServer *pServer = BLEDevice::createServer();
  BLEService *pService = pServer->createService(SERVICE_UUID);
  maskCharacteristic = pService->createCharacteristic(MASK_CHARACTERISTIC_UUID, BLECharacteristic::PROPERTY_NOTIFY);
  maskCharacteristic->addDescriptor(new BLE2902());
  controlCharacteristic = pService->createCharacteristic(CONTROL_CHARACTERISTIC_UUID, BLECharacteristic::PROPERTY_WRITE);
  pServer->setCallbacks(new BrailleServiceCallbacks());
  controlCharacteristic->setCallbacks(new BrailleCharacteristicCallbacks());
  pService->start();

  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMaxPreferred(0x12);
  BLEDevice::startAdvertising();
  
  for (int i = 0; i < NUM_DOTS; i++) 
  {
    initPin(dots[i], dotPins[i]);
  }
  initPin(submitButton, SUBMIT_PIN);
  initPin(resetButton, RESET_PIN);

  Serial.println("Step 2: braille letter test");
  if (readMask() != 0) 
  {
    state = WAITING_DOTS_DOWN;
    Serial.println("Some dots are up. Push all dots down to start.");
  } 
  else 
  {
    Serial.println("READY: raise dots for a letter, then press V.");
  }
}

void loop() 
{
  unsigned long now = millis();
  for (int i = 0; i < NUM_DOTS; i++)
  {
    if (updatePin(dots[i], now)) 
    {
      Serial.print("Dot ");
      Serial.print(i + 1);
      Serial.println(dots[i].stableState == DOT_ACTIVE ? " UP (active)" : " DOWN (default)");
    }
  }

  bool submitPressed = updatePin(submitButton, now) && submitButton.stableState == BUTTON_PRESSED;
  bool resetPressed  = updatePin(resetButton, now)  && resetButton.stableState == BUTTON_PRESSED;
  
  if(disconnectRequested.exchange(false))
  {
    receivedCommand.store(0x00);
    if(state == WAITING_ANSWER)
    {
      state = WAITING_DOTS_DOWN;
    }
  }

  switch (state) 
  {
    case READY:
    {
      if (resetPressed) 
      {
        Serial.println("RESET: letter cancelled (nothing sent). Push all dots down to continue.");
        state = WAITING_DOTS_DOWN;
        break;
      }
      if (submitPressed) 
      {
        uint8_t mask = readMask();
        if (deviceConnected.load() == true)
        {
          receivedCommand.store(0x00);
          maskCharacteristic->setValue(&mask, 1);
          maskCharacteristic->notify();
          state = WAITING_ANSWER;
        }
        else
        {
          Serial.println("BLE not connected!");
        }
      }
      break;
    }

    case WAITING_ANSWER:
    {
      uint8_t command = receivedCommand.exchange(0x00);
      if(command == 0x01)
      {
        Serial.println("Correct!");
      }
      else if (command == 0x02)
      {
        Serial.println("Incorrect!");
      }
      if (command == 0x01 || command == 0x02)
      {
        state = WAITING_DOTS_DOWN;
      }
      break;
    }

    case WAITING_DOTS_DOWN:
      if (submitPressed || resetPressed) 
      {
        Serial.println("Ignored: push all dots down first. Still ");
      }
      if (readMask() == 0) 
      {
        Serial.println("All dots down. READY for the next letter.");
        state = READY;
      }
      break;
  }
}
