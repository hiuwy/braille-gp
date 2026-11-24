import 'dart:async';
import 'dart:math';

import 'package:material_ui/material_ui.dart';

import "TTS.dart";
import "bluetooth.dart";
import "learn_tab.dart"; // for BrailleAlphabet

class AlphabetGamePage extends StatefulWidget {
  final BrailleDevice device;

  const AlphabetGamePage({super.key, required this.device});

  @override
  State<AlphabetGamePage> createState() => _AlphabetGamePageState();
}

class _AlphabetGamePageState extends State<AlphabetGamePage> {
  StreamSubscription<int>? pressSubscription;
  final Random random = Random();

  // The round: a shuffled list of letter indexes (0 = a, 25 = z).
  List<int> order = [];
  int position = 0; // where we are in `order`
  int score = 0;
  List<int> missed = []; // wrong on the first try, or a hint was used
  bool missedThisLetter = false;
  bool finished = false;
  bool endedEarly = false;

  Set<int> pressedButtons = {};
  String feedback = "";

  // True once the dots of the current letter have been revealed, by a wrong
  // answer or by the hint button. Cleared when the next letter appears.
  bool revealed = false;

  int get letterIndex => order[position];
  int get total => order.length;

  // Letters the user has dealt with: every letter passed so far, plus the
  // current one if they already got it wrong or used a hint.
  int get answered => position + (missedThisLetter ? 1 : 0);

  String _letterName(int index) =>
      String.fromCharCode('a'.codeUnitAt(0) + index);

  String get letter => _letterName(letterIndex);

  // How the current letter is pronounced by the speech engine.
  String get spokenLetter => BrailleAlphabet.spokenLetter(letter);

  String get dotsDescription => BrailleAlphabet.describeDots(letterIndex);

  // The bit values of the dots this letter needs, e.g. {1, 8} for "c".
  Set<int> get correctDots {
    final code = BrailleAlphabet.getCurrentLetterCode(letterIndex);
    return {
      for (int i = 0; i < 6; i++)
        if ((code & (1 << i)) != 0) 1 << i,
    };
  }

  @override
  void initState() {
    super.initState();

    _resetRound(List.generate(26, (i) => i));
    pressSubscription = widget.device.onPress.listen(submit);

    textToSpeech("Letter $spokenLetter");
  }

  @override
  void dispose() {
    pressSubscription?.cancel();
    super.dispose();
  }

  // Starts a fresh round with the given letters in random order.
  // Only changes fields, so call it inside setState (or from initState).
  void _resetRound(List<int> letters) {
    order = List<int>.from(letters)..shuffle(random);
    position = 0;
    score = 0;
    missed = [];
    missedThisLetter = false;
    finished = false;
    endedEarly = false;
    revealed = false;
    pressedButtons.clear();
    feedback = "";
  }

  // Records the current letter as missed (once) and shows its dots.
  // Only changes fields, so call it inside setState.
  void _markMissedAndReveal() {
    if (!missedThisLetter) {
      missed.add(letterIndex);
      missedThisLetter = true;
    }
    revealed = true;
  }

  void _speakResults() {
    if (answered == 0) {
      textToSpeech("Round finished. No letters answered.");
      return;
    }

    final intro = endedEarly ? "Round finished early." : "Round complete.";
    final summary = "$intro You got $score out of $answered.";

    if (missed.isEmpty) {
      textToSpeech("$summary Perfect!");
    } else {
      final names = missed
          .map((i) => BrailleAlphabet.spokenNames[i])
          .join(", ");
      textToSpeech("$summary Letters to practice: $names.");
    }
  }

  void submit([int? received]) {
    if (finished) return; // ignore device presses on the results screen

    final value = received ??
        pressedButtons.fold<int>(0, (sum, dot) => sum + dot);

    final correct =
        value == BrailleAlphabet.getCurrentLetterCode(letterIndex);

    if (correct) {
      setState(() {
        if (!missedThisLetter) score++;

        feedback = "Correct!";
        missedThisLetter = false;
        revealed = false;
        pressedButtons.clear();
        position++;

        if (position >= total) {
          finished = true;
        }
      });

      if (finished) {
        _speakResults();
      } else {
        textToSpeech("Correct. Next, letter $spokenLetter");
      }
    } else {
      // Stay on the same letter, reveal the answer and let them try again.
      setState(() {
        _markMissedAndReveal();
        feedback = "Wrong. Try again";
        pressedButtons.clear();
      });

      textToSpeech(
        "Wrong. Letter $spokenLetter is $dotsDescription. Try again.",
      );
    }

    if (received != null) {
      widget.device.sendBrailleResult(correct);
    }
  }

