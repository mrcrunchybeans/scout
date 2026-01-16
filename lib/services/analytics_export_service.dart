import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Advanced export utilities for analytics data
class AnalyticsExportService {
  static final _db = FirebaseFirestore.instance;

  /// Export analytics to CSV with custom formatting
  static Future<String> exportToCsv({
    required DateTime startDate,
    required DateTime endDate,
    required List<String> columns, // e.g., ['date', 'intervention', 'total_usage', 'count']
    String? filterByIntervention,
    String? filterByGrant,
  }) async {
    final buffer = StringBuffer();

    // Write header
    buffer.writeln(columns.map(_escapeCsv).join(','));

    try {
      var query = _db
          .collection('usage_logs')
          .where('usedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('usedAt', isLessThan: Timestamp.fromDate(endDate.add(const Duration(days: 1))));

      if (filterByIntervention != null) {
        query = query.where('interventionId', isEqualTo: filterByIntervention);
      }

      if (filterByGrant != null) {
        query = query.where('grantId', isEqualTo: filterByGrant);
      }

      final snapshot = await query.get();

      // Aggregate data by requested dimensions
      final Map<String, Map<String, dynamic>> aggregated = {};

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final key = _buildAggregationKey(columns, data);

        if (!aggregated.containsKey(key)) {
          aggregated[key] = {
            'count': 0,
            'total_usage': 0.0,
            'items': <String>{},
            'operators': <String>{},
          };
        }

        aggregated[key]!['count']++;
        aggregated[key]!['total_usage'] += (data['qtyUsed'] as num?)?.toDouble() ?? 0;
        if (data['itemId'] != null) aggregated[key]!['items'].add(data['itemId']);
        if (data['operatorName'] != null) aggregated[key]!['operators'].add(data['operatorName']);
      }

      // Write rows
      for (final entry in aggregated.entries) {
        final values = <String>[];
        for (final col in columns) {
          values.add(_formatCsvValue(col, entry.value));
        }
        buffer.writeln(values.map(_escapeCsv).join(','));
      }

      return buffer.toString();
    } catch (e) {
      rethrow;
    }
  }

