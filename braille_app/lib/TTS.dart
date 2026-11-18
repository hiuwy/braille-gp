import 'dart:io';
import 'dart:isolate';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Offline Piper speech for native Flutter apps (Windows and Android).
///
/// The Piper model is loaded once into a long-lived background isolate and
/// reused for every [speak] call, so only the first call pays the load cost.
class TTS {
  TTS() {
    _player.onPlayerComplete.listen((_) {
      debugPrint('Piper audio playback completed.');
    });
  }

  final AudioPlayer _player = AudioPlayer();
  Future<SendPort>? _worker;
  int _request = 0;
  String? _audioFile;
  bool _disposed = false;

  /// Starts the worker (once) and returns the port used to send it requests.
  Future<SendPort> get _ready => _worker ??= _startWorker();

  /// Loads the model in the background so the first [speak] is fast.
  Future<void> warmUp() => _ready;

  Future<SendPort> _startWorker() async {
    final directory = await _prepareModel();
    final port = ReceivePort();
    await Isolate.spawn(
      _ttsWorker,
      <Object>[port.sendPort, directory],
      debugName: 'piper-tts',
    );
    // The worker answers with its SendPort once the model is loaded,
    // or with an error message if loading failed.
    final reply = await port.first;
    if (reply is! SendPort) {
      _worker = null; // allow a retry on the next call
      throw StateError('$reply');
    }
    debugPrint('Piper model loaded and ready.');
    return reply;
  }

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
    if (_disposed || text.trim().isEmpty) return;
    final request = ++_request;
    await _player.stop();
    final worker = await _ready;
    if (request != _request) return;
    final temp = await getTemporaryDirectory();
    final output =
        '${temp.path}/piper-${DateTime.now().microsecondsSinceEpoch}.wav';

    // Inference runs in the persistent worker isolate, off the UI thread.
    final reply = ReceivePort();
    worker.send(<Object>[text, output, reply.sendPort]);
    final error = await reply.first;
    if (error != null) throw StateError('$error');

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
    debugPrint('Piper generated and started playing: $output');
  }

  Future<void> stop() async {
    _request++;
    await _player.stop();
  }

  Future<void> dispose() async {
    _disposed = true;
    _request++;
    await _player.dispose();
    final worker = _worker;
    if (worker != null) {
      try {
        (await worker).send(null); // tells the worker to free the model and exit
      } catch (_) {}
    }
    final file = _audioFile;
    if (file != null && await File(file).exists()) await File(file).delete();
  }
}

final TTS _sharedTts = TTS();

/// Speaks [text] using the offline Piper TTS engine.
Future<void> textToSpeech(String text) => _sharedTts.speak(text);

/// Loads the Piper model ahead of time so the first [textToSpeech] is quick.
Future<void> initTextToSpeech() => _sharedTts.warmUp();

/// Stops any speech that is playing or being generated.
Future<void> stopTextToSpeech() => _sharedTts.stop();

/// Entry point of the background isolate: loads Piper once, then serves
/// requests of the form `[text, outputPath, replyPort]` until it gets `null`.
void _ttsWorker(List<Object> arguments) {
  final mainPort = arguments[0] as SendPort;
  final directory = arguments[1] as String;

  final sherpa.OfflineTts engine;
  try {
    sherpa.initBindings();
    engine = sherpa.OfflineTts(
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
  } catch (error) {
    mainPort.send('Could not load Piper: $error');
    return;
  }

  final requests = ReceivePort();
  mainPort.send(requests.sendPort);

  requests.listen((message) {
    if (message == null) {
      engine.free();
      requests.close(); // isolate exits once nothing is listening
      return;
    }
    final request = message as List<Object>;
    final text = request[0] as String;
    final output = request[1] as String;
    final reply = request[2] as SendPort;
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
      reply.send(null);
    } catch (error) {
      reply.send('$error');
    }
  });
}
