import 'package:flutter/material.dart';
import "package:flutter/services.dart";
import "dart:math";


class BrailleAlphabet {
  static const List<int> letters = [
    1, 3, 9, 25, 17, 11, 27, 19, 10, 26, // A-J
    5, 7, 13, 29, 21, 15, 31, 23, 14, 30, // K-T
    37, 39, 58, 45, 61, 53               // U-Z
  ];

  static int getCode(int letter) {
    return letters[letter];
    // function to return the braille code for the asked letter
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
  Set<int> pressedButtons = {};
  Set<int> correctButtons = {};
  int currentIndex = 0;
  String toType = "";
  Map<int, Color> letterColors = {};
  Random random = Random();

  Future<void> loadRandomWord() async {
    String csvData = await rootBundle.loadString(
      'assets/braille_words_100.csv'
    ); // csv import

    List<String> words = csvData
        .split(RegExp(r'\r?\n'))
        .map((word) => word.trim())
        .where((word) => word.isNotEmpty)
        .toList();
      // splits at end of line and makes it a list

    List<String> randomWords = [];

    for (int i = 0; i < 5; i++) {
      int randomIndex = random.nextInt(words.length);

      randomWords.add(words.removeAt(randomIndex));
    } // select 5 words to show

    if (!mounted) return;

    setState(() {
      toType = randomWords.join(' ');
      currentIndex = 0;
      letterColors.clear();
      pressedButtons.clear();
    });
  }

  void submitBraille(String savedBraille) {
    if (currentIndex >= toType.length) {
      print("finished");
      return;
    }

    String nextLetter = toType[currentIndex];
    // change toType to the next letter

    int letterIndex =
        nextLetter.toLowerCase().codeUnitAt(0) - 'a'.codeUnitAt(0);
        // gets index of the next letter in the alphabet (from 0)

    int submittedCode = pressedButtons.fold<int>(
      0,
      (sum, dot) => sum + dot,
    ); // adds the dot value to sum to compare it to the sum of other characters in binary

    bool isCorrect =
        submittedCode == BrailleAlphabet.getCode(letterIndex);

    setState(() { // update app state
      letterColors[currentIndex] =
          isCorrect ? Colors.grey : Colors.red;
      // coloring of the word

      currentIndex++;
      // move index
      pressedButtons.clear();
      correctButtons.clear();
      // reset buttons

      while (currentIndex < toType.length &&
          toType[currentIndex] == ' ') {
        currentIndex++;
      } // if the words arent finished, and next letter is space, 1 more
    });
  }

  void displayWrongLetter() {
    int letterIndex =
        toType[currentIndex].toLowerCase().codeUnitAt(0) -
        'a'.codeUnitAt(0);
        // letter index of last letter in alphabet (currentIndex gets pushed back when u press backspace)

    int correctCode = BrailleAlphabet.getCode(letterIndex);

    correctButtons.clear();
    // clears the correct buttons so it can replace them if you press backspace multiple times

    for (int i = 0; i < 6; i++) {
      int dotValue = 1 << i;
      // binary calculation

      if ((correctCode & dotValue) != 0) {
        correctButtons.add(dotValue);
      } // ai generated, it compares the binaries of both and if it isnt 0 (so there is a difference) it adds the buttons' value to correctButtons to display
    }
  }

  @override
  void initState() {
    super.initState();

    loadRandomWord();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      home: Scaffold( // what you see when you open the app
        backgroundColor: Colors.white,

        body: Center( // core
          child: Column( // whats in body
            mainAxisAlignment: MainAxisAlignment.center,
            // this has to be outside of children since you're aligning the column, not the innards

            children: [

              Text.rich( // word display
                TextSpan(
                  children: List.generate(toType.length, (index) {
                    return TextSpan(
                      text: toType[index], // words to type
                      style: TextStyle(

                        decoration: index == currentIndex
                            ? TextDecoration.underline 
                            // underline the curr letter
                            : TextDecoration.none,

                        color: letterColors[index] ?? Colors.black,
                        // get the color if it was wrong or right, otherwise make it black

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
                                int dotValue = 1 << (col * 3 + row);

                                setState(() {
                                  if (pressedButtons.contains(dotValue)) {
                                    pressedButtons.remove(dotValue);
                                    // if a pressed button is inside and you press it, it reverts color
                                  } else {
                                    pressedButtons.add(dotValue);
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
                      submitBraille("");
                    },
                    child: const Text("SUBMIT"),
                  ),

                  const SizedBox(width: 10),

                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        if (currentIndex > 0) {
                          // just a check so you don't go under 0,
                          // it changes index and resets letter color

                          currentIndex--;

                          while (currentIndex > 0 &&
                              toType[currentIndex] == ' ') {
                            currentIndex--;
                          } // if you backspace and go over a space, it goes 1 more

                          letterColors.remove(currentIndex);

                          displayWrongLetter();
                        }

                        pressedButtons.clear();
                      });
                      // reset buttons to be empty
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