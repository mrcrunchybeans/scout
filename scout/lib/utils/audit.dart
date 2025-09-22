// lib/utils/audit.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'operator_store.dart';

/// Simple, centralized audit helper for Firestore writes + audit log entries.
///
/// Usage:
///   await Audit.log('item.create', {'itemId': id, 'name': name});
///   final payload = {'name': 'Gauze', ...};
///   await ref.set(Audit.attach(payload), SetOptions(merge: true));
///
class Audit {
  static final _db = FirebaseFirestore.instance;

  /// Attach standard audit fields to any document payload.
  static Map<String, dynamic> attach(Map<String, dynamic> payload) {
    return {
      ...payload,
      'operatorName': _currentOperatorName(), // null okay
      'createdBy': FirebaseAuth.instance.currentUser?.uid,
      'updatedAt': FieldValue.serverTimestamp(),
      // Only set createdAt if the caller didn’t already provide it.
      'createdAt': payload.containsKey('createdAt')
          ? payload['createdAt']
          : FieldValue.serverTimestamp(),
    };
  }

  /// Write an entry to /audit_logs (append-only).
  static Future<void> log(String type, Map<String, dynamic> data) async {
    await _db.collection('audit_logs').add({
      'type': type,                 // e.g. item.create, lot.create, session.close
      'data': data,                 // free-form details
      'operatorName': _currentOperatorName(),
      'createdBy': FirebaseAuth.instance.currentUser?.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// If you already know you’re updating (not creating), use this to only bump updatedAt.
  static Map<String, dynamic> updateOnly(Map<String, dynamic> payload) {
    return {
      ...payload,
      'operatorName': _currentOperatorName(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Returns the current operator name from OperatorStore, with fallback to user info.
  static String? _currentOperatorName() {
    final operatorName = OperatorStore.name.value;
    if (operatorName != null && operatorName.isNotEmpty) {
      return operatorName;
    }
    
    // Fallback to Firebase Auth user display name or email
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      return user.displayName ?? user.email ?? 'User ${user.uid.substring(0, 8)}';
    }
    
    return null; // Will show as "Unknown" in UI
  }
}
