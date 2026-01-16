import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:scout/services/advanced_analytics_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CustomAnalyticsDashboard extends StatefulWidget {
  const CustomAnalyticsDashboard({super.key});

  @override
  State<CustomAnalyticsDashboard> createState() => _CustomAnalyticsDashboardState();
}

class _CustomAnalyticsDashboardState extends State<CustomAnalyticsDashboard> {
  final _db = FirebaseFirestore.instance;

  // Date range
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();

  // Metric selection
  Set<AdvancedAnalyticsService.MetricType> _selectedMetrics = {
    AdvancedAnalyticsService.MetricType.totalUsage,
    AdvancedAnalyticsService.MetricType.usageFrequency,
    AdvancedAnalyticsService.MetricType.velocity,
  };

  // Dimension selection
  Set<AdvancedAnalyticsService.DimensionType> _selectedDimensions = {
    AdvancedAnalyticsService.DimensionType.intervention,
    AdvancedAnalyticsService.DimensionType.grant,
  };

  // Filters
  List<String> _selectedInterventions = [];
  List<String> _selectedGrants = [];
  List<String> _selectedOperators = [];
  List<String> _selectedCategories = [];

  // Lookup data
  Map<String, String> _interventions = {};
  Map<String, String> _grants = {};
  List<String> _operators = [];
  List<String> _categories = [];

  // Results
  bool _loading = false;
  Map<String, dynamic> _results = {};
  Map<String, dynamic> _efficiencyMetrics = {};

  @override
  void initState() {
    super.initState();
    _loadLookups();
  }

