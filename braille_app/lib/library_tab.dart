import 'package:material_ui/material_ui.dart';

import "alphabet_game.dart";
import "braille_alphabet_page.dart";
import "bluetooth.dart";

class LibraryTab extends StatelessWidget {
  final BrailleDevice device;

  const LibraryTab({super.key, required this.device});

  // Opens a page on top of the whole screen. The back arrow in its
  // AppBar brings the user back here.
  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _LibraryButton(
            icon: Icons.grid_view,
            label: 'Braille alphabet',
            onPressed: () => _open(context, const BrailleAlphabetPage()),
          ),
          _LibraryButton(
            icon: Icons.abc,
            label: 'Practice letters',
            onPressed: () => _open(context, AlphabetGamePage(device: device)),
          ),
        ],
      ),
    );
  }
}

class _LibraryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _LibraryButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(64),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 28),
        label: Text(
          label,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}