  /// Export analytics to JSON with nested structure
  static Future<String> exportToJson({
    required DateTime startDate,
    required DateTime endDate,
    required bool includeItemDetails,
    required bool includeOperatorDetails,
    String? filterByIntervention,
    String? filterByGrant,
  }) async {
    try {
      var query = _db
          .collection('usage_logs')
          .where('usedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('usedAt', isLessThan: Timestamp.fromDate(endDate.add(const Duration(days: 1))));

      if (filterByIntervention != null) {
        query = query.where('interventionId', isEqualTo: filterByIntervention);
      }

      if (filterByGrant != null) {
        query = query.where('grantId', isEqualTo: filterByGrant);
      }

      final snapshot = await query.get();

      final data = {
        'exportDate': DateTime.now().toIso8601String(),
        'startDate': startDate.toIso8601String(),
        'endDate': endDate.toIso8601String(),
        'recordCount': snapshot.docs.length,
        'summary': await _buildSummary(snapshot.docs),
        'records': snapshot.docs
            .map((doc) => _prepareJsonRecord(doc, includeItemDetails, includeOperatorDetails))
            .toList(),
      };

      return jsonEncode(data);
    } catch (e) {
      rethrow;
    }
  }

  /// Export analytics in TSV format (tab-separated for Excel)
  static Future<String> exportToTsv({
    required DateTime startDate,
    required DateTime endDate,
    required List<String> columns,
    String? filterByIntervention,
    String? filterByGrant,
  }) async {
    final csv = await exportToCsv(
      startDate: startDate,
      endDate: endDate,
      columns: columns,
      filterByIntervention: filterByIntervention,
      filterByGrant: filterByGrant,
    );

    // Replace commas with tabs
    return csv.replaceAll(',', '\t');
  }

  /// Export custom analytics report with aggregations
  static Future<String> exportCustomReport({
    required DateTime startDate,
    required DateTime endDate,
    required Map<String, String> aggregations, // 'intervention' -> 'groupBy', 'usage' -> 'sum'
    String? filterByIntervention,
    String? filterByGrant,
  }) async {
    try {
      var query = _db
          .collection('usage_logs')
          .where('usedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('usedAt', isLessThan: Timestamp.fromDate(endDate.add(const Duration(days: 1))));

      if (filterByIntervention != null) {
        query = query.where('interventionId', isEqualTo: filterByIntervention);
      }

      if (filterByGrant != null) {
        query = query.where('grantId', isEqualTo: filterByGrant);
      }

      final snapshot = await query.get();

      // Build report structure
      final Map<String, Map<String, dynamic>> report = {};

      for (final doc in snapshot.docs) {
        final data = doc.data();

        // Get grouping key from first 'groupBy' field
        String? groupKey;
        for (final entry in aggregations.entries) {
          if (entry.value == 'groupBy') {
            groupKey = _getFieldValue(data, entry.key) as String?;
            break;
          }
        }

        groupKey = groupKey ?? 'other';

        if (!report.containsKey(groupKey)) {
          report[groupKey] = {};
          for (final col in aggregations.keys) {
            report[groupKey]![col] = aggregations[col] == 'sum' ? 0.0 : 0;
          }
        }

        // Apply aggregations
        for (final entry in aggregations.entries) {
          switch (entry.value) {
            case 'sum':
              final field = _getFieldValue(data, entry.key) as num?;
              report[groupKey]![entry.key] += field?.toDouble() ?? 0;
              break;
            case 'count':
              report[groupKey]![entry.key]++;
              break;
            case 'avg':
              if (!report[groupKey]!.containsKey('${entry.key}_sum')) {
                report[groupKey]!['${entry.key}_sum'] = 0.0;
                report[groupKey]!['${entry.key}_count'] = 0;
              }
              final field = _getFieldValue(data, entry.key) as num?;
              report[groupKey]!['${entry.key}_sum'] += field?.toDouble() ?? 0;
              report[groupKey]!['${entry.key}_count']++;
              break;
          }
        }
      }

      // Calculate averages
      for (final group in report.values) {
        for (final entry in aggregations.entries) {
          if (entry.value == 'avg' && group.containsKey('${entry.key}_sum')) {
            final sum = group['${entry.key}_sum'] as double;
            final count = group['${entry.key}_count'] as int;
            group[entry.key] = count > 0 ? sum / count : 0;
            group.remove('${entry.key}_sum');
            group.remove('${entry.key}_count');
          }
        }
      }

      return jsonEncode(report);
    } catch (e) {
      rethrow;
    }
  }

  /// Generate a comparison report between two periods
  static Future<String> generateComparisonReport({
    required DateTime period1Start,
    required DateTime period1End,
    required DateTime period2Start,
    required DateTime period2End,
  }) async {
    try {
      // Fetch data for both periods
      final query1 = _db
          .collection('usage_logs')
          .where('usedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(period1Start))
          .where('usedAt', isLessThan: Timestamp.fromDate(period1End.add(const Duration(days: 1))));

      final query2 = _db
          .collection('usage_logs')
          .where('usedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(period2Start))
          .where('usedAt', isLessThan: Timestamp.fromDate(period2End.add(const Duration(days: 1))));

      final snapshot1 = await query1.get();
      final snapshot2 = await query2.get();

      // Aggregate metrics for both periods
      final metrics1 = _aggregateMetrics(snapshot1.docs);
      final metrics2 = _aggregateMetrics(snapshot2.docs);

      // Calculate comparisons
      final comparison = {
        'period1': {
          'startDate': period1Start.toIso8601String(),
          'endDate': period1End.toIso8601String(),
          'metrics': metrics1,
        },
        'period2': {
          'startDate': period2Start.toIso8601String(),
          'endDate': period2End.toIso8601String(),
          'metrics': metrics2,
        },
        'comparison': {
          'usageChange': _calculatePercentChange(
            metrics1['totalUsage'] as double,
            metrics2['totalUsage'] as double,
          ),
          'usageCountChange': _calculatePercentChange(
            (metrics1['usageCount'] as int).toDouble(),
            (metrics2['usageCount'] as int).toDouble(),
          ),
          'interventionChanges': _compareInterventions(
            metrics1['byIntervention'] as Map<String, dynamic>,
            metrics2['byIntervention'] as Map<String, dynamic>,
          ),
        },
      };

      return jsonEncode(comparison);
    } catch (e) {
      rethrow;
    }
  }

  // ==================== Helpers ====================

  static String _escapeCsv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  static String _formatCsvValue(String column, Map<String, dynamic> data) {
    switch (column) {
      case 'date':
        return data['date'] ?? '';
      case 'intervention':
        return data['intervention'] ?? '';
      case 'grant':
        return data['grant'] ?? '';
      case 'operator':
        return data['operator'] ?? '';
      case 'total_usage':
        return (data['total_usage'] as double?)?.toStringAsFixed(2) ?? '0';
      case 'count':
        return (data['count'] as int?)?.toString() ?? '0';
      case 'unique_items':
        return (data['items'] as Set?)?.length.toString() ?? '0';
      case 'unique_operators':
        return (data['operators'] as Set?)?.length.toString() ?? '0';
      default:
        return '';
    }
  }

  static String _buildAggregationKey(List<String> columns, Map<String, dynamic> data) {
    final parts = <String>[];
    for (final col in columns) {
      switch (col) {
        case 'date':
          final ts = data['usedAt'] as Timestamp?;
          if (ts != null) {
            parts.add(DateFormat('yyyy-MM-dd').format(ts.toDate()));
          }
          break;
        case 'intervention':
          parts.add(data['interventionId'] ?? 'unknown');
          break;
        case 'grant':
          parts.add(data['grantId'] ?? 'unknown');
          break;
        case 'operator':
          parts.add(data['operatorName'] ?? 'unknown');
          break;
      }
    }
    return parts.join('|');
  }

  static Future<Map<String, dynamic>> _buildSummary(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    double totalUsage = 0;
    final interventions = <String>{};
    final grants = <String>{};
    final operators = <String>{};

    for (final doc in docs) {
      final data = doc.data();
      totalUsage += (data['qtyUsed'] as num?)?.toDouble() ?? 0;
      if (data['interventionId'] != null) interventions.add(data['interventionId']);
      if (data['grantId'] != null) grants.add(data['grantId']);
      if (data['operatorName'] != null) operators.add(data['operatorName']);
    }

    return {
      'totalRecords': docs.length,
      'totalUsage': totalUsage,
      'uniqueInterventions': interventions.length,
      'uniqueGrants': grants.length,
      'uniqueOperators': operators.length,
    };
  }

  static Map<String, dynamic> _prepareJsonRecord(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    bool includeItemDetails,
    bool includeOperatorDetails,
  ) {
    final data = doc.data();
    final record = {
      'id': doc.id,
      'itemId': data['itemId'],
      'qtyUsed': data['qtyUsed'],
      'unit': data['unit'],
      'usedAt': (data['usedAt'] as Timestamp?)?.toDate().toIso8601String(),
      'interventionId': data['interventionId'],
      'grantId': data['grantId'],
      'notes': data['notes'],
    };

    if (includeItemDetails) {
      record['itemName'] = data['itemName'];
      record['lotId'] = data['lotId'];
    }

    if (includeOperatorDetails) {
      record['operatorName'] = data['operatorName'];
      record['createdBy'] = data['createdBy'];
    }

    return record;
  }

  static dynamic _getFieldValue(Map<String, dynamic> data, String field) {
    switch (field) {
      case 'qtyUsed':
        return data['qtyUsed'];
      case 'count':
        return 1;
      case 'intervention':
        return data['interventionId'];
      case 'grant':
        return data['grantId'];
      default:
        return null;
    }
  }

  static Map<String, dynamic> _aggregateMetrics(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    double totalUsage = 0;
    final byIntervention = <String, Map<String, dynamic>>{};
    final byGrant = <String, Map<String, dynamic>>{};

    for (final doc in docs) {
      final data = doc.data();
      final qty = (data['qtyUsed'] as num?)?.toDouble() ?? 0;
      totalUsage += qty;

      final intId = data['interventionId'] as String? ?? 'unknown';
      byIntervention[intId] = byIntervention[intId] ?? {'total': 0.0};
      byIntervention[intId]!['total'] = (byIntervention[intId]!['total'] as num) + qty;

      final grantId = data['grantId'] as String? ?? 'unknown';
      byGrant[grantId] = byGrant[grantId] ?? {'total': 0.0};
      byGrant[grantId]!['total'] = (byGrant[grantId]!['total'] as num) + qty;
    }

    return {
      'totalUsage': totalUsage,
      'usageCount': docs.length,
      'byIntervention': byIntervention,
      'byGrant': byGrant,
    };
  }

  static double _calculatePercentChange(double before, double after) {
    if (before == 0) return after > 0 ? 100 : 0;
    return ((after - before) / before) * 100;
  }

  static Map<String, dynamic> _compareInterventions(
    Map<String, dynamic> interventions1,
    Map<String, dynamic> interventions2,
  ) {
    final comparison = <String, dynamic>{};
    final allIntervention = <String>{...interventions1.keys, ...interventions2.keys};

    for (final id in allIntervention) {
      final val1 = ((interventions1[id] as Map?)? ['total'] as num?)?.toDouble() ?? 0;
      final val2 = ((interventions2[id] as Map?)? ['total'] as num?)?.toDouble() ?? 0;
      comparison[id] = {
        'period1': val1,
        'period2': val2,
        'change': _calculatePercentChange(val1, val2),
      };
    }

    return comparison;
  }
}
