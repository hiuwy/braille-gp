import 'package:material_ui/material_ui.dart';
import 'braille_device.dart';
import 'voices_page.dart';

class SettingsTab extends StatelessWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  final BrailleDevice device;

  const SettingsTab({
    super.key,
    required this.themeMode,
    required this.onThemeChanged,
    required this.device,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('dark mode'),
            secondary: Icon(
              themeMode == ThemeMode.dark
                  ? Icons.dark_mode
                  : Icons.light_mode,
            ),
            value: themeMode == ThemeMode.dark,
            onChanged: (value) {
              onThemeChanged(
                value ? ThemeMode.dark : ThemeMode.light,
              );
            },
          ),

          ListTile(
            leading: Icon(
              device.isConnected
                  ? Icons.bluetooth_connected
                  : Icons.bluetooth_disabled,
            ),
            title: const Text('braille device'),
            trailing: ElevatedButton(
              onPressed: device.scanForBrailleDevice,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    device.isConnected ? Colors.green : Colors.red,
                foregroundColor: Colors.white,
              ),
              child: Text(
                device.isConnected ? "found" : "find",
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          ListTile(
            leading: const Icon(Icons.record_voice_over),
            title: const Text('voices'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const VoicesPage()),
            ),
          ),
        ],
      ),
    );
  }
}
