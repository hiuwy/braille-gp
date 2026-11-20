/// The speech voices bundled with the app.
///
/// Each voice is a Piper model in `assets/tts/voices/<id>/`, holding
/// `<id>.onnx` and `tokens.txt`. All voices share `assets/tts/espeak-ng-data/`.
/// To add a voice: put its folder there, list the folder in pubspec.yaml,
/// and add an entry below.
library;

enum Accent { us, uk }

enum VoiceGender { female, male }

class Voice {
  const Voice({
    required this.id,
    required this.name,
    required this.accent,
    required this.gender,
    this.speaker = 0,
    this.key,
  });

  /// Folder name in assets/tts/voices/, also the model file name.
  final String id;

  /// Name shown in settings.
  final String name;
  final Accent accent;
  final VoiceGender gender;

  /// Speaker number inside multi-speaker models (0 for single-speaker ones).
  final int speaker;

  /// Unique key of this voice. It defaults to [id], and only needs to be set
  /// when several entries use the same model with different speakers.
  final String? key;

  String get uniqueKey => key ?? id;
}

/// The voice used until the user picks another one (the app's original voice).
const String defaultVoiceKey = 'en_US-libritts_r-medium';

/// The sentence spoken when a voice is tapped in settings.
const String voicePreviewSentence =
    'Hello! This is how I will sound when I help you learn braille.';

const List<Voice> voices = [
  // English (US): female
  Voice(id: 'en_US-lessac-medium', name: 'Lessac', accent: Accent.us, gender: VoiceGender.female),
  Voice(id: 'en_US-amy-medium', name: 'Amy', accent: Accent.us, gender: VoiceGender.female),
  Voice(id: 'en_US-hfc_female-medium', name: 'HFC Female', accent: Accent.us, gender: VoiceGender.female),
  // English (US): male
  Voice(id: 'en_US-ryan-medium', name: 'Ryan', accent: Accent.us, gender: VoiceGender.male),
  Voice(id: 'en_US-bryce-medium', name: 'Bryce', accent: Accent.us, gender: VoiceGender.male),
  Voice(id: 'en_US-joe-medium', name: 'Joe', accent: Accent.us, gender: VoiceGender.male),
  // The app's original voice (LibriTTS speaker 0).
  Voice(id: 'en_US-libritts_r-medium', name: 'Original', accent: Accent.us, gender: VoiceGender.female),

  // English (UK): female
  Voice(id: 'en_GB-alba-medium', name: 'Alba', accent: Accent.uk, gender: VoiceGender.female),
  Voice(id: 'en_GB-jenny_dioco-medium', name: 'Jenny', accent: Accent.uk, gender: VoiceGender.female),
  Voice(id: 'en_GB-cori-medium', name: 'Cori', accent: Accent.uk, gender: VoiceGender.female),
  // English (UK): male
  Voice(id: 'en_GB-alan-medium', name: 'Alan', accent: Accent.uk, gender: VoiceGender.male),
  Voice(id: 'en_GB-northern_english_male-medium', name: 'Northern English', accent: Accent.uk, gender: VoiceGender.male),
  // VCTK speaker p232 (male, Southern England) is speaker number 60.
  Voice(id: 'en_GB-vctk-medium', name: 'Southern English', accent: Accent.uk, gender: VoiceGender.male, speaker: 60),
];

Voice voiceByKey(String? key) => voices.firstWhere(
      (v) => v.uniqueKey == key,
      orElse: () => voices.firstWhere((v) => v.uniqueKey == defaultVoiceKey),
    );
