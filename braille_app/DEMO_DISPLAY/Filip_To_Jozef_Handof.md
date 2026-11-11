# Braille Learner — Flutter BLE Integration Guide

**Prepared for:** Jozef — Flutter Developer  
**Updated:** November 11, 2026  
**Hardware:** LilyGO T-Display S3 Long (ESP32-S3)  
**ESP32 framework:** Arduino-ESP32 2.0.14  
**Communication:** Bluetooth Low Energy (BLE)

**Project status: ESP32 BLE communication successfully tested in both directions using nRF Connect. Flutter integration is the next milestone.**

---

## 1. Project overview

Braille Learner is an educational system consisting of an ESP32-S3 touchscreen device and a Flutter application.

The ESP32 device provides a six-dot Braille input interface, recognizes English Braille letters A–Z, displays the recognized letter locally, and communicates with Flutter over BLE.

The Flutter application is responsible for generating exercises, validating submissions, recording results, and managing quiz progression.

### Division of responsibilities

**ESP32-S3 firmware**

- Handles six independently selectable Braille dots.
- Calculates a six-bit mask from the selected dots.
- Recognizes and displays letters A–Z locally.
- Transmits the mask when Submit is pressed.
- Receives correct/incorrect responses from Flutter.
- Resets its input after either valid response.
- Supports a physical Reset button.

**Flutter application**

- Discovers and connects to the ESP32.
- Subscribes to Braille mask notifications.
- Generates questions and determines the expected answer.
- Validates incoming Braille masks.
- Sends correct/incorrect commands to the ESP32.
- Handles scoring, feedback, and learning progression.

**Important:** The ESP32 sends the raw numeric Braille mask, not the recognized letter.

---

## 2. Verified hardware functionality

The following has been tested successfully on the ESP32-S3.

| Feature | Verification | Status |
|---|---|---|
| Six touchscreen dots | Independently toggled on device | PASS |
| Physical Reset | All dots reset to gray | PASS |
| Braille display interface | LVGL display and touch functional | PASS |
| Local letter recognition | Recognition logic implemented; letters reported working | PASS |
| BLE advertising | Device discoverable through nRF Connect | PASS |
| BLE connection | Stable connection established with nRF Connect | PASS |
| ESP32 → Phone | Correct hexadecimal masks received through Notify | PASS |
| Phone → ESP32 | Commands `0x01` and `0x02` written using nRF Connect | PASS |
| Remote reset | Both commands successfully trigger Reset | PASS |
| Flutter integration | Not yet implemented/tested | PENDING |
| Extended reliability testing | Not completed | PENDING |

**Confirmed integration result:** The ESP32 successfully transmits Braille masks to nRF Connect, receives the two response commands, and executes the appropriate reset functionality.

This establishes that the BLE protocol works with a real GATT client.

The exact set of letters individually tested was not recorded, so a full 26-letter regression test is still recommended.

---

## 3. BLE GATT configuration

### Device roles

| Device | BLE role | GATT role |
|---|---|---|
| ESP32-S3 | Peripheral | Server |
| Flutter phone | Central | Client |

**Advertised device name:** `BrailleLearner`

### Service UUID

```text
4fafc201-1fb5-459e-8fcc-c5c9c331914b
```

### Characteristic A — Braille Mask

```text
UUID:
beb5483e-36e1-4688-b7f5-ea07361b26a8

Property: NOTIFY
Direction: ESP32 → Flutter
Format: 1 byte, unsigned integer
Range: 0–63
```

The ESP32 sends the current Braille mask **only when Submit is pressed**.

Flutter must enable notifications on this characteristic after establishing the BLE connection.

The ESP32 uses a BLE2902 CCCD descriptor to support notification subscription.

### Characteristic B — Control

```text
UUID:
a0c14c2b-ce60-4e5e-9a25-946aa608cb37

Property: WRITE
Direction: Flutter → ESP32
Format: 1 byte, unsigned integer
```

Commands:

| Value | Meaning | ESP32 action |
|---|---|---|
| `0x01` | Correct | Reset dots and clear letter |
| `0x02` | Incorrect | Reset dots and clear letter |
| Other | Unsupported command | Ignore |

Both supported commands have been successfully tested using nRF Connect.

**Important:** Use a normal GATT Write operation, not Write Without Response, because the characteristic is configured with `PROPERTY_WRITE`.

---

## 4. Braille payload format

The ESP32 uses standard six-dot Braille numbering:

```text
1   4
2   5
3   6
```

Each dot occupies a specific bit of the transmitted byte:

