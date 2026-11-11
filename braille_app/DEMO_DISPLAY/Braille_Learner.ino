#include <Arduino.h>
#include <lvgl.h>
#include <Wire.h>
#include "pins_config.h"
#include "AXS15231B.h"
#include "Arduino_DriveBus_Library.h"
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <atomic>


static const int W = 180;
static const int H = 640;

static lv_disp_draw_buf_t disp_buf;
static lv_disp_drv_t disp_drv;
static lv_color_t *drawBuffer = nullptr;

std::shared_ptr<Arduino_IIC_DriveBus> IIC_Bus = std::make_shared<Arduino_HWIIC>(TOUCH_IICSDA, TOUCH_IICSCL, &Wire);
std::atomic<bool> resetRequested{false};

bool dotStates[6] = {false};
uint8_t dotIndices[6] = {0, 1, 2, 3, 4, 5};
lv_obj_t *dotButtons[6];
char brailleMap[64];

static const uint8_t read_touchpad_cmd[] = {
    0xB5, 0xAB, 0xA5, 0x5A,
    0x00, 0x00, 0x00, 0x08,
    0x00, 0x00, 0x00
};

//BLE
#define SERVICE_UUID "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define MASK_CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define CONTROL_CHARACTERISTIC_UUID "a0c14c2b-ce60-4e5e-9a25-946aa608cb37"

std::atomic<bool> deviceConnected{false};

class BrailleServiceCallbacks : public BLEServerCallbacks
{
  public:
  void onConnect(BLEServer *pServer) override
  {
    deviceConnected.store(true);
    Serial.println("BLE connected!");
  }

  void onDisconnect(BLEServer *pServer) override
  {
    deviceConnected.store(false);
    BLEDevice::startAdvertising();
    Serial.println("BLE disconnected!");
  }
};

