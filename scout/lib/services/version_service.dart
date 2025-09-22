import 'package:flutter/services.dart' show rootBundle;
import 'package:yaml/yaml.dart';
import 'package:flutter/foundation.dart';

class VersionService {
  static String? _cachedVersion;

  static Future<String> getVersion() async {
    // In debug mode, don't cache to allow for hot reloads during development
    if (!kDebugMode && _cachedVersion != null) return _cachedVersion!;

    try {
      final pubspecString = await rootBundle.loadString('pubspec.yaml');
      final pubspec = loadYaml(pubspecString);
      _cachedVersion = pubspec['version']?.toString() ?? '1.0.0+1';
      return _cachedVersion!;
    } catch (e) {
      // Fallback if pubspec.yaml can't be loaded
      return '1.0.0+1';
    }
  }

  // Method to clear cache (useful for testing or forced reloads)
  static void clearCache() {
    _cachedVersion = null;
  }
}