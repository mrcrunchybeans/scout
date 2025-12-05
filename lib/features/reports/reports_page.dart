import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:scout/utils/operator_store.dart';

/// Redesigned Reports page with tabs for different user needs:
/// - Overview: Quick summary dashboard
/// - By Item: Top items used, low stock items that get used frequently
/// - By Grant: Grant-focused reporting for leadership
/// - By Operator: Who's using what (for accountability)
/// - My Activity: Personal usage history
class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _db = FirebaseFirestore.instance;
  
  // Date range
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  String _selectedPreset = '30 days';
  
  // Cached data
  List<QueryDocumentSnapshot> _usageLogs = [];
  Map<String, String> _itemNames = {};
  Map<String, String> _interventionNames = {};
  Map<String, String> _grantNames = {};
  Map<String, String> _operatorNames = {};
  bool _loading = true;

  // Helper to safely get field from document
  dynamic _getField(QueryDocumentSnapshot doc, String field) {
    try {
      final data = doc.data() as Map<String, dynamic>?;
      return data?[field];
    } catch (e) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    debugPrint('ReportsPage: _loadData started');
    setState(() => _loading = true);
    try {
      // Load usage logs for the period
      final start = Timestamp.fromDate(_startDate);
      final end = Timestamp.fromDate(_endDate.add(const Duration(days: 1)));
      
      debugPrint('ReportsPage: Querying usage_logs from $_startDate to $_endDate');
      
      final usageSnapshot = await _db
          .collection('usage_logs')
          .where('usedAt', isGreaterThanOrEqualTo: start)
          .where('usedAt', isLessThan: end)
          .orderBy('usedAt', descending: true)
          .limit(1000) // Limit to prevent performance issues
          .get();
      
      debugPrint('ReportsPage: Got ${usageSnapshot.docs.length} usage logs');
      _usageLogs = usageSnapshot.docs;
      
      // Load lookups
      await _loadLookups();
      
      debugPrint('ReportsPage: Finished loading, setting _loading = false');
      if (mounted) {
        setState(() => _loading = false);
      }
    } catch (e, stack) {
      debugPrint('ReportsPage error: $e');
      debugPrint('Stack trace: $stack');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load data: $e')),
        );
      }
    }
  }

  Future<void> _loadLookups() async {
    try {
      // Load item names in batch (not one by one!)
      final itemIds = _usageLogs
          .map((d) => d['itemId'] as String?)
          .where((id) => id != null && id.isNotEmpty)
          .toSet()
          .take(100) // Limit to prevent too many reads
          .toList();
      
      // Batch load items - Firestore whereIn is limited to 30 items
      for (var i = 0; i < itemIds.length; i += 30) {
        final batch = itemIds.skip(i).take(30).toList();
        if (batch.isEmpty) continue;
        
        final itemsSnapshot = await _db
            .collection('items')
            .where(FieldPath.documentId, whereIn: batch)
            .get();
        
        for (final doc in itemsSnapshot.docs) {
          _itemNames[doc.id] = doc.data()['name'] as String? ?? 'Unknown Item';
        }
      }
      
      // Load intervention names
      final interventionSnap = await _db.collection('interventions').get();
      for (final doc in interventionSnap.docs) {
        _interventionNames[doc.id] = doc.data()['name'] as String? ?? doc.id;
      }
      
      // Load grant names
      final grantSnap = await _db.collection('grants').get();
      for (final doc in grantSnap.docs) {
        _grantNames[doc.id] = doc.data()['name'] as String? ?? doc.id;
      }
    } catch (e) {
      debugPrint('Error loading lookups: $e');
      // Continue anyway - we can still show reports with IDs instead of names
    }
    
    // Extract unique operator names from usage logs
    for (final doc in _usageLogs) {
      final op = _getField(doc, 'operatorName') as String?;
      if (op != null && op.isNotEmpty) {
        _operatorNames[op] = op;
      }
    }
  }

  void _onPresetChanged(String preset) {
    final now = DateTime.now();
    setState(() {
      _selectedPreset = preset;
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
        case 'This Month':
          _startDate = DateTime(now.year, now.month, 1);
          _endDate = now;
          break;
        case 'Last Month':
          final lastMonth = DateTime(now.year, now.month - 1, 1);
          _startDate = lastMonth;
          _endDate = DateTime(now.year, now.month, 0);
          break;
        case 'This Year':
          _startDate = DateTime(now.year, 1, 1);
          _endDate = now;
          break;
      }
    });
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('ReportsPage: build() called, _loading=$_loading, _usageLogs.length=${_usageLogs.length}');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports & Analytics'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard), text: 'Overview'),
            Tab(icon: Icon(Icons.inventory_2), text: 'By Item'),
            Tab(icon: Icon(Icons.account_balance_wallet), text: 'By Grant'),
            Tab(icon: Icon(Icons.people), text: 'By Operator'),
            Tab(icon: Icon(Icons.person), text: 'My Activity'),
          ],
        ),
        actions: [
          // Time period selector
          PopupMenuButton<String>(
            icon: const Icon(Icons.date_range),
            tooltip: 'Select time period',
            onSelected: _onPresetChanged,
            itemBuilder: (context) => [
              const PopupMenuItem(value: '7 days', child: Text('Last 7 days')),
              const PopupMenuItem(value: '30 days', child: Text('Last 30 days')),
              const PopupMenuItem(value: '90 days', child: Text('Last 90 days')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'This Month', child: Text('This Month')),
              const PopupMenuItem(value: 'Last Month', child: Text('Last Month')),
              const PopupMenuItem(value: 'This Year', child: Text('This Year')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadData,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Date range indicator
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Text(
                        '${DateFormat('MMM d, yyyy').format(_startDate)} – ${DateFormat('MMM d, yyyy').format(_endDate)} ($_selectedPreset)',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_usageLogs.length} transactions',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _safeTabBuilder(_buildOverviewTab, 'Overview'),
                      _safeTabBuilder(_buildByItemTab, 'By Item'),
                      _safeTabBuilder(_buildByGrantTab, 'By Grant'),
                      _safeTabBuilder(_buildByOperatorTab, 'By Operator'),
                      _safeTabBuilder(_buildMyActivityTab, 'My Activity'),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // Helper to safely build tabs with error handling
  Widget _safeTabBuilder(Widget Function() builder, String tabName) {
    try {
      return builder();
    } catch (e, stack) {
      debugPrint('Error building $tabName tab: $e\n$stack');
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
              const SizedBox(height: 16),
              Text('Error loading $tabName'),
              const SizedBox(height: 8),
              Text('$e', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      );
    }
  }

  // ==================== OVERVIEW TAB ====================
  Widget _buildOverviewTab() {
    final totalQty = _usageLogs.fold<double>(0, (sum, doc) => sum + ((_getField(doc, 'qtyUsed') as num?)?.toDouble() ?? 0));
    final uniqueItems = _usageLogs.map((d) => _getField(d, 'itemId')).toSet().length;
    final uniqueOperators = _usageLogs.map((d) => _getField(d, 'operatorName')).where((n) => n != null).toSet().length;
    final days = _endDate.difference(_startDate).inDays + 1;
    final avgPerDay = days > 0 ? totalQty / days : 0;

    // Daily usage for trend
    final dailyUsage = <DateTime, double>{};
    for (final doc in _usageLogs) {
      final usedAt = (_getField(doc, 'usedAt') as Timestamp?)?.toDate();
      final qty = (_getField(doc, 'qtyUsed') as num?)?.toDouble() ?? 0;
      if (usedAt != null) {
        final day = DateTime(usedAt.year, usedAt.month, usedAt.day);
        dailyUsage[day] = (dailyUsage[day] ?? 0) + qty;
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Summary cards
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _SummaryCard(
              title: 'Total Used',
              value: totalQty.toStringAsFixed(0),
              subtitle: 'items',
              icon: Icons.inventory_2,
              color: Theme.of(context).colorScheme.primary,
            ),
            _SummaryCard(
              title: 'Daily Average',
              value: avgPerDay.toStringAsFixed(1),
              subtitle: 'items/day',
              icon: Icons.trending_up,
              color: Colors.green,
            ),
            _SummaryCard(
              title: 'Unique Items',
              value: '$uniqueItems',
              subtitle: 'different products',
              icon: Icons.category,
              color: Colors.orange,
            ),
            _SummaryCard(
              title: 'Team Members',
              value: '$uniqueOperators',
              subtitle: 'active users',
              icon: Icons.people,
              color: Colors.purple,
            ),
          ],
        ),
        const SizedBox(height: 24),
        
        // Usage trend
        _buildTrendChart(dailyUsage, 'Daily Usage Trend'),
        const SizedBox(height: 24),
        
        // Top 5 items quick glance
        _buildTopItemsCard(),
      ],
    );
  }

  Widget _buildTopItemsCard() {
    // Aggregate by item
    final itemTotals = <String, double>{};
    for (final doc in _usageLogs) {
      final itemId = _getField(doc, 'itemId') as String?;
      final qty = (_getField(doc, 'qtyUsed') as num?)?.toDouble() ?? 0;
      if (itemId != null) {
        itemTotals[itemId] = (itemTotals[itemId] ?? 0) + qty;
      }
    }
    
    final sorted = itemTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top5 = sorted.take(5).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.star, color: Colors.amber),
                const SizedBox(width: 8),
                Text('Top 5 Items', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            if (top5.isEmpty)
              const Text('No usage data')
            else
              ...top5.asMap().entries.map((entry) {
                final idx = entry.key;
                final itemId = entry.value.key;
                final qty = entry.value.value;
                final name = _itemNames[itemId] ?? 'Unknown';
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: _getColorForIndex(idx),
                    child: Text('${idx + 1}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                  title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Text('${qty.toStringAsFixed(0)} used', style: const TextStyle(fontWeight: FontWeight.bold)),
                );
              }),
          ],
        ),
      ),
    );
  }

  // ==================== BY ITEM TAB ====================
  Widget _buildByItemTab() {
    // Aggregate by item
    final itemTotals = <String, double>{};
    final itemTransactions = <String, int>{};
    for (final doc in _usageLogs) {
      final itemId = _getField(doc, 'itemId') as String?;
      final qty = (_getField(doc, 'qtyUsed') as num?)?.toDouble() ?? 0;
      if (itemId != null) {
        itemTotals[itemId] = (itemTotals[itemId] ?? 0) + qty;
        itemTransactions[itemId] = (itemTransactions[itemId] ?? 0) + 1;
      }
    }
    
    final sorted = itemTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final totalQty = itemTotals.values.fold<double>(0, (s, v) => s + v);

    if (sorted.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text('No item usage in this period', style: TextStyle(fontSize: 16, color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Summary header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Row(
            children: [
              Icon(Icons.inventory_2, size: 28, color: Theme.of(context).colorScheme.onPrimaryContainer),
              const SizedBox(width: 12),
              Text(
                '${sorted.length} items used  •  ${totalQty.toStringAsFixed(0)} total',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ),
        // Items list
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            itemCount: sorted.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = sorted[index];
              final itemId = entry.key;
              final qty = entry.value;
              final txns = itemTransactions[itemId] ?? 0;
              final name = _itemNames[itemId] ?? 'Unknown Item';
              final pct = totalQty > 0 ? (qty / totalQty * 100) : 0;

              return ListTile(
                dense: true,
                leading: SizedBox(
                  width: 36,
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('$txns transaction${txns == 1 ? '' : 's'}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          qty.toStringAsFixed(0),
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                        Text(
                          '${pct.toStringAsFixed(1)}%',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    // Mini bar showing percentage
                    Container(
                      width: 4,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          width: 4,
                          height: 32 * (pct / 100).clamp(0.05, 1.0),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ==================== BY GRANT TAB ====================
  Widget _buildByGrantTab() {
    // Aggregate by grant
    final grantTotals = <String, double>{};
    final grantTransactions = <String, int>{};
    for (final doc in _usageLogs) {
      final grantId = _getField(doc, 'grantId') as String? ?? '(No Grant)';
      final qty = (_getField(doc, 'qtyUsed') as num?)?.toDouble() ?? 0;
      grantTotals[grantId] = (grantTotals[grantId] ?? 0) + qty;
      grantTransactions[grantId] = (grantTransactions[grantId] ?? 0) + 1;
    }
    
    final sorted = grantTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final totalQty = grantTotals.values.fold<double>(0, (s, v) => s + v);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Summary
        Card(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.account_balance_wallet, size: 32),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${sorted.length} grants with activity', style: Theme.of(context).textTheme.titleLarge),
                    Text('${totalQty.toStringAsFixed(0)} items distributed', style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        
        // Pie chart
        if (sorted.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                height: 250,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 40,
                    sections: sorted.take(8).toList().asMap().entries.map((entry) {
                      final idx = entry.key;
                      final qty = entry.value.value;
                      final pct = totalQty > 0 ? (qty / totalQty * 100) : 0;
                      return PieChartSectionData(
                        value: qty,
                        title: '${pct.toStringAsFixed(0)}%',
                        color: _getColorForIndex(idx),
                        radius: 80,
                        titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        badgeWidget: null,
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 16),
        
        // Grant list
        ...sorted.asMap().entries.map((entry) {
          final idx = entry.key;
          final grantId = entry.value.key;
          final qty = entry.value.value;
          final txns = grantTransactions[grantId] ?? 0;
          final name = _grantNames[grantId] ?? grantId;
          final pct = totalQty > 0 ? (qty / totalQty * 100) : 0;
          
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: _getColorForIndex(idx),
                child: Icon(Icons.account_balance_wallet, color: Colors.white, size: 20),
              ),
              title: Text(name),
              subtitle: Text('$txns transactions'),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${qty.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  Text('${pct.toStringAsFixed(1)}%', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // ==================== BY OPERATOR TAB ====================
  Widget _buildByOperatorTab() {
    // Aggregate by operator
    final operatorTotals = <String, double>{};
    final operatorTransactions = <String, int>{};
    for (final doc in _usageLogs) {
      final rawOp = _getField(doc, 'operatorName');
      final operator = (rawOp as String?)?.trim();
      final displayName = (operator == null || operator.isEmpty) ? '(Unknown)' : operator;
      final qty = (_getField(doc, 'qtyUsed') as num?)?.toDouble() ?? 0;
      operatorTotals[displayName] = (operatorTotals[displayName] ?? 0) + qty;
      operatorTransactions[displayName] = (operatorTransactions[displayName] ?? 0) + 1;
    }
    
    final sorted = operatorTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final totalQty = operatorTotals.values.fold<double>(0, (s, v) => s + v);

    if (sorted.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_outline, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text('No usage data in this period', style: TextStyle(fontSize: 16, color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sorted.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Card(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.people, size: 32),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${sorted.length} team member${sorted.length == 1 ? '' : 's'}', style: Theme.of(context).textTheme.titleLarge),
                      Text('${_usageLogs.length} total transaction${_usageLogs.length == 1 ? '' : 's'}', style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ],
              ),
            ),
          );
        }
        
        final entry = sorted[index - 1];
        final operator = entry.key;
        final qty = entry.value;
        final txns = operatorTransactions[operator] ?? 0;
        final pct = totalQty > 0 ? (qty / totalQty * 100) : 0;

        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _getColorForIndex(index - 1),
              child: Text(operator.isNotEmpty ? operator[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white)),
            ),
            title: Text(operator),
            subtitle: Text('$txns transactions'),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${qty.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                Text('${pct.toStringAsFixed(1)}%', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==================== MY ACTIVITY TAB ====================
  Widget _buildMyActivityTab() {
    final currentOperator = OperatorStore.name.value ?? '';
    
    debugPrint('MyActivity: currentOperator = "$currentOperator"');
    debugPrint('MyActivity: total usage logs = ${_usageLogs.length}');
    
    // Show all unique operators for debugging
    final allOperators = <String>{};
    for (final doc in _usageLogs) {
      final op = _getField(doc, 'operatorName');
      if (op != null) allOperators.add(op.toString());
    }
    debugPrint('MyActivity: all operators in logs = $allOperators');
    
    // Filter to current user's activity (case-insensitive, trimmed)
    final myLogs = _usageLogs.where((doc) {
      final op = (_getField(doc, 'operatorName') as String? ?? '').trim();
      return op.toLowerCase() == currentOperator.trim().toLowerCase();
    }).toList();
    
    debugPrint('MyActivity: matched logs = ${myLogs.length}');

    final totalQty = myLogs.fold<double>(0, (sum, doc) => sum + ((_getField(doc, 'qtyUsed') as num?)?.toDouble() ?? 0));
    final uniqueItems = myLogs.map((d) => _getField(d, 'itemId')).toSet().length;

    if (currentOperator.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No operator name set'),
            Text('Set your name to see your activity'),
          ],
        ),
      );
    }

    // If no activity found, show helpful message
    if (myLogs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text('No activity found for "$currentOperator"'),
              const SizedBox(height: 8),
              Text(
                'Make sure your name matches exactly how it appears when logging usage.',
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
                textAlign: TextAlign.center,
              ),
              if (allOperators.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Names in system: ${allOperators.take(5).join(", ")}${allOperators.length > 5 ? "..." : ""}',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Personal summary
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      child: Text(currentOperator.isNotEmpty ? currentOperator[0].toUpperCase() : '?', style: const TextStyle(fontSize: 20)),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(currentOperator, style: Theme.of(context).textTheme.titleLarge),
                        Text('Your Activity', style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Text('${myLogs.length}', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                          const Text('Transactions'),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text('${totalQty.toStringAsFixed(0)}', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                          const Text('Items Used'),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text('$uniqueItems', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                          const Text('Unique Items'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        
        // Recent activity
        Text('Recent Activity', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        
        if (myLogs.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.inbox, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 8),
                    const Text('No activity in this period'),
                  ],
                ),
              ),
            ),
          )
        else
          ...myLogs.take(20).map((doc) {
            final itemId = _getField(doc, 'itemId') as String?;
            final itemName = _itemNames[itemId ?? ''] ?? 'Unknown Item';
            final qty = (_getField(doc, 'qtyUsed') as num?)?.toDouble() ?? 0;
            final usedAt = (_getField(doc, 'usedAt') as Timestamp?)?.toDate();
            final grantId = _getField(doc, 'grantId') as String?;
            final grantName = grantId != null ? _grantNames[grantId] ?? grantId : null;
            
            return Card(
              child: ListTile(
                leading: const Icon(Icons.remove_circle_outline, color: Colors.orange),
                title: Text(itemName, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${grantName != null ? '$grantName • ' : ''}${usedAt != null ? DateFormat('MMM d, h:mm a').format(usedAt) : ''}',
                ),
                trailing: Text('-${qty.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
              ),
            );
          }),
      ],
    );
  }

  // ==================== SHARED WIDGETS ====================
  Widget _buildTrendChart(Map<DateTime, double> dailyUsage, String title) {
    if (dailyUsage.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(child: Text('No data for trend chart')),
        ),
      );
    }

    final sortedDays = dailyUsage.keys.toList()..sort();
    final trendData = <FlSpot>[];
    for (int i = 0; i < sortedDays.length; i++) {
      trendData.add(FlSpot(i.toDouble(), dailyUsage[sortedDays[i]] ?? 0));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(show: true, drawVerticalLine: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= sortedDays.length) return const Text('');
                          // Show date for first, last, and every 7th day
                          if (idx == 0 || idx == sortedDays.length - 1 || idx % 7 == 0) {
                            return Text(DateFormat('M/d').format(sortedDays[idx]), style: const TextStyle(fontSize: 10));
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: true),
                  lineBarsData: [
                    LineChartBarData(
                      spots: trendData,
                      isCurved: true,
                      color: Theme.of(context).colorScheme.primary,
                      barWidth: 3,
                      belowBarData: BarAreaData(
                        show: true,
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                      ),
                      dotData: FlDotData(show: trendData.length < 15),
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

  Color _getColorForIndex(int index) {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.pink,
      Colors.indigo,
      Colors.amber,
      Colors.cyan,
      Colors.red,
    ];
    return colors[index % colors.length];
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
    return SizedBox(
      width: 160,
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 20),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(title, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}
