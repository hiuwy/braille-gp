import 'package:flutter/material.dart';
import "package:flutter/services.dart";
import "dart:math";
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'dart:async';
import 'package:permission_handler/permission_handler.dart';


class BrailleAlphabet {
  static const List<int> binaryLetterSums = [
    1, 3, 9, 25, 17, 11, 27, 19, 10, 26, // A-J
    5, 7, 13, 29, 21, 15, 31, 23, 14, 30, // K-T
    37, 39, 58, 45, 61, 53               // U-Z
  ];

  static int getCurrentLetterCode(int letterCode) {
    return binaryLetterSums[letterCode];
  }
}

void main() {
  runApp(const MyApp());
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
  // random import


  Future<void> loadRandomWords() async {
    String csvData = await rootBundle.loadString(
      'assets/braille_words_100.csv'
    );

    List<String> chosenWords = csvData
        .split(RegExp(r'\r?\n'))
        .map((word) => word.trim())
        .where((word) => word.isNotEmpty)
        .toList();
      // splits at end of line and makes it a list

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
    });
  }

Future<void> scanForBrailleDevice() async {

  final permissions = await [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
  ].request();

  if (!permissions[Permission.bluetoothScan]!.isGranted ||
      !permissions[Permission.bluetoothConnect]!.isGranted) {
    print("bluetooth permissions not granted");
    return;
  }

  if (ble.status != BleStatus.ready) {
    print("bluetooth status: ${ble.status}");
    return;
  }

  print("looking for braillelearner");

  scanSubscription?.cancel();

  scanSubscription = ble.scanForDevices(
    withServices: [esp32ServiceUUID],
    scanMode: ScanMode.lowLatency,
  ).listen((device) {

    print("found device called ${device.name}");

    if (device.name == "BrailleLearner") {
      scanSubscription?.cancel();

      setState(() {
        esp32ID = device.id;
      });

      print("braillelearner found");
      connectToBrailleDevice();
      // when it finds braillelearner, stops scanning and connects to it
    }
  }, onError: (error) {
    print("scanning error: $error");
  });}
  
  void connectToBrailleDevice() { 
    if (esp32ID == null) {
      return;
    }

    print("connecting.");

    connectionSubscription?.cancel();

    connectionSubscription = ble.connectToDevice( // this performs the conncetion
      id: esp32ID!,
      servicesWithCharacteristicsToDiscover: {
        esp32ServiceUUID: [inputUUID, outputUUID],
      },
      connectionTimeout: const Duration(seconds: 10),
    ).listen((connectionState) {

      print("connection state: ${connectionState.connectionState}");

      if (connectionState.connectionState ==
          DeviceConnectionState.connected) {
        setState(() {
          isConnected = true;
        });

        print("connected");
        listenForBraille();
      }

    }, onError: (error) {
      print("connection error: $error");
    });
  }

  void listenForBraille() {
    final characteristic = QualifiedCharacteristic(
      serviceId: esp32ServiceUUID,
      characteristicId: inputUUID,
      deviceId: esp32ID!,
    ); // bluetooth connection characteristic

    inputSubscription?.cancel();

    inputSubscription = ble.subscribeToCharacteristic(
      characteristic,
    ).listen((data) {

      if (data.length == 1) {
        int receivedInteger = data[0];
        print("received integer: $receivedInteger");
        submitBrailleButtons(receivedInteger);
      }

    }, onError: (error) {
      print("notification error: $error");
    });
  }

  Future<void> submitBrailleButtons([int? receivedInteger]) async {
    if (currentLetterIndex >= randomisedText.length) {
      print("finished");
      return;
    }

    String nextLetter = randomisedText[currentLetterIndex];

    int nextletterIndex =
        nextLetter.toLowerCase().codeUnitAt(0) - 'a'.codeUnitAt(0);
        // gets index of the next letter in the alphabet (from 0)

    int submittedButtonBinary = receivedInteger ?? pressedButtons.fold<int>(
      0,
      (sum, dot) => sum + dot,
    ); // adds the dot value to sum to compare it to the sum of other characters in binary

    bool isCorrect =
        submittedButtonBinary == BrailleAlphabet.getCurrentLetterCode(nextletterIndex);

    setState(() {
      letterColors[currentLetterIndex] =
          isCorrect ? Colors.grey : Colors.red;

      currentLetterIndex++;
      pressedButtons.clear();
      correctButtons.clear();

      while (currentLetterIndex < randomisedText.length &&
          randomisedText[currentLetterIndex] == ' ') {
        currentLetterIndex++;
      }
    });

    if (receivedInteger != null) {
      print("sent result");
      await sendBrailleResult(isCorrect);
    }
  }

  Future<void> sendBrailleResult(bool isCorrect) async {
    final characteristic = QualifiedCharacteristic(
      serviceId: esp32ServiceUUID,
      characteristicId: outputUUID,
      deviceId: esp32ID!,
    );

    int command = isCorrect ? 0x01 : 0x02;
    // sends a "1" byte if correct, else "2"

    try {
      await ble.writeCharacteristicWithResponse(
        characteristic,
        value: [command],
      );

      print("$command");

    } catch (error) {
      print("failed to send command: $error");
    }
  }

  void displayCorrectButtons() {
    int nextletterIndex =
        randomisedText[currentLetterIndex].toLowerCase().codeUnitAt(0) -
        'a'.codeUnitAt(0);
        // letter index of last letter in alphabet (currentLetterIndex gets pushed back when u press backspace)

    int correctLetterCode = BrailleAlphabet.getCurrentLetterCode(nextletterIndex);

    correctButtons.clear();
    // clears the correct buttons so it can replace them if you press backspace multiple times

    for (int i = 0; i < 6; i++) {
      int dotBinaryValue = 1 << i;

      if ((correctLetterCode & dotBinaryValue) != 0) {
        correctButtons.add(dotBinaryValue);
      } // ai generated, it compares the binaries of both and if it isnt 0 (so there is a difference) it adds the buttons' value to correctButtons to display
    }
  }

  @override
  void initState() {
    super.initState();

    loadRandomWords();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      scanForBrailleDevice();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      home: Scaffold(
        backgroundColor: Colors.white,

        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            // this has to be outside of children since you're aligning the column, not the innards

            children: [
              ElevatedButton(
                onPressed: scanForBrailleDevice,
                child: const Text("FIND DEVICE"),
              ),

              Text.rich(
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
                                ) // basically (col * 3 + row) squared
                                    ? Colors.blue
                                    : correctButtons.contains(1 << (col * 3 + row))
                                      ? const Color.fromARGB(255, 168, 189, 198)
                                      : Colors.grey, // blue if active, grey if not
                              ),

                              onPressed: () {
                                int dotBinaryValue = 1 << (col * 3 + row);

                                setState(() {
                                  if (pressedButtons.contains(dotBinaryValue)) {
                                    pressedButtons.remove(dotBinaryValue);
                                    // if a pressed button is inside and you press it, it reverts color
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
                    },
                    child: const Text("BACKSPACE"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}