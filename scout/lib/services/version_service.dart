import 'package:flutter/foundation.dart';

class VersionService {
  static String? _cachedVersion;
  
  // Hardcoded version that matches pubspec.yaml - update this when version changes
  static const String _appVersion = '1.0.0+4';

  static Future<String> getVersion() async {
    // In debug mode, don't cache to allow for hot reloads during development
    if (!kDebugMode && _cachedVersion != null) return _cachedVersion!;

    try {
      // Use hardcoded version to avoid asset loading issues
      _cachedVersion = _appVersion;
      return _cachedVersion!;
    } catch (e) {
      // Fallback version
      return '1.0.0+1';
    }
  }

  // Method to clear cache (useful for testing or forced reloads)
  static void clearCache() {
    _cachedVersion = null;
  }
}