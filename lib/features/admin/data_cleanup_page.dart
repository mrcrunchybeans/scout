import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Admin tool to analyze and clean up item data:
/// - Find potential duplicate items
/// - Standardize category names
/// - Clean up item name formatting
class DataCleanupPage extends StatefulWidget {
  const DataCleanupPage({super.key});

  @override
  State<DataCleanupPage> createState() => _DataCleanupPageState();
}

class _DataCleanupPageState extends State<DataCleanupPage> with SingleTickerProviderStateMixin {
  final _db = FirebaseFirestore.instance;
  late TabController _tabController;
  
  bool _loading = false;
  List<Map<String, dynamic>> _items = [];
  List<_DuplicateGroup> _duplicates = [];
  Map<String, List<Map<String, dynamic>>> _categoryGroups = {};
  List<_NameIssue> _nameIssues = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _analyzeData() async {
    setState(() => _loading = true);
    
    try {
      // Load all non-archived items
      final snapshot = await _db.collection('items')
          .where('archived', isNotEqualTo: true)
          .get();
      
      _items = snapshot.docs.map((doc) => {
        'id': doc.id,
        ...doc.data(),
      }).toList();
      
      // Also get items without archived field
      final snapshot2 = await _db.collection('items')
          .limit(1000)
          .get();
      
      final allItems = <String, Map<String, dynamic>>{};
      for (final doc in snapshot2.docs) {
        final data = doc.data();
        if (data['archived'] != true) {
          allItems[doc.id] = {'id': doc.id, ...data};
        }
      }
      _items = allItems.values.toList();
      
      _findDuplicates();
      _analyzeCategories();
      _analyzeNames();
      
      setState(() => _loading = false);
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _findDuplicates() {
    // Normalize names for comparison
    String normalize(String s) => s.toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '')
        .replaceAll(RegExp(r'\s+'), '');
    
    // Group by normalized name
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final item in _items) {
      final name = item['name'] as String? ?? '';
      final norm = normalize(name);
      if (norm.isEmpty) continue;
      groups.putIfAbsent(norm, () => []).add(item);
    }
    
    // Find groups with multiple items (potential duplicates)
    _duplicates = groups.entries
        .where((e) => e.value.length > 1)
        .map((e) => _DuplicateGroup(
          normalizedName: e.key,
          items: e.value,
        ))
        .toList();
    
    // Sort by group size (largest first)
    _duplicates.sort((a, b) => b.items.length.compareTo(a.items.length));
  }

  void _analyzeCategories() {
    _categoryGroups = {};
    
    for (final item in _items) {
      final category = item['category'] as String? ?? '';
      if (category.isEmpty) {
        _categoryGroups.putIfAbsent('(No Category)', () => []).add(item);
      } else {
        _categoryGroups.putIfAbsent(category, () => []).add(item);
      }
    }
  }

  void _analyzeNames() {
    _nameIssues = [];
    
    for (final item in _items) {
      final name = item['name'] as String? ?? '';
      final issues = <String>[];
      
      // Check for ALL CAPS
      if (name == name.toUpperCase() && name.length > 3) {
        issues.add('ALL CAPS');
      }
      
      // Check for very long category (likely API junk)
      final category = item['category'] as String? ?? '';
      if (category.length > 50) {
        issues.add('Long category (${category.length} chars)');
      }
      
      // Check for comma-separated category (API junk)
      if (category.contains(',')) {
        issues.add('Multi-value category');
      }
      
      // Check for special characters in name
      if (RegExp(r'[®™©]').hasMatch(name)) {
        issues.add('Has trademark symbols');
      }
      
      // Check for leading/trailing whitespace
      if (name != name.trim()) {
        issues.add('Has extra whitespace');
      }
      
      if (issues.isNotEmpty) {
        _nameIssues.add(_NameIssue(item: item, issues: issues));
      }
    }
    
    // Sort by number of issues
    _nameIssues.sort((a, b) => b.issues.length.compareTo(a.issues.length));
  }

