import 'package:cloud_firestore/cloud_firestore.dart';

class CartLine {
  final String itemId;
  final String itemName;
  final String baseUnit;
  final String? lotId;        // optional, if using lots
  final String? lotCode;      // the human-readable lot code (e.g., "2509-001")
  final num initialQty;
  final num? endQty;          // null until closing

  CartLine({
    required this.itemId,
    required this.itemName,
    required this.baseUnit,
    this.lotId,
    this.lotCode,
    required this.initialQty,
    this.endQty,
  });

  CartLine copyWith({
    String? itemId,
    String? itemName,
    String? baseUnit,
    String? lotId,
    String? lotCode,
    num? initialQty,
    num? endQty,
  }) {
    return CartLine(
      itemId: itemId ?? this.itemId,
      itemName: itemName ?? this.itemName,
      baseUnit: baseUnit ?? this.baseUnit,
      lotId: lotId ?? this.lotId,
      lotCode: lotCode ?? this.lotCode,
      initialQty: initialQty ?? this.initialQty,
      endQty: endQty ?? this.endQty,
    );
  }

  num get usedQty => (endQty == null) ? 0 : (initialQty - (endQty ?? 0)).clamp(0, double.infinity);

  Map<String, dynamic> toMap() => {
    'itemId': itemId,
    'itemName': itemName,
    'baseUnit': baseUnit,
    'lotId': lotId,
    'lotCode': lotCode,
    'initialQty': initialQty,
    'endQty': endQty,
  };

  static CartLine fromMap(Map<String, dynamic> m) => CartLine(
    itemId: m['itemId'] as String,
    itemName: (m['itemName'] ?? 'Unnamed') as String,
    baseUnit: (m['baseUnit'] ?? 'each') as String,
    lotId: m['lotId'] as String?,
    lotCode: m['lotCode'] as String?,
    initialQty: (m['initialQty'] ?? 0) as num,
    endQty: m['endQty'] as num?,
  );
}

// ==================== Cart Session Metric Model ====================

/// Represents usage metrics for a single item within a cart session
class ItemUsageBreakdown {
  final String itemId;
  final String? itemName;
  final num initialQty;
  final num? usedQty;
  final double usagePercentage;
  final num? wastedQty;

  ItemUsageBreakdown({
    required this.itemId,
    this.itemName,
    required this.initialQty,
    this.usedQty,
    required this.usagePercentage,
    this.wastedQty,
  });

  double get wastePercentage => 1.0 - usagePercentage;

  Map<String, dynamic> toMap() => {
    'itemId': itemId,
    'itemName': itemName,
    'initialQty': initialQty,
    'usedQty': usedQty,
    'usagePercentage': usagePercentage,
    'wastedQty': wastedQty,
  };

  factory ItemUsageBreakdown.fromMap(Map<String, dynamic> m) => ItemUsageBreakdown(
    itemId: m['itemId'] as String,
    itemName: m['itemName'] as String?,
    initialQty: (m['initialQty'] ?? 0) as num,
    usedQty: m['usedQty'] as num?,
    usagePercentage: (m['usagePercentage'] ?? 0.0) as double,
    wastedQty: m['wastedQty'] as num?,
  );
}

/// Represents a cart session metric for analytics
class CartSessionMetric {
  final String sessionId;
  final DateTime createdAt;
  final DateTime? closedAt;
  final int itemCount;
  final int totalQuantity;
  final double usagePercentage;
  final String interventionId;
  final String? location;
  final List<ItemUsageBreakdown> itemBreakdown;
  final Duration? duration;

  CartSessionMetric({
    required this.sessionId,
    required this.createdAt,
    this.closedAt,
    required this.itemCount,
    required this.totalQuantity,
    required this.usagePercentage,
    required this.interventionId,
    this.location,
    this.itemBreakdown = const [],
    this.duration,
  });

  /// Calculate session duration (closedAt - createdAt)
  Duration? getCalculatedDuration() {
    if (closedAt == null) return null;
    return closedAt!.difference(createdAt);
  }

  Map<String, dynamic> toMap() => {
    'sessionId': sessionId,
    'createdAt': Timestamp.fromDate(createdAt),
    'closedAt': closedAt != null ? Timestamp.fromDate(closedAt!) : null,
    'itemCount': itemCount,
    'totalQuantity': totalQuantity,
    'usagePercentage': usagePercentage,
    'interventionId': interventionId,
    'location': location,
    'itemBreakdown': itemBreakdown.map((e) => e.toMap()).toList(),
  };

