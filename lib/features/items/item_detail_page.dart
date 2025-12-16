import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:scout/utils/audit.dart';
import 'package:scout/utils/operator_store.dart';
import '../../widgets/scanner_sheet.dart';
import '../../widgets/image_picker_widget.dart';
import '../../utils/lot_code.dart';
import 'quick_use_sheet.dart';
import 'bulk_inventory_entry_page.dart';
import 'new_item_page.dart';

String _normalizeBarcode(String s) =>
  s.replaceAll(RegExp(r'[^0-9A-Za-z]'), '').trim();

class ItemDetailPage extends StatelessWidget {
  final String itemId;
  final String itemName;
  final String? lotId; // Optional: highlight this specific lot
  const ItemDetailPage({super.key, required this.itemId, required this.itemName, this.lotId});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: DefaultTabController(
        length: 3,
        initialIndex: lotId != null ? 1 : 0, // Start on "Manage Lots" tab if lotId provided
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back to Items',
              onPressed: () {
                if (GoRouter.of(context).canPop()) {
                  GoRouter.of(context).pop();
                } else {
                  GoRouter.of(context).go('/items');
                }
              },
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
              Tab(text: 'Usage History'),
            ]),
          ),
          body: TabBarView(
            children: [
              _ItemSummaryTab(itemId: itemId),
              _LotsTab(itemId: itemId, highlightLotId: lotId),
              _UsageHistoryTab(itemId: itemId),
            ],
          ),
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
  Map<String, String> _grantNames = {};
  Map<String, String> _locationNames = {};

  @override
  void initState() {
    super.initState();
    _loadLookups();
    _loadUsageData();
  }

  Future<void> _loadLookups() async {
    try {
      final db = FirebaseFirestore.instance;
      
      // Load grant names
      final grantSnap = await db.collection('grants').get();
      final grants = <String, String>{};
      for (final doc in grantSnap.docs) {
        grants[doc.id] = doc.data()['name'] as String? ?? doc.id;
      }
      
      // Load location names (interventions)
      final locSnap = await db.collection('interventions').get();
      final locations = <String, String>{};
      for (final doc in locSnap.docs) {
        locations[doc.id] = doc.data()['name'] as String? ?? doc.id;
      }
      
      if (mounted) {
        setState(() {
          _grantNames = grants;
          _locationNames = locations;
        });
      }
    } catch (e) {
      debugPrint('Error loading lookups: $e');
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
            // Images Section
            _buildImagesSection(data, context),

            const SizedBox(height: 16),

            // Stock Level Card
            _buildStockLevelCard(data, context),

            const SizedBox(height: 16),

            // Usage Analytics Card
            _buildUsageAnalyticsCard(context),

            const SizedBox(height: 16),

            // Item Metadata Card
            _buildMetadataCard(data, context, _grantNames, _locationNames),

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
    final minQty = (data['minQty'] ?? 0) as num;
    final maxQty = (data['maxQty'] ?? 0) as num;
    final baseUnit = (data['baseUnit'] ?? 'each') as String;

    final ts = data['earliestExpiresAt'];
    final exp = (ts is Timestamp) ? ts.toDate() : null;

    // Stream lots to calculate qtyOnHand dynamically
    // Query all lots and filter client-side (archived field may not exist on active lots)
    final db = FirebaseFirestore.instance;
    final lotsStream = db.collection('items').doc(widget.itemId).collection('lots')
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: lotsStream,
      builder: (context, lotsSnap) {
        // Calculate qty from lots (sum of qtyRemaining for non-archived lots)
        num qty = 0;
        if (lotsSnap.hasData) {
          for (final doc in lotsSnap.data!.docs) {
            final lotData = doc.data();
            // Only count non-archived lots (archived field missing = active)
            if (lotData['archived'] != true) {
              qty += (lotData['qtyRemaining'] ?? 0) as num;
            }
          }
        }

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
      },
    );
  }

  Widget _buildImagesSection(Map<String, dynamic> data, BuildContext context) {
    final imageUrls = (data['imageUrls'] as List<dynamic>?)?.cast<String>() ?? [];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ImagePickerWidget(
          imageUrls: imageUrls,
          folder: 'items',
          itemId: widget.itemId,
          onImagesChanged: (newUrls) async {
            // Update the item's imageUrls array
            final ref = FirebaseFirestore.instance.collection('items').doc(widget.itemId);
            await ref.update({
              'imageUrls': newUrls,
            });
          },
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

  Widget _buildMetadataCard(Map<String, dynamic> data, BuildContext context, Map<String, String> grantNames, Map<String, String> locationNames) {
    final category = data['category'] as String?;
    final useType = data['useType'] as String?;
    final homeLocationId = data['homeLocationId'] as String?;
    final grantId = data['grantId'] as String?;
    final lastUsedTs = data['lastUsedAt'];
    final lastUsed = (lastUsedTs is Timestamp) ? lastUsedTs.toDate() : null;

    // Look up display names
    final locationDisplay = homeLocationId != null ? (locationNames[homeLocationId] ?? homeLocationId) : null;
    final grantDisplay = grantId != null ? (grantNames[grantId] ?? grantId) : null;

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
                if (locationDisplay != null)
                  _buildMetadataItem(context, 'Location', locationDisplay),
                if (grantDisplay != null)
                  _buildMetadataItem(context, 'Grant', grantDisplay),
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
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (ctx) => QuickUseSheet(
            itemId: widget.itemId,
            itemName: itemName,
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
    
    // Build the base query
    var lotsQ = db.collection('items').doc(widget.itemId).collection('lots')
      .orderBy('expiresAt', descending: false) // FEFO; nulls last (Firestore sorts nulls first—handle in UI)
      .limit(200);
    
    // Add archived filter only when showing archived lots
    // For active lots, we'll filter client-side to include lots without the archived field
    if (_showArchived) {
      lotsQ = lotsQ.where('archived', isEqualTo: true);
    }

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
              
              // Filter lots based on archived status
              var docs = snap.data!.docs.where((doc) {
                final data = doc.data();
                final isArchived = data['archived'] == true;
                
                if (_showArchived) {
                  // Show only archived lots
                  return isArchived;
                } else {
                  // Show only active lots (not archived or archived field doesn't exist)
                  return !isArchived;
                }
              }).toList();
              
              // Push null-expiry lots to the end for FEFO UX
              docs.sort((a, b) {
                DateTime? ea, eb;
                final ta = a.data()['expiresAt'], tb = b.data()['expiresAt'];
                ea = (ta is Timestamp) ? ta.toDate() : null;
                eb = (tb is Timestamp) ? tb.toDate() : null;
                if (ea == null && eb == null) return 0;
                if (ea == null) return 1; // nulls last
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
                  isArchived: docs[i].data()['archived'] == true,
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

    // Calculate expiration status
    final now = DateTime.now();
    final isExpired = exp != null && exp.isBefore(now);
    final isExpiringSoon = !isExpired && exp != null && exp.difference(now).inDays <= 30;
    
    final remainingText = qtyInitial > 0 
        ? '$qtyRemaining of $qtyInitial $baseUnit remaining'
        : '$qtyRemaining $baseUnit remaining';

    final sub = <String>[
      remainingText,
      if (exp != null) 'Exp: ${MaterialLocalizations.of(context).formatFullDate(exp)}',
      if (opened) 'Opened',
      if (afterOpen != null && afterOpen > 0) 'Use within $afterOpen days after open',
      if (received != null) 'Received: ${MaterialLocalizations.of(context).formatFullDate(received)}',
    ].join(' • ');

    final lotCode = (d['lotCode'] ?? lotDoc.id.substring(0, 6)) as String;
    
    // Determine background color based on expiration status
    Color? backgroundColor;
    if (isHighlighted) {
      backgroundColor = Theme.of(context).colorScheme.primaryContainer.withAlpha((0.3 * 255).round());
    } else if (isExpired) {
      backgroundColor = Colors.red.withAlpha((0.15 * 255).round());
    } else if (isExpiringSoon) {
      backgroundColor = Colors.orange.withAlpha((0.15 * 255).round());
    }

    return Container(
      color: backgroundColor,
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
  final itemData = itemDoc.data() ?? {};
  final suggestedLotCode = await generateNextLotCode(itemId: itemId);

  final cQtyInit = TextEditingController();
  final cQtyRemain = TextEditingController();
  final cLotCode = TextEditingController(text: suggestedLotCode);
  DateTime? receivedAt = DateTime.now();
  DateTime? expiresAt;
  int? expiresAfterOpenDays;
  String baseUnit = 'each';
  
  // Default grant and location from item
  String? selectedGrantId = itemData['grantId'] as String?;
  String? storageLocation = itemData['homeLocationId'] as String?;

  if (!context.mounted) return;
  
  // Load grants for dropdown
  final grantsSnap = await db.collection('grants').orderBy('name').get();
  final grants = grantsSnap.docs;
  
  // Load locations for dropdown
  final locationsSnap = await db.collection('lookups').doc('locations').get();
  final locationsList = (locationsSnap.data()?['values'] as List<dynamic>?)?.cast<String>() ?? [];

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
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Initial quantity'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: cQtyRemain,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                const SizedBox(height: 8),
                // Grant dropdown
                DropdownButtonFormField<String>(
                  value: selectedGrantId,
                  decoration: const InputDecoration(labelText: 'Grant (optional)'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('No grant')),
                    ...grants.map((g) => DropdownMenuItem(
                      value: g.id,
                      child: Text(g.data()['name'] ?? g.id),
                    )),
                  ],
                  onChanged: (v) => bottomSheetSetState(() => selectedGrantId = v),
                ),
                const SizedBox(height: 8),
                // Storage location dropdown
                DropdownButtonFormField<String>(
                  value: storageLocation,
                  decoration: const InputDecoration(labelText: 'Storage location (optional)'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('No location')),
                    ...locationsList.map((loc) => DropdownMenuItem(
                      value: loc,
                      child: Text(loc),
                    )),
                  ],
                  onChanged: (v) => bottomSheetSetState(() => storageLocation = v),
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
                        'grantId': selectedGrantId,
                        'storageLocation': storageLocation,
                      }),
                    );
                    await Audit.log('lot.create', {
                      'itemId': itemId,
                      'lotId': ref.id,
                      'qtyInitial': qi,
                      'qtyRemaining': qr,
                      'grantId': selectedGrantId,
                      'storageLocation': storageLocation,
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
  String? selectedGrantId = d['grantId'] as String?;
  String? storageLocation = d['storageLocation'] as String?;
  
  // Add lot code editing
  final lotCodeController = TextEditingController(text: d['lotCode'] as String? ?? '');
  
  // Load grants for dropdown
  final grantsSnap = await db.collection('grants').orderBy('name').get();
  final grants = grantsSnap.docs;
  
  // Load locations for dropdown
  final locationsSnap = await db.collection('lookups').doc('locations').get();
  final locationsList = (locationsSnap.data()?['values'] as List<dynamic>?)?.cast<String>() ?? [];
  
  if (!context.mounted) return;
  
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
                
                // Lot code editing
                TextField(
                  controller: lotCodeController,
                  decoration: const InputDecoration(
                    labelText: 'Lot Code / Batch Number',
                    helperText: 'Rename this lot (e.g., add flavor: "Dark Chocolate")',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                
                // Move lot to another item button
                OutlinedButton.icon(
                  icon: const Icon(Icons.move_up),
                  label: const Text('Move to Another Item'),
                  onPressed: () async {
                    Navigator.pop(bottomSheetContext);
                    if (context.mounted) {
                      await _showMoveToItemDialog(context, itemId, lotId, d);
                    }
                  },
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                
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
                const SizedBox(height: 8),
                // Grant dropdown
                DropdownButtonFormField<String>(
                  value: selectedGrantId,
                  decoration: const InputDecoration(labelText: 'Grant (optional)'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('No grant')),
                    ...grants.map((g) => DropdownMenuItem(
                      value: g.id,
                      child: Text(g.data()['name'] ?? g.id),
                    )),
                  ],
                  onChanged: (v) => bottomSheetSetState(() => selectedGrantId = v),
                ),
                const SizedBox(height: 8),
                // Storage location dropdown
                DropdownButtonFormField<String>(
                  value: storageLocation,
                  decoration: const InputDecoration(labelText: 'Storage location (optional)'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('No location')),
                    ...locationsList.map((loc) => DropdownMenuItem(
                      value: loc,
                      child: Text(loc),
                    )),
                  ],
                  onChanged: (v) => bottomSheetSetState(() => storageLocation = v),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('Save'),
                  onPressed: () async {
                    final newLotCode = lotCodeController.text.trim();
                    if (newLotCode.isEmpty) {
                      ScaffoldMessenger.of(bottomSheetContext).showSnackBar(
                        const SnackBar(content: Text('Lot code cannot be empty')),
                      );
                      return;
                    }
                    
                    final ref = db.collection('items').doc(itemId).collection('lots').doc(lotId);
                    await ref.set(
                      Audit.updateOnly({
                        'lotCode': newLotCode,
                        'expiresAt':  expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
                        'openAt':     openAt   != null ? Timestamp.fromDate(openAt!)   : null,
                        'expiresAfterOpenDays': afterOpenDays,
                        'grantId': selectedGrantId,
                        'storageLocation': storageLocation,
                      }),
                      SetOptions(merge: true),
                    );
                    await Audit.log('lot.update', {
                      'itemId': itemId,
                      'lotId': lotId,
                      'lotCode': newLotCode,
                      'expiresAt':  expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
                      'openAt':     openAt   != null ? Timestamp.fromDate(openAt!)   : null,
                      'expiresAfterOpenDays': afterOpenDays,
                      'grantId': selectedGrantId,
                      'storageLocation': storageLocation,
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

Future<void> _showMoveToItemDialog(
  BuildContext context, String currentItemId, String lotId, Map<String, dynamic> lotData
) async {
  final db = FirebaseFirestore.instance;
  final searchController = TextEditingController();
  String searchQuery = '';
  
  await showDialog(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, dialogSetState) {
          return AlertDialog(
            title: const Text('Move Lot to Another Item'),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: Column(
                children: [
                  TextField(
                    controller: searchController,
                    decoration: const InputDecoration(
                      labelText: 'Search for item',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      dialogSetState(() => searchQuery = value.toLowerCase());
                    },
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: db.collection('items')
                        .where('archived', isEqualTo: false)
                        .orderBy('name')
                        .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        
                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return const Center(child: Text('No items found'));
                        }
                        
                        // Filter out current item and apply search
                        final items = snapshot.data!.docs.where((doc) {
                          if (doc.id == currentItemId) return false;
                          if (searchQuery.isEmpty) return true;
                          final name = (doc.data()['name'] as String? ?? '').toLowerCase();
                          return name.contains(searchQuery);
                        }).toList();
                        
                        if (items.isEmpty) {
                          return Center(
                            child: Text(
                              searchQuery.isEmpty 
                                ? 'No other items available'
                                : 'No items match "$searchQuery"'
                            ),
                          );
                        }
                        
                        return ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final data = item.data();
                            final name = data['name'] as String? ?? 'Unknown';
                            final category = data['category'] as String? ?? '';
                            
                            return ListTile(
                              title: Text(name),
                              subtitle: category.isNotEmpty ? Text(category) : null,
                              onTap: () async {
                                Navigator.pop(dialogContext);
                                await _moveLotToItem(
                                  context,
                                  currentItemId,
                                  item.id,
                                  lotId,
                                  lotData,
                                  name,
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      );
    },
  );
  
  searchController.dispose();
}

Future<void> _moveLotToItem(
  BuildContext context,
  String fromItemId,
  String toItemId,
  String lotId,
  Map<String, dynamic> lotData,
  String toItemName,
) async {
  final db = FirebaseFirestore.instance;
  
  try {
    // Show confirmation
    final lotCode = lotData['lotCode'] as String? ?? lotId.substring(0, 6);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Move'),
        content: Text(
          'Move lot "$lotCode" to item "$toItemName"?\n\n'
          'This will transfer the lot with all its data (quantity, expiration, grant, etc.).'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Move'),
          ),
        ],
      ),
    );
    
    if (confirmed != true || !context.mounted) return;
    
    // Create lot under new item with same data
    final newLotRef = db.collection('items').doc(toItemId).collection('lots').doc(lotId);
    await newLotRef.set(Audit.updateOnly(lotData));
    
    // Delete lot from old item
    final oldLotRef = db.collection('items').doc(fromItemId).collection('lots').doc(lotId);
    await oldLotRef.delete();
    
    // Log the move
    await Audit.log('lot.move', {
      'fromItemId': fromItemId,
      'toItemId': toItemId,
      'lotId': lotId,
      'lotCode': lotCode,
    });
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lot "$lotCode" moved to "$toItemName"'),
          action: SnackBarAction(
            label: 'View',
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => ItemDetailPage(itemId: toItemId),
                ),
              );
            },
          ),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error moving lot: $e')),
      );
    }
  }
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
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(prefixText: '', labelText: 'Delta (e.g., -2.5)'),
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

                if (!context.mounted) return;
                
                final finalRemaining = widget.currentRemaining + delta;
                
                // If quantity reached 0, prompt to archive BEFORE popping the bottom sheet
                if (finalRemaining == 0) {
                  final shouldArchive = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Archive Lot?'),
                      content: const Text(
                        'This lot now has 0 remaining. Would you like to archive it?'
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('No'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Yes'),
                        ),
                      ],
                    ),
                  );
                  
                  if (shouldArchive == true) {
                    await db.collection('items').doc(widget.itemId)
                      .collection('lots').doc(widget.lotId)
                      .set(Audit.updateOnly({'archived': true}), SetOptions(merge: true));
                    
                    await Audit.log('lot.archive', {
                      'itemId': widget.itemId,
                      'lotId': widget.lotId,
                      'reason': 'quantity_zero',
                    });
                    
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Lot adjusted by $delta and archived')),
                      );
                    }
                    return;
                  }
                }
                
                // Pop the bottom sheet and show success message
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

// Usage History Tab Widget
class _UsageHistoryTab extends StatefulWidget {
  final String itemId;
  
  const _UsageHistoryTab({required this.itemId});

  @override
  State<_UsageHistoryTab> createState() => _UsageHistoryTabState();
}

class _UsageHistoryTabState extends State<_UsageHistoryTab> {
  bool _showReversals = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('usage_logs')
          .where('itemId', isEqualTo: widget.itemId)
          .orderBy('usedAt', descending: true)
          .limit(100) // Show last 100 usage records
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Text('Error loading usage history: ${snapshot.error}'),
              ],
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final usageDocs = snapshot.data?.docs ?? [];
        
        // Filter based on toggle setting
        final filteredDocs = usageDocs.where((doc) {
          final usage = doc.data() as Map<String, dynamic>;
          final isReversal = usage['isReversal'] == true;
          final qtyUsed = (usage['qtyUsed'] ?? 0) as num;
          
          if (!_showReversals) {
            // Filter out reversal entries (they confuse the history)
            return !isReversal && qtyUsed > 0;
          } else {
            // Show all entries when toggle is on
            return true;
          }
        }).toList();
        
        // Count how many were filtered out
        final reversalsCount = usageDocs.length - filteredDocs.length;
        
        if (filteredDocs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.history, color: Colors.grey, size: 48),
                const SizedBox(height: 16),
                Text(
                  _showReversals ? 'No usage history found' : 'No active usage history found',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  _showReversals 
                    ? 'This item hasn\'t been used in any cart sessions yet.'
                    : 'This item hasn\'t been used in any active cart sessions.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 14),
                ),
                if (reversalsCount > 0 && !_showReversals) ...[
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => setState(() => _showReversals = true),
                    icon: const Icon(Icons.visibility),
                    label: Text('Show $reversalsCount deleted session${reversalsCount == 1 ? '' : 's'}'),
                  ),
                ],
              ],
            ),
          );
        }

        return Column(
          children: [
            // Toggle for showing reversals
            if (reversalsCount > 0 || _showReversals)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _showReversals 
                        ? 'Showing all entries (${filteredDocs.length})'
                        : 'Showing active entries (${filteredDocs.length})',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          'Show deleted sessions',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                        Switch(
                          value: _showReversals,
                          onChanged: (value) => setState(() => _showReversals = value),
                          activeThumbColor: Theme.of(context).colorScheme.primary,
                          activeTrackColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                          inactiveThumbColor: Theme.of(context).colorScheme.onSurfaceVariant,
                          inactiveTrackColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            
            // List
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  // The StreamBuilder will automatically refresh
                },
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filteredDocs.length + 1, // +1 for summary card
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      // Summary card
                      return _UsageSummaryCard(usageDocs: filteredDocs);
                    }
                    final usage = filteredDocs[index - 1].data() as Map<String, dynamic>;
                    return _UsageHistoryCard(usage: usage);
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// Usage Summary Card
class _UsageSummaryCard extends StatelessWidget {
  final List<QueryDocumentSnapshot> usageDocs;
  
  const _UsageSummaryCard({required this.usageDocs});

  @override
  Widget build(BuildContext context) {
    if (usageDocs.isEmpty) return const SizedBox.shrink();
    
    // Calculate summary statistics
    double totalUsed = 0;
    final Map<String, double> sessionTotals = {};
    final Set<String> uniqueSessions = {};
    String? mostCommonUnit;
    final Map<String, int> unitCounts = {};
    
    for (final doc in usageDocs) {
      final usage = doc.data() as Map<String, dynamic>;
      final qtyUsed = (usage['qtyUsed'] ?? 0) as num;
      final sessionId = usage['sessionId'] as String?;
      final unit = usage['unit'] as String? ?? 'each';
      
      totalUsed += qtyUsed.toDouble();
      
      if (sessionId != null) {
        uniqueSessions.add(sessionId);
        sessionTotals[sessionId] = (sessionTotals[sessionId] ?? 0) + qtyUsed.toDouble();
      }
      
      unitCounts[unit] = (unitCounts[unit] ?? 0) + 1;
    }
    
    // Find most common unit
    if (unitCounts.isNotEmpty) {
      mostCommonUnit = unitCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key;
    }
    
    // Find last usage date
    final lastUsage = usageDocs.first.data() as Map<String, dynamic>;
    final lastUsedAt = lastUsage['usedAt'] as Timestamp?;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                  'Usage Summary',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Summary stats in a grid
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                _buildSummaryItem(
                  'Total Used',
                  '${totalUsed.toString()} ${mostCommonUnit ?? 'items'}',
                  Icons.inventory,
                ),
                _buildSummaryItem(
                  'Sessions',
                  '${uniqueSessions.length}',
                  Icons.shopping_cart,
                ),
                _buildSummaryItem(
                  'Records',
                  '${usageDocs.length}',
                  Icons.list,
                ),
                if (lastUsedAt != null)
                  _buildSummaryItem(
                    'Last Used',
                    _formatDateTime(lastUsedAt.toDate()),
                    Icons.schedule,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inDays == 0) {
      // Today - show time
      final hour = dateTime.hour.toString().padLeft(2, '0');
      final minute = dateTime.minute.toString().padLeft(2, '0');
      return 'Today $hour:$minute';
    } else if (difference.inDays == 1) {
      // Yesterday
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      // This week - show day of week
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[dateTime.weekday - 1];
    } else {
      // Older - show date
      final month = dateTime.month.toString().padLeft(2, '0');
      final day = dateTime.day.toString().padLeft(2, '0');
      return '${dateTime.year}-$month-$day';
    }
  }
}

// Individual usage history card
class _UsageHistoryCard extends StatefulWidget {
  final Map<String, dynamic> usage;
  
  const _UsageHistoryCard({required this.usage});

  @override
  State<_UsageHistoryCard> createState() => _UsageHistoryCardState();
}

class _UsageHistoryCardState extends State<_UsageHistoryCard> {
  String? _lotCode;
  String? _sessionName;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAdditionalData();
  }

  Future<void> _loadAdditionalData() async {
    final sessionId = widget.usage['sessionId'] as String?;
    final lotId = widget.usage['lotId'] as String?;
    final itemId = widget.usage['itemId'] as String?;
    
    try {
      final futures = <Future>[];
      
      // Fetch lot code if lotId exists
      if (lotId != null && itemId != null) {
        futures.add(
          FirebaseFirestore.instance
            .collection('items')
            .doc(itemId)
            .collection('lots')
            .doc(lotId)
            .get()
            .then((doc) {
              if (doc.exists) {
                final data = doc.data()!;
                _lotCode = data['lotCode'] as String? ?? lotId.substring(0, 6);
              }
            })
        );
      }
      
      // Fetch session name if sessionId exists
      if (sessionId != null) {
        futures.add(
          FirebaseFirestore.instance
            .collection('cart_sessions')
            .doc(sessionId)
            .get()
            .then((doc) {
              if (doc.exists) {
                final data = doc.data()!;
                final interventionName = data['interventionName'] as String?;
                final locationText = data['locationText'] as String?;
                final startedAt = data['startedAt'] as Timestamp?;
                
                // Build a human-readable session name
                if (interventionName != null) {
                  String sessionName = interventionName;
                  if (locationText != null && locationText.isNotEmpty) {
                    sessionName += ' on $locationText';
                  }
                  if (startedAt != null) {
                    final date = startedAt.toDate();
                    final now = DateTime.now();
                    final difference = now.difference(date);
                    
                    if (difference.inDays == 0) {
                      final hour = date.hour.toString().padLeft(2, '0');
                      final minute = date.minute.toString().padLeft(2, '0');
                      sessionName += ' (Today $hour:$minute)';
                    } else if (difference.inDays == 1) {
                      sessionName += ' (Yesterday)';
                    } else if (difference.inDays < 7) {
                      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                      sessionName += ' (${days[date.weekday - 1]})';
                    } else {
                      final month = date.month.toString().padLeft(2, '0');
                      final day = date.day.toString().padLeft(2, '0');
                      sessionName += ' (${date.year}-$month-$day)';
                    }
                  }
                  _sessionName = sessionName;
                } else {
                  _sessionName = 'Session ${sessionId.substring(0, 8)}';
                }
              } else {
                _sessionName = 'Session ${sessionId.substring(0, 8)} (deleted)';
              }
            })
        );
      }
      
      await Future.wait(futures);
    } catch (e) {
      // Handle errors silently - show IDs as fallback
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final qtyUsed = widget.usage['qtyUsed'] ?? 0;
    final unit = widget.usage['unit'] ?? 'each';
    final usedAt = widget.usage['usedAt'] as Timestamp?;
    final sessionId = widget.usage['sessionId'] as String?;
    final lotId = widget.usage['lotId'] as String?;
    final interventionName = widget.usage['interventionName'] as String?;
    final grantId = widget.usage['grantId'] as String?;
    final notes = widget.usage['notes'] as String?;
    final operatorName = widget.usage['operatorName'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with quantity and date
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${qtyUsed.toString()} $unit used',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                if (usedAt != null)
                  Text(
                    _formatDateTime(usedAt.toDate()),
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            
            // Session information with loading state
            if (sessionId != null)
              _buildInfoRow(
                'Session', 
                _loading 
                  ? 'Loading...' 
                  : (_sessionName ?? sessionId), 
                Icons.shopping_cart
              ),
            
            // Lot information with loading state
            if (lotId != null)
              _buildInfoRow(
                'Lot', 
                _loading 
                  ? 'Loading...' 
                  : (_lotCode ?? lotId), 
                Icons.inventory_2
              ),
            
            // Intervention/Program
            if (interventionName != null)
              _buildInfoRow('Program', interventionName, Icons.medical_services),
            
            // Grant information
            if (grantId != null)
              _buildInfoRow('Grant', grantId, Icons.account_balance),
            
            // Operator - show if available and not a UUID
            () {
              String? displayName = operatorName;
              // Check if it looks like a UUID (Firebase UIDs are 28 chars)
              bool looksLikeUid = displayName != null && 
                  displayName.length >= 20 && 
                  RegExp(r'^[a-zA-Z0-9]+$').hasMatch(displayName);
              
              if (displayName == null || displayName.isEmpty || looksLikeUid || displayName.startsWith('User ')) {
                // Try fallback to current operator name
                displayName = OperatorStore.name.value;
              }
              if (displayName != null && displayName.isNotEmpty && !displayName.startsWith('User ')) {
                return _buildInfoRow('Operator', displayName, Icons.person);
              }
              return const SizedBox.shrink();
            }(),
            
            // Notes
            if (notes != null && notes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.note, size: 16, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text(
                            'Notes',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        notes,
                        style: const TextStyle(fontSize: 14),
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

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inDays == 0) {
      // Today - show time
      final hour = dateTime.hour.toString().padLeft(2, '0');
      final minute = dateTime.minute.toString().padLeft(2, '0');
      return 'Today $hour:$minute';
    } else if (difference.inDays == 1) {
      // Yesterday
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      // This week - show day of week
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[dateTime.weekday - 1];
    } else {
      // Older - show date
      final month = dateTime.month.toString().padLeft(2, '0');
      final day = dateTime.day.toString().padLeft(2, '0');
      return '${dateTime.year}-$month-$day';
    }
  }
}