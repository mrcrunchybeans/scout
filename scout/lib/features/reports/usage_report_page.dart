import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

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
  List<Map<String, dynamic>> _report = [];
  Map<String, String> _interventions = {};
  Map<String, String> _grants = {};

  @override
  void initState() {
    super.initState();
    // Default to last 30 days
    final now = DateTime.now();
    _startDate = now.subtract(const Duration(days: 30));
    _endDate = now;
    _loadFilters();
    _generateReport();
  }

  Future<void> _loadFilters() async {
    final interventionsDoc = await FirebaseFirestore.instance.collection('lookups').doc('interventions').get();
    final grantsDoc = await FirebaseFirestore.instance.collection('lookups').doc('grants').get();

    if (mounted) {
      setState(() {
        _interventions = Map<String, String>.from(interventionsDoc.data() ?? {});
        _grants = Map<String, String>.from(grantsDoc.data() ?? {});
      });
    }
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _startDate = picked);
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
      setState(() => _endDate = picked);
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

      // Group by interventionId, then grantId
      final grouped = <String, Map<String, dynamic>>{};
      for (final doc in usages.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final interventionId = data['interventionId'] as String?;
        final grantId = data['grantId'] as String?;
        final qty = (data['qtyUsed'] as num?) ?? 0;
        final itemId = data['itemId'] as String?;
        final key = '$interventionId|$grantId';
        if (!grouped.containsKey(key)) {
          grouped[key] = {
            'interventionId': interventionId,
            'grantId': grantId,
            'totalQty': 0.0,
            'lineCount': 0,
            'itemIds': <String>{},
          };
        }
        grouped[key]!['totalQty'] += qty;
        grouped[key]!['lineCount'] += 1;
        if (itemId != null) (grouped[key]!['itemIds'] as Set<String>).add(itemId);
      }

      // Fetch names
      final interventions = await FirebaseFirestore.instance.collection('lookups').doc('interventions').get();
      final grants = await FirebaseFirestore.instance.collection('lookups').doc('grants').get();
      final interventionMap = interventions.data() ?? {};
      final grantMap = grants.data() ?? {};

      final report = grouped.values.map((g) {
        final interventionName = interventionMap[g['interventionId']] ?? 'Unknown';
        final grantName = grantMap[g['grantId']] ?? 'Unknown';
        return {
          ...g,
          'interventionName': interventionName,
          'grantName': grantName,
          'itemCount': (g['itemIds'] as Set<String>).length,
        };
      }).toList();

      setState(() => _report = report);
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Usage Report'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _exportCsv,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: _pickStartDate,
                        child: Text(_startDate != null
                            ? 'Start: ${_startDate!.toLocal().toString().split(' ')[0]}'
                            : 'Pick Start Date'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextButton(
                        onPressed: _pickEndDate,
                        child: Text(_endDate != null
                            ? 'End: ${_endDate!.toLocal().toString().split(' ')[0]}'
                            : 'Pick End Date'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedInterventionId,
                        decoration: const InputDecoration(labelText: 'Intervention (optional)'),
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
                        decoration: const InputDecoration(labelText: 'Grant (optional)'),
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
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _report.length,
                    itemBuilder: (context, index) {
                      final item = _report[index];
                      return ListTile(
                        title: Text('${item['interventionName']} - ${item['grantName']}'),
                        subtitle: Text(
                          'Qty: ${item['totalQty']}, Items: ${item['itemCount']}, Lines: ${item['lineCount']}',
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _exportCsv() {
    final buffer = StringBuffer();
    buffer.writeln('Intervention,Grant,Total Qty,Distinct Items,Lines');

    for (final item in _report) {
      final interventionName = item['interventionName'] ?? 'Unknown';
      final grantName = item['grantName'] ?? 'Unknown';
      final totalQty = item['totalQty'] ?? 0;
      final itemCount = item['itemCount'] ?? 0;
      final lineCount = item['lineCount'] ?? 0;

      // Escape commas in names
      final safeIntervention = interventionName.toString().replaceAll(',', ';');
      final safeGrant = grantName.toString().replaceAll(',', ';');

      buffer.writeln('$safeIntervention,$safeGrant,$totalQty,$itemCount,$lineCount');
    }

    final csvData = buffer.toString();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
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
    );
  }
}
