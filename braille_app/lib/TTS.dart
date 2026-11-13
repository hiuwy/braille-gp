import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Offline Piper speech for native Flutter apps (Windows and Android).
class TTS {
  TTS() {
    _player.onPlayerComplete.listen((_) {
      debugPrint('Piper audio playback completed.');
    });
  }

  final AudioPlayer _player = AudioPlayer();
  late final Future<String> _ready = _prepareModel();
  int _request = 0;
  String? _audioFile;

  Future<String> _prepareModel() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/piper-libritts-v1');
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    for (final asset in manifest.listAssets().where(
      (a) => a.startsWith('assets/tts/'),
    )) {
      final file = File('${directory.path}/${asset.substring(11)}');
      if (await file.exists()) continue;
      await file.parent.create(recursive: true);
      final data = await rootBundle.load(asset);
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    return directory.path;
  }

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    final request = ++_request;
    await _player.stop();
    final directory = await _ready;
    if (request != _request) return;
    final temp = await getTemporaryDirectory();
    final output =
        '${temp.path}/piper-${DateTime.now().microsecondsSinceEpoch}.wav';
    // Inference runs off the UI thread. No system TTS engine is used.
    await compute(_generateSpeech, [directory, text, output]);
    if (request != _request) {
      await File(output).delete();
      return;
    }
    final previous = _audioFile;
    _audioFile = output;
    if (previous != null && await File(previous).exists()) {
      await File(previous).delete();
    }
    await _player.play(DeviceFileSource(output));
    debugPrint('Piper model generated and started playing: $output');
  }

  Future<void> stop() async {
    _request++;
    await _player.stop();
  }

  Future<void> dispose() async {
    _request++;
    await _player.dispose();
    final file = _audioFile;
    if (file != null && await File(file).exists()) await File(file).delete();
  }
}

void _generateSpeech(List<String> arguments) {
  final [directory, text, output] = arguments;
  sherpa.initBindings();
  final engine = sherpa.OfflineTts(
    sherpa.OfflineTtsConfig(
      model: sherpa.OfflineTtsModelConfig(
        vits: sherpa.OfflineTtsVitsModelConfig(
          model: '$directory/en_US-libritts_r-medium.onnx',
          tokens: '$directory/tokens.txt',
          dataDir: '$directory/espeak-ng-data',
          noiseScale: 0.333,
          noiseScaleW: 0.333,
          lengthScale: 1.5,
        ),
        numThreads: 2,
      ),
    ),
  );
  try {
    final audio = engine.generate(text: text, sid: 0, speed: 1.0);
    if (audio.samples.isEmpty) throw StateError('Piper generated no audio.');
    if (!sherpa.writeWave(
      filename: output,
      samples: audio.samples,
      sampleRate: audio.sampleRate,
    )) {
      throw StateError('Could not save Piper audio.');
    }
    debugPrint(
      'Piper: ${audio.samples.length} samples at ${audio.sampleRate} Hz',
    );
  } finally {
    engine.free();
  }
}
