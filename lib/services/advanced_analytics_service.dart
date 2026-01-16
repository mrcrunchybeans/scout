import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

// ==================== Enums ====================

/// Represents a metric that can be calculated
enum MetricType {
  totalUsage,        // Total quantity used
  averageUsage,      // Average per transaction
  usageFrequency,    // Number of times used
  costPerUse,        // Estimated cost effectiveness
  velocity,          // Usage per day
  waste,             // Amount wasted
  efficiency,        // Usage vs waste ratio
  adoption,          // Percentage of items used
  trends,            // Change over time
}

/// Dimensions for segmentation
enum DimensionType {
  intervention,      // By intervention type
  grant,            // By funding source
  operator,         // By staff member
  item,             // By item
  category,         // By item category
  location,         // By storage location
  useType,          // Staff vs patient use
  dateDay,          // Daily trends
  dateWeek,         // Weekly trends
  dateMonth,        // Monthly trends
}

// ==================== Models ====================

/// Advanced analytics result
class AnalyticsResult {
  final String label;
  final double value;
  final Map<String, dynamic> metadata;
  final DateTime? timestamp;
  final int count;
  double? trend; // % change from previous period
  
  AnalyticsResult({
    required this.label,
    required this.value,
    this.metadata = const {},
    this.timestamp,
    this.count = 0,
    this.trend,
  });

  Map<String, dynamic> toJson() => {
    'label': label,
    'value': value,
    'metadata': metadata,
    'timestamp': timestamp?.toIso8601String(),
    'count': count,
    'trend': trend,
  };
}

/// Customizable analytics query
class AnalyticsQuery {
  final DateTime startDate;
  final DateTime endDate;
  final List<MetricType> metrics;
  final List<DimensionType> dimensions;
  final List<String>? filterByInterventions;
  final List<String>? filterByGrants;
  final List<String>? filterByOperators;
  final List<String>? filterByItems;
  final List<String>? filterByCategories;
  final bool includeWaste;
  final bool includeArchived;
  final int? topN; // Top N items
  final String? sortBy; // Sort by metric or dimension
  final bool descending;

  AnalyticsQuery({
    required this.startDate,
    required this.endDate,
    required this.metrics,
    required this.dimensions,
    this.filterByInterventions,
    this.filterByGrants,
    this.filterByOperators,
    this.filterByItems,
    this.filterByCategories,
    this.includeWaste = true,
    this.includeArchived = false,
    this.topN,
    this.sortBy,
    this.descending = true,
  });
}

// ==================== Advanced Analytics Service ====================

