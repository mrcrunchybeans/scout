import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:scout/features/items/new_item_page.dart';
import '../dashboard/dashboard_page.dart';
import '../items/item_detail_page.dart';
import '../../services/search_service.dart';

import '../../dev/seed_lookups.dart';

enum SortOption { updatedDesc, nameAsc, nameDesc, categoryAsc, categoryDesc, qtyAsc, qtyDesc }
enum ViewMode { active, archived }

class ItemsPage extends StatefulWidget {
  const ItemsPage({super.key});
  @override
  State<ItemsPage> createState() => _ItemsPageState();
}

class _ItemsPageState extends State<ItemsPage> {
  final _db = FirebaseFirestore.instance;
  final _searchService = SearchService(
    FirebaseFirestore.instance,
    const SearchConfig(
      strategy: SearchStrategy.hybrid, // Temporarily use hybrid search to bypass Algolia issues
      enableAlgolia: true, // Keep Algolia enabled for when index is populated
       algoliaAppId: 'COMHTF4QM1',
       algoliaSearchApiKey: '86a6aa6baaa3bbfc8e5e75c0c272fa00',
       algoliaWriteApiKey: '3ca7664f0aaf7555ab3c43bd179d17d8',
       algoliaIndexName: 'scout_items',
    ),
  );
  bool _busy = false;
  SearchFilters _filters = const SearchFilters();
  SortOption _sortOption = SortOption.updatedDesc;
  ViewMode _viewMode = ViewMode.active;
  bool _selectionMode = false;
  bool _showAdvancedFilters = false;
  final Set<String> _selectedIds = {};
  int _refreshCounter = 0; // Counter to force refresh after operations

