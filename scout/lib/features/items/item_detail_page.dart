import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import '../../utils/audit.dart';
import '../../widgets/scanner_sheet.dart';
import 'quick_use_sheet.dart';
import 'bulk_inventory_entry_page.dart';
import 'new_item_page.dart';

String _normalizeBarcode(String s) =>
  s.replaceAll(RegExp(r'[^0-9A-Za-z]'), '').trim();

// Helper to generate lot codes in YYMM-XXX format (e.g., 2509-001)
Future<String> _generateLotCode(String itemId) async {
  final now = DateTime.now();
  final yy = now.year.toString().substring(2); // Last two digits of year
  final mm = now.month.toString().padLeft(2, '0'); // Month with leading zero
  final monthPrefix = '$yy$mm';

  // Query existing lot codes for this month to find the next sequential number
  final db = FirebaseFirestore.instance;
  final lotsQuery = await db
      .collection('items')
      .doc(itemId)
      .collection('lots')
      .where('lotCode', isGreaterThanOrEqualTo: monthPrefix)
      .where('lotCode', isLessThan: '${monthPrefix}Z')
      .orderBy('lotCode', descending: true)
      .limit(1)
      .get();

  int nextNumber = 1; // Default to 001
  if (lotsQuery.docs.isNotEmpty) {
    final lastLotCode = lotsQuery.docs.first.data()['lotCode'] as String?;
    if (lastLotCode != null && lastLotCode.startsWith(monthPrefix) && lastLotCode.length >= 7) {
      // Extract the number part (last 3 characters) and increment
      final numberPart = lastLotCode.substring(lastLotCode.length - 3);
      final currentNumber = int.tryParse(numberPart) ?? 0;
      nextNumber = currentNumber + 1;
    }
  }

  // Format as 3-digit number with leading zeros
  final formattedNumber = nextNumber.toString().padLeft(3, '0');
  return '$monthPrefix-$formattedNumber';
}

class ItemDetailPage extends StatelessWidget {
  final String itemId;
  final String itemName;
  final String? lotId; // Optional: highlight this specific lot
  const ItemDetailPage({super.key, required this.itemId, required this.itemName, this.lotId});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: lotId != null ? 1 : 0, // Start on "Manage Lots" tab if lotId provided
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back to Items',
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(itemName),
          actions: [
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Edit Item',
              onPressed: () => _editItem(context),
            ),
          ],
          bottom: const TabBar(tabs: [
            Tab(text: 'Details'),
            Tab(text: 'Manage Lots'),
          ]),
        ),
        body: TabBarView(
          children: [
            _ItemSummaryTab(itemId: itemId),
            _LotsTab(itemId: itemId, highlightLotId: lotId),
          ],
        ),
      ),
    );
  }

  void _editItem(BuildContext context) async {
    // Fetch the current item data
    final doc = await FirebaseFirestore.instance.collection('items').doc(itemId).get();
    if (!doc.exists) return;

    final itemData = doc.data()!;
    
    if (!context.mounted) return;
    
    // Navigate to edit page
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NewItemPage(
          itemId: itemId,
          existingItem: itemData,
        ),
      ),
    );

    // If item was updated, refresh the page (optional)
    if (result == true && context.mounted) {
      // Could refresh data here if needed
    }
  }
}

class _ItemSummaryTab extends StatefulWidget {
  final String itemId;
  const _ItemSummaryTab({required this.itemId});

  @override
  State<_ItemSummaryTab> createState() => _ItemSummaryTabState();
}

class _ItemSummaryTabState extends State<_ItemSummaryTab> {
  Map<String, dynamic>? _usageStats;
  List<Map<String, dynamic>> _recentUsage = [];
  bool _loadingUsage = true;

  @override
  void initState() {
    super.initState();
    _loadUsageData();
  }

