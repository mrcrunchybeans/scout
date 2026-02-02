import 'package:cloud_firestore/cloud_firestore.dart';

/// Model representing a saved cart template for recurring interventions.
class CartTemplate {
  final String id;
  final String name;
  final String? interventionId;  // Optional: link to specific intervention
  final List<TemplateLine> lines;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
  final String createdBy;

  CartTemplate({
    required this.id,
    required this.name,
    this.interventionId,
    required this.lines,
    required this.createdAt,
    this.lastUsedAt,
    required this.createdBy,
  });

  /// Convert to Firestore document format
  Map<String, dynamic> toMap() => {
    'name': name,
    'interventionId': interventionId,
    'lines': lines.map((line) => line.toMap()).toList(),
    'createdAt': Timestamp.fromDate(createdAt),
    'lastUsedAt': lastUsedAt != null ? Timestamp.fromDate(lastUsedAt!) : null,
    'createdBy': createdBy,
  };

  /// Create from Firestore document snapshot
  factory CartTemplate.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final lines = (data['lines'] as List<dynamic>?)
        ?.map((item) => TemplateLine.fromMap(item as Map<String, dynamic>))
        .toList() ?? [];

    return CartTemplate(
      id: doc.id,
      name: data['name'] as String,
      interventionId: data['interventionId'] as String?,
      lines: lines,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastUsedAt: (data['lastUsedAt'] as Timestamp?)?.toDate(),
      createdBy: data['createdBy'] as String,
    );
  }
}

/// Represents a single line item in a template.
class TemplateLine {
  final String itemId;
  final String itemName;
  final String baseUnit;
  final String? lotCode;
  final int quantity;

  TemplateLine({
    required this.itemId,
    required this.itemName,
    required this.baseUnit,
    this.lotCode,
    required this.quantity,
  });

  /// Convert to map for Firestore storage
  Map<String, dynamic> toMap() => {
    'itemId': itemId,
    'itemName': itemName,
    'baseUnit': baseUnit,
    'lotCode': lotCode,
    'quantity': quantity,
  };

  /// Create from map
  factory TemplateLine.fromMap(Map<String, dynamic> map) => TemplateLine(
    itemId: map['itemId'] as String,
    itemName: map['itemName'] as String,
    baseUnit: map['baseUnit'] as String,
    lotCode: map['lotCode'] as String?,
    quantity: (map['quantity'] as num).toInt(),
  );
}