  // The hint costs the point for this letter. Pressing it again just
  // repeats the dots without any further penalty.
  void useHint() {
    if (finished) return;

    setState(() {
      _markMissedAndReveal();
      feedback = "Hint used. Now try it yourself";
    });

    textToSpeech("Letter $spokenLetter is $dotsDescription.");
  }

  // Asks first, so a stray tap doesn't throw away the round.
  Future<void> confirmFinish() async {
    final shouldFinish = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Finish round?'),
        content: Text(
          'You have answered $answered of $total letters. '
          'The rest will not be counted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('KEEP PLAYING'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('FINISH'),
          ),
        ],
      ),
    );

    // The page may have been closed, or the round already ended by a device
    // press, while the dialog was open.
    if (shouldFinish == true && mounted && !finished) {
      setState(() {
        finished = true;
        endedEarly = true;
        pressedButtons.clear();
      });

      _speakResults();
    }
  }

  void toggleDot(int dotBinaryValue) {
    setState(() {
      if (pressedButtons.contains(dotBinaryValue)) {
        pressedButtons.remove(dotBinaryValue);
      } else {
        pressedButtons.add(dotBinaryValue);
      }
    });
  }

  void _startNewRound(List<int> letters) {
    setState(() => _resetRound(letters));
    textToSpeech("Letter $spokenLetter");
  }

  Widget _buildResults(BuildContext context) {
    final missedNames =
        missed.map((i) => _letterName(i).toUpperCase()).join(", ");

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alphabet'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(
                  endedEarly ? 'Round finished' : 'Round complete',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),

              const SizedBox(height: 16),

              if (answered == 0)
                Text(
                  'No letters answered',
                  style: Theme.of(context).textTheme.titleMedium,
                )
              else ...[
                Semantics(
                  liveRegion: true,
                  child: Text(
                    '$score / $answered',
                    style: const TextStyle(
                      fontSize: 72,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                if (endedEarly) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Finished early: $answered of $total letters answered',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],

                const SizedBox(height: 16),

                Text(
                  missed.isEmpty
                      ? 'Perfect, no mistakes!'
                      : 'Letters to practice:\n$missedNames',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],

              const SizedBox(height: 32),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(220, 56),
                ),
                onPressed: () =>
                    _startNewRound(List.generate(26, (i) => i)),
                child: const Text('PLAY AGAIN'),
              ),

              if (missed.isNotEmpty) ...[
                const SizedBox(height: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(220, 56),
                  ),
                  onPressed: () => _startNewRound(missed),
                  child: const Text('PRACTICE MISSED'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (finished) return _buildResults(context);

    final hintColor = const Color.fromARGB(255, 168, 189, 198);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alphabet'),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Letter ${position + 1} of $total',
                style: Theme.of(context).textTheme.titleMedium,
              ),

              const SizedBox(height: 20),

              Semantics(
                label: 'Letter $letter',
                excludeSemantics: true,
                child: Text(
                  letter.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 96,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              const SizedBox(height: 10),

              Semantics(
                liveRegion: true, // screen readers announce changes
                child: Text(
                  feedback.isEmpty ? ' ' : feedback,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),

              const SizedBox(height: 25),

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
                                // pressed beats revealed beats plain grey
                                backgroundColor: pressedButtons
                                        .contains(1 << (col * 3 + row))
                                    ? Colors.blue
                                    : (revealed &&
                                            correctDots
                                                .contains(1 << (col * 3 + row)))
                                        ? hintColor
                                        : Colors.grey,
                              ),
                              onPressed: () =>
                                  toggleDot(1 << (col * 3 + row)),
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

              const SizedBox(height: 25),

              // Wrap lets the buttons flow onto a second line at large text sizes.
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  ElevatedButton(
                    onPressed: submit,
                    child: const Text("SUBMIT"),
                  ),
                  ElevatedButton(
                    onPressed: () => setState(() => pressedButtons.clear()),
                    child: const Text("CLEAR"),
                  ),
                  ElevatedButton(
                    onPressed: useHint,
                    child: const Text("HINT"),
                  ),
                  OutlinedButton(
                    onPressed: confirmFinish,
                    child: const Text("FINISH"),
                  ),
                ],
              ),

              const SizedBox(height: 15),

              Text(
                'A hint or a wrong answer costs the point for this letter',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}