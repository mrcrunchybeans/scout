import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../features/session/cart_models.dart';

class CartSessionCacheService {
  static const String _keyPrefix = 'cart_session_cache_';
  static const String _draftKeyPrefix = 'cart_session_draft_';
  
  /// Save a cart session to local storage for recovery
  static Future<void> saveSessionDraft({
    String? sessionId,
    String? interventionId,
    String? interventionName,
    String? grantId,
    String? locationText,
    String? notes,
    required List<CartLine> lines,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Use sessionId if available, otherwise create a temporary key
      final key = sessionId != null 
          ? '$_keyPrefix$sessionId' 
          : '${_draftKeyPrefix}new_session';
      
      final data = {
        'sessionId': sessionId,
        'interventionId': interventionId,
        'interventionName': interventionName,
        'grantId': grantId,
        'locationText': locationText ?? '',
        'notes': notes ?? '',
        'lines': lines.map((line) => line.toMap()).toList(),
        'savedAt': DateTime.now().toIso8601String(),
        'version': 1, // For future compatibility
      };
      
      await prefs.setString(key, jsonEncode(data));
    } catch (e) {
      // Silently fail - autosave shouldn't interrupt user workflow
      debugPrint('Failed to save session draft: $e');
    }
  }
  
  /// Load a cached cart session
  static Future<CartSessionCache?> loadSessionDraft(String? sessionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      String? key;
      if (sessionId != null) {
        key = '$_keyPrefix$sessionId';
      } else {
        // Look for new session draft
        key = '${_draftKeyPrefix}new_session';
      }
      
      final jsonString = prefs.getString(key);
      if (jsonString == null) return null;
      
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      return CartSessionCache.fromMap(data);
    } catch (e) {
      debugPrint('Failed to load session draft: $e');
      return null;
    }
  }
  
  /// Get all cached sessions for recovery UI
  static Future<List<CartSessionCache>> getAllCachedSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((key) => 
        key.startsWith(_keyPrefix) || key.startsWith(_draftKeyPrefix)
      ).toList();
      
      final sessions = <CartSessionCache>[];
      for (final key in keys) {
        final jsonString = prefs.getString(key);
        if (jsonString != null) {
          try {
            final data = jsonDecode(jsonString) as Map<String, dynamic>;
            sessions.add(CartSessionCache.fromMap(data));
          } catch (e) {
            // Skip corrupted cache entries
            continue;
          }
        }
      }
      
      // Sort by saved date, newest first
      sessions.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      return sessions;
    } catch (e) {
      debugPrint('Failed to load cached sessions: $e');
      return [];
    }
  }
  
  /// Clear a specific session cache
  static Future<void> clearSessionDraft(String? sessionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      if (sessionId != null) {
        await prefs.remove('$_keyPrefix$sessionId');
      } else {
        await prefs.remove('${_draftKeyPrefix}new_session');
      }
    } catch (e) {
      debugPrint('Failed to clear session draft: $e');
    }
  }
  
  /// Clear all cached sessions (for cleanup)
  static Future<void> clearAllCachedSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((key) => 
        key.startsWith(_keyPrefix) || key.startsWith(_draftKeyPrefix)
      ).toList();
      
      for (final key in keys) {
        await prefs.remove(key);
      }
    } catch (e) {
      debugPrint('Failed to clear all cached sessions: $e');
    }
  }
  
  /// Check if a session has cached data
  static Future<bool> hasSessionDraft(String? sessionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = sessionId != null 
          ? '$_keyPrefix$sessionId' 
          : '${_draftKeyPrefix}new_session';
      return prefs.containsKey(key);
    } catch (e) {
      return false;
    }
  }
  
  /// Clean up old cache entries (older than 7 days)
  static Future<void> cleanupOldCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((key) => 
        key.startsWith(_keyPrefix) || key.startsWith(_draftKeyPrefix)
      ).toList();
      
      final cutoffDate = DateTime.now().subtract(const Duration(days: 7));
      
      for (final key in keys) {
        final jsonString = prefs.getString(key);
        if (jsonString != null) {
          try {
            final data = jsonDecode(jsonString) as Map<String, dynamic>;
            final savedAt = DateTime.parse(data['savedAt'] as String);
            if (savedAt.isBefore(cutoffDate)) {
              await prefs.remove(key);
            }
          } catch (e) {
            // Remove corrupted entries
            await prefs.remove(key);
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to cleanup old cache: $e');
    }
  }
}

class CartSessionCache {
  final String? sessionId;
  final String? interventionId;
  final String? interventionName;
  final String? grantId;
  final String locationText;
  final String notes;
  final List<CartLine> lines;
  final DateTime savedAt;
  final int version;
  
  const CartSessionCache({
    this.sessionId,
    this.interventionId,
    this.interventionName,
    this.grantId,
    required this.locationText,
    required this.notes,
    required this.lines,
    required this.savedAt,
    required this.version,
  });
  
  factory CartSessionCache.fromMap(Map<String, dynamic> map) {
    return CartSessionCache(
      sessionId: map['sessionId'] as String?,
      interventionId: map['interventionId'] as String?,
      interventionName: map['interventionName'] as String?,
      grantId: map['grantId'] as String?,
      locationText: map['locationText'] as String? ?? '',
      notes: map['notes'] as String? ?? '',
      lines: (map['lines'] as List<dynamic>)
          .map((lineMap) => CartLine.fromMap(lineMap as Map<String, dynamic>))
          .toList(),
      savedAt: DateTime.parse(map['savedAt'] as String),
      version: map['version'] as int? ?? 1,
    );
  }
  
  bool get isNewSession => sessionId == null;
  bool get hasContent => lines.isNotEmpty || locationText.isNotEmpty || notes.isNotEmpty;
  
  String get displayName {
    if (interventionName != null) {
      return interventionName!;
    }
    if (isNewSession) {
      return 'New Session Draft';
    }
    return 'Session ${sessionId?.substring(0, 8) ?? 'Unknown'}';
  }
}