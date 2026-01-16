# Advanced Analytics System

Scout now includes a comprehensive, customizable analytics engine that provides deep insights into inventory usage patterns, efficiency metrics, and predictive analytics.

## Features

### 1. **Advanced Analytics Service** (`advanced_analytics_service.dart`)
Deep analytics engine with multiple metric types and custom segmentation.

#### Metrics Available:
- **Total Usage** - Total quantity used in period
- **Average Usage** - Average quantity per transaction
- **Usage Frequency** - Number of transactions
- **Cost Per Use** - Efficiency metric
- **Velocity** - Usage per day
- **Waste** - Amount wasted
- **Efficiency** - Usage vs waste ratio
- **Adoption** - Percentage of items in use
- **Trends** - Change over time

#### Dimensions for Segmentation:
- By Intervention
- By Grant
- By Operator/Staff Member
- By Item
- By Category
- By Storage Location
- By Use Type (Staff/Patient)
- By Date (Daily/Weekly/Monthly)

#### Core Methods:

```dart
// Get comprehensive usage analytics with multiple metrics
Future<Map<String, dynamic>> getUsageAnalytics(AnalyticsQuery query)

// Get trend analysis over multiple periods
Future<List<AnalyticsResult>> getTrendAnalysis({
  required String itemId,
  required int forecastDays,
  required int historicalDays,
})

// Get user activity breakdown with personal statistics
Future<Map<String, dynamic>> getUserActivityProfile(String operatorName)

// Get inventory efficiency metrics
Future<Map<String, dynamic>> getInventoryEfficiency({
  required DateTime startDate,
  required DateTime endDate,
})

// Get predictive analytics (simple forecasting)
Future<List<AnalyticsResult>> getPredictedUsage({
  required String itemId,
  required int forecastDays,
  required int historicalDays,
})
```

### 2. **Custom Analytics Dashboard** (`custom_analytics_dashboard.dart`)
Interactive UI for customizable analytics queries with real-time results.

**Features:**
- Date range picker with quick presets (7 days, 30 days, 90 days, Year)
- Multi-select metric and dimension filters
- Advanced filter panel for:
  - Interventions
  - Grants
  - Operators
  - Categories
- Real-time analytics visualization
- Inventory efficiency scoring (0-100)
- Status indicators (Optimal/Good/Needs Attention)

**Usage:**
```dart
Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => const CustomAnalyticsDashboard()),
);
```

### 3. **Analytics Export Service** (`analytics_export_service.dart`)
Export analytics in multiple formats for external analysis.

#### Export Formats:

```dart
// CSV export with custom columns
Future<String> exportToCsv({
  required DateTime startDate,
  required DateTime endDate,
  required List<String> columns,
  String? filterByIntervention,
  String? filterByGrant,
})

// JSON export with nested structure
Future<String> exportToJson({
  required DateTime startDate,
  required DateTime endDate,
  required bool includeItemDetails,
  required bool includeOperatorDetails,
  String? filterByIntervention,
  String? filterByGrant,
})

// TSV export (Tab-separated for Excel)
Future<String> exportToTsv({
  required DateTime startDate,
  required DateTime endDate,
  required List<String> columns,
  String? filterByIntervention,
  String? filterByGrant,
})

// Custom aggregation report
Future<String> exportCustomReport({
  required DateTime startDate,
  required DateTime endDate,
  required Map<String, String> aggregations,
  String? filterByIntervention,
  String? filterByGrant,
})

// Period comparison report
Future<String> generateComparisonReport({
  required DateTime period1Start,
  required DateTime period1End,
  required DateTime period2Start,
  required DateTime period2End,
})
```

**CSV Columns Available:**
- `date` - Transaction date
- `intervention` - Intervention ID
- `grant` - Grant ID
- `operator` - Staff member name
- `total_usage` - Sum of quantities
- `count` - Number of transactions
- `unique_items` - Count of unique items
- `unique_operators` - Count of unique operators

### 4. **Cloud Functions** (Firebase)
Backend functions for performance optimization and pre-computation.

#### `precomputeAnalytics` (Daily, 3 AM)
Runs daily to pre-compute and cache analytics metrics:
- Aggregates usage by intervention, grant, operator
- Identifies top items
- Stores in `analytics` collection for fast retrieval

#### `getPrecomputedAnalytics` (Callable)
Retrieves pre-computed analytics for a date range:
```typescript
const result = await functions.httpsCallable('getPrecomputedAnalytics')({
  startDate: '2024-01-01',
  endDate: '2024-01-31'
});
```

#### `getOperatorMetrics` (Callable)
Gets efficiency metrics for a specific operator:
```typescript
const result = await functions.httpsCallable('getOperatorMetrics')({
  operatorName: 'John Doe',
  daysBack: 30
});
```

