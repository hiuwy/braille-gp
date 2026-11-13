import 'dart:async';

import 'package:flutter/material.dart';

import 'TTS.dart';

void main() => runApp(const MaterialApp(home: TtsTestApp()));

class TtsTestApp extends StatefulWidget {
  const TtsTestApp({super.key});
  @override
  State<TtsTestApp> createState() => _TtsTestAppState();
}

class _TtsTestAppState extends State<TtsTestApp> {
  final TTS _tts = TTS();
  bool _busy = false;
  String _status = 'Piper: en_US-libritts_r-medium (offline)';

  @override
  void initState() {
    super.initState();
    if (const bool.fromEnvironment('TTS_SMOKE_TEST')) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _speak());
    }
  }

  Future<void> _speak() async {
    setState(() {
      _busy = true;
      _status = 'Generating speech with Piper...';
    });
    try {
      await _tts.speak(
        'Hello! This is the downloaded Piper voice running in Flutter.',
      );
      if (mounted) {
        setState(() => _status = 'Playing the downloaded Piper voice.');
      }
    } catch (error, stack) {
      debugPrint('Piper test failed: $error\n$stack');
      if (mounted) setState(() => _status = 'Speech failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    unawaited(_tts.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Piper TTS Test')),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_status, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _busy ? null : _speak,
            child: Text(_busy ? 'Generating...' : 'Test Piper voice'),
          ),
          TextButton(onPressed: _tts.stop, child: const Text('Stop')),
        ],
      ),
    ),
  );
}
