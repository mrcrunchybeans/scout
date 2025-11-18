import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

class UsageReportPage extends StatefulWidget {
  const UsageReportPage({super.key});

  @override
  State<UsageReportPage> createState() => _UsageReportPageState();
}

class _UsageReportPageState extends State<UsageReportPage> {
  DateTime? _startDate;
  DateTime? _endDate;
  String? _selectedInterventionId;
  String? _selectedGrantId;
  bool _loading = false;

  // Analytics data
  List<Map<String, dynamic>> _usageData = [];
  Map<String, double> _interventionTotals = {};
  Map<String, double> _grantTotals = {};
  Map<String, String> _interventions = {};
  Map<String, String> _grants = {};
  List<FlSpot> _trendData = [];

  // Time period presets
  final List<String> _timePresets = ['7 days', '30 days', '90 days', 'Custom'];
  String _selectedPreset = '30 days';

  @override
  void initState() {
    super.initState();
    _setDefaultDateRange();
    _loadData();
  }

  Future<void> _loadData() async {
    await _loadFilters();
    await _generateReport();
  }

  void _setDefaultDateRange() {
    final now = DateTime.now();
    _startDate = now.subtract(const Duration(days: 30));
    _endDate = now;
  }

  Future<void> _loadFilters() async {
    final interventionsMap = await _loadLookupMap(collectionName: 'interventions', lookupDocId: 'interventions');
    final grantsMap = await _loadLookupMap(collectionName: 'grants', lookupDocId: 'grants');

    if (mounted) {
      setState(() {
        _interventions = interventionsMap;
        _grants = grantsMap;
      });
    }
  }

  /// Load a lookup map in a robust way:
  /// - Prefer a document at `lookups/<lookupDocId>` that contains a map of id->name.
  /// - Otherwise fall back to querying the collection `<collectionName>` for documents
  ///   and using each doc's `name` field (or id if missing).
  Future<Map<String, String>> _loadLookupMap({required String collectionName, required String lookupDocId}) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('lookups').doc(lookupDocId).get();
      if (doc.exists) {
        final data = doc.data();
        if (data != null) {
          // Normalize values to strings
          final out = <String, String>{};
          data.forEach((k, v) {
            if (v != null) out[k] = v.toString();
          });
          if (out.isNotEmpty) return out;
        }
      }

