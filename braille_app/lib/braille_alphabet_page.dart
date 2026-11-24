import 'package:material_ui/material_ui.dart';

import "TTS.dart";
import "learn_tab.dart"; // for BrailleAlphabet

class BrailleAlphabetPage extends StatelessWidget {
  const BrailleAlphabetPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Braille alphabet'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'Tap a letter to hear its dots',
              style: Theme.of(context).textTheme.bodyMedium,
            ),

            const SizedBox(height: 16),

            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                for (int i = 0; i < 26; i++) _LetterCard(index: i),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LetterCard extends StatelessWidget {
  final int index; // 0 = a, 25 = z

  const _LetterCard({required this.index});

  String get letter => String.fromCharCode('a'.codeUnitAt(0) + index);

  void _speak() {
    textToSpeech(
      "Letter, ${BrailleAlphabet.spokenLetter(letter)},"
      "${BrailleAlphabet.describeDots(index)}",
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dots = BrailleAlphabet.dotNumbers(index);

    return Semantics(
      label: 'Letter $letter: ${BrailleAlphabet.describeDots(index)}',
      button: true,
      onTap: _speak,
      excludeSemantics: true, // the card reads as one item, not many
      child: InkWell(
        onTap: _speak,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 88,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: scheme.onSurface.withValues(alpha: 0.2),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                letter.toUpperCase(),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              // Dots 1 to 3 down the left column, 4 to 6 down the right.
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int col = 0; col < 2; col++)
                    Column(
                      children: [
                        for (int row = 0; row < 3; row++)
                          _Dot(
                            filled: dots.contains(col * 3 + row + 1),
                            color: scheme.onSurface,
                          ),
                      ],
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

class _Dot extends StatelessWidget {
  final bool filled;
  final Color color;

  const _Dot({required this.filled, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      margin: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? color : Colors.transparent,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
    );
  }
}