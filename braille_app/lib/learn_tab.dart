import 'dart:async';
import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import "TTS.dart";
import "bluetooth.dart";

class BrailleAlphabet {
  static const List<int> binaryLetterSums = [
    1, 3, 9, 25, 17, 11, 27, 19, 10, 26,
    5, 7, 13, 29, 21, 15, 31, 23, 14, 30,
    37, 39, 58, 45, 61, 53
  ];

  static int getCurrentLetterCode(int letterCode) {
    return binaryLetterSums[letterCode];
  }

  static List<int> dotNumbers(int letterIndex) {
    final code = binaryLetterSums[letterIndex];
    return [
      for (int i = 0; i < 6; i++)
        if ((code & (1 << i)) != 0) i + 1,
    ];
  }

  static String describeDots(int letterIndex) {
    final numbers = dotNumbers(letterIndex);

    if (numbers.length == 1) return "dot ${numbers.first}";

    final allButLast = numbers.sublist(0, numbers.length - 1).join(", ");
    return "dots $allButLast and ${numbers.last}";
  }

  static const List<String> spokenNames = [
    "eigh", "bee", "see", "dee", "ee", "eff", "jee", "aitch", "eye", "jay",
    "kay", "el", "em", "en", "oh", "pee", "cue", "are", "ess", "tee",
    "you", "vee", "double you", "ex", "why", "zee",
  ];

  static String spokenLetter(String letter) {
    final index = letter.toLowerCase().codeUnitAt(0) - 'a'.codeUnitAt(0);

    if (index < 0 || index >= spokenNames.length) return letter;
    return spokenNames[index];
  }
}

class LearnTab extends StatefulWidget {
  final BrailleDevice device;
  final bool isActive;

  const LearnTab({super.key, required this.device, required this.isActive});

  @override
  State<LearnTab> createState() => _LearnTabState();
}

class _LearnTabState extends State<LearnTab> {
  StreamSubscription<int>? pressSubscription;

  Set<int> pressedButtons = {};
  Set<int> correctButtons = {};

  int wordAmount = 5;
  int currentLetterIndex = 0;
  String randomisedText = "";

  Map<int, Color> letterColors = {};
  Random random = Random();

  @override
  void initState() {
    super.initState();

    loadRandomWords();
    pressSubscription = widget.device.onPress.listen(submitBrailleButtons);
  }

  @override
  void dispose() {
    pressSubscription?.cancel();
    super.dispose();
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
      textToSpeech(
        "letter, ${BrailleAlphabet.spokenLetter(randomisedText[0])}",
      );
    }
  }

  Future<void> submitBrailleButtons([int? receivedInteger]) async {
    if (!widget.isActive) return; // ignore presses meant for another tab

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
      textToSpeech(
        "$feedback. Next, letter "
        "${BrailleAlphabet.spokenLetter(randomisedText[currentLetterIndex])}",
      );
    } else {
      textToSpeech("$feedback. Exercise completed!");
    }

    if (receivedInteger != null) {
      await widget.device.sendBrailleResult(isCorrect);
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
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;

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
                          color: letterColors[index] ?? textColor,
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    }),
                  ),
                  textAlign: TextAlign.center,
                ),
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
                          child: Semantics(
                            label: 'Dot ${col * 3 + row + 1}',
                            selected: pressedButtons
                                .contains(1 << (col * 3 + row)),
                            child: const SizedBox.shrink(),
                          ),
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
}