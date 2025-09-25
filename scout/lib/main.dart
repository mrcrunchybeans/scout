import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:web/web.dart' as web;
import 'package:go_router/go_router.dart';
import 'package:url_strategy/url_strategy.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
// JS interop removed; go_router and url_strategy handle routing for web

import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'features/dashboard/dashboard_page.dart';
import 'features/items/item_detail_page.dart';
import 'dev/label_qr_test_page.dart';
import 'features/admin/algolia_config_page.dart';
import 'features/admin/label_config_page.dart';

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

  // No manual hash-change listener needed when using a router and path URLs
}

final Future<void> _ready = _bootstrap();

/// Parse deep link from URL hash (e.g., "#/lot/itemId/lotId")
/// Returns null if no valid deep link, or a map with 'itemId' and 'lotId'
// Legacy hash deep-link parsing kept for optional migration switch
Map<String, String>? _parseLegacyHash() {
  if (!kIsWeb) return null;
  try {
    // Defensive: guard against missing/undefined location or hash in some
    // web embed environments where accessing .hash may yield null/undefined.
  final loc = web.window.location;
  final hash = (loc.hash as String?);
    if (hash == null || hash.isEmpty) return null;
    if (!hash.startsWith('#/')) return null;
    final path = hash.substring(2);
    final parts = path.split('/');
    if (parts.isNotEmpty && parts[0] == 'lot' && parts.length >= 2) {
      return {
        'itemId': parts[1],
        'lotId': parts.length >= 3 ? parts[2] : '',
      };
    }
  } catch (_) {}
  return null;
}

void main() {
  // Use path URL strategy (no hash) for clean URLs on web
  try {
    setPathUrlStrategy();
  } catch (_) {}

  runApp(const ScoutApp());
}

// Create a global GoRouter instance so programmatic navigation still works
final GoRouter _router = GoRouter(
  initialLocation: '/',
  navigatorKey: navigatorKey,
  routes: [
    GoRoute(
      path: '/',
      name: 'dashboard',
      builder: (context, state) => const DashboardPage(),
    ),
    GoRoute(
      path: '/items/:id',
      name: 'itemDetail',
      builder: (context, state) {
        final itemId = state.params['id']!;
        return ItemDetailLoader(itemId: itemId, lotId: state.queryParams['lotId']);
      },
    ),
    GoRoute(
      path: '/lot/:itemId/:lotId',
      name: 'lotDeep',
      builder: (context, state) {
        final itemId = state.params['itemId']!;
        final lotId = state.params['lotId']!;
        return ItemDetailLoader(itemId: itemId, lotId: lotId);
      },
    ),
    GoRoute(
      path: '/dev/label-test',
      name: 'labelQrTest',
      builder: (context, state) => const LabelQrTestPage(),
    ),
    GoRoute(
      path: '/admin/algolia',
      name: 'algoliaAdmin',
      builder: (context, state) => const AlgoliaConfigPage(),
    ),
    GoRoute(
      path: '/admin/labels',
      name: 'labelConfig',
      builder: (context, state) => const LabelConfigPage(),
    ),
  ],
);

class ScoutApp extends StatelessWidget {
  const ScoutApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeModeNotifier.instance,
      builder: (context, mode, _) {
        return FutureBuilder<void>(
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

            // If a legacy hash deeplink exists, redirect to the new path-based route
            try {
              final legacy = _parseLegacyHash();
              if (legacy != null && kIsWeb) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final itemId = legacy['itemId']!;
                  final lotId = legacy['lotId'] ?? '';
                  _router.go('/lot/$itemId/$lotId');
                });
              }
            } catch (_) {}

            return MaterialApp.router(
              title: 'SCOUT',
              debugShowCheckedModeBanner: false,
              theme: BrandTheme().lightTheme,
              darkTheme: BrandTheme().darkTheme,
              themeMode: mode,
              routerConfig: _router,
            );
          },
        );
      },
    );
  }
}

/// Widget that loads the item name for an itemId and shows `ItemDetailPage`
class ItemDetailLoader extends StatelessWidget {
  final String itemId;
  final String? lotId;
  const ItemDetailLoader({super.key, required this.itemId, this.lotId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('items').doc(itemId).get(),
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (!snap.hasData || !snap.data!.exists) {
          return const DashboardPage();
        }
        final name = snap.data!.data()?['name'] ?? 'Unknown Item';
        return ItemDetailPage(itemId: itemId, itemName: name, lotId: lotId);
      },
    );
  }
}
