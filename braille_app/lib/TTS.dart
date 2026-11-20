import 'dart:io';
import 'dart:isolate';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'crash_log.dart';
import 'voices.dart';

/// Change this whenever the files in assets/tts/ change, so phones copy the
/// new files instead of reusing old ones.
const String _modelVersion = 'piper-v5';

/// Offline Piper speech for native Flutter apps (Windows and Android).
///
/// The selected voice's model is loaded once into a long-lived background
/// isolate and reused for every [speak] call. Picking a voice that uses a
/// different model replaces the isolate.
class TTS {
  TTS() {
    _player.onPlayerComplete.listen((_) {
      CrashLog.log('TTS', 'Playback finished');
    });
  }

  final AudioPlayer _player = AudioPlayer();
  _Worker? _worker;
  Voice? _voice;
  int _request = 0;
  String? _audioFile;
  bool _disposed = false;

  /// Copies in progress, by folder, so two requests never copy the same
  /// files at the same time.
  final Map<String, Future<String>> _copying = {};

  /// The selected voice (read from disk the first time).
  Future<Voice> get voice async => _voice ??= await _loadSavedVoice();

  /// Starts the worker for [voice]'s model if it is not running yet.
  _Worker _workerFor(Voice voice) {
    final current = _worker;
    if (current != null && current.modelId == voice.id) return current;
    _stopWorker();
    final worker = _Worker(voice.id);
    _worker = worker;
    worker.port = _startWorker(worker);
    return worker;
  }

  /// Loads the model in the background so the first [speak] is fast.
  Future<void> warmUp() async {
    try {
      await _workerFor(await voice).port;
    } catch (error, stack) {
      CrashLog.error('TTS', 'Warm-up failed: $error', stack);
    }
  }

  /// Switches to [voice] and remembers it for the next app start.
  Future<void> setVoice(Voice voice) async {
    _voice = voice;
    CrashLog.log('TTS', 'Voice set to ${voice.uniqueKey}');
    try {
      final file = File('${(await getApplicationSupportDirectory()).path}/voice.txt');
      await file.writeAsString(voice.uniqueKey, flush: true);
    } catch (error, stack) {
      CrashLog.error('TTS', 'Could not save voice: $error', stack);
    }
  }

  Future<Voice> _loadSavedVoice() async {
    try {
      final file = File('${(await getApplicationSupportDirectory()).path}/voice.txt');
      if (await file.exists()) return voiceByKey((await file.readAsString()).trim());
    } catch (_) {}
    return voiceByKey(defaultVoiceKey);
  }

  /// Asks the current worker (if any) to free its model and exit.
  void _stopWorker() {
    final worker = _worker;
    if (worker == null) return;
    _worker = null;
    worker.retired = true;
    worker.port.then((port) => port.send(null), onError: (_) {});
  }

  Future<SendPort> _startWorker(_Worker worker) async {
    try {
      final shared = await _copyOnce('espeak-ng-data');
      final model = await _copyOnce('voices/${worker.modelId}');
      _deleteOtherVoiceCopies(keep: {worker.modelId, (await voice).id});
      CrashLog.log('TTS', 'Loading voice ${worker.modelId} (${CrashLog.memory()})');

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
        if (!_disposed && !worker.retired) {
          CrashLog.log('TTS', '!!! Speech worker stopped unexpectedly');
        }
        if (identical(_worker, worker)) _worker = null;
        for (final pending in worker.replies.toList()) {
          pending.sendPort.send('Speech worker stopped');
        }
      });

      await Isolate.spawn(
        _ttsWorker,
        <Object?>[
          port.sendPort,
          '$model/${worker.modelId}.onnx',
          '$model/tokens.txt',
          shared,
          CrashLog.path,
        ],
        debugName: 'piper-tts',
        onError: errors.sendPort,
        onExit: exit.sendPort,
      );

