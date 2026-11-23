import 'dart:io';
import 'dart:isolate';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'crash_log.dart';

/// Change this whenever the files in assets/tts/ change, so phones copy the
/// new model instead of reusing the old one.
const String _modelVersion = 'piper-libritts-v4';

/// Offline Piper speech for native Flutter apps (Windows and Android).
///
/// The Piper model is loaded once into a long-lived background isolate and
/// reused for every [speak] call, so only the first call pays the load cost.
class TTS {
  TTS() {
    _player.onPlayerComplete.listen((_) {
      CrashLog.log('TTS', 'Playback finished');
    });
  }

  final AudioPlayer _player = AudioPlayer();
  Future<SendPort>? _worker;
  int _request = 0;
  String? _audioFile;
  bool _disposed = false;

  /// Reply ports of requests the worker has not answered yet. If the worker
  /// dies, these get an error so [speak] does not wait forever.
  final Set<ReceivePort> _pending = {};

  /// Starts the worker (once) and returns the port used to send it requests.
  Future<SendPort> get _ready => _worker ??= _startWorker();

  /// Loads the model in the background so the first [speak] is fast.
  Future<void> warmUp() async {
    try {
      await _ready;
    } catch (error, stack) {
      CrashLog.error('TTS', 'Warm-up failed: $error', stack);
    }
  }

  Future<SendPort> _startWorker() async {
    try {
      final directory = await _prepareModel();
      CrashLog.log('TTS', 'Loading Piper model (${CrashLog.memory()})');

      final port = ReceivePort();
      final errors = ReceivePort();
      final exit = ReceivePort();

      // Errors thrown inside the worker isolate.
      errors.listen((message) {
        final parts = message as List<Object?>;
        CrashLog.log('TTS worker', '!!! ERROR: ${parts[0]}\n${parts[1]}');
      });

      // The worker stopped. If it was not asked to, report it and allow a
      // fresh worker to be started by the next speak().
      exit.listen((_) {
        errors.close();
        exit.close();
        if (!_disposed) {
          CrashLog.log('TTS', '!!! Speech worker stopped unexpectedly');
        }
        _worker = null;
        for (final pending in _pending.toList()) {
          pending.sendPort.send('Speech worker stopped unexpectedly');
        }
      });

      await Isolate.spawn(
        _ttsWorker,
        <Object?>[port.sendPort, directory, CrashLog.path],
        debugName: 'piper-tts',
        onError: errors.sendPort,
        onExit: exit.sendPort,
      );

      // The worker answers with its SendPort once the model is loaded,
      // or with an error message if loading failed.
      final reply = await port.first;
      if (reply is! SendPort) throw StateError('$reply');
      CrashLog.log('TTS', 'Piper model ready (${CrashLog.memory()})');
      return reply;
    } catch (_) {
      _worker = null; // allow a retry on the next call
      rethrow;
    }
  }

  /// Copies the model out of the app's assets into a real folder, because
  /// the speech engine can only read normal files.
  ///
  /// A "done" marker is written only after every file is fully copied. If
  /// the app was killed half way through a copy, the marker is missing and
  /// everything is copied again, instead of loading a broken model file
  /// (which crashes the speech engine).
  Future<String> _prepareModel() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/$_modelVersion');
    final marker = File('${directory.path}/.copy-complete');
    if (await marker.exists()) return directory.path;

    // Remove copies of older model versions (they are ~80 MB each).
    await for (final entry in support.list()) {
      final name = entry.path.split(RegExp(r'[\\/]')).last;
      if (entry is Directory &&
          name.startsWith('piper-') &&
          name != _modelVersion) {
        try {
          await entry.delete(recursive: true);
        } catch (_) {}
      }
    }

    CrashLog.log('TTS', 'Copying speech model to the phone (first run)...');
    final watch = Stopwatch()..start();
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = manifest
        .listAssets()
        .where((a) => a.startsWith('assets/tts/'))
        .toList();
    for (final asset in assets) {
      final file = File('${directory.path}/${asset.substring(11)}');
      await file.parent.create(recursive: true);
      final data = await rootBundle.load(asset);
      var bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      // A Windows checkout can give tokens.txt CRLF line endings, which makes
      // sherpa-onnx abort natively ("Duplicated token") and kill the app.
      if (asset.endsWith('tokens.txt')) {
        bytes = Uint8List.fromList(bytes.where((b) => b != 13).toList());
      }
      // Write to a temporary name, then rename, so a half-written file is
      // never mistaken for a finished one.
      final partial = File('${file.path}.part');
      await partial.writeAsBytes(bytes, flush: true);
      if (await file.exists()) await file.delete();
      await partial.rename(file.path);
    }
    await marker.writeAsString(_modelVersion, flush: true);
    CrashLog.log(
      'TTS',
      'Copied ${assets.length} model files in ${watch.elapsedMilliseconds} ms '
          '(${CrashLog.memory()})',
    );
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
    CrashLog.log('TTS', 'Generating "$text" (${CrashLog.memory()})');
    final reply = ReceivePort();
    _pending.add(reply);
    worker.send(<Object>[text, output, reply.sendPort]);
    final Object? error;
    try {
      error = await reply.first;
    } finally {
      _pending.remove(reply);
    }
    if (error != null) throw StateError('$error');

    if (request != _request) {
      await _deleteQuietly(output);
      return;
    }
    final previous = _audioFile;
    _audioFile = output;
    if (previous != null) await _deleteQuietly(previous);
    CrashLog.log('TTS', 'Playing audio');
    await _player.play(DeviceFileSource(output));
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
    if (file != null) await _deleteQuietly(file);
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

final TTS _sharedTts = TTS();

/// Speaks [text] using the offline Piper TTS engine.
///
/// Never throws: failures are logged, so a speech problem can't take down
/// the code that asked for speech.
Future<void> textToSpeech(String text) async {
  try {
    await _sharedTts.speak(text);
  } catch (error, stack) {
    CrashLog.error('TTS', 'Could not speak "$text": $error', stack);
  }
}

/// Loads the Piper model ahead of time so the first [textToSpeech] is quick.
Future<void> initTextToSpeech() => _sharedTts.warmUp();

/// Stops any speech that is playing or being generated.
Future<void> stopTextToSpeech() => _sharedTts.stop();

/// Entry point of the background isolate: loads Piper once, then serves
/// requests of the form `[text, outputPath, replyPort]` until it gets `null`.
void _ttsWorker(List<Object?> arguments) {
  final mainPort = arguments[0] as SendPort;
  final directory = arguments[1] as String;
  CrashLog.attach(arguments[2] as String?);

  final sherpa.OfflineTts engine;
  try {
    CrashLog.log('TTS worker', 'Starting speech engine');
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
    CrashLog.log('TTS worker', 'Speech engine loaded (${CrashLog.memory()})');
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
      CrashLog.log(
        'TTS worker',
        'Generated ${audio.samples.length} samples at ${audio.sampleRate} Hz '
            '(${CrashLog.memory()})',
      );
      reply.send(null);
    } catch (error) {
      reply.send('$error');
    }
  });
}