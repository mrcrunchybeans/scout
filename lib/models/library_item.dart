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
  final String? serialNumber;
  final LibraryItemStatus status;
  final String? checkedOutBy; // Operator name
  final Timestamp? checkedOutAt;
  final Timestamp? dueDate;
  final String? location;
  final Timestamp createdAt;
  final Timestamp updatedAt;
  final String? createdBy;
  final String? notes;

  LibraryItem({
    required this.id,
    required this.name,
    this.description,
    this.category,
    this.barcode,
    this.serialNumber,
    required this.status,
    this.checkedOutBy,
    this.checkedOutAt,
    this.dueDate,
    this.location,
    required this.createdAt,
    required this.updatedAt,
    this.createdBy,
    this.notes,
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
      serialNumber: data['serialNumber'],
      status: LibraryItemStatus.fromString(data['status'] ?? 'available'),
      checkedOutBy: data['checkedOutBy'],
      checkedOutAt: data['checkedOutAt'],
      dueDate: data['dueDate'],
      location: data['location'],
      createdAt: data['createdAt'] ?? Timestamp.now(),
      updatedAt: data['updatedAt'] ?? Timestamp.now(),
      createdBy: data['createdBy'],
      notes: data['notes'],
    );
  }

  /// Convert to Firestore document data
  Map<String, dynamic> toFirestore() {
    final data = <String, dynamic>{
      'name': name,
      'status': status.value,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };

    if (description != null) data['description'] = description;
    if (category != null) data['category'] = category;
    if (barcode != null) data['barcode'] = barcode;
    if (serialNumber != null) data['serialNumber'] = serialNumber;
    if (checkedOutBy != null) data['checkedOutBy'] = checkedOutBy;
    if (checkedOutAt != null) data['checkedOutAt'] = checkedOutAt;
    if (dueDate != null) data['dueDate'] = dueDate;
    if (location != null) data['location'] = location;
    if (createdBy != null) data['createdBy'] = createdBy;
    if (notes != null) data['notes'] = notes;

    return data;
  }

  /// Check if item is overdue
  bool get isOverdue {
    if (status != LibraryItemStatus.checkedOut || dueDate == null) {
      return false;
    }
    return dueDate!.toDate().isBefore(DateTime.now());
  }

  /// Copy with updated fields
  LibraryItem copyWith({
    String? name,
    String? description,
    String? category,
    String? barcode,
    String? serialNumber,
    LibraryItemStatus? status,
    String? checkedOutBy,
    Timestamp? checkedOutAt,
    Timestamp? dueDate,
    String? location,
    Timestamp? updatedAt,
    String? notes,
  }) {
    return LibraryItem(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      barcode: barcode ?? this.barcode,
      serialNumber: serialNumber ?? this.serialNumber,
      status: status ?? this.status,
      checkedOutBy: checkedOutBy ?? this.checkedOutBy,
      checkedOutAt: checkedOutAt ?? this.checkedOutAt,
      dueDate: dueDate ?? this.dueDate,
      location: location ?? this.location,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy,
      notes: notes ?? this.notes,
    );
  }
}