  @override
  Widget build(BuildContext context) {
    // Get sort field name
    final sortField = switch (_sortOption) {
      SortOption.updatedDesc => 'updatedAt',
      SortOption.nameAsc || SortOption.nameDesc => 'name',
      SortOption.categoryAsc || SortOption.categoryDesc => 'category',
      SortOption.qtyAsc || SortOption.qtyDesc => 'qtyOnHand',
    };

    final sortDescending = switch (_sortOption) {
      SortOption.updatedDesc || SortOption.nameDesc || SortOption.categoryDesc || SortOption.qtyDesc => true,
      SortOption.nameAsc || SortOption.categoryAsc || SortOption.qtyAsc => false,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('SCOUT — Items'),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          if (_selectionMode) ...[
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _selectedIds.isEmpty ? null : _bulkDelete,
            ),
            IconButton(
              icon: Icon(_viewMode == ViewMode.active ? Icons.archive : Icons.unarchive),
              onPressed: _selectedIds.isEmpty ? null : _bulkArchive,
            ),
            Text('${_selectedIds.length} selected'),
          ] else ...[
            IconButton(
  tooltip: 'Dashboard',
  icon: const Icon(Icons.dashboard_outlined),
  onPressed: () {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DashboardPage()));
  },
),
            PopupMenuButton<String>(
              tooltip: 'Tools',
              enabled: !_busy,
              onSelected: (key) async {
                setState(() => _busy = true);
                try {
                  if (key == 'seed-once') {
                    await seedLookups();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Seeded (only empty collections).')),
                    );
                  } else if (key == 'reseed-merge') {
                    await reseedLookupsMerge();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Lookups upserted by code.')),
                    );
                  } else if (key == 'reset-seed') {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Reset & seed lookups?'),
                        content: const Text('This will DELETE all lookup docs, then reseed.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Reset'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await resetAndSeedLookups();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Lookups reset & seeded.')),
                      );
                    }
                  } else if (key == 'sync-algolia') {
                    setState(() => _busy = true);
                    try {
                      await _searchService.syncItemsToAlgolia();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Items synced to Algolia successfully')),
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to sync to Algolia: $e')),
                      );
                    } finally {
                      setState(() => _busy = false);
                    }
                  } else if (key == 'toggle-view') {
                    setState(() => _viewMode = _viewMode == ViewMode.active ? ViewMode.archived : ViewMode.active);
                  } else if (key == 'bulk-edit') {
                    setState(() => _selectionMode = true);
                  }
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(value: 'toggle-view', child: Text('Show ${_viewMode == ViewMode.active ? 'Archived' : 'Active'}')),
                const PopupMenuItem(value: 'bulk-edit', child: Text('Bulk Edit')),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'sync-algolia', child: Text('Sync to Algolia')),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'seed-once', child: Text('Seed (only if empty)')),
                const PopupMenuItem(value: 'reseed-merge', child: Text('Reseed (merge by code)')),
                const PopupMenuItem(value: 'reset-seed', child: Text('Reset & seed (destructive)')),
              ],
              icon: const Icon(Icons.settings),
            ),
          ],
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(_showAdvancedFilters ? 300 : 100),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search items...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.qr_code_scanner),
                      onPressed: _scanBarcode,
                      tooltip: 'Scan barcode',
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() => _filters = _filters.copyWith(query: value.trim())),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Sort: '),
                    DropdownButton<SortOption>(
                      value: _sortOption,
                      items: const [
                        DropdownMenuItem(value: SortOption.updatedDesc, child: Text('Recent')),
                        DropdownMenuItem(value: SortOption.nameAsc, child: Text('Name (A-Z)')),
                        DropdownMenuItem(value: SortOption.nameDesc, child: Text('Name (Z-A)')),
                        DropdownMenuItem(value: SortOption.categoryAsc, child: Text('Category (A-Z)')),
                        DropdownMenuItem(value: SortOption.categoryDesc, child: Text('Category (Z-A)')),
                        DropdownMenuItem(value: SortOption.qtyAsc, child: Text('Quantity (Low-High)')),
                        DropdownMenuItem(value: SortOption.qtyDesc, child: Text('Quantity (High-Low)')),
                      ],
                      onChanged: (value) => setState(() => _sortOption = value!),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => setState(() => _showAdvancedFilters = !_showAdvancedFilters),
                      icon: Icon(_showAdvancedFilters ? Icons.filter_list_off : Icons.filter_list),
                      label: Text(_showAdvancedFilters ? 'Hide Filters' : 'Advanced Filters'),
                    ),
                  ],
                ),
                if (_showAdvancedFilters) ...[
                  const SizedBox(height: 8),
                  _buildAdvancedFilters(),
                ],
              ],
            ),
          ),
        ),
      ),

      floatingActionButton: _selectionMode
          ? FloatingActionButton(
              onPressed: () => setState(() {
                _selectionMode = false;
                _selectedIds.clear();
              }),
              child: const Icon(Icons.close),
            )
          : FloatingActionButton.extended(
              heroTag: 'new',
              onPressed: () async {
                final ctx = context;
                final created = await Navigator.of(ctx).push<bool>(
                  MaterialPageRoute(builder: (_) => const NewItemPage()),
                );
                if (!ctx.mounted) return;
                if (created == true) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Item created')),
                  );
                }
              },
              label: const Text('New item'),
              icon: const Icon(Icons.add_box),
            ),

      body: FutureBuilder<SearchResult>(
        key: ValueKey('${_filters.hashCode}_${_viewMode}_${sortField}_$sortDescending$_refreshCounter'),
        future: _searchService.searchItems(
          filters: _filters,
          showArchived: _viewMode == ViewMode.archived,
          sortField: sortField,
          sortDescending: sortDescending,
          limit: 1000,
        ),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Search error: ${snap.error}'));
          }
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          final result = snap.data!;
          final docs = result.documents;
          
          if (docs.isEmpty) {
            // Nicer empty state that nudges to create the first item
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.inventory_2_outlined, size: 56),
                    const SizedBox(height: 12),
                    Text('No ${_viewMode == ViewMode.active ? 'active' : 'archived'} items', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    const Text('Tap “New item” to add your first inventory item.'),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      icon: const Icon(Icons.add_box),
                      label: const Text('New item'),
                      onPressed: () async {
                        final ctx = context;
                        final created = await Navigator.of(ctx).push<bool>(
                          MaterialPageRoute(builder: (_) => const NewItemPage()),
                        );
                        if (!ctx.mounted) return;
                        if (created == true) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('Item created')),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final d = docs[i];
              final data = d.data() as Map<String, dynamic>;
              final name = (data['name'] ?? 'Unnamed') as String;
              final category = (data['category'] ?? '') as String;
              final qty = (data['qtyOnHand'] ?? 0);
              final minQty = (data['minQty'] ?? 0);
              final hasLots = (data['lots'] != null && (data['lots'] as List?)?.isNotEmpty == true);

              return ListTile(
                leading: _selectionMode
                    ? Checkbox(
                        value: _selectedIds.contains(d.id),
                        onChanged: (selected) {
                          setState(() {
                            if (selected == true) {
                              _selectedIds.add(d.id);
                            } else {
                              _selectedIds.remove(d.id);
                            }
                          });
                        },
                      )
                    : null,
                title: Text(name),
                subtitle: Text('${category.isNotEmpty ? '$category • ' : ''}Qty: $qty • Min: $minQty${hasLots ? ' • Has lots' : ''}'),
                onTap: _selectionMode
                    ? () {
                        setState(() {
                          if (_selectedIds.contains(d.id)) {
                            _selectedIds.remove(d.id);
                          } else {
                            _selectedIds.add(d.id);
                          }
                        });
                      }
                    : () {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => ItemDetailPage(itemId: d.id, itemName: name),
                        ));
                      },
                onLongPress: !_selectionMode
                    ? () => setState(() => _selectionMode = true)
                    : null,
                trailing: _selectionMode
                    ? null
                    : PopupMenuButton<String>(
                        onSelected: (action) async {
                          if (action == 'delete') {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text('Delete Item'),
                                content: Text('Delete "$name"? This cannot be undone.'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                  FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                                ],
                              ),
                            );
                            if (ok == true) {
                              await _db.collection('items').doc(d.id).delete();
                              // Also sync the deletion to Algolia if configured
                              try {
                                await _searchService.syncItemToAlgolia(d.id);
                              } catch (e) {
                                // Algolia sync failure shouldn't block the UI
                                debugPrint('Failed to sync deletion to Algolia: $e');
                              }
                              setState(() => _refreshCounter++); // Force refresh
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Deleted "$name"')));
                            }
                          } else if (action == 'archive') {
                            await _db.collection('items').doc(d.id).update({'archived': _viewMode == ViewMode.active});
                            // Sync the update to Algolia
                            try {
                              await _searchService.syncItemToAlgolia(d.id);
                            } catch (e) {
                              debugPrint('Failed to sync archive to Algolia: $e');
                            }
                            setState(() => _refreshCounter++); // Force refresh
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_viewMode == ViewMode.active ? 'Archived' : 'Unarchived'} "$name"')));
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'archive', child: Text('Archive/Unarchive')),
                          const PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _scanBarcode() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Scan Barcode')),
          body: MobileScanner(
            onDetect: (capture) {
              final barcodes = capture.barcodes;
              if (barcodes.isNotEmpty) {
                final code = barcodes.first.rawValue;
                if (code != null) {
                  Navigator.of(context).pop(code);
                }
              }
            },
          ),
        ),
      ),
    );

    if (result != null) {
      setState(() => _filters = _filters.copyWith(query: result));
    }
  }

  Future<void> _bulkDelete() async {
    final ctx = context;
    final count = _selectedIds.length;
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Delete Items'),
        content: Text('Delete $count selected items? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final batch = _db.batch();
      for (final id in _selectedIds) {
        batch.delete(_db.collection('items').doc(id));
      }
      await batch.commit();
      
      // Sync deletions to Algolia
      for (final id in _selectedIds) {
        try {
          await _searchService.syncItemToAlgolia(id);
        } catch (e) {
          debugPrint('Failed to sync deletion to Algolia for $id: $e');
        }
      }
      
      setState(() {
        _selectionMode = false;
        _selectedIds.clear();
        _refreshCounter++; // Force refresh
      });
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Deleted $count items')));
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _bulkArchive() async {
    final ctx = context;
    final count = _selectedIds.length;
    final archiving = _viewMode == ViewMode.active;
    setState(() => _busy = true);
    try {
      final batch = _db.batch();
      for (final id in _selectedIds) {
        batch.update(_db.collection('items').doc(id), {'archived': archiving});
      }
      await batch.commit();
      setState(() {
        _selectionMode = false;
        _selectedIds.clear();
        _refreshCounter++; // Force refresh
      });
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('${archiving ? 'Archived' : 'Unarchived'} $count items')));
    } finally {
      setState(() => _busy = false);
    }
  }

  Widget _buildAdvancedFilters() {
    return FutureBuilder<QuerySnapshot>(
      future: _db.collection('items').where('archived', isEqualTo: _viewMode == ViewMode.archived).get(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        
        final categories = <String>{};
        final baseUnits = <String>{};
        double maxQty = 0;
        
        for (final doc in snap.data!.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final category = (data['category'] ?? '') as String;
          final baseUnit = (data['baseUnit'] ?? '') as String;
          final qty = (data['qtyOnHand'] ?? 0) as num;
          
          if (category.isNotEmpty) categories.add(category);
          if (baseUnit.isNotEmpty) baseUnits.add(baseUnit);
          if (qty > maxQty) maxQty = qty.toDouble();
        }
        
        final categoryList = categories.toList()..sort();
        final baseUnitList = baseUnits.toList()..sort();
        
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('Filters', style: TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setState(() => _filters = const SearchFilters()),
                      child: const Text('Clear All'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (categoryList.isNotEmpty) ...[
                  const Text('Categories:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  Wrap(
                    spacing: 8,
                    children: categoryList.map((cat) => FilterChip(
                      label: Text(cat),
                      selected: _filters.categories.contains(cat),
                      onSelected: (selected) {
                        setState(() {
                          final newCategories = Set<String>.from(_filters.categories);
                          if (selected) {
                            newCategories.add(cat);
                          } else {
                            newCategories.remove(cat);
                          }
                          _filters = _filters.copyWith(categories: newCategories);
                        });
                      },
                    )).toList(),
                  ),
                  const SizedBox(height: 12),
                ],
                if (baseUnitList.isNotEmpty) ...[
                  const Text('Units:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  Wrap(
                    spacing: 8,
                    children: baseUnitList.map((unit) => FilterChip(
                      label: Text(unit),
                      selected: _filters.baseUnits.contains(unit),
                      onSelected: (selected) {
                        setState(() {
                          final newBaseUnits = Set<String>.from(_filters.baseUnits);
                          if (selected) {
                            newBaseUnits.add(unit);
                          } else {
                            newBaseUnits.remove(unit);
                          }
                          _filters = _filters.copyWith(baseUnits: newBaseUnits);
                        });
                      },
                    )).toList(),
                  ),
                  const SizedBox(height: 12),
                ],
                const Text('Quantity Range:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                RangeSlider(
                  values: _filters.qtyRange ?? RangeValues(0, maxQty),
                  min: 0,
                  max: maxQty,
                  divisions: maxQty > 0 ? maxQty.toInt() : 1,
                  labels: RangeLabels(
                    (_filters.qtyRange?.start ?? 0).toStringAsFixed(0),
                    (_filters.qtyRange?.end ?? maxQty).toStringAsFixed(0),
                  ),
                  onChanged: (values) => setState(() => _filters = _filters.copyWith(qtyRange: values)),
                ),
                const SizedBox(height: 8),
                // First row of checkboxes
                Row(
                  children: [
                    Expanded(
                      child: CheckboxListTile(
                        title: const Text('Low Stock Only', style: TextStyle(fontSize: 14)),
                        value: _filters.hasLowStock ?? false,
                        onChanged: (value) => setState(() => _filters = _filters.copyWith(hasLowStock: value)),
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                      ),
                    ),
                    Expanded(
                      child: CheckboxListTile(
                        title: const Text('Has Lots', style: TextStyle(fontSize: 14)),
                        value: _filters.hasLots ?? false,
                        onChanged: (value) => setState(() => _filters = _filters.copyWith(hasLots: value)),
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                      ),
                    ),
                  ],
                ),
                // Second row of checkboxes
                Row(
                  children: [
                    Expanded(
                      child: CheckboxListTile(
                        title: const Text('Has Barcode', style: TextStyle(fontSize: 14)),
                        value: _filters.hasBarcode ?? false,
                        onChanged: (value) => setState(() => _filters = _filters.copyWith(hasBarcode: value)),
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                      ),
                    ),
                    Expanded(
                      child: CheckboxListTile(
                        title: const Text('Has Min Qty', style: TextStyle(fontSize: 14)),
                        value: _filters.hasMinQty ?? false,
                        onChanged: (value) => setState(() => _filters = _filters.copyWith(hasMinQty: value)),
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