| Dot | Bit position | Decimal value |
|---|---|---|
| 1 | 0 | 1 |
| 2 | 1 | 2 |
| 3 | 2 | 4 |
| 4 | 3 | 8 |
| 5 | 4 | 16 |
| 6 | 5 | 32 |

### Example — Letter C

Active dots: 1 and 4.

```text
Dot 1 = 1
Dot 4 = 8

Mask = 1 + 8 = 9

Decimal: 9
Hex:     0x09
Binary:  00001001
```

The ESP32 sends **one byte containing `0x09`**.

It does not send ASCII `"9"`, the string `"0x09"`, or the character `"C"`.

In Flutter, the notification bytes can be interpreted directly as unsigned byte values.

---

## 5. Complete Braille A–Z mask mapping

The following mappings match the ESP32 firmware's lookup table.

| Letter | Active dots | Decimal | Hex |
|---|---|---:|---|
| A | 1 | 1 | `0x01` |
| B | 1,2 | 3 | `0x03` |
| C | 1,4 | 9 | `0x09` |
| D | 1,4,5 | 25 | `0x19` |
| E | 1,5 | 17 | `0x11` |
| F | 1,2,4 | 11 | `0x0B` |
| G | 1,2,4,5 | 27 | `0x1B` |
| H | 1,2,5 | 19 | `0x13` |
| I | 2,4 | 10 | `0x0A` |
| J | 2,4,5 | 26 | `0x1A` |
| K | 1,3 | 5 | `0x05` |
| L | 1,2,3 | 7 | `0x07` |
| M | 1,3,4 | 13 | `0x0D` |
| N | 1,3,4,5 | 29 | `0x1D` |
| O | 1,3,5 | 21 | `0x15` |
| P | 1,2,3,4 | 15 | `0x0F` |
| Q | 1,2,3,4,5 | 31 | `0x1F` |
| R | 1,2,3,5 | 23 | `0x17` |
| S | 2,3,4 | 14 | `0x0E` |
| T | 2,3,4,5 | 30 | `0x1E` |
| U | 1,3,6 | 37 | `0x25` |
| V | 1,2,3,6 | 39 | `0x27` |
| W | 2,4,5,6 | 58 | `0x3A` |
| X | 1,3,4,6 | 45 | `0x2D` |
| Y | 1,3,4,5,6 | 61 | `0x3D` |
| Z | 1,3,5,6 | 53 | `0x35` |

The first version supports only A–Z.

Other combinations are not recognized as letters. The ESP32 displays `?` for unmapped patterns but can still transmit their raw masks.

An empty cell corresponds to `0x00`.

---

## 6. Complete communication flow

### Example: Flutter asks the user to write C

**Step 1 — Flutter generates the exercise**

```text
Expected letter: C
Expected mask:   0x09
```

**Step 2 — User enters the Braille pattern**

On the ESP32 touchscreen, the user activates dots 1 and 4.

No BLE messages are sent during dot selection.

**Step 3 — User presses Submit**

The ESP32:

1. Calculates the current bitmask.
2. Recognizes the corresponding character locally.
3. Updates the letter label on its display.
4. Sends the raw mask using a BLE notification if connected.

```text
ESP32 → Flutter
Payload: 09
```

**Step 4 — Flutter receives and validates**

```dart
final int receivedMask = notificationBytes[0];
final bool isCorrect = receivedMask == expectedMask;
```

This is illustrative Dart application logic, not a complete BLE implementation.

**Step 5 — Flutter responds**

For a correct answer:

```text
Flutter → ESP32
Payload: 01
```

For an incorrect answer:

```text
Flutter → ESP32
Payload: 02
```

**Step 6 — ESP32 resets**

The ESP32's BLE Write callback receives the response and records a reset request.

The main LVGL loop performs the actual reset, which:

- Sets all six dot states to inactive.
- Changes all six dots to gray.
- Clears the recognized-letter label.

Flutter can then present the next exercise or allow the user to retry.

### Important implementation detail

The ESP32 does **not** immediately reset when Submit is pressed.

The reset occurs after receiving `0x01` or `0x02`, or when the user presses the physical Reset button.

---

## 7. Flutter integration requirements

The Flutter BLE implementation should:

1. Request appropriate Bluetooth permissions for the target platform.
2. Scan for the Braille Learner device or service UUID.
3. Connect to the ESP32 peripheral.
4. Discover the Braille Learner GATT service.
5. Locate both characteristics by UUID.
6. Enable notifications on the Mask characteristic.
7. Listen for incoming one-byte payloads.
8. Compare each mask with the active exercise's expected mask.
9. Write `0x01` or `0x02` to the Control characteristic.
10. Handle disconnection, reconnection, and notification re-subscription.