## Usage Examples

### Example 1: Basic Analytics Query

```dart
import 'package:scout/services/advanced_analytics_service.dart';

// Create a custom query
final query = AdvancedAnalyticsService.AnalyticsQuery(
  startDate: DateTime.now().subtract(Duration(days: 30)),
  endDate: DateTime.now(),
  metrics: [
    AdvancedAnalyticsService.MetricType.totalUsage,
    AdvancedAnalyticsService.MetricType.averageUsage,
  ],
  dimensions: [
    AdvancedAnalyticsService.DimensionType.intervention,
    AdvancedAnalyticsService.DimensionType.grant,
  ],
  filterByGrants: ['grant-001', 'grant-002'],
  topN: 10,
);

// Run analysis
final results = await AdvancedAnalyticsService.getUsageAnalytics(query);
print('Total Usage: ${results['totalUsage']}');
```

### Example 2: Trend Analysis

```dart
// Analyze trends over time
final trends = await AdvancedAnalyticsService.getTrendAnalysis(
  startDate: DateTime.now().subtract(Duration(days: 90)),
  endDate: DateTime.now(),
  metric: 'totalUsage',
  period: Duration(days: 7), // Weekly
  filterByIntervention: 'intervention-001',
);

// Each result includes trend percentage
for (final point in trends) {
  print('${point.label}: ${point.value} (${point.trend}% vs previous)');
}
```

### Example 3: User Activity Profile

```dart
// Get individual operator stats
final profile = await AdvancedAnalyticsService.getUserActivityProfile('John Doe');

print('Total Usage: ${profile['totalUsage']}');
print('Unique Items: ${profile['uniqueItems']}');
print('Last Used: ${profile['lastUsed']}');
print('Actions: ${profile['actionsPerformed']}');
```

### Example 4: Export Analysis

```dart
import 'package:scout/services/analytics_export_service.dart';

// Export to CSV
final csv = await AnalyticsExportService.exportToCsv(
  startDate: DateTime(2024, 1, 1),
  endDate: DateTime(2024, 1, 31),
  columns: ['date', 'intervention', 'total_usage', 'count'],
);

// Export to JSON
final json = await AnalyticsExportService.exportToJson(
  startDate: DateTime(2024, 1, 1),
  endDate: DateTime(2024, 1, 31),
  includeItemDetails: true,
  includeOperatorDetails: true,
);

// Compare two periods
final comparison = await AnalyticsExportService.generateComparisonReport(
  period1Start: DateTime(2024, 1, 1),
  period1End: DateTime(2024, 1, 31),
  period2Start: DateTime(2024, 2, 1),
  period2End: DateTime(2024, 2, 28),
);
```

## Inventory Efficiency Scoring

The system calculates an efficiency score (0-100) for each item based on:

- **Turnover Rate**: How quickly inventory is used
- **Overstock Penalty**: Too much inventory on hand
- **Velocity**: Usage per day

Status Levels:
- **Optimal (70+)**: Well-managed inventory
- **Good (40-69)**: Acceptable performance
- **Needs Attention (<40)**: Review stocking levels

## Performance Optimization

1. **Pre-computed Caching**: Daily analytics are pre-computed and cached for faster queries
2. **Batching**: Large queries are batched to prevent Firestore limits
3. **Index Optimization**: Efficient queries with proper composite indexes
4. **Lazy Loading**: Dashboard loads data progressively

## Database Schema

### Analytics Collection
Stores pre-computed daily analytics:
```
analytics/
  ├── daily_2024-01-15/
  │   ├── date: "2024-01-15"
  │   ├── totalUsage: 125.5
  │   ├── usageCount: 23
  │   ├── byIntervention: {...}
  │   ├── byGrant: {...}
  │   └── topItems: [...]
```

## Future Enhancements

1. **Machine Learning Predictions**: More sophisticated forecasting models
2. **Anomaly Detection**: Alert on unusual usage patterns
3. **Scheduled Reports**: Email reports to stakeholders
4. **Real-time Dashboards**: Live updating metrics
5. **Custom Metrics**: User-defined aggregations
6. **Advanced Visualizations**: More chart types and interactive features

## Troubleshooting

**Issue**: Analytics query returns empty results
- **Solution**: Check date range and filters, ensure data exists in period

**Issue**: Pre-computed analytics not updating
- **Solution**: Verify Cloud Function `precomputeAnalytics` is deployed and running

**Issue**: Export file is too large
- **Solution**: Narrow date range or add more specific filters

## Configuration

No additional configuration needed. The service uses existing Firestore collections:
- `usage_logs`
- `audit_logs`
- `items`
- `config` (for interventions, grants)

The Cloud Functions run automatically on schedule (3 AM daily).
