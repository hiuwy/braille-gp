
import 'dart:async';
import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import "TTS.dart";
import "crash_log.dart";
import "braille_device.dart";

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
  runAppWithCrashLogging(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final BrailleDevice device = BrailleDevice();
  late StreamSubscription<int> pressSubscription;

  Set<int> pressedButtons = {};
  Set<int> correctButtons = {};

  int wordAmount = 5;
  int currentLetterIndex = 0;
  String randomisedText = "";

  Map<int, Color> letterColors = {};
  Random random = Random();

  int _selectedIndex = 1;
  ThemeMode _themeMode = ThemeMode.light;

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
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

    if (randomisedText.isNotEmpty) {
      textToSpeech("letter ${randomisedText[0]}");
    }
  }

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

      while (currentLetterIndex < randomisedText.length &&
          randomisedText[currentLetterIndex] == ' ') {
        currentLetterIndex++;
      }
    });

    final feedback = isCorrect ? "Correct" : "Wrong";

    if (currentLetterIndex < randomisedText.length) {
      textToSpeech("$feedback. Next, letter ${randomisedText[currentLetterIndex]}");
    } else {
      textToSpeech("$feedback. Exercise completed!");
    }

    if (receivedInteger != null) {
      await device.sendBrailleResult(isCorrect);
    }

    if (currentLetterIndex >= randomisedText.length) {
      debugPrint("Exercise completed!");
    }
  }

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

    initTextToSpeech();
    loadRandomWords();

    device.addListener(() => setState(() {}));
    pressSubscription = device.onPress.listen(submitBrailleButtons);
    device.start();
  }

  @override
  void dispose() {
    pressSubscription.cancel();
    device.dispose();
    super.dispose();
  }

  Widget _buildLearnPage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
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
                          color: letterColors[index] ??
                            (_themeMode == ThemeMode.dark
                                ? Colors.white
                                : Colors.black),
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    }),
                  ),
                  textAlign: TextAlign.center
                ),
              ),

              /*IconButton(
                icon: const Icon(Icons.volume_up),
                iconSize: 32,
                tooltip: "Speak text",
                onPressed: randomisedText.isEmpty
                    ? null
                    : () => textToSpeech(randomisedText),
              ), */
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

  Widget _buildLibraryPage() {
    return const Center(
      child: Text(
        'Library',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildSettingsPage() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('dark mode'),
            secondary: Icon(
              _themeMode == ThemeMode.dark
                  ? Icons.dark_mode
                  : Icons.light_mode,
            ),
            value: _themeMode == ThemeMode.dark,
            onChanged: (value) {
              setState(() {
                _themeMode = value
                    ? ThemeMode.dark
                    : ThemeMode.light;
              });
            },
          ),

          ListTile(
            leading: Icon(
              device.isConnected
                  ? Icons.bluetooth_connected
                  : Icons.bluetooth_disabled,
            ),
            title: const Text('braille device'),
            trailing: ElevatedButton(
              onPressed: device.scanForBrailleDevice,
              style: ElevatedButton.styleFrom(
                backgroundColor: device.isConnected ? Colors.green : Colors.red,
                foregroundColor: Colors.white,
              ),
              child: Text(
                device.isConnected ? "found" : "find",
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: _themeMode,
      home: Scaffold(
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