      // The worker answers with its SendPort once the model is loaded,
      // or with an error message if loading failed.
      final reply = await port.first;
      if (reply is! SendPort) throw StateError('$reply');
      CrashLog.log('TTS', 'Voice ${worker.modelId} ready (${CrashLog.memory()})');
      return reply;
    } catch (_) {
      if (identical(_worker, worker)) _worker = null; // retry on next call
      rethrow;
    }
  }

  Future<String> _copyOnce(String folder) {
    return _copying[folder] ??= _copyFolder(folder).whenComplete(() {
      _copying.remove(folder);
    });
  }

  /// Copies `assets/tts/<folder>/` into a real folder, because the speech
  /// engine can only read normal files.
  ///
  /// A "done" marker is written only after every file is fully copied. If
  /// the app was killed half way through a copy, the marker is missing and
  /// everything is copied again, instead of loading a broken model file
  /// (which crashes the speech engine).
  Future<String> _copyFolder(String folder) async {
    final root = await _root();
    final directory = Directory('$root/$folder');
    final marker = File('${directory.path}/.copy-complete');
    if (await marker.exists()) return directory.path;

    CrashLog.log('TTS', 'Copying $folder to the phone (first use)...');
    final watch = Stopwatch()..start();
    final prefix = 'assets/tts/$folder/';
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets =
        manifest.listAssets().where((a) => a.startsWith(prefix)).toList();
    if (assets.isEmpty) throw StateError('No files found in $prefix');
    for (final asset in assets) {
      final file = File('${directory.path}/${asset.substring(prefix.length)}');
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
      'Copied ${assets.length} files of $folder in '
          '${watch.elapsedMilliseconds} ms (${CrashLog.memory()})',
    );
    return directory.path;
  }

  String? _rootPath;

  /// The folder holding the copied speech files. Removes copies made by
  /// older app versions (they are ~80 MB per voice).
  Future<String> _root() async {
    if (_rootPath != null) return _rootPath!;
    final support = await getApplicationSupportDirectory();
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
    return _rootPath = '${support.path}/$_modelVersion';
  }

  /// Voices are ~65 MB each, so only the selected voice and the one being
  /// loaded are kept on the phone. Others are copied again when needed.
  Future<void> _deleteOtherVoiceCopies({required Set<String> keep}) async {
    try {
      final folder = Directory('${await _root()}/voices');
      if (!await folder.exists()) return;
      await for (final entry in folder.list()) {
        final name = entry.path.split(RegExp(r'[\\/]')).last;
        if (entry is Directory &&
            !keep.contains(name) &&
            !_copying.containsKey('voices/$name')) {
          await entry.delete(recursive: true);
        }
      }
    } catch (_) {}
  }

  Future<void> speak(String text) async {
    if (_disposed || text.trim().isEmpty) return;
    final request = ++_request;
    await _player.stop();
    final voice = await this.voice;
    final worker = _workerFor(voice);
    final workerPort = await worker.port;
    if (request != _request) return;
    final temp = await getTemporaryDirectory();
    final output =
        '${temp.path}/piper-${DateTime.now().microsecondsSinceEpoch}.wav';

    // Inference runs in the persistent worker isolate, off the UI thread.
    CrashLog.log('TTS', 'Generating "$text" (${CrashLog.memory()})');
    // If the worker dies, [worker.replies] get an error so this does not
    // wait forever.
    final reply = ReceivePort();
    worker.replies.add(reply);
    workerPort.send(<Object>[text, output, voice.speaker, reply.sendPort]);
    final Object? error;
    try {
      error = await reply.first;
    } finally {
      worker.replies.remove(reply);
    }
    if (request != _request) {
      await _deleteQuietly(output);
      return; // a newer request (or a voice change) replaced this one
    }
    if (error != null) throw StateError('$error');

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
    _stopWorker();
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

/// One background isolate serving one voice model.
class _Worker {
  _Worker(this.modelId);

  final String modelId;
  late Future<SendPort> port;

  /// Set when this worker was replaced and asked to exit.
  bool retired = false;

  /// Requests sent to this worker that have not been answered yet.
  final Set<ReceivePort> replies = {};
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

/// The voice currently used for speech.
Future<Voice> currentVoice() => _sharedTts.voice;

/// Switches to [voice] (and remembers it), then says [voicePreviewSentence].
Future<void> selectAndPreviewVoice(Voice voice) async {
  await _sharedTts.setVoice(voice);
  await textToSpeech(voicePreviewSentence);
}

/// Entry point of the background isolate: loads one Piper model, then serves
/// requests of the form `[text, outputPath, speaker, replyPort]` until it
/// gets `null`.
void _ttsWorker(List<Object?> arguments) {
  final mainPort = arguments[0] as SendPort;
  final model = arguments[1] as String;
  final tokens = arguments[2] as String;
  final dataDir = arguments[3] as String;
  CrashLog.attach(arguments[4] as String?);

  final sherpa.OfflineTts engine;
  try {
    CrashLog.log('TTS worker', 'Starting speech engine with $model');
    sherpa.initBindings();
    engine = sherpa.OfflineTts(
      sherpa.OfflineTtsConfig(
        model: sherpa.OfflineTtsModelConfig(
          vits: sherpa.OfflineTtsVitsModelConfig(
            model: model,
            tokens: tokens,
            dataDir: dataDir,
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
    final speaker = request[2] as int;
    final reply = request[3] as SendPort;
    try {
      final audio = engine.generate(text: text, sid: speaker, speed: 1.0);
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