### Recommended application logic

```text
On question generated:
    Save expected Braille mask

On Mask notification:
    Validate payload length
    Read unsigned byte
    Compare with expected mask
    Record result
    Write 0x01 or 0x02 to Control characteristic

On disconnection:
    Stop relying on the previous connection
    Reconnect when appropriate
    Rediscover characteristics if required
    Re-enable notifications
```

**Do not validate an answer by reading the letter from the ESP32 display.** The application should validate the received numerical mask.

---

## 8. Verified BLE test results

The following tests were reported successful with nRF Connect:

### Test A — ESP32 → Phone

- Connected nRF Connect to the ESP32.
- Enabled notifications on the Mask characteristic.
- Entered Braille patterns.
- Pressed Submit.
- Observed the correct hexadecimal payloads arriving on the phone.

**Result: PASS**

### Test B — Phone → ESP32 (Correct)

- Wrote the binary byte `0x01` to the Control characteristic.
- ESP32 processed the command.
- The Braille cell reset successfully.

**Result: PASS**

### Test C — Phone → ESP32 (Incorrect)

- Wrote the binary byte `0x02` to the Control characteristic.
- ESP32 processed the command.
- The Braille cell reset successfully.

**Result: PASS**

### Test D — Connection stability

- The device established a stable connection with nRF Connect.
- Earlier attempts through Windows Bluetooth showed repeated connections and disconnections.

**Result: Phone connection verified; Windows behavior remains unresolved.**

### Overall conclusion

**Bidirectional GATT communication is verified on the physical ESP32-S3 and a mobile BLE client.**

This gives the Flutter developer a working embedded endpoint to integrate against.

---

## 9. Remaining work and limitations

The following are not currently blockers for initial Flutter development, but they should be addressed or tested before release.

### Duplicate submissions

The ESP32 currently permits repeated Submit presses while waiting for Flutter's response.

The app should avoid counting multiple submissions unintentionally. A future firmware improvement could disable Submit until a result arrives.

### Empty or unsupported patterns

An empty cell sends `0x00`. Unsupported Braille patterns can also be transmitted.

Flutter should define how to handle these inputs.

### Lost responses

If Flutter disconnects or fails to write a response, the ESP32 does not currently implement an acknowledgement timeout.

The physical Reset button remains available.

### BLE subscription

Receiving notifications requires an active BLE subscription, not merely a connection.

After reconnection, Flutter should ensure notifications are enabled again.

### Validation and reliability

A final test should cover all 26 letter mappings, repeated submissions, repeated resets, disconnects, and reconnects.

### No quiz logic in firmware

The ESP32 does not generate random questions or decide whether a submitted answer is correct.

All learning and quiz logic belongs to Flutter.

---

## 10. Quick integration reference

```text
DEVICE NAME
BrailleLearner

BLE ROLE
ESP32: Peripheral / GATT Server
Flutter: Central / GATT Client

SERVICE UUID
4fafc201-1fb5-459e-8fcc-c5c9c331914b

MASK CHARACTERISTIC
beb5483e-36e1-4688-b7f5-ea07361b26a8

PROPERTY
NOTIFY

PAYLOAD
One binary uint8 byte
Valid bitmask range: 0–63

CONTROL CHARACTERISTIC
a0c14c2b-ce60-4e5e-9a25-946aa608cb37

PROPERTY
WRITE

PAYLOAD
0x01 = Correct
0x02 = Incorrect

BOTH RESPONSES
Trigger Braille cell reset

TRANSMISSION
Only when Submit is pressed

LOCAL ESP32 OUTPUT
Displays recognized Braille letter

VALIDATION
Performed by Flutter against expected mask

BLE HARDWARE TEST STATUS
Notify: PASS
Write 0x01: PASS
Write 0x02: PASS
Remote reset: PASS

FLUTTER INTEGRATION
PENDING
```

---

## 11. Recommended next milestone

The immediate objective is to replace nRF Connect with Flutter as the GATT client.

A successful first Flutter integration test should demonstrate:

- Flutter establishes a connection to `BrailleLearner`.
- Flutter subscribes to the Mask characteristic.
- The user enters a Braille pattern and presses Submit.
- Flutter receives the correct one-byte mask.
- Flutter validates the answer.
- Flutter writes `0x01` or `0x02`.
- The ESP32 resets automatically.

**The ESP32 side of this communication sequence has already been verified using nRF Connect. The next task is implementing and validating the same sequence in Flutter.**

---

**End of developer handoff — Braille Learner BLE Protocol v1.0**