class BrailleCharacteristicCallbacks : public BLECharacteristicCallbacks
{
  public:
  void onWrite(BLECharacteristic *pCharacteristic) override
  {
    std::string value = pCharacteristic->getValue();

    if (value.length() == 1)
    {
      uint8_t command = static_cast<uint8_t>(value[0]);
      if(command == 0x01)
      {
        resetRequested.store(true);
        Serial.println("Correct!");
      }
      else if(command == 0x02)
      {
        resetRequested.store(true);
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

uint8_t getBrailleMask()
{
  uint8_t mask = 0;

  for (int i = 0; i < 6; i++)
  {
    if(dotStates[i])
    {
      mask |= (1 << i);
    }
  }
  return mask;
}


volatile bool touchInterruptFlag = false;

void AXS15231_Touch()
{
  touchInterruptFlag = true;
} 

void flush_px(lv_disp_drv_t * disp_drv, const lv_area_t * area, lv_color_t * color_p)
{
    Serial.println("LVGL flush called");
    int32_t x, y;
    x = (area->x2 - area->x1) + 1;
    y = (area->y2 - area->y1) + 1;
    lcd_PushColors(area->x1, area->y1, x, y, reinterpret_cast<uint16_t*>(color_p));
    lv_disp_flush_ready(disp_drv);
} 

void button_event_cb(lv_event_t *event)
{ 
  if(lv_event_get_code(event) == LV_EVENT_CLICKED)
  {
    void *userData = lv_event_get_user_data(event);
    uint8_t *indexPointer = static_cast<uint8_t *>(userData);
    uint8_t index = *indexPointer;
    dotStates[index] = !dotStates[index];
    Serial.println("Button Clicked");
    lv_obj_t *clickedButton = lv_event_get_target(event);
  
    if(dotStates[index])
    {
      lv_obj_set_style_bg_color(clickedButton, lv_color_hex(0x90D5FF), LV_PART_MAIN);
    }
    else
    {
      lv_obj_set_style_bg_color(clickedButton, lv_color_hex(0x808080), LV_PART_MAIN);
    }
    lv_obj_invalidate(lv_scr_act());
  }
}

lv_obj_t *rec_let_lbl;
BLECharacteristic *maskCharacteristic = nullptr;
BLECharacteristic *controlCharacteristic = nullptr;

void resetBrailleCell()
{
  for (int i = 0; i < 6; i++)
  {
    dotStates[i] = false;
    lv_obj_set_style_bg_color(dotButtons[i], lv_color_hex(0x808080), LV_PART_MAIN);
  }
  lv_label_set_text(rec_let_lbl, "-");
  lv_obj_invalidate(lv_scr_act()); 
}

void reset_btn_cb(lv_event_t *event)
{
  if(lv_event_get_code(event) == LV_EVENT_CLICKED)
  {
    resetBrailleCell();
  }
}

void submit_btn_cb(lv_event_t *event)
{
    if (lv_event_get_code(event) == LV_EVENT_CLICKED)
    {
        uint8_t mask_submit = getBrailleMask();
        maskCharacteristic->setValue(&mask_submit, 1);
        if (deviceConnected.load())
        {
          maskCharacteristic->notify();
        }
        char letter = brailleMap[mask_submit];
        char text[2] = {letter, '\0'};

        lv_label_set_text(rec_let_lbl, text);
        lv_obj_invalidate(lv_scr_act());
    }
}

void read_cord(lv_indev_drv_t *drv, lv_indev_data_t *data)
{

   uint8_t touchData[8] = {0};
   static bool isPressed = false;
   static uint32_t lastReadTime = 0;
   static uint16_t lastX = 0;
   static uint16_t lastY = 0;

   if(touchInterruptFlag == true && millis() - lastReadTime >= 20)
   {
     touchInterruptFlag = false;
     lastReadTime = millis();

     IIC_Bus->IIC_ReadCData_Data(0x3B, read_touchpad_cmd, sizeof(read_touchpad_cmd), touchData, sizeof(touchData));
     uint8_t fingers_number = touchData[1];
     uint8_t touch_event = touchData[2] >> 4;
     Serial.printf("Fingers=%u Event=0x%02X\n",fingers_number, touch_event);

     if(fingers_number == 1 && (touch_event == 0x00 || touch_event == 0x08))
     {
       isPressed = true;
       uint16_t touch_x = ((uint16_t)(touchData[4] & 0x0F) << 8) | touchData[5];
       uint16_t touch_y = ((uint16_t)(touchData[2] & 0x0F) << 8) | touchData[3];
       lastX = touch_x;
       lastY = H - touch_y;
     }
     else if (touch_event == 0x04)
     {
      isPressed = false;
     }
   }
   data->point.x = lastX;
   data->point.y = lastY;
   data->state = isPressed ? LV_INDEV_STATE_PRESSED : LV_INDEV_STATE_RELEASED;
}


void setup() {

  Serial.begin(115200);
  lv_init();
  pinMode(TOUCH_RES, OUTPUT);
  pinMode(TOUCH_INT, INPUT_PULLUP);

  digitalWrite(TOUCH_RES, HIGH);
  delay(2);

  digitalWrite(TOUCH_RES, LOW);
  delay(100);

  digitalWrite(TOUCH_RES, HIGH);
  delay(2);

  IIC_Bus->begin();

  axs15231_init();
  pinMode(TFT_BL, OUTPUT);
  digitalWrite(TFT_BL, HIGH);
  
  //BLE
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


  Serial.println("Initialized");
  if(psramFound() == false)
  {
    Serial.print("No PSRAM available!");
    while (true)
    {
      delay(1000);
    }
  }

  drawBuffer = (lv_color_t*) ps_malloc(W * H * sizeof(lv_color_t));

  if(drawBuffer == nullptr)
  {
    Serial.print("Memory allocation failed!");
    while (true)
    {
      delay(1000);
    }
  }

  //interupt setup
  pinMode(TOUCH_INT, INPUT_PULLUP);
  attachInterrupt(digitalPinToInterrupt(TOUCH_INT), AXS15231_Touch , FALLING);

  lv_disp_draw_buf_init(&disp_buf, drawBuffer, NULL, W * H);
  lv_disp_drv_init(&disp_drv);
  disp_drv.hor_res = W;
  disp_drv.ver_res = H;
  disp_drv.draw_buf = &disp_buf;
  disp_drv.flush_cb = flush_px;
  lv_disp_drv_register(&disp_drv);

  //object creation, styling
  lv_obj_t *screen = lv_scr_act();
  
  //button creation loop
  for (int i = 0; i < 2; i++)
  {
    for (int j = 0; j < 3; j++)
    {
      int x = 15 + i * 80;
      int y = 180 + j * 100;
      lv_obj_t *button = lv_obj_create(screen);
      dotButtons[i * 3 + j] = button;
      lv_obj_set_size(button, 70, 70);
      lv_obj_set_pos(button, x, y);
      lv_obj_set_style_bg_color(button, lv_color_hex(0x808080), LV_PART_MAIN);
      lv_obj_set_style_radius(button, 10, LV_PART_MAIN);
      lv_obj_set_style_border_width(button, 0, LV_PART_MAIN);
      lv_obj_add_event_cb(button, button_event_cb, LV_EVENT_CLICKED, &dotIndices[i * 3 + j]);
    }
  }

  for(int i = 0; i < 64; i++)
  {
    brailleMap[i] = '?';
  }

  brailleMap[1] = 'A';
  brailleMap[3] = 'B';
  brailleMap[9] = 'C';
  brailleMap[25] = 'D';
  brailleMap[17] = 'E';
  brailleMap[11] = 'F';  
  brailleMap[27] = 'G';  
  brailleMap[19] = 'H';  
  brailleMap[10] = 'I';  
  brailleMap[26] = 'J';
  brailleMap[5]  = 'K';  
  brailleMap[7]  = 'L'; 
  brailleMap[13] = 'M';  
  brailleMap[29] = 'N';  
  brailleMap[21] = 'O';  
  brailleMap[15] = 'P';  
  brailleMap[31] = 'Q';  
  brailleMap[23] = 'R';  
  brailleMap[14] = 'S';  
  brailleMap[30] = 'T';  
  brailleMap[37] = 'U';  
  brailleMap[39] = 'V';  
  brailleMap[58] = 'W';  
  brailleMap[45] = 'X';  
  brailleMap[61] = 'Y';  
  brailleMap[53] = 'Z';  

  //reset
  lv_obj_t *reset_btn = lv_obj_create(screen);
  lv_obj_t *rst_lbl;
  lv_obj_set_size(reset_btn, 70, 70);
  lv_obj_set_pos(reset_btn, 15, 470);
  lv_obj_set_style_bg_color(reset_btn, lv_color_hex(0xFF2C2C), LV_PART_MAIN);
  lv_obj_set_style_radius(reset_btn, 10, LV_PART_MAIN);
  lv_obj_set_style_border_width(reset_btn, 0, LV_PART_MAIN);
  lv_obj_add_event_cb(reset_btn, reset_btn_cb, LV_EVENT_CLICKED, NULL);

  rst_lbl = lv_label_create(reset_btn);
  lv_label_set_text(rst_lbl, "RESET");
  lv_obj_center(rst_lbl);
  
  //submit (for now nuthing but a button)
  lv_obj_t *submit_btn = lv_obj_create(screen);
  lv_obj_t *sbm_lbl;
  lv_obj_set_size(submit_btn, 70, 70);
  lv_obj_set_pos(submit_btn, 95, 470);
  lv_obj_set_style_bg_color(submit_btn, lv_color_hex(0x111184), LV_PART_MAIN);
  lv_obj_set_style_radius(submit_btn, 10, LV_PART_MAIN);
  lv_obj_set_style_border_width(submit_btn, 0, LV_PART_MAIN);
  lv_obj_add_event_cb(submit_btn, submit_btn_cb, LV_EVENT_CLICKED, NULL);

  sbm_lbl = lv_label_create(submit_btn);
  lv_label_set_text(sbm_lbl, "SUBMIT");
  lv_obj_center(sbm_lbl);

  //leter recognition
  lv_obj_t *rec_letter = lv_obj_create(screen);
  lv_obj_set_size(rec_letter, 180, 30);
  lv_obj_set_pos(rec_letter, 0, 40);
  lv_obj_set_style_bg_color(rec_letter, lv_color_hex(0x000000), LV_PART_MAIN);
  lv_obj_set_style_radius(rec_letter, 10, LV_PART_MAIN);
  lv_obj_set_style_border_width(rec_letter, 0, LV_PART_MAIN);

  rec_let_lbl = lv_label_create(rec_letter);
  lv_label_set_text(rec_let_lbl, "_");
  lv_obj_center(rec_let_lbl);

  //input delcaration
  static lv_indev_drv_t touch;
  lv_indev_drv_init(&touch);
  touch.type = LV_INDEV_TYPE_POINTER;
  touch.read_cb = read_cord;
  lv_indev_drv_register(&touch);
}

void loop() {

  if(resetRequested.exchange(false))
  {
    resetBrailleCell();
  }
  lv_timer_handler();
  delay(5);
}