  factory CartSessionMetric.fromMap(Map<String, dynamic> m) => CartSessionMetric(
    sessionId: m['sessionId'] as String,
    createdAt: (m['createdAt'] as Timestamp).toDate(),
    closedAt: (m['closedAt'] as Timestamp?)?.toDate(),
    itemCount: (m['itemCount'] ?? 0) as int,
    totalQuantity: (m['totalQuantity'] ?? 0) as int,
    usagePercentage: (m['usagePercentage'] ?? 0.0) as double,
    interventionId: m['interventionId'] as String,
    location: m['location'] as String?,
    itemBreakdown: (m['itemBreakdown'] as List?)
        ?.map((e) => ItemUsageBreakdown.fromMap(e as Map<String, dynamic>))
        .toList() ?? [],
  );
}

/// Lightweight item usage metric for top lists
class ItemUsageMetric {
  final String itemId;
  final String? itemName;
  final double totalUsagePercentage;
  final int usageCount;
  final int totalQuantity;

  ItemUsageMetric({
    required this.itemId,
    this.itemName,
    required this.totalUsagePercentage,
    required this.usageCount,
    required this.totalQuantity,
  });

  Map<String, dynamic> toMap() => {
    'itemId': itemId,
    'itemName': itemName,
    'totalUsagePercentage': totalUsagePercentage,
    'usageCount': usageCount,
    'totalQuantity': totalQuantity,
  };

  factory ItemUsageMetric.fromMap(Map<String, dynamic> m) => ItemUsageMetric(
    itemId: m['itemId'] as String,
    itemName: m['itemName'] as String?,
    totalUsagePercentage: (m['totalUsagePercentage'] ?? 0.0) as double,
    usageCount: (m['usageCount'] ?? 0) as int,
    totalQuantity: (m['totalQuantity'] ?? 0) as int,
  );
}

/// Time series metric for trend analysis
class TimeSeriesMetric {
  final DateTime date;
  final double value;
  final String? label;

  TimeSeriesMetric({
    required this.date,
    required this.value,
    this.label,
  });

  Map<String, dynamic> toMap() => {
    'date': Timestamp.fromDate(date),
    'value': value,
    'label': label,
  };

  factory TimeSeriesMetric.fromMap(Map<String, dynamic> m) => TimeSeriesMetric(
    date: (m['date'] as Timestamp).toDate(),
    value: (m['value'] ?? 0.0) as double,
    label: m['label'] as String?,
  );
}

// ==================== Cart Audit Models ====================

/// Enum representing the type of action performed on a cart session
enum AuditAction {
  created,
  itemAdded,
  itemRemoved,
  quantityChanged,
  lotChanged,
  reopened,
  closed,
  deleted,
  templateLoaded,
}

/// Represents a single audit entry for a cart session
class CartAuditEntry {
  final String id;
  final String sessionId;
  final String userId;
  final String userName;
  final DateTime timestamp;
  final AuditAction action;
  final Map<String, dynamic>? details;

  CartAuditEntry({
    required this.id,
    required this.sessionId,
    required this.userId,
    required this.userName,
    required this.timestamp,
    required this.action,
    this.details,
  });

  /// Convert to Firestore document format
  Map<String, dynamic> toMap() => {
        'sessionId': sessionId,
        'userId': userId,
        'userName': userName,
        'timestamp': Timestamp.fromDate(timestamp),
        'action': action.name,
        if (details != null) 'details': details,
      };

  /// Create from Firestore document
  factory CartAuditEntry.fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final timestamp = data['timestamp'];
    return CartAuditEntry(
      id: doc.id,
      sessionId: data['sessionId'] as String,
      userId: data['userId'] as String,
      userName: data['userName'] as String,
      timestamp: timestamp is Timestamp ? timestamp.toDate() : DateTime.now(),
      action: _parseAction(data['action'] as String),
      details: data['details'] as Map<String, dynamic>?,
    );
  }

  static AuditAction _parseAction(String actionName) {
    try {
      return AuditAction.values.firstWhere((e) => e.name == actionName);
    } catch (_) {
      return AuditAction.created;
    }
  }
}
