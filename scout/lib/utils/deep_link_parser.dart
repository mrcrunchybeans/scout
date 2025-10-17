import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

/// Utility functions for parsing Scout deep links and QR codes
class DeepLinkParser {
  /// Parse a scanned value to check if it's a lot deep link
  /// Returns a map with 'itemId' and 'lotId' if valid, null otherwise
  /// 
  /// Handles both old hash-based and new path-based URLs:
  /// - https://scout.littleempathy.com/lot/ITEMID/LOTID (new format)
  /// - https://scout.littleempathy.com/#/lot/ITEMID/LOTID (legacy format)
  /// - scout.littleempathy.com/#/lot/ITEMID/LOTID
  /// - #/lot/ITEMID/LOTID
  /// - /lot/ITEMID/LOTID
  static Map<String, String>? parseLotDeepLink(String scannedValue) {
    if (scannedValue.isEmpty) return null;

    if (kDebugMode) {
      debugPrint('DeepLinkParser: Parsing scanned value: $scannedValue');
    }

    try {
      String path = scannedValue.trim();

      // Remove protocol if present
      path = path.replaceFirst(RegExp(r'^https?://'), '');
      
      // Remove domain if present (handle both with and without www)
      // This handles: scout.littleempathy.com, www.scout.littleempathy.com, etc.
      path = path.replaceFirst(RegExp(r'^[a-zA-Z0-9.-]+\.[a-zA-Z]+'), '');

      if (kDebugMode) {
        debugPrint('DeepLinkParser: After domain removal: $path');
      }

      // Remove leading slash if present (from domain removal)
      if (path.startsWith('/')) {
        path = path.substring(1);
      }

      // Remove hash if present (for legacy URLs like #/lot/...)
      if (path.startsWith('#')) {
        path = path.substring(1);
      }

      if (kDebugMode) {
        debugPrint('DeepLinkParser: After hash removal: $path');
      }

      // Ensure path starts with /
      if (!path.startsWith('/')) {
        path = '/$path';
      }

      // Split path into parts
      final parts = path.split('/').where((p) => p.isNotEmpty).toList();

      if (kDebugMode) {
        debugPrint('DeepLinkParser: Path parts: $parts');
      }

      // Check if it's a lot path: /lot/itemId/lotId
      if (parts.length >= 3 && parts[0] == 'lot') {
        final itemId = parts[1];
        final lotId = parts[2];

        if (itemId.isNotEmpty && lotId.isNotEmpty) {
          if (kDebugMode) {
            debugPrint('DeepLinkParser: Successfully parsed lot link - itemId: $itemId, lotId: $lotId');
          }
          return {
            'itemId': itemId,
            'lotId': lotId,
          };
        }
      }
      
      if (kDebugMode) {
        debugPrint('DeepLinkParser: Not a valid lot link format');
      }
    } catch (e) {
      // Invalid format, return null
      if (kDebugMode) {
        debugPrint('DeepLinkParser: Error parsing: $e');
      }
      return null;
    }

    return null;
  }

  /// Check if a scanned value is a lot deep link
  static bool isLotDeepLink(String scannedValue) {
    return parseLotDeepLink(scannedValue) != null;
  }
}