      // Fallback: read collection documents
      final snap = await FirebaseFirestore.instance.collection(collectionName).get();
      final map = <String, String>{};
      for (final d in snap.docs) {
        final data = d.data();
        final name = (data['name'] ?? data['label'] ?? d.id) as String;
        map[d.id] = name;
      }
      return map;
    } catch (e) {
      return {};
    }
  }

  void _onPresetChanged(String preset) {
    setState(() {
      _selectedPreset = preset;
      final now = DateTime.now();

      switch (preset) {
        case '7 days':
          _startDate = now.subtract(const Duration(days: 7));
          _endDate = now;
          break;
        case '30 days':
          _startDate = now.subtract(const Duration(days: 30));
          _endDate = now;
          break;
        case '90 days':
          _startDate = now.subtract(const Duration(days: 90));
          _endDate = now;
          break;
        case 'Custom':
          // Keep current dates for custom selection
          break;
      }
    });
    _generateReport();
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
        _selectedPreset = 'Custom';
      });
      _generateReport();
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _endDate = picked;
        _selectedPreset = 'Custom';
      });
      _generateReport();
    }
  }

  Future<void> _generateReport() async {
    if (_startDate == null || _endDate == null) return;

    setState(() => _loading = true);
    try {
      final start = Timestamp.fromDate(_startDate!);
      final end = Timestamp.fromDate(_endDate!.add(const Duration(days: 1)));

      Query query = FirebaseFirestore.instance
          .collection('usage_logs')
          .where('usedAt', isGreaterThanOrEqualTo: start)
          .where('usedAt', isLessThan: end);

      // Apply optional filters
      if (_selectedInterventionId != null && _selectedInterventionId!.isNotEmpty) {
        query = query.where('interventionId', isEqualTo: _selectedInterventionId);
      }
      if (_selectedGrantId != null && _selectedGrantId!.isNotEmpty) {
        query = query.where('grantId', isEqualTo: _selectedGrantId);
      }

      final usages = await query.get();

      // Process data for analytics
      final interventionTotals = <String, double>{};
      final grantTotals = <String, double>{};
      final dailyUsage = <DateTime, double>{};

      for (final doc in usages.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final interventionId = data['interventionId'] as String?;
        final grantId = data['grantId'] as String?;
        final qty = (data['qtyUsed'] as num?)?.toDouble() ?? 0.0;
        final usedAt = (data['usedAt'] as Timestamp?)?.toDate();

        // Aggregate by intervention
        if (interventionId != null) {
          interventionTotals[interventionId] = (interventionTotals[interventionId] ?? 0) + qty;
        }

        // Aggregate by grant
        if (grantId != null) {
          grantTotals[grantId] = (grantTotals[grantId] ?? 0) + qty;
        }

        // Daily usage for trend chart
        if (usedAt != null) {
          final day = DateTime(usedAt.year, usedAt.month, usedAt.day);
          dailyUsage[day] = (dailyUsage[day] ?? 0) + qty;
        }
      }

      // Create trend data points
      final sortedDays = dailyUsage.keys.toList()..sort();
      final trendData = <FlSpot>[];
      for (int i = 0; i < sortedDays.length; i++) {
        trendData.add(FlSpot(i.toDouble(), dailyUsage[sortedDays[i]] ?? 0));
      }

      // Use previously-loaded lookup maps (fall back to unknown labels)
      final interventionMap = _interventions;
      final grantMap = _grants;

      String labelFor(Map<String, String> map, String id, String fallback) {
        if (map.containsKey(id) && map[id]!.trim().isNotEmpty) return map[id]!;
        return fallback;
      }

      // Create usage data with names
      final usageData = [
        ...interventionTotals.entries.map((entry) => {
              'type': 'intervention',
              'id': entry.key,
              'name': labelFor(interventionMap, entry.key, 'Unknown Intervention'),
              'total': entry.value,
            }),
        ...grantTotals.entries.map((entry) => {
              'type': 'grant',
              'id': entry.key,
              'name': labelFor(grantMap, entry.key, 'Unknown Grant'),
              'total': entry.value,
            }),
      ]..sort((a, b) => (b['total'] as double).compareTo(a['total'] as double));

      setState(() {
        _usageData = usageData;
        _interventionTotals = interventionTotals;
        _grantTotals = grantTotals;
        _trendData = trendData;
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Usage Analytics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _exportCsv,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Time Period Selector
                  _buildTimeSelector(),

                  const SizedBox(height: 24),

                  // Summary Cards
                  _buildSummaryCards(),

                  const SizedBox(height: 32),

                  // Usage Trend Chart
                  _buildTrendChart(),

                  const SizedBox(height: 32),

                  // Breakdown Charts
                  _buildBreakdownCharts(),

                  const SizedBox(height: 32),

                  // Detailed Data Table
                  _buildDataTable(),
                ],
              ),
            ),
    );
  }

  Widget _buildTimeSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Time Period',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedPreset,
                    decoration: const InputDecoration(
                      labelText: 'Quick Select',
                      border: OutlineInputBorder(),
                    ),
                    items: _timePresets.map((preset) => DropdownMenuItem(
                      value: preset,
                      child: Text(preset),
                    )).toList(),
                    onChanged: (value) => value != null ? _onPresetChanged(value) : null,
                  ),
                ),
                if (_selectedPreset == 'Custom') ...[
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: _pickStartDate,
                      icon: const Icon(Icons.calendar_today),
                      label: Text(_startDate != null
                          ? DateFormat('MMM dd').format(_startDate!)
                          : 'Start Date'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: _pickEndDate,
                      icon: const Icon(Icons.calendar_today),
                      label: Text(_endDate != null
                          ? DateFormat('MMM dd').format(_endDate!)
                          : 'End Date'),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedInterventionId,
                    decoration: const InputDecoration(
                      labelText: 'Filter by Intervention',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('All Interventions'),
                      ),
                      ..._interventions.entries.map((entry) => DropdownMenuItem<String>(
                        value: entry.key,
                        child: Text(entry.value),
                      )),
                    ],
                    onChanged: (value) {
                      setState(() => _selectedInterventionId = value);
                      _generateReport();
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedGrantId,
                    decoration: const InputDecoration(
                      labelText: 'Filter by Grant',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('All Grants'),
                      ),
                      ..._grants.entries.map((entry) => DropdownMenuItem<String>(
                        value: entry.key,
                        child: Text(entry.value),
                      )),
                    ],
                    onChanged: (value) {
                      setState(() => _selectedGrantId = value);
                      _generateReport();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    // Use intervention totals to avoid double-counting (each usage has both intervention and grant)
    final totalUsage = _interventionTotals.values.fold<double>(0, (sum, value) => sum + value);
    final interventionCount = _interventionTotals.length;
    final grantCount = _grantTotals.length;
    final avgDaily = totalUsage / (_endDate!.difference(_startDate!).inDays + 1);

    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            title: 'Total Usage',
            value: totalUsage.toStringAsFixed(1),
            subtitle: 'items used',
            icon: Icons.inventory_2,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryCard(
            title: 'Daily Average',
            value: avgDaily.toStringAsFixed(1),
            subtitle: 'items/day',
            icon: Icons.trending_up,
            color: Theme.of(context).colorScheme.secondary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryCard(
            title: 'Active Categories',
            value: '$interventionCount',
            subtitle: 'interventions',
            icon: Icons.category,
            color: Theme.of(context).colorScheme.tertiary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryCard(
            title: 'Grants',
            value: '$grantCount',
            subtitle: 'funded programs',
            icon: Icons.account_balance_wallet,
            color: Theme.of(context).colorScheme.primaryContainer,
          ),
        ),
      ],
    );
  }

  Widget _buildTrendChart() {
    if (_trendData.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: Text('No usage data for selected period')),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Usage Trend',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() >= _trendData.length) return const Text('');
                          // This is simplified - in a real app you'd map to actual dates
                          return Text('${value.toInt() + 1}');
                        },
                      ),
                    ),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: true),
                  lineBarsData: [
                    LineChartBarData(
                      spots: _trendData,
                      isCurved: true,
                      color: Theme.of(context).colorScheme.primary,
                      barWidth: 3,
                      belowBarData: BarAreaData(
                        show: true,
                        color: Theme.of(context).colorScheme.primary.withValues(alpha:0.1),
                      ),
                      dotData: FlDotData(show: false),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBreakdownCharts() {
    return Row(
      children: [
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'By Intervention',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 200,
                    child: _interventionTotals.isEmpty
                        ? const Center(child: Text('No data'))
                        : PieChart(
                            PieChartData(
                              sections: _interventionTotals.entries.map((entry) {
                                final interventionName = _interventions[entry.key] ?? 'Unknown';
                                return PieChartSectionData(
                                  value: entry.value,
                                  title: '${entry.value.toStringAsFixed(1)}\n${interventionName.substring(0, min(10, interventionName.length))}',
                                  color: _getColorForIndex(_interventionTotals.keys.toList().indexOf(entry.key)),
                                  radius: 60,
                                  titleStyle: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'By Grant',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 200,
                    child: _grantTotals.isEmpty
                        ? const Center(child: Text('No data'))
                        : PieChart(
                            PieChartData(
                              sections: _grantTotals.entries.map((entry) {
                                final grantName = _grants[entry.key] ?? 'Unknown';
                                return PieChartSectionData(
                                  value: entry.value,
                                  title: '${entry.value.toStringAsFixed(1)}\n${grantName.substring(0, min(10, grantName.length))}',
                                  color: _getColorForIndex(_grantTotals.keys.toList().indexOf(entry.key)),
                                  radius: 60,
                                  titleStyle: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDataTable() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Detailed Breakdown',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            _usageData.isEmpty
                ? const Center(child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('No usage data for selected period'),
                  ))
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _usageData.length,
                    itemBuilder: (context, index) {
                      final item = _usageData[index];
                      final isIntervention = item['type'] == 'intervention';

                      // Calculate percentage within the same category
                      final categoryTotal = _usageData
                          .where((i) => i['type'] == item['type'])
                          .fold<double>(0, (sum, i) => sum + (i['total'] as double));
                      final percentage = categoryTotal > 0 
                          ? ((item['total'] as double) / categoryTotal * 100)
                          : 0.0;

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isIntervention
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.secondary,
                          child: Icon(
                            isIntervention ? Icons.healing : Icons.account_balance_wallet,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        title: Text(item['name'] as String),
                        subtitle: Text('${item['type']} • ${item['total'].toStringAsFixed(1)} items used'),
                        trailing: Text(
                          '${percentage.toStringAsFixed(1)}%',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }

  Color _getColorForIndex(int index) {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.red,
      Colors.purple,
      Colors.teal,
      Colors.pink,
      Colors.indigo,
      Colors.amber,
      Colors.cyan,
    ];
    return colors[index % colors.length];
  }

  void _exportCsv() {
    final buffer = StringBuffer();
    buffer.writeln('Type,Name,Total Usage,Percentage');

    final totalUsage = _usageData.fold<double>(0, (currentSum, item) => currentSum + (item['total'] as double));

    for (final item in _usageData) {
      final type = item['type'];
      final name = item['name'];
      final total = item['total'];
      final percentage = (total / totalUsage * 100).toStringAsFixed(1);

      buffer.writeln('$type,"$name",$total,$percentage%');
    }

    final csvData = buffer.toString();

    showDialog(
      context: context,
      builder: (_) => Theme(
        data: Theme.of(context),
        child: AlertDialog(
          title: const Text('CSV Export'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Copy the CSV data below:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SelectableText(
                    csvData,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const Spacer(),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
