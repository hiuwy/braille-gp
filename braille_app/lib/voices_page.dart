import 'package:material_ui/material_ui.dart';

import 'TTS.dart';
import 'voices.dart';

/// Settings screen for choosing the speech voice, with one tab per accent.
/// Tapping a voice selects it and speaks a short sample sentence.
class VoicesPage extends StatefulWidget {
  const VoicesPage({super.key});

  @override
  State<VoicesPage> createState() => _VoicesPageState();
}

class _VoicesPageState extends State<VoicesPage> {
  String? _selectedKey;

  @override
  void initState() {
    super.initState();
    currentVoice().then((voice) {
      if (mounted) setState(() => _selectedKey = voice.uniqueKey);
    });
  }

  @override
  void dispose() {
    stopTextToSpeech();
    super.dispose();
  }

  void _choose(Voice voice) {
    setState(() => _selectedKey = voice.uniqueKey);
    selectAndPreviewVoice(voice);
  }

  Widget _list(Accent accent) {
    final list = voices.where((v) => v.accent == accent).toList();
    return ListView(
      children: [
        for (final voice in list)
          ListTile(
            leading: Icon(
              voice.gender == VoiceGender.female ? Icons.face_3 : Icons.face,
            ),
            title: Text(voice.name),
            subtitle: Text(
              voice.gender == VoiceGender.female ? 'female' : 'male',
            ),
            trailing: voice.uniqueKey == _selectedKey
                ? const Icon(Icons.check_circle, color: Colors.green)
                : const Icon(Icons.play_circle_outline),
            selected: voice.uniqueKey == _selectedKey,
            onTap: () => _choose(voice),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Voices'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'English (US)'),
              Tab(text: 'English (UK)'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _list(Accent.us),
            _list(Accent.uk),
          ],
        ),
      ),
    );
  }
}
