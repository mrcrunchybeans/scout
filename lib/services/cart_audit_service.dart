import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../features/session/cart_models.dart';

/// Service for managing cart session audit trails
class CartAuditService {
  static final _db = FirebaseFirestore.instance;
  static const String _collectionPath = 'cart_sessions';

  /// Log an audit entry for a cart session
  ///
  /// [sessionId] - The ID of the cart session
  /// [userId] - The ID of the user performing the action
  /// [userName] - The display name of the user
  /// [action] - The type of action being performed
  /// [details] - Optional additional details about the action
  static Future<CartAuditEntry> log({
    required String sessionId,
    required String userId,
    required String userName,
    required AuditAction action,
    Map<String, dynamic>? details,
  }) async {
    final id = const Uuid().v4();
    final now = DateTime.now();

    final entry = CartAuditEntry(
      id: id,
      sessionId: sessionId,
      userId: userId,
      userName: userName,
      timestamp: now,
      action: action,
      details: details,
    );

    await _db
        .collection(_collectionPath)
        .doc(sessionId)
        .collection('audit')
        .doc(id)
        .set(entry.toMap());

    return entry;
  }

  /// Get the audit log for a specific session, ordered by timestamp
  static Stream<List<CartAuditEntry>> getAuditStream(String sessionId) {
    return _db
        .collection(_collectionPath)
        .doc(sessionId)
        .collection('audit')
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => CartAuditEntry.fromDocument(doc))
          .toList();
    });
  }

  /// Get the audit log for a specific session (one-time fetch)
  static Future<List<CartAuditEntry>> getAuditLog(String sessionId) async {
    final snapshot = await _db
        .collection(_collectionPath)
        .doc(sessionId)
        .collection('audit')
        .orderBy('timestamp', descending: true)
        .limit(100)
        .get();

    return snapshot.docs
        .map((doc) => CartAuditEntry.fromDocument(doc))
        .toList();
  }

  /// Get recent activity for a specific user across all sessions
  static Future<List<CartAuditEntry>> getRecentActivityForUser(
    String userId, {
    int limit = 50,
  }) async {
    final snapshot = await _db
        .collectionGroup('audit')
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs
        .map((doc) => CartAuditEntry.fromDocument(doc))
        .toList();
  }

  /// Get audit entries for a session filtered by action type
  static Future<List<CartAuditEntry>> getAuditLogByAction(
    String sessionId,
    AuditAction action,
  ) async {
    final snapshot = await _db
        .collection(_collectionPath)
        .doc(sessionId)
        .collection('audit')
        .where('action', isEqualTo: action.name)
        .orderBy('timestamp', descending: true)
        .get();

    return snapshot.docs
        .map((doc) => CartAuditEntry.fromDocument(doc))
        .toList();
  }

  /// Get count of audit entries for a session
  static Future<int> getAuditCount(String sessionId) async {
    final snapshot = await _db
        .collection(_collectionPath)
        .doc(sessionId)
        .collection('audit')
        .count()
        .get();

    return snapshot.count ?? 0;
  }

  /// Delete all audit entries for a session (admin only)
  static Future<void> clearAuditLog(String sessionId) async {
    final batch = _db.batch();
    final snapshot = await _db
        .collection(_collectionPath)
        .doc(sessionId)
        .collection('audit')
        .get();

    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }

    await batch.commit();
  }
}
