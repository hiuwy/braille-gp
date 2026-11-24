import 'package:accessibility_tools/accessibility_tools.dart';
import 'package:material_ui/material_ui.dart';

import "TTS.dart";
import "crash_log.dart";
import "bluetooth.dart";
import "app_settings.dart";
import "settings_tab.dart";
import "library_tab.dart";
import "learn_tab.dart";

void main() {
  runAppWithCrashLogging(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final BrailleDevice device = BrailleDevice();
  final AppSettings settings = AppSettings();

  int _selectedIndex = 1;

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  void initState() {
    super.initState();

    initTextToSpeech();

    device.addListener(() => setState(() {}));
    settings.addListener(() => setState(() {}));
    device.start();
  }

  @override
  void dispose() {
    settings.dispose();
    device.dispose();
    super.dispose();
  }

  ThemeData _buildTheme(Brightness brightness) {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: brightness,
      ),
      visualDensity: settings.visualDensity,
      useMaterial3: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      showSemanticsDebugger: settings.screenReaderMode,
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);

        Widget app = MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: TextScaler.linear(
              mediaQuery.textScaler.scale(1.0) * settings.textScale,
            ),
            boldText: mediaQuery.boldText || settings.boldText,
          ),
          child: child!,
        );

        final direction = settings.textDirection;
        if (direction != null) {
          app = Directionality(textDirection: direction, child: app);
        }

        final filter = settings.colorFilter;
        if (filter != null) {
          app = ColorFiltered(colorFilter: filter, child: app);
        }

        return AccessibilityTools(
          testingToolsConfiguration: const TestingToolsConfiguration(
            enabled: false, // your Settings tab replaces the wrench panel
          ),
          child: app,
        );
      },
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: settings.themeMode,
      home: Scaffold(
        body: IndexedStack(
          index: _selectedIndex,
          children: [
            LibraryTab(device: device),
            LearnTab(device: device, isActive: _selectedIndex == 1),
            SettingsTab(settings: settings, device: device),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          selectedItemColor: Colors.blue,
          unselectedItemColor: Colors.grey,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.library_books),
              label: 'Library',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.school),
              label: 'Learn',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}