  String _toTitleCase(String s) {
    if (s.isEmpty) return s;
    return s.split(' ').map((word) {
      if (word.isEmpty) return word;
      // Keep short words lowercase (unless first word)
      if (word.length <= 2 && !['a', 'an', 'the', 'of', 'in', 'on', 'at', 'to', 'for'].contains(word.toLowerCase())) {
        return word;
      }
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  Future<void> _fixItemName(Map<String, dynamic> item) async {
    final currentName = item['name'] as String? ?? '';
    final suggestedName = _toTitleCase(currentName.trim());
    
    final controller = TextEditingController(text: suggestedName);
    
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fix Item Name'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current: $currentName', style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'New Name',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    
    if (newName != null && newName.isNotEmpty && newName != currentName) {
      await _db.collection('items').doc(item['id']).update({
        'name': newName,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Updated: $newName')),
        );
        _analyzeData(); // Refresh
      }
    }
  }

  Future<void> _fixItemCategory(Map<String, dynamic> item) async {
    final currentCategory = item['category'] as String? ?? '';
    
    // Get existing categories for suggestions
    final existingCategories = _categoryGroups.keys
        .where((c) => c != '(No Category)' && c.length < 50 && !c.contains(','))
        .toList()
      ..sort();
    
    final controller = TextEditingController(text: currentCategory);
    String? selectedCategory = existingCategories.contains(currentCategory) ? currentCategory : null;
    
    final newCategory = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Fix Category'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Item: ${item['name']}'),
                const SizedBox(height: 8),
                Text('Current: $currentCategory', 
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Select existing category',
                    border: OutlineInputBorder(),
                  ),
                  items: existingCategories.map((c) => DropdownMenuItem(
                    value: c,
                    child: Text(c, overflow: TextOverflow.ellipsis),
                  )).toList(),
                  onChanged: (v) {
                    setDialogState(() {
                      selectedCategory = v;
                      if (v != null) {
                        controller.text = v;
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'Or enter new category',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    // Clear dropdown selection when typing custom value
                    if (v != selectedCategory) {
                      setDialogState(() => selectedCategory = null);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    
    if (newCategory != null && newCategory.isNotEmpty && newCategory != currentCategory) {
      await _db.collection('items').doc(item['id']).update({
        'category': newCategory,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Category updated to "$newCategory"')),
        );
        _analyzeData(); // Refresh
      }
    }
  }

  Future<void> _mergeItems(_DuplicateGroup group) async {
    // Show dialog to select primary item and confirm merge
    Map<String, dynamic>? primaryItem;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Merge Duplicate Items'),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Select the PRIMARY item to keep.\n\nAll lots, barcodes, and usage history from duplicates will be merged into this item:'),
                const SizedBox(height: 16),
                ...group.items.map((item) => RadioListTile<Map<String, dynamic>>(
                  value: item,
                  groupValue: primaryItem,
                  title: Text(item['name'] ?? 'Unnamed'),
                  subtitle: Text(
                    'Category: ${item['category'] ?? 'None'}\n'
                    'Qty: ${item['qtyOnHand'] ?? 0} • Barcodes: ${_formatBarcodes(item)}\n'
                    'ID: ${(item['id'] as String).substring(0, 8)}...',
                  ),
                  onChanged: (v) => setDialogState(() => primaryItem = v),
                )),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This will:\n'
                          '• Move all lots to the primary item\n'
                          '• Merge all barcodes\n'
                          '• Update usage history references\n'
                          '• Archive the duplicate items',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: primaryItem == null ? null : () => Navigator.pop(ctx, true),
              child: const Text('Merge'),
            ),
          ],
        ),
      ),
    );
    
    if (confirmed != true || primaryItem == null) return;
    
    setState(() => _loading = true);
    
    try {
      final primaryId = primaryItem!['id'] as String;
      final duplicateIds = group.items
          .where((item) => item['id'] != primaryId)
          .map((item) => item['id'] as String)
          .toList();
      
      // Collect all barcodes from all items
      final allBarcodes = <String>{};
      for (final item in group.items) {
        final barcodes = item['barcodes'] as List<dynamic>? ?? [];
        for (final b in barcodes) {
          if (b is String && b.isNotEmpty) allBarcodes.add(b);
        }
        final singleBarcode = item['barcode'] as String?;
        if (singleBarcode != null && singleBarcode.isNotEmpty) {
          allBarcodes.add(singleBarcode);
        }
      }
      
      int lotsMoved = 0;
      int usageLogsUpdated = 0;
      
      // Process each duplicate item
      for (final duplicateId in duplicateIds) {
        // 1. Move all lots from duplicate to primary
        final lotsSnapshot = await _db
            .collection('items')
            .doc(duplicateId)
            .collection('lots')
            .get();
        
        for (final lotDoc in lotsSnapshot.docs) {
          final lotData = lotDoc.data();
          
          // Create the lot under the primary item
          await _db
              .collection('items')
              .doc(primaryId)
              .collection('lots')
              .doc(lotDoc.id)
              .set({
            ...lotData,
            'mergedFrom': duplicateId,
            'mergedAt': FieldValue.serverTimestamp(),
          });
          
          // Delete from the duplicate (or mark as moved)
          await lotDoc.reference.delete();
          lotsMoved++;
        }
        
        // 2. Update usage_logs to point to primary item
        final usageLogsSnapshot = await _db
            .collection('usage_logs')
            .where('itemId', isEqualTo: duplicateId)
            .get();
        
        final batch = _db.batch();
        for (final logDoc in usageLogsSnapshot.docs) {
          batch.update(logDoc.reference, {
            'itemId': primaryId,
            'originalItemId': duplicateId, // Keep reference to original
            'mergedAt': FieldValue.serverTimestamp(),
          });
          usageLogsUpdated++;
        }
        if (usageLogsSnapshot.docs.isNotEmpty) {
          await batch.commit();
        }
        
        // 3. Update audit_logs references (optional, for history)
        final auditLogsSnapshot = await _db
            .collection('audit_logs')
            .where('data.itemId', isEqualTo: duplicateId)
            .limit(500)
            .get();
        
        if (auditLogsSnapshot.docs.isNotEmpty) {
          final auditBatch = _db.batch();
          for (final logDoc in auditLogsSnapshot.docs) {
            final data = logDoc.data();
            final logData = Map<String, dynamic>.from(data['data'] as Map? ?? {});
            logData['itemId'] = primaryId;
            logData['originalItemId'] = duplicateId;
            auditBatch.update(logDoc.reference, {'data': logData});
          }
          await auditBatch.commit();
        }
      }
      
      // 4. Update the primary item with merged barcodes and recalculate qty
      // First, get all lots to recalculate qtyOnHand
      final primaryLotsSnapshot = await _db
          .collection('items')
          .doc(primaryId)
          .collection('lots')
          .get();
      
      num totalQty = 0;
      for (final lotDoc in primaryLotsSnapshot.docs) {
        final lotData = lotDoc.data();
        if (lotData['archived'] != true) {
          totalQty += (lotData['qtyRemaining'] as num?) ?? 0;
        }
      }
      
      // If no lots, sum up qtyOnHand from all items
      if (primaryLotsSnapshot.docs.isEmpty) {
        for (final item in group.items) {
          totalQty += (item['qtyOnHand'] as num?) ?? 0;
        }
      }
      
      await _db.collection('items').doc(primaryId).update({
        'barcodes': allBarcodes.toList(),
        'barcode': allBarcodes.isNotEmpty ? allBarcodes.first : null,
        'qtyOnHand': totalQty,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      // 5. Archive the duplicate items
      final archiveBatch = _db.batch();
      for (final duplicateId in duplicateIds) {
        archiveBatch.update(_db.collection('items').doc(duplicateId), {
          'archived': true,
          'mergedInto': primaryId,
          'mergedAt': FieldValue.serverTimestamp(),
          'qtyOnHand': 0, // Clear qty since lots were moved
        });
      }
      await archiveBatch.commit();
      
      // 6. Log the merge operation
      await _db.collection('audit_logs').add({
        'type': 'item.merge',
        'data': {
          'primaryItemId': primaryId,
          'primaryItemName': primaryItem!['name'],
          'mergedItemIds': duplicateIds,
          'lotsMoved': lotsMoved,
          'usageLogsUpdated': usageLogsUpdated,
          'barcodesConsolidated': allBarcodes.length,
        },
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Merged ${duplicateIds.length} items into "${primaryItem!['name']}"\n'
              '$lotsMoved lots moved, $usageLogsUpdated usage logs updated, ${allBarcodes.length} barcodes consolidated'
            ),
            duration: const Duration(seconds: 5),
          ),
        );
        await _analyzeData(); // Refresh
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Merge failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }
  
  String _formatBarcodes(Map<String, dynamic> item) {
    final barcodes = <String>[];
    final list = item['barcodes'] as List<dynamic>? ?? [];
    for (final b in list) {
      if (b is String && b.isNotEmpty) barcodes.add(b);
    }
    final single = item['barcode'] as String?;
    if (single != null && single.isNotEmpty && !barcodes.contains(single)) {
      barcodes.add(single);
    }
    if (barcodes.isEmpty) return 'None';
    if (barcodes.length == 1) return barcodes.first;
    return '${barcodes.length} codes';
  }

  Future<void> _bulkFixCategory(String oldCategory, String newCategory) async {
    final items = _categoryGroups[oldCategory] ?? [];
    if (items.isEmpty) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bulk Update Category'),
        content: Text(
          'Update ${items.length} items from:\n'
          '"$oldCategory"\n\n'
          'to:\n'
          '"$newCategory"?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Update All'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      final batch = _db.batch();
      for (final item in items) {
        batch.update(_db.collection('items').doc(item['id']), {
          'category': newCategory.isEmpty ? null : newCategory,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Updated ${items.length} items')),
        );
        _analyzeData(); // Refresh
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Cleanup'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Duplicates (${_duplicates.length})'),
            Tab(text: 'Categories (${_categoryGroups.length})'),
            Tab(text: 'Name Issues (${_nameIssues.length})'),
          ],
        ),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _analyzeData,
              tooltip: 'Analyze Data',
            ),
        ],
      ),
      body: _items.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.analytics_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('Click the refresh button to analyze your items'),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _analyzeData,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start Analysis'),
                  ),
                ],
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _buildDuplicatesTab(),
                _buildCategoriesTab(),
                _buildNameIssuesTab(),
              ],
            ),
    );
  }

  Widget _buildDuplicatesTab() {
    if (_duplicates.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
            SizedBox(height: 16),
            Text('No duplicate items found!'),
          ],
        ),
      );
    }
    
    return ListView.builder(
      itemCount: _duplicates.length,
      itemBuilder: (context, index) {
        final group = _duplicates[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ExpansionTile(
            title: Text('${group.items.length} items: "${group.items.first['name']}"'),
            subtitle: Text('Normalized: ${group.normalizedName}'),
            children: [
              ...group.items.map((item) => ListTile(
                title: Text(item['name'] ?? 'Unnamed'),
                subtitle: Text(
                  'Category: ${item['category'] ?? 'None'} • Qty: ${item['qtyOnHand'] ?? 0}\n'
                  'Barcodes: ${_formatBarcodes(item)}',
                ),
                trailing: Text(
                  (item['id'] as String).substring(0, 8),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                isThreeLine: true,
              )),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: () => _mergeItems(group),
                  icon: const Icon(Icons.merge),
                  label: const Text('Merge These Items'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCategoriesTab() {
    final sortedCategories = _categoryGroups.entries.toList()
      ..sort((a, b) {
        // Put problematic categories first
        final aProblematic = a.key.length > 50 || a.key.contains(',');
        final bProblematic = b.key.length > 50 || b.key.contains(',');
        if (aProblematic && !bProblematic) return -1;
        if (!aProblematic && bProblematic) return 1;
        return b.value.length.compareTo(a.value.length);
      });
    
    return ListView.builder(
      itemCount: sortedCategories.length,
      itemBuilder: (context, index) {
        final entry = sortedCategories[index];
        final category = entry.key;
        final items = entry.value;
        final isProblematic = category.length > 50 || category.contains(',');
        
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          color: isProblematic ? Colors.orange.shade50 : null,
          child: ExpansionTile(
            leading: isProblematic 
                ? const Icon(Icons.warning, color: Colors.orange)
                : null,
            title: Text(
              category.length > 60 ? '${category.substring(0, 60)}...' : category,
              style: TextStyle(
                fontWeight: isProblematic ? FontWeight.bold : null,
              ),
            ),
            subtitle: Text('${items.length} items'),
            children: [
              if (isProblematic)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Full category: $category', style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          FilledButton.icon(
                            onPressed: () async {
                              final controller = TextEditingController();
                              final newCat = await showDialog<String>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('New Category Name'),
                                  content: TextField(
                                    controller: controller,
                                    decoration: const InputDecoration(
                                      labelText: 'Category',
                                      border: OutlineInputBorder(),
                                    ),
                                    autofocus: true,
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: const Text('Cancel'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                                      child: const Text('Update All'),
                                    ),
                                  ],
                                ),
                              );
                              if (newCat != null) {
                                await _bulkFixCategory(category, newCat);
                              }
                            },
                            icon: const Icon(Icons.edit),
                            label: const Text('Fix Category'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ...items.take(10).map((item) => ListTile(
                dense: true,
                title: Text(item['name'] ?? 'Unnamed'),
                trailing: IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: () => _fixItemCategory(item),
                ),
              )),
              if (items.length > 10)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('...and ${items.length - 10} more', 
                    style: const TextStyle(color: Colors.grey)),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNameIssuesTab() {
    if (_nameIssues.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
            SizedBox(height: 16),
            Text('No naming issues found!'),
          ],
        ),
      );
    }
    
    return ListView.builder(
      itemCount: _nameIssues.length,
      itemBuilder: (context, index) {
        final issue = _nameIssues[index];
        final item = issue.item;
        
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            title: Text(item['name'] ?? 'Unnamed'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Category: ${item['category'] ?? 'None'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Wrap(
                  spacing: 4,
                  children: issue.issues.map((i) => Chip(
                    label: Text(i, style: const TextStyle(fontSize: 10)),
                    backgroundColor: Colors.orange.shade100,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  )).toList(),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (issue.issues.contains('ALL CAPS') || 
                    issue.issues.contains('Has extra whitespace'))
                  IconButton(
                    icon: const Icon(Icons.auto_fix_high),
                    onPressed: () => _fixItemName(item),
                    tooltip: 'Fix Name',
                  ),
                if (issue.issues.any((i) => i.contains('category')))
                  IconButton(
                    icon: const Icon(Icons.category),
                    onPressed: () => _fixItemCategory(item),
                    tooltip: 'Fix Category',
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DuplicateGroup {
  final String normalizedName;
  final List<Map<String, dynamic>> items;
  
  _DuplicateGroup({required this.normalizedName, required this.items});
}

class _NameIssue {
  final Map<String, dynamic> item;
  final List<String> issues;
  
  _NameIssue({required this.item, required this.issues});
}
