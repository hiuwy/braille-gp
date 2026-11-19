
import 'package:material_ui/material_ui.dart';
import 'braille_device.dart';

class LibraryTab extends StatelessWidget {
  final BrailleDevice device;

  const LibraryTab({
    super.key,
    required this.device,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
      ),
      body: const Center(
        child: Text('hi lol'),
      ),
    );
  }
}