/// Advanced analytics service with deep metrics, segmentation, and customization
class AdvancedAnalyticsService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ==================== Usage Analytics ====================

  /// Get comprehensive usage analytics with multiple metrics
  static Future<Map<String, dynamic>> getUsageAnalytics(AnalyticsQuery query) async {
    final results = <String, dynamic>{};
    
    try {
      // Fetch raw usage logs
      var usageQuery = _db
          .collection('usage_logs')
          .where('usedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(query.startDate))
          .where('usedAt', isLessThan: Timestamp.fromDate(query.endDate.add(const Duration(days: 1))));

      final usageDocs = await usageQuery.get();
      final usageLogs = _filterUsageLogs(usageDocs, query);

      // Calculate metrics
      for (final metric in query.metrics) {
        results[metric.toString()] = await _calculateMetric(metric, usageLogs, query);
      }

      // Segment by dimensions
      for (final dimension in query.dimensions) {
        results['by_${dimension.toString()}'] = await _segmentByDimension(dimension, usageLogs, query);
      }

      return results;
    } catch (e) {
      rethrow;
    }
  }

  /// Get trend analysis over multiple periods
  static Future<List<AnalyticsResult>> getTrendAnalysis({
    required DateTime startDate,
    required DateTime endDate,
    required String metric,
    required Duration period,
    String? filterByIntervention,
    String? filterByGrant,
  }) async {
    final trends = <AnalyticsResult>[];
    var current = startDate;

    while (current.isBefore(endDate)) {
      final periodEnd = current.add(period);
      
      var query = _db
          .collection('usage_logs')
          .where('usedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(current))
          .where('usedAt', isLessThan: Timestamp.fromDate(periodEnd));

      if (filterByIntervention != null) {
        query = query.where('interventionId', isEqualTo: filterByIntervention);
      }
      if (filterByGrant != null) {
        query = query.where('grantId', isEqualTo: filterByGrant);
      }

      final docs = await query.get();
      final totalUsage = docs.docs.fold<double>(
        0,
        (sum, doc) => sum + ((doc['qtyUsed'] as num?)?.toDouble() ?? 0),
      );

      trends.add(AnalyticsResult(
        label: _formatPeriodLabel(current, period),
        value: totalUsage,
        timestamp: current,
        count: docs.docs.length,
      ));

      current = periodEnd;
    }

    // Calculate trend percentages
    for (int i = 1; i < trends.length; i++) {
      if (trends[i - 1].value > 0) {
        trends[i].trend = ((trends[i].value - trends[i - 1].value) / trends[i - 1].value) * 100;
      }
    }

    return trends;
  }

  /// Get user activity breakdown with personal statistics
  static Future<Map<String, dynamic>> getUserActivityProfile(String operatorName) async {
    try {
      final usageQuery = _db
          .collection('usage_logs')
          .where('operatorName', isEqualTo: operatorName);

      final auditQuery = _db
          .collection('audit_logs')
          .where('operatorName', isEqualTo: operatorName);

      final usageDocs = await usageQuery.get();
      final auditDocs = await auditQuery.get();

      final totalUsage = usageDocs.docs.fold<double>(
        0,
        (sum, doc) => sum + ((doc['qtyUsed'] as num?)?.toDouble() ?? 0),
      );

      final uniqueItems = usageDocs.docs
          .map((doc) => doc['itemId'])
          .toSet()
          .length;

      final interventions = usageDocs.docs
          .map((doc) => doc['interventionId'])
          .toSet()
          .length;

      final lastUsed = usageDocs.docs.isNotEmpty
          ? (usageDocs.docs.first['usedAt'] as Timestamp?)?.toDate()
          : null;

      final actionCounts = <String, int>{};
      for (final doc in auditDocs.docs) {
        final action = doc['action'] ?? 'unknown';
        actionCounts[action] = (actionCounts[action] ?? 0) + 1;
      }

      return {
        'operatorName': operatorName,
        'totalUsage': totalUsage,
        'usageCount': usageDocs.docs.length,
        'uniqueItems': uniqueItems,
        'interventions': interventions,
        'lastUsed': lastUsed?.toIso8601String(),
        'actionsPerformed': actionCounts,
        'totalActions': auditDocs.docs.length,
      };
    } catch (e) {
      rethrow;
    }
  }

  /// Get inventory efficiency metrics
  static Future<Map<String, dynamic>> getInventoryEfficiency({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final itemsSnapshot = await _db.collection('items').get();
      final efficiency = <String, dynamic>{};

      for (final itemDoc in itemsSnapshot.docs) {
        final itemData = itemDoc.data();
        final itemId = itemDoc.id;
        final itemName = itemData['name'] ?? 'Unknown';
        final qtyOnHand = (itemData['qtyOnHand'] as num?)?.toDouble() ?? 0;
        final minQty = (itemData['minQty'] as num?)?.toDouble() ?? 1;

        // Get usage for this item
        final usageQuery = _db
            .collection('usage_logs')
            .where('itemId', isEqualTo: itemId)
            .where('usedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
            .where('usedAt', isLessThan: Timestamp.fromDate(endDate.add(const Duration(days: 1))));

        final usageDocs = await usageQuery.get();
        final totalUsed = usageDocs.docs.fold<double>(
          0,
          (sum, doc) => sum + ((doc['qtyUsed'] as num?)?.toDouble() ?? 0),
        );

        // Calculate efficiency score (0-100)
        final turnover = totalUsed > 0 ? totalUsed / (qtyOnHand + totalUsed) : 0;
        final overstock = qtyOnHand > (minQty * 3) ? 1.0 : 0.0;
        final efficiency_score = (turnover * 60) - (overstock * 10);

        efficiency[itemId] = {
          'name': itemName,
          'qtyOnHand': qtyOnHand,
          'minQty': minQty,
          'totalUsed': totalUsed,
          'turnover': turnover,
          'efficiencyScore': efficiency_score.clamp(0, 100),
          'status': efficiency_score > 70 ? 'optimal' : efficiency_score > 40 ? 'good' : 'needs_attention',
        };
      }

      return efficiency;
    } catch (e) {
      rethrow;
    }
  }

  /// Get predictive analytics (simple forecasting)
  static Future<List<AnalyticsResult>> getPredictedUsage({
    required String itemId,
    required int forecastDays,
    required int historicalDays,
  }) async {
    try {
      final now = DateTime.now();
      final histStart = now.subtract(Duration(days: historicalDays));

      // Get historical usage
      final historyQuery = _db
          .collection('usage_logs')
          .where('itemId', isEqualTo: itemId)
          .where('usedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(histStart))
          .where('usedAt', isLessThan: Timestamp.fromDate(now.add(const Duration(days: 1))));

      final historyDocs = await historyQuery.get();

      // Calculate daily averages
      final dailyUsage = <DateTime, double>{};
      for (final doc in historyDocs.docs) {
        final usedAt = (doc['usedAt'] as Timestamp?)?.toDate();
        final qty = (doc['qtyUsed'] as num?)?.toDouble() ?? 0;
        if (usedAt != null) {
          final day = DateTime(usedAt.year, usedAt.month, usedAt.day);
          dailyUsage[day] = (dailyUsage[day] ?? 0) + qty;
        }
      }

      final avgDaily = dailyUsage.isEmpty
          ? 0.0
          : dailyUsage.values.fold<double>(0, (a, b) => a + b) / historicalDays;

      // Generate forecast
      final forecast = <AnalyticsResult>[];
      for (int i = 1; i <= forecastDays; i++) {
        final forecastDate = now.add(Duration(days: i));
        // Simple linear forecast with some variance
        final predicted = avgDaily * (0.9 + (i * 0.02)); // Slight upward trend
        forecast.add(AnalyticsResult(
          label: DateFormat('MMM dd').format(forecastDate),
          value: predicted.clamp(0, double.infinity),
          timestamp: forecastDate,
        ));
      }

      return forecast;
    } catch (e) {
      rethrow;
    }
  }

  // ==================== Helper Methods ====================

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterUsageLogs(
    QuerySnapshot<Map<String, dynamic>> docs,
    AnalyticsQuery query,
  ) {
    return docs.docs.where((doc) {
      final data = doc.data();
      
      if (query.filterByInterventions != null &&
          !query.filterByInterventions!.contains(data['interventionId'])) {
        return false;
      }
      
      if (query.filterByGrants != null &&
          !query.filterByGrants!.contains(data['grantId'])) {
        return false;
      }
      
      if (query.filterByOperators != null &&
          !query.filterByOperators!.contains(data['operatorName'])) {
        return false;
      }

      return true;
    }).toList();
  }

  static Future<dynamic> _calculateMetric(
    MetricType metric,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> logs,
    AnalyticsQuery query,
  ) async {
    switch (metric) {
      case MetricType.totalUsage:
        return logs.fold<double>(0, (sum, doc) {
          final qtyUsed = doc['qtyUsed'] as num?;
          return sum + (qtyUsed?.toDouble() ?? 0);
        });

      case MetricType.averageUsage:
        final total = logs.fold<double>(0, (sum, doc) {
          final qtyUsed = doc['qtyUsed'] as num?;
          return sum + (qtyUsed?.toDouble() ?? 0);
        });
        return logs.isEmpty ? 0 : total / logs.length;

      case MetricType.usageFrequency:
        return logs.length;

      case MetricType.velocity:
        final total = logs.fold<double>(0, (sum, doc) {
          final qtyUsed = doc['qtyUsed'] as num?;
          return sum + (qtyUsed?.toDouble() ?? 0);
        });
        final days = query.endDate.difference(query.startDate).inDays + 1;
        return days > 0 ? total / days : 0;

      case MetricType.efficiency:
        final total = logs.fold<double>(0, (sum, doc) {
          final qtyUsed = doc['qtyUsed'] as num?;
          return sum + (qtyUsed?.toDouble() ?? 0);
        });
        return (total / (logs.length + 1)) * 100;

      case MetricType.adoption:
        final uniqueItems = logs.map((doc) => doc['itemId']).toSet().length;
        final totalItems = await _db.collection('items').count().get();
        final itemCount = totalItems.count ?? 0;
        return itemCount > 0 ? (uniqueItems / itemCount) * 100 : 0;

      default:
        return 0;
    }
  }

  static Future<Map<String, dynamic>> _segmentByDimension(
    DimensionType dimension,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> logs,
    AnalyticsQuery query,
  ) async {
    final segments = <String, Map<String, dynamic>>{};

    for (final log in logs) {
      final data = log.data();
      final key = _getDimensionKey(dimension, data);
      
      if (key != null) {
        if (!segments.containsKey(key)) {
          segments[key] = {
            'total': 0.0,
            'count': 0,
            'label': key,
          };
        }
        segments[key]!['total'] += (data['qtyUsed'] as num?)?.toDouble() ?? 0;
        segments[key]!['count']++;
      }
    }

    // Sort and limit if topN specified
    final sorted = segments.entries.toList()
        ..sort((a, b) => (b.value['total'] as num).compareTo(a.value['total'] as num));

    if (query.topN != null) {
      return Map.fromEntries(sorted.take(query.topN!));
    }

    return Map.fromEntries(sorted);
  }

  static String? _getDimensionKey(DimensionType dimension, Map<String, dynamic> data) {
    switch (dimension) {
      case DimensionType.intervention:
        return data['interventionId'] as String?;
      case DimensionType.grant:
        return data['grantId'] as String?;
      case DimensionType.operator:
        return data['operatorName'] as String?;
      case DimensionType.item:
        return data['itemId'] as String?;
      case DimensionType.category:
        return data['category'] as String?;
      case DimensionType.useType:
        return data['forUseType'] as String?;
      case DimensionType.dateDay:
        final ts = data['usedAt'] as Timestamp?;
        if (ts == null) return null;
        final date = ts.toDate();
        return DateFormat('yyyy-MM-dd').format(date);
      case DimensionType.dateWeek:
        final ts = data['usedAt'] as Timestamp?;
        if (ts == null) return null;
        final date = ts.toDate();
        return 'Week ${date.difference(DateTime(date.year, 1, 1)).inDays ~/ 7 + 1}';
      case DimensionType.dateMonth:
        final ts = data['usedAt'] as Timestamp?;
        if (ts == null) return null;
        final date = ts.toDate();
        return DateFormat('yyyy-MM').format(date);
      default:
        return null;
    }
  }

  static String _formatPeriodLabel(DateTime date, Duration period) {
    if (period.inDays == 1) {
      return DateFormat('MMM dd').format(date);
    } else if (period.inDays == 7) {
      return 'Week of ${DateFormat('MMM dd').format(date)}';
    } else if (period.inDays >= 28 && period.inDays <= 31) {
      return DateFormat('MMMM yyyy').format(date);
    }
    return DateFormat('MMM dd').format(date);
  }
}
