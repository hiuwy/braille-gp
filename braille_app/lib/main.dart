
import 'dart:async';
import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

import "TTS.dart";
import "crash_log.dart";

class BrailleAlphabet {
  static const List<int> binaryLetterSums = [
    1, 3, 9, 25, 17, 11, 27, 19, 10, 26,
    5, 7, 13, 29, 21, 15, 31, 23, 14, 30,
    37, 39, 58, 45, 61, 53
  ];

  static int getCurrentLetterCode(int letterCode) {
    return binaryLetterSums[letterCode];
  }
}

void main() {
  // Logs every error (and every tap) to the terminal; see crash_log.dart.
  runAppWithCrashLogging(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final FlutterReactiveBle ble = FlutterReactiveBle();

  static final esp32ServiceUUID = Uuid.parse(
    '4fafc201-1fb5-459e-8fcc-c5c9c331914b'
  );

  static final inputUUID = Uuid.parse(
    'beb5483e-36e1-4688-b7f5-ea07361b26a8'
  );

  static final outputUUID = Uuid.parse(
    'a0c14c2b-ce60-4e5e-9a25-946aa608cb37'
  );

  String? esp32ID;
  bool isConnected = false;

  StreamSubscription<BleStatus>? bleStatusSubscription;
  StreamSubscription<DiscoveredDevice>? scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? connectionSubscription;
  StreamSubscription<List<int>>? inputSubscription;

  Set<int> pressedButtons = {};
  Set<int> correctButtons = {};

  int wordAmount = 5;
  int currentLetterIndex = 0;
  String randomisedText = "";

  Map<int, Color> letterColors = {};
  Random random = Random();

  // LEARN IS THE DEFAULT OPENING TAB
  int _selectedIndex = 1;

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }


  // LOAD RANDOM PRACTICE WORDS
  Future<void> loadRandomWords() async {
    String csvData = await rootBundle.loadString(
      'assets/braille_words_100.csv'
    );

    List<String> chosenWords = csvData
        .split(RegExp(r'\r?\n'))
        .map((word) => word.trim())
        .where((word) => word.isNotEmpty)
        .toList();

    if (chosenWords.length < wordAmount) {
      debugPrint("Not enough words in the CSV file.");
      return;
    }

    List<String> randomWords = [];

    for (int i = 0; i < wordAmount; i++) {
      int randomIndex = random.nextInt(chosenWords.length);
      randomWords.add(chosenWords.removeAt(randomIndex));
    }

    if (!mounted) return;

    setState(() {
      randomisedText = randomWords.join(' ');
      currentLetterIndex = 0;
      letterColors.clear();
      pressedButtons.clear();
      correctButtons.clear();
    });

    // ANNOUNCE THE FIRST LETTER
    if (randomisedText.isNotEmpty) {
      textToSpeech("letter ${randomisedText[0]}");
    }
  }

  // FIND THE BRAILLELEARNER DEVICE
  Future<void> scanForBrailleDevice() async {
    final permissions = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    if (!permissions[Permission.bluetoothScan]!.isGranted ||
        !permissions[Permission.bluetoothConnect]!.isGranted) {
      debugPrint("Bluetooth permissions not granted");
      return;
    }

    if (ble.status != BleStatus.ready) {
      debugPrint("Bluetooth status: ${ble.status}");
      return;
    }

    debugPrint("Looking for BrailleLearner");

    await scanSubscription?.cancel();

    scanSubscription = ble.scanForDevices(
      withServices: [esp32ServiceUUID],
      scanMode: ScanMode.lowLatency,
    ).listen((device) {
      debugPrint("Found device called ${device.name}");

      if (device.name == "BrailleLearner") {
        scanSubscription?.cancel();

        if (!mounted) return;

        setState(() {
          esp32ID = device.id;
        });

        debugPrint("BrailleLearner found");
        connectToBrailleDevice();
      }
    }, onError: (error, stack) {
      CrashLog.error("BLE", "Scanning error: $error", stack);
    });
  }

  // CONNECT TO THE ESP32
  void connectToBrailleDevice() {
    if (esp32ID == null) return;

    debugPrint("Connecting...");

    connectionSubscription?.cancel();

    connectionSubscription = ble.connectToDevice(
      id: esp32ID!,
      servicesWithCharacteristicsToDiscover: {
        esp32ServiceUUID: [inputUUID, outputUUID],
      },
      connectionTimeout: const Duration(seconds: 10),
    ).listen((connectionState) {
      CrashLog.log(
        "BLE",
        "Connection state: ${connectionState.connectionState}"
        "${connectionState.failure != null ? " (reason: ${connectionState.failure})" : ""}",
      );

      if (connectionState.connectionState ==
          DeviceConnectionState.connected) {
        if (!mounted) return;

        setState(() {
          isConnected = true;
        });

        listenForBraille();
      }

      if (connectionState.connectionState ==
          DeviceConnectionState.disconnected) {
        inputSubscription?.cancel();
        inputSubscription = null;

        if (!mounted) return;

        setState(() {
          isConnected = false;
        });
      }
    }, onError: (error, stack) {
      CrashLog.error("BLE", "Connection error: $error", stack);
    });
  }

  // LISTEN FOR BRAILLE INPUT FROM THE ESP32
  void listenForBraille() {
    final deviceId = esp32ID;
    if (deviceId == null) return;

    final characteristic = QualifiedCharacteristic(
      serviceId: esp32ServiceUUID,
      characteristicId: inputUUID,
      deviceId: deviceId,
    );

    inputSubscription?.cancel();

    inputSubscription = ble.subscribeToCharacteristic(
      characteristic,
    ).listen((data) {
      if (data.length == 1) {
        int receivedInteger = data[0];

        CrashLog.log("BLE", "Received integer: $receivedInteger");

        submitBrailleButtons(receivedInteger);
      }
    }, onError: (error, stack) {
      CrashLog.error("BLE", "Notification error: $error", stack);
    });
  }

  // CHECK THE SUBMITTED BRAILLE LETTER
  Future<void> submitBrailleButtons([int? receivedInteger]) async {
    if (currentLetterIndex >= randomisedText.length) {
      debugPrint("Exercise finished");
      return;
    }

    String nextLetter = randomisedText[currentLetterIndex];

    int nextletterIndex =
        nextLetter.toLowerCase().codeUnitAt(0) -
        'a'.codeUnitAt(0);

    if (nextletterIndex < 0 || nextletterIndex >= 26) {
      debugPrint("Invalid letter: $nextLetter");
      return;
    }

    int submittedButtonBinary = receivedInteger ?? pressedButtons.fold<int>(
      0,
      (sum, dot) => sum + dot,
    );

    bool isCorrect =
        submittedButtonBinary ==
        BrailleAlphabet.getCurrentLetterCode(nextletterIndex);

    if (!mounted) return;

    setState(() {
      letterColors[currentLetterIndex] =
          isCorrect ? Colors.grey : Colors.red;

      currentLetterIndex++;

      pressedButtons.clear();
      correctButtons.clear();

      // SKIP SPACES BETWEEN WORDS
      while (currentLetterIndex < randomisedText.length &&
          randomisedText[currentLetterIndex] == ' ') {
        currentLetterIndex++;
      }
    });

    // ANNOUNCE THE NEXT LETTER TO TYPE
    final feedback = isCorrect ? "Correct" : "Wrong";
    if (currentLetterIndex < randomisedText.length) {
      textToSpeech("$feedback. Next, letter ${randomisedText[currentLetterIndex]}");
    } else {
      textToSpeech("$feedback. Exercise completed!");
    }

    // SEND THE RESULT TO THE ESP32
    if (receivedInteger != null) {
      await sendBrailleResult(isCorrect);
    }

    if (currentLetterIndex >= randomisedText.length) {
      debugPrint("Exercise completed!");
    }
  }

  // SEND CORRECT OR INCORRECT RESULT TO ESP32
  Future<void> sendBrailleResult(bool isCorrect) async {
    final deviceId = esp32ID;
    if (deviceId == null || !isConnected) return;

    final characteristic = QualifiedCharacteristic(
      serviceId: esp32ServiceUUID,
      characteristicId: outputUUID,
      deviceId: deviceId,
    );

    int command = isCorrect ? 0x01 : 0x02;

    try {
      await ble.writeCharacteristicWithResponse(
        characteristic,
        value: [command],
      );

      CrashLog.log("BLE", "Sent result: $isCorrect, $command");
    } catch (error, stack) {
      CrashLog.error("BLE", "Failed to send command: $error", stack);
    }
  }

  // DISPLAY THE CORRECT BRAILLE DOTS
  void displayCorrectButtons() {
    if (currentLetterIndex >= randomisedText.length) return;

    int nextletterIndex =
        randomisedText[currentLetterIndex].toLowerCase().codeUnitAt(0) -
        'a'.codeUnitAt(0);

    if (nextletterIndex < 0 || nextletterIndex >= 26) return;

    int correctLetterCode =
        BrailleAlphabet.getCurrentLetterCode(nextletterIndex);

    correctButtons.clear();

    for (int i = 0; i < 6; i++) {
      int dotBinaryValue = 1 << i;

      if ((correctLetterCode & dotBinaryValue) != 0) {
        correctButtons.add(dotBinaryValue);
      }
    }
  }

  @override
  void initState() {
    super.initState();

    // LOAD THE SPEECH MODEL ONCE IN THE BACKGROUND
    initTextToSpeech();

    loadRandomWords();

    bleStatusSubscription = ble.statusStream.listen((status) {
      debugPrint("Bluetooth status changed: $status");

      if (status == BleStatus.ready) {
        scanForBrailleDevice();
      }
    });
  }

  @override
  void dispose() {
    scanSubscription?.cancel();
    connectionSubscription?.cancel();
    inputSubscription?.cancel();
    bleStatusSubscription?.cancel();

    super.dispose();
  }

  // LEARN PAGE
  Widget _buildLearnPage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ElevatedButton(
            onPressed: scanForBrailleDevice,
            child: const Text("FIND DEVICE"),
          ),

          Text(
            isConnected ? "Device connected" : "Device disconnected",
            style: const TextStyle(fontSize: 14),
          ),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text.rich(
                  TextSpan(
                    children: List.generate(randomisedText.length, (index) {
                      return TextSpan(
                        text: randomisedText[index],
                        style: TextStyle(
                          decoration: index == currentLetterIndex
                              ? TextDecoration.underline
                              : TextDecoration.none,
                          color: letterColors[index] ?? Colors.black,
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    }),
                  ),
                ),
              ),

              // SPEAK THE EXERCISE TEXT
              IconButton(
                icon: const Icon(Icons.volume_up),
                iconSize: 32,
                tooltip: "Speak text",
                onPressed: randomisedText.isEmpty
                    ? null
                    : () => textToSpeech(randomisedText),
              ),
            ],
          ),

          const SizedBox(height: 35),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (int col = 0; col < 2; col++)
                Column(
                  children: [
                    for (int row = 0; row < 3; row++)
                      SizedBox(
                        width: 70,
                        height: 70,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: pressedButtons.contains(
                              1 << (col * 3 + row)
                            )
                                ? Colors.blue
                                : correctButtons.contains(
                                    1 << (col * 3 + row)
                                  )
                                    ? const Color.fromARGB(
                                        255, 168, 189, 198
                                      )
                                    : Colors.grey,
                          ),
                          onPressed: () {
                            int dotBinaryValue = 1 << (col * 3 + row);

                            setState(() {
                              if (pressedButtons.contains(dotBinaryValue)) {
                                pressedButtons.remove(dotBinaryValue);
                              } else {
                                pressedButtons.add(dotBinaryValue);
                              }
                            });
                          },
                          child: const Text(""),
                        ),
                      ),
                  ],
                ),
            ],
          ),

          const SizedBox(height: 35),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () {
                  submitBrailleButtons();
                },
                child: const Text("SUBMIT"),
              ),

              const SizedBox(width: 10),

              ElevatedButton(
                onPressed: () {
                  setState(() {
                    if (currentLetterIndex > 0) {
                      currentLetterIndex--;

                      while (currentLetterIndex > 0 &&
                          randomisedText[currentLetterIndex] == ' ') {
                        currentLetterIndex--;
                      }

                      letterColors.remove(currentLetterIndex);
                      displayCorrectButtons();
                    }

                    pressedButtons.clear();
                  });

                  // ANNOUNCE THE LETTER AGAIN AFTER BACKSPACE
                  
                },
                child: const Text("BACKSPACE"),
              ),
            ],
          ),

          const SizedBox(height: 20),

          ElevatedButton(
            onPressed: loadRandomWords,
            child: const Text("NEW EXERCISE"),
          ),
        ],
      ),
    );
  }

  // LIBRARY PAGE
  Widget _buildLibraryPage() {
    return const Center(
      child: Text(
        'Library',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
      ),
    );
  }

  // SETTINGS PAGE
  Widget _buildSettingsPage() {
    return const Center(
      child: Text(
        'Settings',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      home: Scaffold(
        backgroundColor: Colors.white,

        body: IndexedStack(
          index: _selectedIndex,
          children: [
            _buildLibraryPage(),
            _buildLearnPage(),
            _buildSettingsPage(),
          ],
        ),

        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          selectedItemColor: Colors.blue,
          unselectedItemColor: Colors.grey,
          type: BottomNavigationBarType.fixed,

          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.library_books),
              label: 'Library',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.school),
              label: 'Learn',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