  Future<void> _loadLookups() async {
    try {
      // Load interventions
      final interventionsDoc = await _db.collection('config').doc('interventions').get();
      if (interventionsDoc.exists) {
        final data = interventionsDoc.data() as Map<String, dynamic>? ?? {};
        setState(() {
          _interventions = Map<String, String>.from(data);
        });
      }

      // Load grants
      final grantsDoc = await _db.collection('config').doc('grants').get();
      if (grantsDoc.exists) {
        final data = grantsDoc.data() as Map<String, dynamic>? ?? {};
        setState(() {
          _grants = Map<String, String>.from(data);
        });
      }

      // Load operators from recent usage logs
      final operatorsSnapshot = await _db
          .collection('usage_logs')
          .where('usedAt',
              isGreaterThanOrEqualTo:
                  Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 90))))
          .limit(1000)
          .get();

      final ops = <String>{};
      for (final doc in operatorsSnapshot.docs) {
        final op = doc['operatorName'] as String?;
        if (op != null && op.isNotEmpty) {
          ops.add(op);
        }
      }

      // Load categories
      final categoriesSnapshot = await _db.collection('items').get();
      final cats = <String>{};
      for (final doc in categoriesSnapshot.docs) {
        final cat = doc['category'] as String?;
        if (cat != null && cat.isNotEmpty) {
          cats.add(cat);
        }
      }

      setState(() {
        _operators = ops.toList()..sort();
        _categories = cats.toList()..sort();
      });
    } catch (e) {
      debugPrint('Error loading lookups: $e');
    }
  }

  Future<void> _runAnalysis() async {
    setState(() => _loading = true);
    try {
      final query = AdvancedAnalyticsService.AnalyticsQuery(
        startDate: _startDate,
        endDate: _endDate,
        metrics: _selectedMetrics.toList(),
        dimensions: _selectedDimensions.toList(),
        filterByInterventions: _selectedInterventions.isEmpty ? null : _selectedInterventions,
        filterByGrants: _selectedGrants.isEmpty ? null : _selectedGrants,
        filterByOperators: _selectedOperators.isEmpty ? null : _selectedOperators,
        filterByCategories: _selectedCategories.isEmpty ? null : _selectedCategories,
        topN: 10,
      );

      final results = await AdvancedAnalyticsService.getUsageAnalytics(query);
      final efficiency = await AdvancedAnalyticsService.getInventoryEfficiency(
        startDate: _startDate,
        endDate: _endDate,
      );

      setState(() {
        _results = results;
        _efficiencyMetrics = efficiency;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Advanced Analytics'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date Range Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Date Range', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ListTile(
                            title: Text(DateFormat('MMM dd, yyyy').format(_startDate)),
                            leading: const Icon(Icons.calendar_today),
                            onTap: () => _pickDate(true),
                          ),
                        ),
                        Expanded(
                          child: ListTile(
                            title: Text(DateFormat('MMM dd, yyyy').format(_endDate)),
                            leading: const Icon(Icons.calendar_today),
                            onTap: () => _pickDate(false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Quick presets
                    Wrap(
                      spacing: 8,
                      children: ['7 days', '30 days', '90 days', 'Year'].map((label) {
                        return ChoiceChip(
                          label: Text(label),
                          selected: false,
                          onSelected: (_) => _setDatePreset(label),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Metrics Selection
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Metrics', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: AdvancedAnalyticsService.MetricType.values
                          .map((metric) => FilterChip(
                                label: Text(_formatMetricName(metric)),
                                selected: _selectedMetrics.contains(metric),
                                onSelected: (selected) {
                                  setState(() {
                                    if (selected) {
                                      _selectedMetrics.add(metric);
                                    } else {
                                      _selectedMetrics.remove(metric);
                                    }
                                  });
                                },
                              ))
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Dimensions Selection
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Segment By', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: AdvancedAnalyticsService.DimensionType.values
                          .map((dimension) => FilterChip(
                                label: Text(_formatDimensionName(dimension)),
                                selected: _selectedDimensions.contains(dimension),
                                onSelected: (selected) {
                                  setState(() {
                                    if (selected) {
                                      _selectedDimensions.add(dimension);
                                    } else {
                                      _selectedDimensions.remove(dimension);
                                    }
                                  });
                                },
                              ))
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Filters Expander
            _buildFiltersCard(colorScheme),
            const SizedBox(height: 16),

            // Run Analysis Button
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _loading ? null : _runAnalysis,
                icon: const Icon(Icons.analytics),
                label: _loading ? const Text('Analyzing...') : const Text('Run Analysis'),
              ),
            ),
            const SizedBox(height: 24),

            // Results
            if (_results.isNotEmpty) ...[
              Text('Results', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              ..._buildResultsCards(colorScheme),
              const SizedBox(height: 24),
            ],

            // Efficiency Metrics
            if (_efficiencyMetrics.isNotEmpty) ...[
              Text('Inventory Efficiency', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              ..._buildEfficiencyCards(colorScheme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFiltersCard(ColorScheme colorScheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Filters', style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() {
                    _selectedInterventions.clear();
                    _selectedGrants.clear();
                    _selectedOperators.clear();
                    _selectedCategories.clear();
                  }),
                ),
              ],
            ),
            if (_selectedInterventions.isNotEmpty || _selectedGrants.isNotEmpty || _selectedOperators.isNotEmpty || _selectedCategories.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  children: [
                    ..._selectedInterventions.map((id) => Chip(
                          label: Text(_interventions[id] ?? id),
                          onDeleted: () {
                            setState(() => _selectedInterventions.remove(id));
                          },
                        )),
                    ..._selectedGrants.map((id) => Chip(
                          label: Text(_grants[id] ?? id),
                          onDeleted: () {
                            setState(() => _selectedGrants.remove(id));
                          },
                        )),
                    ..._selectedOperators.map((op) => Chip(
                          label: Text(op),
                          onDeleted: () {
                            setState(() => _selectedOperators.remove(op));
                          },
                        )),
                    ..._selectedCategories.map((cat) => Chip(
                          label: Text(cat),
                          onDeleted: () {
                            setState(() => _selectedCategories.remove(cat));
                          },
                        )),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _showMultiSelect('Interventions', _interventions, _selectedInterventions, (ids) {
                      setState(() => _selectedInterventions = ids);
                    }),
                    child: Text('Interventions${_selectedInterventions.isEmpty ? '' : ' (${_selectedInterventions.length})'}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _showMultiSelect('Grants', _grants, _selectedGrants, (ids) {
                      setState(() => _selectedGrants = ids);
                    }),
                    child: Text('Grants${_selectedGrants.isEmpty ? '' : ' (${_selectedGrants.length})'}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _showMultiSelectList('Operators', _operators, _selectedOperators, (ops) {
                      setState(() => _selectedOperators = ops);
                    }),
                    child: Text('Operators${_selectedOperators.isEmpty ? '' : ' (${_selectedOperators.length})'}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _showMultiSelectList('Categories', _categories, _selectedCategories, (cats) {
                      setState(() => _selectedCategories = cats);
                    }),
                    child: Text('Categories${_selectedCategories.isEmpty ? '' : ' (${_selectedCategories.length})'}'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildResultsCards(ColorScheme colorScheme) {
    final widgets = <Widget>[];

    for (final entry in _results.entries) {
      if (entry.key.startsWith('by_')) {
        final dimension = entry.key.replaceFirst('by_', '');
        final data = entry.value as Map<String, dynamic>? ?? {};

        widgets.add(
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'By ${_formatDimensionName(_formatDimensionFromString(dimension))}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  ...data.entries.take(10).map((d) {
                    final label = d.key.toString();
                    final value = (d.value['total'] as num?)?.toStringAsFixed(2) ?? '0';
                    final count = d.value['count'] ?? 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(label, style: Theme.of(context).textTheme.bodyMedium),
                                Text('$count uses', style: Theme.of(context).textTheme.bodySmall),
                              ],
                            ),
                          ),
                          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
          ),
        );

        widgets.add(const SizedBox(height: 16));
      } else if (entry.key != 'byInterventionType' && entry.key != 'byGrant') {
        final value = entry.value;
        final label = _formatMetricName(_formatMetricFromString(entry.key));

        widgets.add(
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    value is double ? value.toStringAsFixed(2) : value.toString(),
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        widgets.add(const SizedBox(height: 16));
      }
    }

    return widgets;
  }

  List<Widget> _buildEfficiencyCards(ColorScheme colorScheme) {
    final widgets = <Widget>[];
    final efficiency = _efficiencyMetrics as Map<String, dynamic>;

    // Sort by efficiency score
    final sorted = efficiency.entries.toList()
        ..sort((a, b) {
          final scoreA = ((a.value as Map)['efficiencyScore'] as num?)?.toDouble() ?? 0;
          final scoreB = ((b.value as Map)['efficiencyScore'] as num?)?.toDouble() ?? 0;
          return scoreB.compareTo(scoreA);
        });

    for (final entry in sorted.take(10)) {
      final itemData = entry.value as Map<String, dynamic>;
      final name = itemData['name'] as String? ?? 'Unknown';
      final score = ((itemData['efficiencyScore'] as num?)?.toDouble() ?? 0).toStringAsFixed(1);
      final status = itemData['status'] as String? ?? 'unknown';

      final statusColor = status == 'optimal'
          ? Colors.green
          : status == 'good'
              ? Colors.blue
              : Colors.orange;

      widgets.add(
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      score,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: Theme.of(context).textTheme.bodyMedium),
                      Text(
                        status.replaceAll('_', ' ').toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.trending_up, color: statusColor),
              ],
            ),
          ),
        ),
      );

      widgets.add(const SizedBox(height: 8));
    }

    return widgets;
  }

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  void _setDatePreset(String label) {
    final now = DateTime.now();
    switch (label) {
      case '7 days':
        setState(() {
          _startDate = now.subtract(const Duration(days: 7));
          _endDate = now;
        });
        break;
      case '30 days':
        setState(() {
          _startDate = now.subtract(const Duration(days: 30));
          _endDate = now;
        });
        break;
      case '90 days':
        setState(() {
          _startDate = now.subtract(const Duration(days: 90));
          _endDate = now;
        });
        break;
      case 'Year':
        setState(() {
          _startDate = DateTime(now.year, 1, 1);
          _endDate = now;
        });
        break;
    }
  }

  void _showMultiSelect(
    String title,
    Map<String, String> options,
    List<String> selected,
    Function(List<String>) onSelected,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Select $title'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: options.entries.map((entry) {
              return CheckboxListTile(
                title: Text(entry.value),
                value: selected.contains(entry.key),
                onChanged: (checked) {
                  if (checked == true) {
                    selected.add(entry.key);
                  } else {
                    selected.remove(entry.key);
                  }
                  setState(() {});
                },
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _showMultiSelectList(
    String title,
    List<String> options,
    List<String> selected,
    Function(List<String>) onSelected,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Select $title'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: options.map((option) {
              return CheckboxListTile(
                title: Text(option),
                value: selected.contains(option),
                onChanged: (checked) {
                  if (checked == true) {
                    selected.add(option);
                  } else {
                    selected.remove(option);
                  }
                  setState(() {});
                },
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  String _formatMetricName(AdvancedAnalyticsService.MetricType metric) {
    return metric.toString().split('.').last.replaceAllMapped(
          RegExp(r'([A-Z])'),
          (m) => ' ${m.group(1)}',
        ).trim();
  }

  String _formatDimensionName(AdvancedAnalyticsService.DimensionType dimension) {
    return dimension.toString().split('.').last.replaceAllMapped(
          RegExp(r'([A-Z])'),
          (m) => ' ${m.group(1)}',
        ).trim();
  }

  AdvancedAnalyticsService.MetricType _formatMetricFromString(String str) {
    return AdvancedAnalyticsService.MetricType.values.firstWhere(
      (m) => m.toString() == 'AdvancedAnalyticsService.MetricType.$str',
      orElse: () => AdvancedAnalyticsService.MetricType.totalUsage,
    );
  }

  AdvancedAnalyticsService.DimensionType _formatDimensionFromString(String str) {
    return AdvancedAnalyticsService.DimensionType.values.firstWhere(
      (d) => d.toString() == 'AdvancedAnalyticsService.DimensionType.$str',
      orElse: () => AdvancedAnalyticsService.DimensionType.intervention,
    );
  }
}
