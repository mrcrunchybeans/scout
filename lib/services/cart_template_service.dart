import 'package:cloud_firestore/cloud_firestore.dart';
import '../features/session/cart_template.dart';

/// Service for managing cart templates in Firestore.
///
/// Handles saving, loading, and deleting cart templates for recurring interventions.
class CartTemplateService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _collectionName = 'cart_templates';

  /// Save a new template to Firestore.
  /// Returns the created template ID.
  Future<String> saveTemplate({
    required String name,
    required List<TemplateLine> lines,
    required String createdBy,
    String? interventionId,
  }) async {
    final template = CartTemplate(
      id: '',  // Will be set by Firestore
      name: name,
      interventionId: interventionId,
      lines: lines,
      createdAt: DateTime.now(),
      lastUsedAt: null,
      createdBy: createdBy,
    );

    final docRef = await _db.collection(_collectionName).add(template.toMap());
    return docRef.id;
  }

  /// Load all templates accessible to the current user.
  /// Optionally filter by intervention ID or creator.
  Future<List<CartTemplate>> loadTemplates({
    String? interventionId,
    String? createdBy,
    int limit = 50,
  }) async {
    Query<Map<String, dynamic>> query = _db.collection(_collectionName);

    // Apply optional filters
    if (interventionId != null) {
      query = query.where('interventionId', isEqualTo: interventionId);
    }
    if (createdBy != null) {
      query = query.where('createdBy', isEqualTo: createdBy);
    }

    // Order by most recently used/created and limit results
    query = query
        .orderBy('lastUsedAt', descending: true)
        .orderBy('createdAt', descending: true)
        .limit(limit);

    final snapshot = await query.get();
    return snapshot.docs.map((doc) => CartTemplate.fromDocument(doc)).toList();
  }

  /// Load all templates (no filters).
  Future<List<CartTemplate>> loadAllTemplates({int limit = 100}) async {
    final snapshot = await _db
        .collection(_collectionName)
        .orderBy('lastUsedAt', descending: true)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs.map((doc) => CartTemplate.fromDocument(doc)).toList();
  }

  /// Delete a template by ID.
  Future<void> deleteTemplate(String templateId) async {
    await _db.collection(_collectionName).doc(templateId).delete();
  }

  /// Update the lastUsedAt timestamp when a template is used.
  Future<void> recordTemplateUse(String templateId) async {
    await _db.collection(_collectionName).doc(templateId).update({
      'lastUsedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  /// Update a template's name, lines, or interventionId.
  Future<void> updateTemplate({
    required String templateId,
    required String name,
    required List<TemplateLine> lines,
    String? interventionId,
  }) async {
    await _db.collection(_collectionName).doc(templateId).update({
      'name': name,
      'lines': lines.map((line) => line.toMap()).toList(),
      if (interventionId != null) 'interventionId': interventionId,
    });
  }

  /// Get a single template by ID.
  Future<CartTemplate?> getTemplate(String templateId) async {
    final doc = await _db.collection(_collectionName).doc(templateId).get();
    if (!doc.exists) return null;
    return CartTemplate.fromDocument(doc);
  }
}