  Future<void> _syncToAlgolia() async {
    final fn = FirebaseFunctions.instance.httpsCallable('syncItemToAlgoliaCallable');
    try {
      await fn.call({'itemId': widget.itemId});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sync requested')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sync failed: $e')));
    }
  }

  Future<void> _loadUsageData() async {
    try {
      final now = DateTime.now();
      final thirtyDaysAgo = now.subtract(const Duration(days: 30));
      final ninetyDaysAgo = now.subtract(const Duration(days: 90));

      // Get usage statistics for last 30 and 90 days
      final thirtyDayQuery = FirebaseFirestore.instance
          .collection('usage_logs')
          .where('itemId', isEqualTo: widget.itemId)
          .where('usedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(thirtyDaysAgo))
          .orderBy('usedAt', descending: true);

      final ninetyDayQuery = FirebaseFirestore.instance
          .collection('usage_logs')
          .where('itemId', isEqualTo: widget.itemId)
          .where('usedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(ninetyDaysAgo))
          .orderBy('usedAt', descending: true)
          .limit(50); // Get recent usage for history

      final [thirtyDayResult, ninetyDayResult] = await Future.wait([
        thirtyDayQuery.get(),
        ninetyDayQuery.get(),
      ]);

      // Calculate statistics
      double totalUsed30 = 0;
      double totalUsed90 = 0;
      final recentUsage = <Map<String, dynamic>>[];

      for (final doc in thirtyDayResult.docs) {
        final data = doc.data();
        totalUsed30 += (data['qtyUsed'] as num?)?.toDouble() ?? 0;
      }

      for (final doc in ninetyDayResult.docs) {
        final data = doc.data();
        totalUsed90 += (data['qtyUsed'] as num?)?.toDouble() ?? 0;

        // Collect recent usage for history (last 10)
        if (recentUsage.length < 10) {
          final usedAt = (data['usedAt'] as Timestamp?)?.toDate();
          if (usedAt != null) {
            recentUsage.add({
              'date': usedAt,
              'quantity': data['qtyUsed'] ?? 0,
              'unit': data['unit'] ?? 'each',
              'interventionId': data['interventionId'],
              'grantId': data['grantId'],
            });
          }
        }
      }

      final avgDaily30 = totalUsed30 / 30;
      final avgDaily90 = totalUsed90 / 90;

      if (mounted) {
        setState(() {
          _usageStats = {
            'totalUsed30': totalUsed30,
            'totalUsed90': totalUsed90,
            'avgDaily30': avgDaily30,
            'avgDaily90': avgDaily90,
          };
          _recentUsage = recentUsage;
          _loadingUsage = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingUsage = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final ref = db.collection('items').doc(widget.itemId);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (ctx, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final data = snap.data!.data() ?? {};

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Stock Level Card
            _buildStockLevelCard(data, context),

            const SizedBox(height: 16),

            // Usage Analytics Card
            _buildUsageAnalyticsCard(context),

            const SizedBox(height: 16),

            // Item Metadata Card
            _buildMetadataCard(data, context),

            const SizedBox(height: 16),

            // Quick Actions
            _buildQuickActions(context),

            const SizedBox(height: 16),

            // Recent Usage History
            if (_recentUsage.isNotEmpty) _buildRecentUsageCard(context),

            const SizedBox(height: 16),

            // Barcodes Section
            _buildBarcodesSection(data, ref, context),
          ],
        );
      },
    );
  }

  Widget _buildStockLevelCard(Map<String, dynamic> data, BuildContext context) {
    final qty = (data['qtyOnHand'] ?? 0) as num;
    final minQty = (data['minQty'] ?? 0) as num;
    final maxQty = (data['maxQty'] ?? 0) as num;
    final baseUnit = (data['baseUnit'] ?? 'each') as String;

    // Calculate stock level percentage
    final stockLevel = maxQty > 0 ? (qty / maxQty).clamp(0.0, 1.0) : 1.0;
    final isLow = qty <= minQty && minQty > 0;
    final isExcess = maxQty > 0 && qty > maxQty;

    // Status flags
    final flags = [
      if (data['flagLow'] == true || isLow) 'LOW',
      if (data['flagExcess'] == true || isExcess) 'EXCESS',
      if (data['flagStale'] == true) 'STALE',
      if (data['flagExpiringSoon'] == true) 'EXPIRING',
    ];

    final ts = data['earliestExpiresAt'];
    final exp = (ts is Timestamp) ? ts.toDate() : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.inventory, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('Stock Level', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),

            // Quantity display
            Row(
              children: [
                Text(
                  '$qty',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isLow ? Colors.red : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  baseUnit,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Min: $minQty',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (maxQty > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Max: $maxQty',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ],
            ),

            const SizedBox(height: 12),

            // Progress bar
            if (maxQty > 0) ...[
              LinearProgressIndicator(
                value: stockLevel,
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isLow ? Colors.red :
                  isExcess ? Colors.orange :
                  stockLevel > 0.8 ? Colors.green : Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${(stockLevel * 100).round()}% of maximum capacity',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Expiration info
            if (exp != null) ...[
              Row(
                children: [
                  Icon(Icons.schedule, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    'Earliest expiration: ${MaterialLocalizations.of(context).formatFullDate(exp)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],

            // Status flags
            if (flags.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                children: flags.map((flag) {
                  Color color;
                  switch (flag) {
                    case 'LOW': color = Colors.red;
                    case 'EXCESS': color = Colors.orange;
                    case 'STALE': color = Colors.amber;
                    case 'EXPIRING': color = Colors.deepOrange;
                    default: color = Theme.of(context).colorScheme.primary;
                  }
                  return Chip(
                    label: Text(flag, style: const TextStyle(fontSize: 12)),
                    backgroundColor: color.withValues(alpha: 0.1),
                    side: BorderSide(color: color.withValues(alpha: 0.3)),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUsageAnalyticsCard(BuildContext context) {
    if (_loadingUsage) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.analytics, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('Usage Analytics', style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
          ),
        ),
      );
    }

    if (_usageStats == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.analytics, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('Usage Analytics', style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'No usage data available',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final stats = _usageStats!;
    final totalUsed30 = stats['totalUsed30'] as double;
    final totalUsed90 = stats['totalUsed90'] as double;
    final avgDaily30 = stats['avgDaily30'] as double;
    final avgDaily90 = stats['avgDaily90'] as double;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('Usage Analytics', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),

            // Usage stats grid
            Row(
              children: [
                Expanded(
                  child: _buildUsageStat(
                    context,
                    'Last 30 days',
                    '${totalUsed30.toStringAsFixed(1)} units',
                    'Avg: ${avgDaily30.toStringAsFixed(2)}/day',
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildUsageStat(
                    context,
                    'Last 90 days',
                    '${totalUsed90.toStringAsFixed(1)} units',
                    'Avg: ${avgDaily90.toStringAsFixed(2)}/day',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Usage trend indicator
            if (avgDaily30 > 0 && avgDaily90 > 0) ...[
              Row(
                children: [
                  Icon(
                    avgDaily30 > avgDaily90 ? Icons.trending_up : Icons.trending_down,
                    color: avgDaily30 > avgDaily90 ? Colors.green : Colors.red,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    avgDaily30 > avgDaily90
                      ? 'Usage increasing recently'
                      : 'Usage decreasing recently',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: avgDaily30 > avgDaily90 ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUsageStat(BuildContext context, String period, String total, String average) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            period,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            total,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            average,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataCard(Map<String, dynamic> data, BuildContext context) {
    final category = data['category'] as String?;
    final useType = data['useType'] as String?;
    final homeLocationId = data['homeLocationId'] as String?;
    final grantId = data['grantId'] as String?;
    final lastUsedTs = data['lastUsedAt'];
    final lastUsed = (lastUsedTs is Timestamp) ? lastUsedTs.toDate() : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('Item Details', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),

            // Metadata grid
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                if (category != null)
                  _buildMetadataItem(context, 'Category', category),
                if (useType != null)
                  _buildMetadataItem(context, 'Use Type', useType),
                if (homeLocationId != null)
                  _buildMetadataItem(context, 'Location', homeLocationId),
                if (grantId != null)
                  _buildMetadataItem(context, 'Grant', grantId),
                if (lastUsed != null)
                  _buildMetadataItem(
                    context,
                    'Last Used',
                    MaterialLocalizations.of(context).formatFullDate(lastUsed),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetadataItem(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        SelectableText(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.electric_bolt, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('Quick Actions', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _showQuickUseSheet(context),
                    icon: const Icon(Icons.remove_circle),
                    label: const Text('Use Item'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showAddStockSheet(context),
                    icon: const Icon(Icons.add_circle),
                    label: const Text('Add Stock'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _syncToAlgolia,
                    icon: const Icon(Icons.sync),
                    label: const Text('Sync to Algolia'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentUsageCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('Recent Usage', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),

            // Recent usage list
            ..._recentUsage.take(5).map((usage) {
              final date = usage['date'] as DateTime;
              final quantity = usage['quantity'] as num;
              final unit = usage['unit'] as String? ?? 'each';

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Text(
                      MaterialLocalizations.of(context).formatShortDate(date),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${quantity.toStringAsFixed(1)} $unit',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildBarcodesSection(Map<String, dynamic> data, DocumentReference<Map<String, dynamic>> ref, BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Barcodes', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final b in (data['barcodes'] as List?)?.cast<String>() ?? const <String>[])
                  InputChip(
                    label: SelectableText(b),
                    onDeleted: () async {
                      await ref.set(
                        Audit.updateOnly({'barcodes': FieldValue.arrayRemove([b])}),
                        SetOptions(merge: true),
                      );
                      await Audit.log('item.barcode.remove', {'itemId': ref.id, 'barcode': b});
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _RowAddBarcode(ref: ref),
          ],
        ),
      ),
    );
  }

  void _showQuickUseSheet(BuildContext context) async {
    // Get item name from the current data
    final db = FirebaseFirestore.instance;
    final ref = db.collection('items').doc(widget.itemId);

    try {
      final doc = await ref.get();
      if (!mounted) return;
      if (doc.exists) {
        final data = doc.data()!;
        final itemName = data['name'] as String? ?? 'Unknown Item';
        if (!context.mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => QuickUseSheet(
              itemId: widget.itemId,
              itemName: itemName,
            ),
          ),
        );
      }
    } catch (_) {
      // ignore errors
    }
  }

  void _showAddStockSheet(BuildContext context) {
    // Navigate to add stock functionality
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BulkInventoryEntryPage(),
      ),
    );
  }
}

class _LotsTab extends StatelessWidget {
  final String itemId;
  final String? highlightLotId;
  const _LotsTab({required this.itemId, this.highlightLotId});

  @override
  Widget build(BuildContext context) {
    return _LotsTabContent(itemId: itemId, highlightLotId: highlightLotId);
  }
}

class _LotsTabContent extends StatefulWidget {
  final String itemId;
  final String? highlightLotId;
  const _LotsTabContent({required this.itemId, this.highlightLotId});

  @override
  State<_LotsTabContent> createState() => _LotsTabContentState();
}

class _LotsTabContentState extends State<_LotsTabContent> {
  bool _showArchived = false;
  final ScrollController _scrollController = ScrollController();
  bool _hasScrolledToHighlight = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Scroll to highlighted lot after the first build
    if (widget.highlightLotId != null && !_hasScrolledToHighlight) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToHighlightedLot();
      });
    }
  }

  void _scrollToHighlightedLot() {
    if (widget.highlightLotId == null || !mounted) return;
    
    // We need to wait for the StreamBuilder to have data
    // This is called after the first build, but we need to scroll after data loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Try again in the next frame to ensure data is loaded
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!mounted) return;
        // The scrolling will be handled by the ListView automatically maintaining position
        // For now, just ensure the highlighted item is visible
        _hasScrolledToHighlight = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final lotsQ = db.collection('items').doc(widget.itemId).collection('lots')
      .where('archived', isEqualTo: _showArchived ? true : null) // Show archived or active lots
      .orderBy('expiresAt', descending: false) // FEFO; nulls last (Firestore sorts nulls first—handle in UI)
      .limit(200);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _showArchived ? 'Archived Lots' : 'Lots (FEFO)',
                  style: Theme.of(context).textTheme.titleMedium
                )
              ),
              TextButton.icon(
                icon: Icon(_showArchived ? Icons.visibility_off : Icons.archive),
                label: Text(_showArchived ? 'Show Active' : 'Show Archived'),
                onPressed: () => setState(() => _showArchived = !_showArchived),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add lot'),
                onPressed: () => _showAddLotSheet(context, widget.itemId),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: lotsQ.snapshots(),
            builder: (ctx, snap) {
              if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              // Push null-expiry lots to the end for FEFO UX
              final docs = snap.data!.docs.toList()
                ..sort((a, b) {
                  DateTime? ea, eb;
                  final ta = a.data()['expiresAt'], tb = b.data()['expiresAt'];
                  ea = (ta is Timestamp) ? ta.toDate() : null;
                  eb = (tb is Timestamp) ? tb.toDate() : null;
                  if (ea == null && eb == null) return 0;
                  if (ea == null) return 1; // null last
                  if (eb == null) return -1;
                  return ea.compareTo(eb); // soonest first
                });

              // Scroll to highlighted lot after data loads
              if (widget.highlightLotId != null && !_hasScrolledToHighlight) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final highlightedIndex = docs.indexWhere((doc) => doc.id == widget.highlightLotId);
                  if (highlightedIndex >= 0) {
                    _scrollController.animateTo(
                      highlightedIndex * 72.0, // Approximate height of each list item
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeInOut,
                    );
                  }
                  _hasScrolledToHighlight = true;
                });
              }

              if (docs.isEmpty) {
                return Center(
                  child: Text(
                    _showArchived
                      ? 'No archived lots.'
                      : 'No lots yet. Add one to start tracking expiration and remaining.'
                  )
                );
              }

              return ListView.separated(
                controller: _scrollController,
                itemCount: docs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) => _LotRow(
                  itemId: widget.itemId,
                  lotDoc: docs[i],
                  isArchived: _showArchived,
                  isHighlighted: docs[i].id == widget.highlightLotId,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LotRow extends StatelessWidget {
  final String itemId;
  final QueryDocumentSnapshot<Map<String, dynamic>> lotDoc;
  final bool isArchived;
  final bool isHighlighted;
  const _LotRow({required this.itemId, required this.lotDoc, this.isArchived = false, this.isHighlighted = false});

  @override
  Widget build(BuildContext context) {
    final d = lotDoc.data();
    final baseUnit = (d['baseUnit'] ?? 'each') as String;
    final qtyInitial = (d['qtyInitial'] ?? 0) as num;
    final qtyRemaining = (d['qtyRemaining'] ?? 0) as num;
    final expTs = d['expiresAt'];  final exp = (expTs is Timestamp) ? expTs.toDate() : null;
    final openTs = d['openAt'];    final opened = openTs is Timestamp;
    final afterOpen = d['expiresAfterOpenDays'] as int?;
    final receivedTs = d['receivedAt']; final received = (receivedTs is Timestamp) ? receivedTs.toDate() : null;

    final sub = <String>[
      'Remaining: $qtyRemaining / $qtyInitial $baseUnit',
      if (exp != null) 'Exp: ${MaterialLocalizations.of(context).formatFullDate(exp)}',
      if (opened) 'Opened',
      if (afterOpen != null && afterOpen > 0) 'Use within $afterOpen days after open',
      if (received != null) 'Received: ${MaterialLocalizations.of(context).formatFullDate(received)}',
    ].join(' • ');

    final lotCode = (d['lotCode'] ?? lotDoc.id.substring(0, 6)) as String;

    return Container(
      color: isHighlighted ? Theme.of(context).colorScheme.primaryContainer.withAlpha((0.3 * 255).round()) : null,
      child: ListTile(
        title: Text('${isArchived ? '[ARCHIVED] ' : ''}Lot $lotCode'),
        subtitle: Text(sub),
        onTap: () => _showEditLotSheet(context, itemId, lotDoc.id, d),
        trailing: PopupMenuButton<String>(
          onSelected: (key) async {
            if (!context.mounted) return;
            switch (key) {
              case 'adjust': await showAdjustSheet(context, itemId, lotDoc.id, qtyRemaining, opened); break;
              case 'edit':   await _showEditLotSheet(context, itemId, lotDoc.id, d); break;
              case 'archive': await _showArchiveLotDialog(context, itemId, lotDoc.id, d); break;
              case 'unarchive': await _showUnarchiveLotDialog(context, itemId, lotDoc.id, d); break;
              case 'delete': await _showDeleteLotDialog(context, itemId, lotDoc.id, d); break;
              case 'qr':     _showQrScan(context, itemId, lotDoc.id); break;
            }
          },
          itemBuilder: (_) => [
            if (!isArchived) ...[
              const PopupMenuItem(value: 'adjust', child: Text('Adjust remaining')),
              const PopupMenuItem(value: 'edit',   child: Text('Edit dates/rules')),
              const PopupMenuItem(value: 'archive', child: Text('Archive lot')),
            ] else ...[
              const PopupMenuItem(value: 'unarchive', child: Text('Unarchive lot')),
            ],
            const PopupMenuItem(value: 'delete', child: Text('Delete lot')),
            const PopupMenuItem(value: 'qr',     child: Text('Scan/QR (stub)')),
          ],
        ),
      ),
    );
  }
}

// Widget for adding a barcode
class _RowAddBarcode extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>> ref;
  const _RowAddBarcode({required this.ref});
  @override
  State<_RowAddBarcode> createState() => _RowAddBarcodeState();
}

class _RowAddBarcodeState extends State<_RowAddBarcode> {
  final _c = TextEditingController();
  bool _saving = false;

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _c,
            decoration: InputDecoration(
              labelText: 'Add barcode',
              hintText: 'Type, paste, or scan',
              prefixIcon: IconButton(
                tooltip: 'Scan barcode',
                icon: const Icon(Icons.qr_code),
                onPressed: () async {
                  final rootCtx = context;
                  final code = await showModalBottomSheet<String>(
                    context: rootCtx,
                    isScrollControlled: true,
                    builder: (_) => const ScannerSheet(
                      title: 'Scan barcode to add',
                    ),
                  );
                  if (!rootCtx.mounted) return;
                  if (code == null || code.isEmpty) return;
                  setState(() => _c.text = _normalizeBarcode(code));
                  ScaffoldMessenger.of(rootCtx).showSnackBar(
                    SnackBar(content: Text('Scanned: $code')),
                  );
                },
              ),
            ),
            onSubmitted: (_) => _add(),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _saving ? null : _add,
          child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                         : const Text('Add'),
        ),
      ],
    );
  }

  Future<void> _add() async {
    final raw = _c.text;
    final code = _normalizeBarcode(raw);
    if (code.isEmpty) return;
    setState(() => _saving = true);
    try {
      final doc = await widget.ref.get();
      final barcodes = doc.data()?['barcodes'] as List? ?? [];
      final wasEmpty = barcodes.isEmpty;
      await widget.ref.set(
        Audit.updateOnly({
          'barcodes': FieldValue.arrayUnion([code]),
          if (wasEmpty) 'barcode': code, // set primary if empty
        }),
        SetOptions(merge: true),
      );
      await Audit.log('item.attach_barcode', {
        'itemId': widget.ref.id,
        'code': code,
        'addedToArray': true,
        'setPrimaryIfEmpty': wasEmpty,
      });
      _c.clear();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

Future<void> _showAddLotSheet(BuildContext context, String itemId) async {
  final db = FirebaseFirestore.instance;

  final itemDoc = await db.collection('items').doc(itemId).get();
  if (!itemDoc.exists || !context.mounted) return;
  final suggestedLotCode = await _generateLotCode(itemId);

  final cQtyInit = TextEditingController();
  final cQtyRemain = TextEditingController();
  final cLotCode = TextEditingController(text: suggestedLotCode);
  DateTime? receivedAt = DateTime.now();
  DateTime? expiresAt;
  int? expiresAfterOpenDays;
  String baseUnit = 'each';

  if (!context.mounted) return;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (bottomSheetContext, bottomSheetSetState) {
          Future<DateTime?> pickDate(DateTime? initial) => showDatePicker(
            context: bottomSheetContext,
            initialDate: initial ?? DateTime.now(),
            firstDate: DateTime(DateTime.now().year - 1),
            lastDate: DateTime(DateTime.now().year + 3),
          );

          return Padding(
            padding: EdgeInsets.only(
              left: 16, right: 16, top: 16,
              bottom: 16 + MediaQuery.of(bottomSheetContext).viewInsets.bottom,
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                Text('Add lot', style: Theme.of(bottomSheetContext).textTheme.titleLarge),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: baseUnit,
                  items: const ['each','quart','ml','g','serving','scoop']
                    .map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                  onChanged: (v) => bottomSheetSetState(() => baseUnit = v ?? 'each'),
                  decoration: const InputDecoration(labelText: 'Base unit'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: cQtyInit,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Initial quantity'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: cQtyRemain,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Starting remaining (optional)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: cLotCode,
                  decoration: InputDecoration(
                    labelText: 'Lot code',
                    hintText: suggestedLotCode,
                    helperText: 'Auto-generated in YYMM-XXX format (e.g., 2509-001)',
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Received date'),
                  subtitle: Text(receivedAt == null
                    ? 'None'
                    : MaterialLocalizations.of(bottomSheetContext).formatFullDate(receivedAt!)),
                  trailing: TextButton.icon(
                    icon: const Icon(Icons.edit_calendar),
                    label: const Text('Pick'),
                    onPressed: () async {
                      final picked = await pickDate(receivedAt);
                      if (picked != null) {
                        bottomSheetSetState(() => receivedAt = picked);
                      }
                    },
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Expiration (optional)'),
                  subtitle: Text(expiresAt == null
                    ? 'Optional - select if applicable'
                    : MaterialLocalizations.of(bottomSheetContext).formatFullDate(expiresAt!)),
                  trailing: TextButton.icon(
                    icon: const Icon(Icons.event),
                    label: const Text('Pick'),
                    onPressed: () async {
                      final picked = await pickDate(expiresAt);
                      if (picked != null) {
                        bottomSheetSetState(() => expiresAt = picked);
                      }
                    },
                  ),
                ),
                TextField(
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Days after open (optional)',
                    helperText: 'Use within N days after opening',
                  ),
                  onChanged: (s) => expiresAfterOpenDays = int.tryParse(s),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('Save lot'),
                  onPressed: () async {
                    final qi = num.tryParse(cQtyInit.text) ?? 0;
                    final qr = (cQtyRemain.text.trim().isEmpty)
                      ? qi
                      : (num.tryParse(cQtyRemain.text) ?? qi);
                    final ref = db.collection('items').doc(itemId).collection('lots').doc();
                    await ref.set(
                      Audit.attach({
                        'lotCode': cLotCode.text.trim().isEmpty ? null : cLotCode.text.trim(),
                        'baseUnit': baseUnit,
                        'qtyInitial': qi,
                        'qtyRemaining': qr,
                        'receivedAt': receivedAt != null ? Timestamp.fromDate(receivedAt!) : null,
                        'expiresAt':  expiresAt  != null ? Timestamp.fromDate(expiresAt!)  : null,
                        'openAt': null,
                        'expiresAfterOpenDays': expiresAfterOpenDays,
                      }),
                    );
                    await Audit.log('lot.create', {
                      'itemId': itemId,
                      'lotId': ref.id,
                      'qtyInitial': qi,
                      'qtyRemaining': qr,
                    });
                    if (bottomSheetContext.mounted) {
                      Navigator.pop(bottomSheetContext);
                    }
                  },
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

Future<void> _showEditLotSheet(
  BuildContext context, String itemId, String lotId, Map<String, dynamic> d
) async {
  final db = FirebaseFirestore.instance;
  
  // Initialize variables outside StatefulBuilder to persist across state updates
  DateTime? expiresAt = (d['expiresAt'] is Timestamp) ? (d['expiresAt'] as Timestamp).toDate() : null;
  DateTime? openAt     = (d['openAt']   is Timestamp) ? (d['openAt']   as Timestamp).toDate() : null;
  int? afterOpenDays   = d['expiresAfterOpenDays'] as int?;
  
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (bottomSheetContext, bottomSheetSetState) {

          Future<DateTime?> pick(DateTime? init) => showDatePicker(
            context: bottomSheetContext,
            initialDate: init ?? DateTime.now(),
            firstDate: DateTime(DateTime.now().year - 1),
            lastDate: DateTime(DateTime.now().year + 3),
          );

          return Padding(
            padding: EdgeInsets.only(
              left: 16, right: 16, top: 16,
              bottom: 16 + MediaQuery.of(bottomSheetContext).viewInsets.bottom,
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                Text('Edit lot', style: Theme.of(bottomSheetContext).textTheme.titleLarge),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Expiration'),
                  subtitle: Text(expiresAt == null
                    ? 'None'
                    : MaterialLocalizations.of(bottomSheetContext).formatFullDate(expiresAt!)),
                  trailing: TextButton.icon(
                    icon: const Icon(Icons.edit_calendar), label: const Text('Pick'),
                    onPressed: () async {
                      final picked = await pick(expiresAt);
                      if (picked != null) {
                        bottomSheetSetState(() => expiresAt = picked);
                      }
                    },
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Opened at'),
                  subtitle: Text(openAt == null
                    ? 'None'
                    : MaterialLocalizations.of(bottomSheetContext).formatFullDate(openAt!)),
                  trailing: TextButton.icon(
                    icon: const Icon(Icons.edit_calendar), label: const Text('Pick'),
                    onPressed: () async {
                      final picked = await pick(openAt);
                      if (picked != null) {
                        bottomSheetSetState(() => openAt = picked);
                      }
                    },
                  ),
                ),
                TextField(
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Days after open (optional)'),
                  controller: TextEditingController(text: afterOpenDays?.toString() ?? ''),
                  onChanged: (s) => afterOpenDays = int.tryParse(s),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('Save'),
                  onPressed: () async {
                    final ref = db.collection('items').doc(itemId).collection('lots').doc(lotId);
                    await ref.set(
                      Audit.updateOnly({
                        'expiresAt':  expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
                        'openAt':     openAt   != null ? Timestamp.fromDate(openAt!)   : null,
                        'expiresAfterOpenDays': afterOpenDays,
                      }),
                      SetOptions(merge: true),
                    );
                    await Audit.log('lot.update', {
                      'itemId': itemId,
                      'lotId': lotId,
                      'expiresAt':  expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
                      'openAt':     openAt   != null ? Timestamp.fromDate(openAt!)   : null,
                      'expiresAfterOpenDays': afterOpenDays,
                    });
                    if (bottomSheetContext.mounted) {
                      Navigator.pop(bottomSheetContext);
                    }
                  },
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

Future<void> showAdjustSheet(
  BuildContext context, String itemId, String lotId, num currentRemaining, bool alreadyOpened
) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return _AdjustSheetContent(
        itemId: itemId,
        lotId: lotId,
        currentRemaining: currentRemaining,
        alreadyOpened: alreadyOpened,
      );
    },
  );
}

class _AdjustSheetContent extends StatefulWidget {
  final String itemId;
  final String lotId;
  final num currentRemaining;
  final bool alreadyOpened;

  const _AdjustSheetContent({
    required this.itemId,
    required this.lotId,
    required this.currentRemaining,
    required this.alreadyOpened,
  });

  @override
  State<_AdjustSheetContent> createState() => _AdjustSheetContentState();
}

class _AdjustSheetContentState extends State<_AdjustSheetContent> {
  late final TextEditingController cDelta;
  late String reason;
  late DateTime usedAt;
  final db = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    cDelta = TextEditingController();
    reason = 'use';
    usedAt = DateTime.now();
  }

  @override
  void dispose() {
    cDelta.dispose();
    super.dispose();
  }

  Future<DateTime?> pick(DateTime init) => showDatePicker(
    context: context,
    initialDate: init,
    firstDate: DateTime(DateTime.now().year - 1),
    lastDate: DateTime(DateTime.now().year + 1),
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text('Adjust remaining (− for use, + for correction)', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text('Current remaining: ${widget.currentRemaining}'),
          const SizedBox(height: 8),
          TextField(
            controller: cDelta,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(prefixText: '', labelText: 'Delta (e.g., -2)'),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: reason,
            items: const [
              DropdownMenuItem(value: 'use', child: Text('Used')),
              DropdownMenuItem(value: 'waste', child: Text('Waste/expired')),
              DropdownMenuItem(value: 'correction', child: Text('Manual correction')),
            ],
            onChanged: (v) => setState(() => reason = v ?? 'use'),
            decoration: const InputDecoration(labelText: 'Reason'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('When'),
            subtitle: Text(MaterialLocalizations.of(context).formatFullDate(usedAt)),
            trailing: TextButton.icon(
              icon: const Icon(Icons.edit_calendar), label: const Text('Pick'),
              onPressed: () async {
                final d = await pick(usedAt);
                if (d != null) {
                  setState(() => usedAt = d);
                }
              },
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            icon: const Icon(Icons.check),
            label: const Text('Apply'),
            onPressed: () async {
              final delta = num.tryParse(cDelta.text.trim()) ?? 0;
              if (delta == 0) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a non-zero adjustment amount')),
                  );
                }
                return;
              }

              try {
                final lotRef = db.collection('items').doc(widget.itemId).collection('lots').doc(widget.lotId);
                await db.runTransaction((tx) async {
                  final snap = await tx.get(lotRef);
                  final data = snap.data() ?? {};
                  final rem = (data['qtyRemaining'] ?? 0) as num;
                  final newRem = rem + delta;
                  if (newRem < 0) throw Exception('Cannot reduce quantity below 0');

                  final patch = <String, dynamic>{
                    'qtyRemaining': newRem,
                    'updatedAt': FieldValue.serverTimestamp(),
                  };
                  if (delta < 0 && (data['openAt'] == null) && !widget.alreadyOpened) {
                    patch['openAt'] = Timestamp.fromDate(usedAt);
                  }
                  tx.set(lotRef, Audit.updateOnly(patch), SetOptions(merge: true));

                  // Create adjustment record within the transaction
                  final adjustmentRef = db.collection('items').doc(widget.itemId)
                    .collection('lot_adjustments').doc();
                  tx.set(adjustmentRef, {
                    'lotId': widget.lotId,
                    'delta': delta,
                    'reason': reason,
                    'at': Timestamp.fromDate(usedAt),
                    'createdAt': FieldValue.serverTimestamp(),
                  });
                });

                // Log audit outside transaction (audit logs are append-only)
                await Audit.log('lot.adjust', {
                  'itemId': widget.itemId,
                  'lotId': widget.lotId,
                  'delta': delta,
                  'reason': reason,
                  'previousRemaining': widget.currentRemaining,
                  'newRemaining': widget.currentRemaining + delta,
                  'at': Timestamp.fromDate(usedAt),
                });

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Lot adjusted by $delta')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error adjusting lot: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }
}

Future<void> _showQrScan(BuildContext context, String itemId, String lotId) async {
  final scannedCode = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const ScannerSheet(
      title: 'Scan barcode for lot',
    ),
  );

  if (!context.mounted || scannedCode == null || scannedCode.isEmpty) return;

  // Normalize the barcode
  final normalizedCode = _normalizeBarcode(scannedCode);

  try {
    // Update the lot with the scanned barcode
    await FirebaseFirestore.instance
        .collection('items')
        .doc(itemId)
        .collection('lots')
        .doc(lotId)
        .update({
          'barcode': normalizedCode,
          'updatedAt': FieldValue.serverTimestamp(),
        });

    // Log the audit
    await Audit.log('lot.barcode_scan', {
      'itemId': itemId,
      'lotId': lotId,
      'barcode': normalizedCode,
      'rawScan': scannedCode,
    });

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Barcode scanned and saved: $normalizedCode')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save barcode: $e')),
      );
    }
  }
}

Future<void> _showArchiveLotDialog(BuildContext context, String itemId, String lotId, Map<String, dynamic> lotData) async {
  final lotCode = lotData['lotCode'] ?? lotId;
  final qtyRemaining = (lotData['qtyRemaining'] ?? 0) as num;

  final result = await showDialog<bool>(
    context: context,
    builder: (_) => Theme(
      data: Theme.of(context),
      child: AlertDialog(
        title: const Text('Archive Lot'),
        content: Text(
          'Archive lot "$lotCode"? This will hide the lot from active inventory but keep it for historical records.\n\n'
          'Remaining quantity: $qtyRemaining\n\n'
          'You can unarchive lots later if needed.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    ),
  );

  if (result == true && context.mounted) {
    final db = FirebaseFirestore.instance;
    final lotRef = db.collection('items').doc(itemId).collection('lots').doc(lotId);

    await lotRef.set(
      Audit.updateOnly({
        'archived': true,
        'archivedAt': FieldValue.serverTimestamp(),
      }),
      SetOptions(merge: true),
    );

    await Audit.log('lot.archive', {
      'itemId': itemId,
      'lotId': lotId,
      'lotCode': lotCode,
      'qtyRemaining': qtyRemaining,
    });
  }
}

Future<void> _showUnarchiveLotDialog(BuildContext context, String itemId, String lotId, Map<String, dynamic> lotData) async {
  final lotCode = lotData['lotCode'] ?? lotId;
  final qtyRemaining = (lotData['qtyRemaining'] ?? 0) as num;

  final result = await showDialog<bool>(
    context: context,
    builder: (_) => Theme(
      data: Theme.of(context),
      child: AlertDialog(
        title: const Text('Unarchive Lot'),
        content: Text(
          'Unarchive lot "$lotCode"? This will restore the lot to active inventory.\n\n'
          'Remaining quantity: $qtyRemaining\n\n'
          'The lot will be available for use again.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Unarchive'),
          ),
        ],
      ),
    ),
  );

  if (result == true && context.mounted) {
    final db = FirebaseFirestore.instance;
    final lotRef = db.collection('items').doc(itemId).collection('lots').doc(lotId);

    await lotRef.set(
      Audit.updateOnly({
        'archived': FieldValue.delete(), // Remove the archived field
        'archivedAt': FieldValue.delete(),
      }),
      SetOptions(merge: true),
    );

    await Audit.log('lot.unarchive', {
      'itemId': itemId,
      'lotId': lotId,
      'lotCode': lotCode,
      'qtyRemaining': qtyRemaining,
    });
  }
}

Future<void> _showDeleteLotDialog(BuildContext context, String itemId, String lotId, Map<String, dynamic> lotData) async {
  final lotCode = lotData['lotCode'] ?? lotId;
  final qtyRemaining = (lotData['qtyRemaining'] ?? 0) as num;

  // Prevent deleting lots with remaining inventory
  if (qtyRemaining > 0) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot delete lot with remaining inventory. Adjust quantity to 0 first.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
    return;
  }

  final result = await showDialog<bool>(
    context: context,
    builder: (_) => Theme(
      data: Theme.of(context),
      child: AlertDialog(
        title: const Text('Delete Lot'),
        content: Text(
          'Permanently delete lot "$lotCode"? This action cannot be undone.\n\n'
          '⚠️ Warning: This will permanently remove all data for this lot.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    ),
  );

  if (result == true && context.mounted) {
    final db = FirebaseFirestore.instance;
    final lotRef = db.collection('items').doc(itemId).collection('lots').doc(lotId);

    try {
      // Debug: Check if lot exists before delete
      final doc = await lotRef.get();
      if (!doc.exists) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Lot no longer exists')),
          );
        }
        return;
      }

      await lotRef.delete();

      // Debug: Verify deletion
      final verifyDoc = await lotRef.get();
      if (verifyDoc.exists) {
        throw Exception('Delete failed - lot still exists after delete operation');
      }

      await Audit.log('lot.delete', {
        'itemId': itemId,
        'lotId': lotId,
        'lotCode': lotCode,
        'qtyRemaining': qtyRemaining,
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lot "$lotCode" deleted successfully')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting lot: $e')),
        );
      }
    }
  }
}