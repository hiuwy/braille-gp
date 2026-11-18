import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Simple offline Piper TTS for Android.
///
/// The Piper model is loaded once and reused for subsequent speech requests.
class TTS {
  TTS();

  final AudioPlayer _player = AudioPlayer();

  sherpa.OfflineTts? _engine;

  Future<void>? _initializing;

  int _request = 0;

  String? _audioFile;

  bool _disposed = false;

  /// Initialize Piper once.
  Future<void> warmUp() async {
    if (_disposed) return;

    if (_engine != null) {
      return;
    }

    _initializing ??= _initialize();

    try {
      await _initializing;
    } catch (_) {
      _initializing = null;
      rethrow;
    }
  }

  /// Copy the Piper model from Flutter assets to a writable directory.
  Future<String> _prepareModel() async {
    final supportDirectory = await getApplicationSupportDirectory();

    final modelDirectory = Directory(
      '${supportDirectory.path}/piper-libritts-v1',
    );

    await modelDirectory.create(recursive: true);

    const assets = [
      'assets/tts/en_US-libritts_r-medium.onnx',
      'assets/tts/tokens.txt',
    ];

    for (final asset in assets) {
      final filename = asset.split('/').last;

      final destination = File(
        '${modelDirectory.path}/$filename',
      );

      final data = await rootBundle.load(asset);

      await destination.writeAsBytes(
        data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        ),
        flush: true,
      );

      debugPrint(
        'Copied $filename (${data.lengthInBytes} bytes)',
      );
    }

    // Copy espeak-ng-data recursively.
    final manifest = await AssetManifest.loadFromAssetBundle(
      rootBundle,
    );

    const prefix = 'assets/tts/espeak-ng-data/';

    final espeakAssets = manifest
        .listAssets()
        .where((asset) => asset.startsWith(prefix))
        .toList();

    for (final asset in espeakAssets) {
      final relativePath = asset.substring(prefix.length);

      if (relativePath.isEmpty) {
        continue;
      }

      final destination = File(
        '${modelDirectory.path}/espeak-ng-data/$relativePath',
      );

      await destination.parent.create(
        recursive: true,
      );

      final data = await rootBundle.load(asset);

      await destination.writeAsBytes(
        data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        ),
        flush: true,
      );
    }

    debugPrint(
      'Copied ${espeakAssets.length} espeak-ng-data files.',
    );

    return modelDirectory.path;
  }

  Future<void> _initialize() async {
    debugPrint('Initializing Piper...');

    final directory = await _prepareModel();

    final modelFile = File(
      '$directory/en_US-libritts_r-medium.onnx',
    );

    final tokensFile = File(
      '$directory/tokens.txt',
    );

    final espeakDirectory = Directory(
      '$directory/espeak-ng-data',
    );

    if (!await modelFile.exists()) {
      throw StateError(
        'Piper model not found: ${modelFile.path}',
      );
    }

    if (!await tokensFile.exists()) {
      throw StateError(
        'Piper tokens.txt not found: ${tokensFile.path}',
      );
    }

    if (!await espeakDirectory.exists()) {
      throw StateError(
        'Piper espeak-ng-data not found: ${espeakDirectory.path}',
      );
    }

    final tokensSize = await tokensFile.length();
    final modelSize = await modelFile.length();

    debugPrint(
      'Piper model size: $modelSize bytes',
    );

    debugPrint(
      'Piper tokens.txt size: $tokensSize bytes',
    );

    debugPrint(
      'Piper espeak directory: ${espeakDirectory.path}',
    );

    // Initialize Sherpa-ONNX native bindings.
    sherpa.initBindings();

    debugPrint(
      'Sherpa-ONNX bindings initialized.',
    );

    final config = sherpa.OfflineTtsConfig(
      model: sherpa.OfflineTtsModelConfig(
        vits: sherpa.OfflineTtsVitsModelConfig(
          model: modelFile.path,
          tokens: tokensFile.path,
          dataDir: espeakDirectory.path,

          noiseScale: 0.333,
          noiseScaleW: 0.333,

          // 1.0 = normal speed.
          lengthScale: 1.0,
        ),

        // Use one thread while testing.
        numThreads: 1,
      ),
    );

    try {
      _engine = sherpa.OfflineTts(config);
    } catch (error, stackTrace) {
      debugPrint(
        'Piper failed to initialize: $error',
      );

      debugPrint(
        '$stackTrace',
      );

      rethrow;
    }

    debugPrint(
      'Piper initialized successfully.',
    );
    
    debugPrint(
      'Piper speakers: ${_engine!.numSpeakers}',
    );

    debugPrint(
      'Piper sample rate: ${_engine!.sampleRate}',
    );
  }

  /// Speak text using Piper.
  Future<void> speak(String text) async {
    if (_disposed) return;

    final cleanedText = text.trim();

    if (cleanedText.isEmpty) {
      return;
    }

    try {
      await warmUp();

      final engine = _engine;

      if (engine == null) {
        throw StateError(
          'Piper engine was not initialized.',
        );
      }

      final request = ++_request;

      await _player.stop();

      debugPrint(
        'Piper generating: "$cleanedText"',
      );

      final audio = engine.generate(
        text: cleanedText,
        sid: 0,
        speed: 1.0,
      );

      if (audio.samples.isEmpty) {
        throw StateError(
          'Piper generated no audio.',
        );
      }

      if (request != _request) {
        return;
      }

      final temporaryDirectory =
          await getTemporaryDirectory();

      final output = File(
        '${temporaryDirectory.path}/'
        'piper-${DateTime.now().microsecondsSinceEpoch}.wav',
      );

      final success = sherpa.writeWave(
        filename: output.path,
        samples: audio.samples,
        sampleRate: audio.sampleRate,
      );

      if (!success) {
        throw StateError(
          'Piper could not create WAV file.',
        );
      }

      final previous = _audioFile;

      _audioFile = output.path;

      if (previous != null) {
        final previousFile = File(previous);

        if (await previousFile.exists()) {
          await previousFile.delete();
        }
      }

      if (request != _request) {
        return;
      }

      debugPrint(
        'Piper playing: ${output.path}',
      );

      await _player.play(
        DeviceFileSource(output.path),
      );

      debugPrint(
        'Piper playback started.',
      );
    } catch (error, stackTrace) {
      debugPrint(
        'Piper TTS error: $error',
      );

      debugPrint(
        '$stackTrace',
      );

      // Do not allow a TTS failure to crash the application.
    }
  }

  Future<void> stop() async {
    _request++;

    try {
      await _player.stop();
    } catch (error) {
      debugPrint(
        'Could not stop Piper audio: $error',
      );
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;

    _disposed = true;

    _request++;

    try {
      await _player.stop();
    } catch (_) {}

    try {
      await _player.dispose();
    } catch (_) {}

    final engine = _engine;

    _engine = null;

    if (engine != null) {
      try {
        engine.free();
      } catch (_) {}
    }

    final file = _audioFile;

    if (file != null) {
      final audioFile = File(file);

      if (await audioFile.exists()) {
        try {
          await audioFile.delete();
        } catch (_) {}
      }
    }
  }
}


//
// ONE SHARED TTS INSTANCE
//

final TTS _sharedTts = TTS();


/// Speak text using Piper.
Future<void> textToSpeech(String text) {
  return _sharedTts.speak(text);
}


/// Initialize Piper before the first speech request.
Future<void> initTextToSpeech() {
  return _sharedTts.warmUp();
}


/// Stop currently playing speech.
Future<void> stopTextToSpeech() {
  return _sharedTts.stop();
}