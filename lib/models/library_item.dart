import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Status enum for library items
enum LibraryItemStatus {
  available('available'),
  checkedOut('checked_out'),
  maintenance('maintenance'),
  retired('retired');

  final String value;
  const LibraryItemStatus(this.value);

  static LibraryItemStatus fromString(String value) {
    return LibraryItemStatus.values.firstWhere(
      (status) => status.value == value,
      orElse: () => LibraryItemStatus.available,
    );
  }

  String get displayName {
    switch (this) {
      case LibraryItemStatus.available:
        return 'Available';
      case LibraryItemStatus.checkedOut:
        return 'Checked Out';
      case LibraryItemStatus.maintenance:
        return 'Maintenance';
      case LibraryItemStatus.retired:
        return 'Retired';
    }
  }

  Color get color {
    switch (this) {
      case LibraryItemStatus.available:
        return const Color(0xFF4CAF50); // Green
      case LibraryItemStatus.checkedOut:
        return const Color(0xFF2196F3); // Blue
      case LibraryItemStatus.maintenance:
        return const Color(0xFFFF9800); // Orange
      case LibraryItemStatus.retired:
        return const Color(0xFF9E9E9E); // Grey
    }
  }
}

/// Model for reusable library items that can be checked in and out
class LibraryItem {
  final String id;
  final String name;
  final String? description;
  final String? category;
  final String? barcode;
  final LibraryItemStatus status;
  final String? checkedOutBy; // Operator name
  final Timestamp? checkedOutAt;
  final String? usedAtLocation; // Where the item was/is being used
  final String? location; // Default storage location
  final int usageCount; // Number of times used
  final int? maxUses; // How many uses before restocking needed (e.g., kit for X people)
  final int? restockThreshold; // Flag for restocking when remaining uses <= this value
  final Timestamp createdAt;
  final Timestamp updatedAt;
  final String? createdBy;
  final String? notes;
  final String? grantId; // Associated grant/budget
  final List<String> imageUrls; // Photos of the item

  LibraryItem({
    required this.id,
    required this.name,
    this.description,
    this.category,
    this.barcode,
    required this.status,
    this.checkedOutBy,
    this.checkedOutAt,
    this.usedAtLocation,
    this.location,
    this.usageCount = 0,
    this.maxUses,
    this.restockThreshold,
    required this.createdAt,
    required this.updatedAt,
    this.createdBy,
    this.notes,
    this.grantId,
    this.imageUrls = const [],
  });

  /// Create from Firestore document
  factory LibraryItem.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return LibraryItem(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'],
      category: data['category'],
      barcode: data['barcode'],
      status: LibraryItemStatus.fromString(data['status'] ?? 'available'),
      checkedOutBy: data['checkedOutBy'],
      checkedOutAt: data['checkedOutAt'],
      usedAtLocation: data['usedAtLocation'],
      location: data['location'],
      usageCount: (data['usageCount'] as num?)?.toInt() ?? 0,
      maxUses: (data['maxUses'] as num?)?.toInt(),
      restockThreshold: (data['restockThreshold'] as num?)?.toInt(),
      createdAt: data['createdAt'] ?? Timestamp.now(),
      updatedAt: data['updatedAt'] ?? Timestamp.now(),
      createdBy: data['createdBy'],
      notes: data['notes'],
      grantId: data['grantId'],
      imageUrls: (data['imageUrls'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }

  /// Convert to Firestore document data
  Map<String, dynamic> toFirestore() {
    final data = <String, dynamic>{
      'name': name,
      'status': status.value,
      'usageCount': usageCount,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };

    if (description != null) data['description'] = description;
    if (category != null) data['category'] = category;
    if (barcode != null) data['barcode'] = barcode;
    if (checkedOutBy != null) data['checkedOutBy'] = checkedOutBy;
    if (checkedOutAt != null) data['checkedOutAt'] = checkedOutAt;
    if (usedAtLocation != null) data['usedAtLocation'] = usedAtLocation;
    if (location != null) data['location'] = location;
    if (maxUses != null) data['maxUses'] = maxUses;
    if (restockThreshold != null) data['restockThreshold'] = restockThreshold;
    if (createdBy != null) data['createdBy'] = createdBy;
    if (notes != null) data['notes'] = notes;
    if (grantId != null) data['grantId'] = grantId;
    if (imageUrls.isNotEmpty) data['imageUrls'] = imageUrls;

    return data;
  }

  /// Check if item needs restocking
  bool get needsRestocking {
    if (maxUses == null || maxUses == 0) return false;
    final threshold = restockThreshold ?? 0;
    final remaining = maxUses! - usageCount;
    return remaining <= threshold;
  }

  /// Get remaining uses
  int? get remainingUses {
    if (maxUses == null) return null;
    return maxUses! - usageCount;
  }

  /// Copy with updated fields
  LibraryItem copyWith({
    String? name,
    String? description,
    String? category,
    String? barcode,
    LibraryItemStatus? status,
    String? checkedOutBy,
    Timestamp? checkedOutAt,
    String? usedAtLocation,
    String? location,
    int? usageCount,
    int? maxUses,
    int? restockThreshold,
    Timestamp? updatedAt,
    String? notes,
    String? grantId,
    List<String>? imageUrls,
  }) {
    return LibraryItem(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      barcode: barcode ?? this.barcode,
      status: status ?? this.status,
      checkedOutBy: checkedOutBy ?? this.checkedOutBy,
      checkedOutAt: checkedOutAt ?? this.checkedOutAt,
      usedAtLocation: usedAtLocation ?? this.usedAtLocation,
      location: location ?? this.location,
      usageCount: usageCount ?? this.usageCount,
      maxUses: maxUses ?? this.maxUses,
      restockThreshold: restockThreshold ?? this.restockThreshold,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy,
      notes: notes ?? this.notes,
      grantId: grantId ?? this.grantId,
      imageUrls: imageUrls ?? this.imageUrls,
    );
  }
}
