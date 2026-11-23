import 'package:material_ui/material_ui.dart';
import 'app_settings.dart';
import 'bluetooth.dart';

class SettingsTab extends StatelessWidget {
  final AppSettings settings;
  final BrailleDevice device;

  const SettingsTab({
    super.key,
    required this.settings,
    required this.device,
  });

  static const Map<ColorMode, String> _colorModeNames = {
    ColorMode.none: 'none',
    ColorMode.protanopia: 'protanopia (red)',
    ColorMode.deuteranopia: 'deuteranopia (green)',
    ColorMode.tritanopia: 'tritanopia (blue)',
    ColorMode.inverted: 'inverted colors',
    ColorMode.grayscale: 'grayscale',
  };

  static const Map<DensityOption, String> _densityNames = {
    DensityOption.comfortable: 'comfortable',
    DensityOption.standard: 'standard',
    DensityOption.compact: 'compact',
  };

  static const Map<DirectionOption, String> _directionNames = {
    DirectionOption.auto: 'automatic',
    DirectionOption.ltr: 'left to right',
    DirectionOption.rtl: 'right to left',
  };

  Widget _dropdownItemText(String text) {
    return Text(text, overflow: TextOverflow.ellipsis);
  }

  // The darker blue used for section titles and their lines.
  Color _accent(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? Colors.blue.shade300 : Colors.blue.shade800;
  }

  // Section title with a line running to the right of it.
  Widget _header(BuildContext context, String title) {
    final textColor = Theme.of(context).colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
      child: Row(
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Divider(
              height: 1,
              thickness: 1,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  // Header, then the tiles with a faint line between them (not after the last).
  List<Widget> _section(
    BuildContext context,
    String title,
    List<Widget> tiles,
  ) {
    final faint =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12);

    return [
      _header(context, title),
      for (int i = 0; i < tiles.length; i++) ...[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: tiles[i],
        ),
        if (i < tiles.length - 1)
          Divider(
            height: 1,
            thickness: 1,
            indent: 16,
            endIndent: 16,
            color: faint,
          ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          ..._section(context, 'Visual', [
            SwitchListTile(
              title: const Text('dark mode'),
              secondary: Icon(
                settings.themeMode == ThemeMode.dark
                    ? Icons.dark_mode
                    : Icons.light_mode,
              ),
              value: settings.themeMode == ThemeMode.dark,
              onChanged: (value) {
                settings.themeMode =
                    value ? ThemeMode.dark : ThemeMode.light;
              },
            ),

            ListTile(
              leading: const Icon(Icons.text_fields),
              title: const Text('text size'),
              subtitle: Slider(
                value: settings.textScale,
                min: 1.0,
                max: 2.0,
                divisions: 4,
                label: '${(settings.textScale * 100).round()}%',
                semanticFormatterCallback: (value) =>
                    '${(value * 100).round()} percent',
                onChanged: (value) => settings.textScale = value,
              ),
            ),

            SwitchListTile(
              title: const Text('bold text'),
              secondary: const Icon(Icons.format_bold),
              value: settings.boldText,
              onChanged: (value) => settings.boldText = value,
            ),

            ListTile(
              leading: const Icon(Icons.format_textdirection_l_to_r),
              title: const Text('text direction'),
              subtitle: DropdownButton<DirectionOption>(
                isExpanded: true,
                value: settings.direction,
                onChanged: (value) {
                  if (value != null) settings.direction = value;
                },
                items: [
                  for (final entry in _directionNames.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: _dropdownItemText(entry.value),
                    ),
                ],
              ),
            ),

            ListTile(
              leading: const Icon(Icons.density_medium),
              title: const Text('density'),
              subtitle: DropdownButton<DensityOption>(
                isExpanded: true,
                value: settings.density,
                onChanged: (value) {
                  if (value != null) settings.density = value;
                },
                items: [
                  for (final entry in _densityNames.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: _dropdownItemText(entry.value),
                    ),
                ],
              ),
            ),

            ListTile(
              leading: const Icon(Icons.palette),
              title: const Text('color mode'),
              subtitle: DropdownButton<ColorMode>(
                isExpanded: true,
                value: settings.colorMode,
                onChanged: (value) {
                  if (value != null) settings.colorMode = value;
                },
                items: [
                  for (final entry in _colorModeNames.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: _dropdownItemText(entry.value),
                    ),
                ],
              ),
            ),
          ]),

          ..._section(context, 'Screen Reader', [
            SwitchListTile(
              title: const Text('screen reader mode'),
              subtitle: const Text('shows how screen readers see the app'),
              secondary: const Icon(Icons.accessibility_new),
              value: settings.screenReaderMode,
              onChanged: (value) => settings.screenReaderMode = value,
            ),
          ]),

          ..._section(context, 'Device', [
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
                  minimumSize: const Size(48, 48),
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
          ]),
        ],
      ),
    );
  }
}