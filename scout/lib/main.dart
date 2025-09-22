import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'features/dashboard/dashboard_page.dart';

/// Global navigator key for back button handling
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Theme toggle
class ThemeModeNotifier extends ValueNotifier<ThemeMode> {
  ThemeModeNotifier._() : super(ThemeMode.light);
  static final ThemeModeNotifier instance = ThemeModeNotifier._();
  void toggle() {
    // Cycle: light → dark → system → light
    if (value == ThemeMode.light) {
      value = ThemeMode.dark;
    } else if (value == ThemeMode.dark) {
      value = ThemeMode.system;
    } else {
      value = ThemeMode.light;
    }
  }
}

/// Lightweight operator store (name shown in UI, cached locally)
class OperatorStore {
  static final ValueNotifier<String?> name = ValueNotifier<String?>(null);
  static String? _mem; // in-memory fallback if prefs unavailable

  static Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      name.value = sp.getString('operator_name');
      _mem = name.value;
    } catch (_) {
      // Safari Private Mode or storage blocked: use in-memory
      name.value = _mem;
    }
  }

  static Future<void> set(String? v) async {
    _mem = (v == null || v.isEmpty) ? null : v;
    name.value = _mem;
    try {
      final sp = await SharedPreferences.getInstance();
      if (_mem == null) {
        await sp.remove('operator_name');
      } else {
        await sp.setString('operator_name', _mem!);
      }
    } catch (_) {
      // ignore — we already updated the in-memory value
    }
  }
}

/// Initialize Firebase (single app) and ensure anonymous auth + operator loaded
Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Auth persistence: LOCAL → SESSION → NONE
  try {
    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
  } catch (_) {
    try {
      await FirebaseAuth.instance.setPersistence(Persistence.SESSION);
    } catch (_) {
      await FirebaseAuth.instance.setPersistence(Persistence.NONE);
    }
  }

  // Anonymous auth (best-effort)
  try {
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }
  } catch (_) {
    // don't block startup if anonymous auth isn't enabled
  }

  // Load operator cache (guard SharedPreferences failures on iOS Safari)
  try {
    await OperatorStore.load();
  } catch (_) {
    // ignore — OperatorStore falls back to in-memory
  }
}

final Future<void> _ready = _bootstrap();

void main() {
  runApp(const ScoutApp());
}

class ScoutApp extends StatelessWidget {
  const ScoutApp({super.key});

  /// Handle back button press - navigate to dashboard before exiting
  Future<bool> _handleBackPress() async {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return true;

    // If we can pop (not on dashboard), go back to dashboard
    if (navigator.canPop()) {
      navigator.popUntil((route) => route.isFirst);
      return false; // Don't exit app
    }

    // If we're on the dashboard (first route), allow exit
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeModeNotifier.instance,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'SCOUT',
          debugShowCheckedModeBanner: false,
          theme: BrandTheme().lightTheme,
          darkTheme: BrandTheme().darkTheme,
          themeMode: mode,
          navigatorKey: navigatorKey,
          home: PopScope(
            canPop: false, // We handle back navigation manually
            onPopInvokedWithResult: (didPop, result) async {
              if (didPop) return;
              final shouldPop = await _handleBackPress();
              if (shouldPop && context.mounted) {
                Navigator.of(context).pop();
              }
            },
            child: FutureBuilder<void>(
            future: _ready,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return Scaffold(
                  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                  body: const Center(child: CircularProgressIndicator()),
                );
              }
              if (snap.hasError) {
                return Scaffold(
                  body: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: SelectableText(
                        'Startup failed:\n${snap.error}\n\n'
                        '• Check firebase_options.dart matches your project\n'
                        '• Verify hosting is served over HTTPS\n'
                        '• See browser console for details',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                );
              }
              return const DashboardPage();
            },
          ),
        ),
        );
      },
    );
  }
}
