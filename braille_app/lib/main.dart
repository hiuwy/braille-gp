import 'package:flutter/material.dart';
import "package:flutter/services.dart";
import "dart:math";
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'dart:async';


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

  void scanForBrailleDevice() {
    if (ble.status != BleStatus.ready){
      print("bluetooth isnt connected");
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
          print("device id: $esp32ID");
        }

      }, onError: (error) {
        print("scanning error: $error");
      });
  }

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

  void submitBrailleButtons(String savedBraille) {
    if (currentLetterIndex >= randomisedText.length) {
      print("finished");
      return;
    }

    String nextLetter = randomisedText[currentLetterIndex];

    int nextletterIndex =
        nextLetter.toLowerCase().codeUnitAt(0) - 'a'.codeUnitAt(0);
        // gets index of the next letter in the alphabet (from 0)

    int submittedButtonBinary = pressedButtons.fold<int>(
      0,
      (sum, dot) => sum + dot,
    ); // adds the dot value to sum to compare it to the sum of other characters in binary

    bool isCorrect =
        submittedButtonBinary == BrailleAlphabet.getCurrentLetterCode(nextletterIndex);

    setState(() {
      letterColors[currentLetterIndex] =
          isCorrect ? Colors.grey : Colors.red;
      // coloring of the word

      currentLetterIndex++;
      pressedButtons.clear();
      correctButtons.clear();
      // clear area and move index

      while (currentLetterIndex < randomisedText.length &&
          randomisedText[currentLetterIndex] == ' ') {
        currentLetterIndex++;
      }
    });
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
      // binary calculation

      if ((correctLetterCode & dotBinaryValue) != 0) {
        correctButtons.add(dotBinaryValue);
      } // ai generated, it compares the binaries of both and if it isnt 0 (so there is a difference) it adds the buttons' value to correctButtons to display
    }
  }

  @override
  void initState() {
    super.initState();

    loadRandomWords();
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

              Text.rich( // word display
                TextSpan(
                  children: List.generate(randomisedText.length, (index) {
                    return TextSpan(
                      text: randomisedText[index],
                      style: TextStyle(

                        decoration: index == currentLetterIndex
                            ? TextDecoration.underline 
                            // underline the curr letter
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

                              child: const Text(""), // button syntax
                            ),
                          ),
                      ],
                    ),
                ],
              ),

              const SizedBox(height: 35),
              // space between the thing before and after

              Row(
                mainAxisAlignment: MainAxisAlignment.center,

                children: [

                  ElevatedButton(
                    onPressed: () {
                      submitBrailleButtons("");
                    },
                    child: const Text("SUBMIT"),
                  ),

                  const SizedBox(width: 10),

                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        if (currentLetterIndex > 0) {
                          // just a check so you don't go under 0,
                          // it changes index and resets letter color

                          currentLetterIndex--;

                          while (currentLetterIndex > 0 &&
                              randomisedText[currentLetterIndex] == ' ') {
                            currentLetterIndex--;
                          } // if you backspace and go over a space, it goes 1 more

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