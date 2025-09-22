import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:scout/features/items/new_item_page.dart';
import '../dashboard/dashboard_page.dart';
import '../items/item_detail_page.dart';
import '../lookups_management_page.dart';
import '../../services/search_service.dart';
import '../../data/lookups_service.dart';
import '../../models/option_item.dart';
import '../../utils/audit.dart';
import '../../services/label_export_service.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../dev/seed_lookups.dart';

enum SortOption { updatedDesc, nameAsc, nameDesc, categoryAsc, categoryDesc, qtyAsc, qtyDesc, expirationAsc, expirationDesc }
enum ViewMode { active, archived }

class ItemsPage extends StatefulWidget {
  final SearchFilters? initialFilters;
  final bool isFromDashboard;
  
  const ItemsPage({super.key, this.initialFilters, this.isFromDashboard = false});
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
  late SearchFilters _filters;
  SortOption _sortOption = SortOption.updatedDesc;
  ViewMode _viewMode = ViewMode.active;
  bool _selectionMode = false;
  bool _showAdvancedFilters = false;
  final Set<String> _selectedIds = {};
  int _refreshCounter = 0; // Counter to force refresh after operations

  @override
  void initState() {
    super.initState();
    _filters = widget.initialFilters ?? const SearchFilters();
  }

  @override
  Widget build(BuildContext context) {
    // Get sort field name
    final sortField = switch (_sortOption) {
      SortOption.updatedDesc => 'updatedAt',
      SortOption.nameAsc || SortOption.nameDesc => 'name',
      SortOption.categoryAsc || SortOption.categoryDesc => 'category',
      SortOption.qtyAsc || SortOption.qtyDesc => 'qtyOnHand',
      SortOption.expirationAsc || SortOption.expirationDesc => 'earliestExpiresAt',
    };

    final sortDescending = switch (_sortOption) {
      SortOption.updatedDesc || SortOption.nameDesc || SortOption.categoryDesc || SortOption.qtyDesc || SortOption.expirationDesc => true,
      SortOption.nameAsc || SortOption.categoryAsc || SortOption.qtyAsc || SortOption.expirationAsc => false,
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
            IconButton(
              icon: const Icon(Icons.label),
              tooltip: 'Export Labels',
              onPressed: _selectedIds.isEmpty ? null : _exportLabels,
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
                      builder: (_) => Theme(
                        data: Theme.of(context),
                        child: AlertDialog(
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
                  } else if (key == 'manage-lookups') {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LookupsManagementPage()),
                    );
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
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'manage-lookups', child: Text('Manage Lookups')),
              ],
              icon: const Icon(Icons.settings),
            ),
          ],
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(_showAdvancedFilters ? 500 : 100),
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
                        DropdownMenuItem(value: SortOption.expirationAsc, child: Text('Expiration (Soonest)')),
                        DropdownMenuItem(value: SortOption.expirationDesc, child: Text('Expiration (Latest)')),
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
          showAllItems: widget.isFromDashboard,
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
              final expirationDate = data['earliestExpiresAt'] != null ? (data['earliestExpiresAt'] as Timestamp).toDate() : null;
              
              // Determine expiration status
              Color? tileColor;
              if (expirationDate != null) {
                final now = DateTime.now();
                final daysUntilExpiration = expirationDate.difference(now).inDays;
                if (expirationDate.isBefore(now)) {
                  tileColor = Colors.red.withValues(alpha:0.1); // Expired - red
                } else if (daysUntilExpiration <= 14) {
                  tileColor = Colors.yellow.withValues(alpha:.1); // Expiring within 2 weeks - yellow
                }
              }

              return ListTile(
                tileColor: tileColor,
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
                          if (action == 'edit') {
                            final result = await Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => NewItemPage(
                                itemId: d.id,
                                existingItem: data,
                              ),
                            ));
                            if (result == true) {
                              setState(() => _refreshCounter++);
                            }
                          } else if (action == 'delete') {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (_) => Theme(
                                data: Theme.of(context),
                                child: AlertDialog(
                                  title: const Text('Delete Item'),
                                  content: Text('Delete "$name"? This cannot be undone.'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                    FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                                  ],
                                ),
                              ),
                            );
                            if (ok == true) {
                              await _db.collection('items').doc(d.id).delete();
                              
                              // Log the item deletion
                              await Audit.log('item.delete', {
                                'itemId': d.id,
                                'name': name,
                                'category': data['category'],
                                'baseUnit': data['baseUnit'],
                                'qtyOnHand': data['qtyOnHand'],
                              });
                              
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
                          const PopupMenuItem(value: 'edit', child: Text('Edit Item')),
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
      builder: (_) => Theme(
        data: Theme.of(context),
        child: AlertDialog(
          title: const Text('Delete Items'),
          content: Text('Delete $count selected items? This cannot be undone.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
          ],
        ),
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      // First, collect item data for audit logging before deletion
      final itemsData = <String, Map<String, dynamic>>{};
      for (final id in _selectedIds) {
        try {
          final doc = await _db.collection('items').doc(id).get();
          if (doc.exists) {
            itemsData[id] = doc.data()!;
          }
        } catch (e) {
          debugPrint('Failed to fetch data for item $id: $e');
        }
      }
      
      final batch = _db.batch();
      for (final id in _selectedIds) {
        batch.delete(_db.collection('items').doc(id));
      }
      await batch.commit();
      
      // Log bulk item deletions
      for (final id in _selectedIds) {
        final data = itemsData[id];
        if (data != null) {
          await Audit.log('item.delete', {
            'itemId': id,
            'name': data['name'] ?? 'Unknown',
            'category': data['category'],
            'baseUnit': data['baseUnit'],
            'qtyOnHand': data['qtyOnHand'],
            'bulkDelete': true,
          });
        } else {
          await Audit.log('item.delete', {
            'itemId': id,
            'bulkDelete': true,
            'error': 'Could not fetch item data before deletion',
          });
        }
      }
      
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

  Future<void> _exportLabels() async {
    final ctx = context;
    setState(() => _busy = true);
    try {
      // Get lots data for selected items
      final lotsData = await LabelExportService.getLotsForItems(_selectedIds.toList());

      if (lotsData.isEmpty) {
        if (!ctx.mounted) return;
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('No lots found for selected items')),
        );
        return;
      }

      // Generate PDF
      final pdfBytes = await LabelExportService.generateLabels(lotsData);

      // Export based on platform
      if (kIsWeb) {
        // Web: Direct download (not supported in WASM)
        await LabelExportService.exportLabels(lotsData);
      } else {
        // Mobile: Save to temp file and share
        final tempDir = await getTemporaryDirectory();
        final fileName = 'item_labels_${DateTime.now().millisecondsSinceEpoch}.pdf';
        final file = File('${tempDir.path}/$fileName');
        await file.writeAsBytes(pdfBytes);

        // Share the file
        await Share.shareXFiles(
          [XFile(file.path, name: fileName)],
          text: 'Item Labels PDF',
        );
      }

      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text('Generated labels for ${lotsData.length} lots')),
      );
    } catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text('Failed to export labels: $e')),
      );
    } finally {
      setState(() => _busy = false);
    }
  }

  Widget _buildAdvancedFilters() {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        _db.collection('items').where('archived', isEqualTo: _viewMode == ViewMode.archived).get(),
        LookupsService().locations(),
        LookupsService().grants(),
      ]),
      key: ValueKey('filters_$_viewMode$_refreshCounter'),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        
        final itemsSnap = snap.data![0] as QuerySnapshot;
        final locations = snap.data![1] as List<OptionItem>;
        final grants = snap.data![2] as List<OptionItem>;
        
        final categories = <String>{};
        final baseUnits = <String>{};
        final locationIds = <String>{};
        final grantIds = <String>{};
        final useTypes = <String>{};
        double maxQty = 0;
        int totalItems = itemsSnap.docs.length;
        
        for (final doc in itemsSnap.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final category = (data['category'] ?? '') as String;
          final baseUnit = (data['baseUnit'] ?? '') as String;
          final locationId = (data['homeLocationId'] ?? '') as String;
          final grantId = (data['grantId'] ?? '') as String;
          final useType = (data['useType'] ?? '') as String;
          final qty = (data['qtyOnHand'] ?? 0) as num;
          
          if (category.isNotEmpty) categories.add(category);
          if (baseUnit.isNotEmpty) baseUnits.add(baseUnit);
          if (locationId.isNotEmpty) locationIds.add(locationId);
          if (grantId.isNotEmpty) grantIds.add(grantId);
          if (useType.isNotEmpty) useTypes.add(useType);
          if (qty > maxQty) maxQty = qty.toDouble();
        }
        
        final categoryList = categories.toList()..sort();
        final baseUnitList = baseUnits.toList()..sort();
        
        // Create location name mappings
        final locationMap = <String, String>{};
        for (final loc in locations) {
          if (locationIds.contains(loc.id)) {
            locationMap[loc.id] = loc.name;
          }
        }
        final locationList = locationMap.values.toList()..sort();
        
        // Create grant name mappings
        final grantMap = <String, String>{};
        for (final grant in grants) {
          if (grantIds.contains(grant.id)) {
            grantMap[grant.id] = grant.name;
          }
        }
        final grantList = grantMap.values.toList()..sort();
        
        final useTypeList = useTypes.toList()..sort();
        
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Advanced Filters ($totalItems items)', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setState(() => _filters = const SearchFilters()),
                      child: const Text('Clear All'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // Search query and basic filters
                if (totalItems > 10) ...[
                  _buildFilterSection(
                    title: 'Quick Filters',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilterChip(
                          label: const Text('Low Stock'),
                          selected: _filters.hasLowStock ?? false,
                          onSelected: (selected) => setState(() => _filters = _filters.copyWith(hasLowStock: selected ? true : null)),
                        ),
                        FilterChip(
                          label: const Text('Has Lots'),
                          selected: _filters.hasLots ?? false,
                          onSelected: (selected) => setState(() => _filters = _filters.copyWith(hasLots: selected ? true : null)),
                        ),
                        FilterChip(
                          label: const Text('Has Barcode'),
                          selected: _filters.hasBarcode ?? false,
                          onSelected: (selected) => setState(() => _filters = _filters.copyWith(hasBarcode: selected ? true : null)),
                        ),
                        FilterChip(
                          label: const Text('Has Min Qty'),
                          selected: _filters.hasMinQty ?? false,
                          onSelected: (selected) => setState(() => _filters.copyWith(hasMinQty: selected ? true : null)),
                        ),
                        FilterChip(
                          label: const Text('Expiring Soon'),
                          selected: _filters.hasExpiringSoon ?? false,
                          onSelected: (selected) => setState(() => _filters = _filters.copyWith(hasExpiringSoon: selected ? true : null)),
                        ),
                        FilterChip(
                          label: const Text('Expired'),
                          selected: _filters.hasExpired ?? false,
                          onSelected: (selected) => setState(() => _filters = _filters.copyWith(hasExpired: selected ? true : null)),
                        ),
                        FilterChip(
                          label: const Text('Stale'),
                          selected: _filters.hasStale ?? false,
                          onSelected: (selected) => setState(() => _filters = _filters.copyWith(hasStale: selected ? true : null)),
                        ),
                        FilterChip(
                          label: const Text('Excess Stock'),
                          selected: _filters.hasExcess ?? false,
                          onSelected: (selected) => setState(() => _filters = _filters.copyWith(hasExcess: selected ? true : null)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Categories
                if (categoryList.isNotEmpty) ...[
                  _buildFilterSection(
                    title: 'Categories (${categoryList.length})',
                    child: _buildExpandableChipList(
                      items: categoryList,
                      selectedItems: _filters.categories,
                      onSelectionChanged: (selected, category) {
                        setState(() {
                          final newCategories = Set<String>.from(_filters.categories);
                          if (selected) {
                            newCategories.add(category);
                          } else {
                            newCategories.remove(category);
                          }
                          _filters = _filters.copyWith(categories: newCategories);
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Units and Quantity
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (baseUnitList.isNotEmpty) 
                      Expanded(
                        child: _buildFilterSection(
                          title: 'Units (${baseUnitList.length})',
                          child: _buildExpandableChipList(
                            items: baseUnitList,
                            selectedItems: _filters.baseUnits,
                            maxVisible: 6,
                            onSelectionChanged: (selected, unit) {
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
                          ),
                        ),
                      ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildFilterSection(
                        title: 'Quantity Range',
                        child: Column(
                          children: [
                            RangeSlider(
                              values: _filters.qtyRange ?? RangeValues(0, maxQty),
                              min: 0,
                              max: maxQty,
                              divisions: maxQty > 0 ? (maxQty / 10).ceil() : 1,
                              labels: RangeLabels(
                                (_filters.qtyRange?.start ?? 0).toStringAsFixed(0),
                                (_filters.qtyRange?.end ?? maxQty).toStringAsFixed(0),
                              ),
                              onChanged: (values) => setState(() => _filters = _filters.copyWith(qtyRange: values.start == 0 && values.end == maxQty ? null : values)),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('0', style: Theme.of(context).textTheme.bodySmall),
                                Text(maxQty.toStringAsFixed(0), style: Theme.of(context).textTheme.bodySmall),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Locations and Grants
                if (locationList.isNotEmpty || grantList.isNotEmpty) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (locationList.isNotEmpty)
                        Expanded(
                          child: _buildFilterSection(
                            title: 'Locations (${locationList.length})',
                            child: _buildExpandableChipList(
                              items: locationList,
                              selectedItems: _filters.locationIds.map((id) => locationMap.entries.firstWhere((e) => e.key == id, orElse: () => MapEntry('', '')).value).where((name) => name.isNotEmpty).toSet(),
                              maxVisible: 4,
                              onSelectionChanged: (selected, locationName) {
                                // Find the ID for this location name
                                final locationId = locationMap.entries.firstWhere((e) => e.value == locationName).key;
                                setState(() {
                                  final newLocationIds = Set<String>.from(_filters.locationIds);
                                  if (selected) {
                                    newLocationIds.add(locationId);
                                  } else {
                                    newLocationIds.remove(locationId);
                                  }
                                  _filters = _filters.copyWith(locationIds: newLocationIds);
                                });
                              },
                            ),
                          ),
                        ),
                      if (locationList.isNotEmpty && grantList.isNotEmpty)
                        const SizedBox(width: 16),
                      if (grantList.isNotEmpty)
                        Expanded(
                          child: _buildFilterSection(
                            title: 'Grants (${grantList.length})',
                            child: _buildExpandableChipList(
                              items: grantList,
                              selectedItems: _filters.grantIds.map((id) => grantMap.entries.firstWhere((e) => e.key == id, orElse: () => MapEntry('', '')).value).where((name) => name.isNotEmpty).toSet(),
                              maxVisible: 4,
                              onSelectionChanged: (selected, grantName) {
                                // Find the ID for this grant name
                                final grantId = grantMap.entries.firstWhere((e) => e.value == grantName).key;
                                setState(() {
                                  final newGrantIds = Set<String>.from(_filters.grantIds);
                                  if (selected) {
                                    newGrantIds.add(grantId);
                                  } else {
                                    newGrantIds.remove(grantId);
                                  }
                                  _filters = _filters.copyWith(grantIds: newGrantIds);
                                });
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // Use Types
                if (useTypeList.isNotEmpty) ...[
                  _buildFilterSection(
                    title: 'Usage Types',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: useTypeList.map((useType) => FilterChip(
                        label: Text(_formatUseType(useType)),
                        selected: _filters.useTypes.contains(useType),
                        onSelected: (selected) {
                          setState(() {
                            final newUseTypes = Set<String>.from(_filters.useTypes);
                            if (selected) {
                              newUseTypes.add(useType);
                            } else {
                              newUseTypes.remove(useType);
                            }
                            _filters = _filters.copyWith(useTypes: newUseTypes);
                          });
                        },
                      )).toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilterSection({required String title, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _buildExpandableChipList({
    required List<String> items,
    required Set<String> selectedItems,
    required Function(bool, String) onSelectionChanged,
    int maxVisible = 8,
  }) {
    final showAll = items.length <= maxVisible;
    final visibleItems = showAll ? items : items.take(maxVisible).toList();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: visibleItems.map((item) => FilterChip(
            label: Text(item, style: const TextStyle(fontSize: 12)),
            selected: selectedItems.contains(item),
            onSelected: (selected) => onSelectionChanged(selected, item),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          )).toList(),
        ),
        if (!showAll) ...[
          const SizedBox(height: 4),
          TextButton(
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Select Items'),
                  content: SizedBox(
                    width: double.maxFinite,
                    height: 300,
                    child: ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return CheckboxListTile(
                          title: Text(item),
                          value: selectedItems.contains(item),
                          onChanged: (selected) {
                            onSelectionChanged(selected ?? false, item);
                          },
                          dense: true,
                        );
                      },
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text('+ ${items.length - maxVisible} more', style: const TextStyle(fontSize: 12)),
          ),
        ],
      ],
    );
  }

  String _formatUseType(String useType) {
    switch (useType.toLowerCase()) {
      case 'staff': return 'Staff Only';
      case 'patient': return 'Patient Only';
      case 'both': return 'Staff & Patient';
      default: return useType;
    }
  }
}
