import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

class VersionService {
  static String? _cachedVersion;

  static const String _versionOverride = String.fromEnvironment('APP_VERSION', defaultValue: '');
  static const String _buildDateOverride = String.fromEnvironment('BUILD_DATE', defaultValue: '');

  static Future<String> getVersion() async {
    if (!kDebugMode && _cachedVersion != null) return _cachedVersion!;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final baseVersion = packageInfo.version.isNotEmpty ? packageInfo.version : '1.0.0';
      final buildNumber = packageInfo.buildNumber.isNotEmpty ? packageInfo.buildNumber : '1';
      final computedVersion = '$baseVersion+$buildNumber';
      final effectiveVersion = _versionOverride.isNotEmpty ? _versionOverride : computedVersion;

      final buildDate = _buildDateOverride.isNotEmpty
          ? _buildDateOverride
          : _formatBuildDate(DateTime.now());

      _cachedVersion = '$effectiveVersion ($buildDate)';
      return _cachedVersion!;
    } catch (e) {
      final fallbackDate = _formatBuildDate(DateTime.now());
      return '1.0.0+1 ($fallbackDate)';
    }
  }

  static void clearCache() {
    _cachedVersion = null;
  }

  static String _formatBuildDate(DateTime date) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }
}

















