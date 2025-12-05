// lib/features/audit/audit_logs_page.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// All known audit log types for filtering
class AuditLogTypes {
  static const all = 'All';
  
  // Item events
  static const itemCreate = 'item.create';
  static const itemCreated = 'item.created';
  static const itemUpdate = 'item.update';
  static const itemDelete = 'item.delete';
  static const itemQuickUse = 'item.quickUse';
  static const itemMerge = 'item.merge';
  static const itemRestore = 'item.restore';
  static const itemBarcodeAttach = 'item.attach_barcode';
  static const itemBarcodeRemove = 'item.barcode.remove';
  
  // Lot events
  static const lotCreate = 'lot.create';
  static const lotUpdate = 'lot.update';
  static const lotAdjust = 'lot.adjust';
  static const lotArchive = 'lot.archive';
  static const lotUnarchive = 'lot.unarchive';
  static const lotDelete = 'lot.delete';
  static const lotBarcodeScan = 'lot.barcode_scan';
  static const lotAddStock = 'lot.add_stock';
  static const lotWaste = 'lot.waste';
  static const lotUpdateAudit = 'lot.update_audit';
  
  // Inventory events
  static const inventoryBulkAdd = 'inventory.bulk_add';
  static const inventoryBulkAdjust = 'inventory_bulk_adjust';
  
  // Library events
  static const libraryItemCreate = 'library.item.create';
  static const libraryItemUpdate = 'library.item.update';
  static const libraryItemDelete = 'library.item.delete';
  static const libraryCheckout = 'library.checkout';
  static const libraryCheckin = 'library.checkin';
  static const libraryRestock = 'library.restock';
  
  // Session events
  static const sessionSave = 'session.save';
  static const sessionClose = 'session.close';
  
  // Config events
  static const configUpdate = 'config.timeTracking.update';
  
  // Undo events
  static const actionUndo = 'action.undo';
  
  /// Categories for grouping in the filter UI
  static const Map<String, List<String>> categories = {
    'Items': [itemCreate, itemCreated, itemUpdate, itemDelete, itemQuickUse, itemMerge, itemRestore, itemBarcodeAttach, itemBarcodeRemove],
    'Lots': [lotCreate, lotUpdate, lotAdjust, lotArchive, lotUnarchive, lotDelete, lotBarcodeScan, lotAddStock, lotWaste, lotUpdateAudit],
    'Inventory': [inventoryBulkAdd, inventoryBulkAdjust],
    'Library': [libraryItemCreate, libraryItemUpdate, libraryItemDelete, libraryCheckout, libraryCheckin, libraryRestock],
    'Sessions': [sessionSave, sessionClose],
    'Config': [configUpdate],
    'System': [actionUndo],
  };
  
  /// Get a friendly display name for a type
  static String displayName(String type) {
    switch (type) {
      case itemCreate: return 'Item Created';
      case itemCreated: return 'Item Created (Bulk)';
      case itemUpdate: return 'Item Updated';
      case itemDelete: return 'Item Deleted';
      case itemQuickUse: return 'Quick Use';
      case itemMerge: return 'Items Merged';
      case itemRestore: return 'Item Restored';
      case itemBarcodeAttach: return 'Barcode Attached';
      case itemBarcodeRemove: return 'Barcode Removed';
      case lotCreate: return 'Lot Created';
      case lotUpdate: return 'Lot Updated';
      case lotAdjust: return 'Lot Adjusted';
      case lotArchive: return 'Lot Archived';
      case lotUnarchive: return 'Lot Unarchived';
      case lotDelete: return 'Lot Deleted';
      case lotBarcodeScan: return 'Barcode Scanned';
      case lotAddStock: return 'Stock Added';
      case lotWaste: return 'Waste Recorded';
      case lotUpdateAudit: return 'Audit Update';
      case inventoryBulkAdd: return 'Bulk Add';
      case inventoryBulkAdjust: return 'Bulk Adjust';
      case libraryItemCreate: return 'Library Item Created';
      case libraryItemUpdate: return 'Library Item Updated';
      case libraryItemDelete: return 'Library Item Deleted';
      case libraryCheckout: return 'Checked Out';
      case libraryCheckin: return 'Checked In';
      case libraryRestock: return 'Restocked';
      case sessionSave: return 'Session Saved';
      case sessionClose: return 'Session Closed';
      case configUpdate: return 'Config Updated';
      case actionUndo: return 'Action Undone';
      default: return type.split('.').map((p) => p.isNotEmpty ? '${p[0].toUpperCase()}${p.substring(1)}' : p).join(' ');
    }
  }
}

class AuditLogsPage extends StatefulWidget {
  const AuditLogsPage({super.key});

  @override
  State<AuditLogsPage> createState() => _AuditLogsPageState();
}

class _AuditLogsPageState extends State<AuditLogsPage> {
  final Set<String> _selectedTypes = {}; // For multi-select filter
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit Logs'),
        actions: [
          if (_selectedTypes.isNotEmpty)
            TextButton.icon(
              onPressed: () => setState(() => _selectedTypes.clear()),
              icon: const Icon(Icons.clear),
              label: Text('Clear (${_selectedTypes.length})'),
            ),
          IconButton(
            icon: Badge(
              isLabelVisible: _selectedTypes.isNotEmpty,
              label: Text('${_selectedTypes.length}'),
              child: const Icon(Icons.filter_list),
            ),
            onPressed: () => _showFilterDialog(context),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _buildQuery().snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          // Client-side filter if multiple types selected (Firestore doesn't support OR queries well)
          final filteredDocs = _selectedTypes.isEmpty
              ? docs
              : docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final type = data['type'] as String? ?? '';
                  return _selectedTypes.contains(type);
                }).toList();

          if (filteredDocs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history, size: 64, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 16),
                  Text(
                    _selectedTypes.isEmpty ? 'No audit logs found' : 'No logs match the selected filters',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (_selectedTypes.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => setState(() => _selectedTypes.clear()),
                      child: const Text('Clear filters'),
                    ),
                  ],
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: filteredDocs.length,
            itemBuilder: (context, index) {
              final doc = filteredDocs[index];
              final data = doc.data() as Map<String, dynamic>;

              return _AuditLogTile(
                docId: doc.id,
                type: data['type'] as String? ?? 'Unknown',
                operatorName: data['operatorName'] as String?,
                createdAt: data['createdAt'] as Timestamp?,
                details: data['data'] as Map<String, dynamic>? ?? {},
                undoData: data['undoData'] as Map<String, dynamic>?,
                canUndo: data['canUndo'] as bool? ?? false,
                onUndo: () => _handleUndo(doc.id, data),
              );
            },
          );
        },
      ),
    );
  }
  
  Future<void> _handleUndo(String docId, Map<String, dynamic> auditData) async {
    final type = auditData['type'] as String? ?? '';
    final undoData = auditData['undoData'] as Map<String, dynamic>?;
    
    if (undoData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No undo data available for this action')),
      );
      return;
    }
    
    // Confirm undo
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Undo Action'),
        content: Text(
          'Are you sure you want to undo this ${AuditLogTypes.displayName(type)}?\n\n'
          'This will attempt to restore the previous state.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Undo'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    try {
      final db = FirebaseFirestore.instance;
      
      switch (type) {
        case 'item.merge':
          await _undoMerge(db, undoData);
          break;
        case 'item.delete':
        case 'lot.delete':
          await _undoDelete(db, type, undoData);
          break;
        case 'item.update':
        case 'lot.update':
        case 'lot.adjust':
          await _undoUpdate(db, type, undoData);
          break;
        default:
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Undo not supported for "$type"')),
          );
          return;
      }
      
      // Mark as undone in the audit log
      await db.collection('audit_logs').doc(docId).update({
        'canUndo': false,
        'undoneAt': FieldValue.serverTimestamp(),
      });
      
      // Log the undo action
      await db.collection('audit_logs').add({
        'type': 'action.undo',
        'data': {
          'originalAuditLogId': docId,
          'originalType': type,
        },
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Successfully undone!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Undo failed: $e')),
        );
      }
    }
  }
  
  Future<void> _undoMerge(FirebaseFirestore db, Map<String, dynamic> undoData) async {
    final primaryItem = undoData['primaryItem'] as Map<String, dynamic>?;
    final duplicateItems = (undoData['duplicateItems'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final movedLots = (undoData['movedLots'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final updatedUsageLogs = (undoData['updatedUsageLogs'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    
    if (primaryItem == null) throw Exception('No primary item data to restore');
    
    final primaryId = primaryItem['id'] as String;
    
    // 1. Restore the duplicate items (unarchive)
    for (final dupItem in duplicateItems) {
      final dupId = dupItem['id'] as String;
      await db.collection('items').doc(dupId).update({
        'archived': false,
        'mergedInto': FieldValue.delete(),
        'mergedAt': FieldValue.delete(),
        'qtyOnHand': dupItem['qtyOnHand'] ?? 0,
      });
    }
    
    // 2. Move lots back to their original items
    for (final lotInfo in movedLots) {
      final originalItemId = lotInfo['originalItemId'] as String;
      final lotId = lotInfo['lotId'] as String;
      final lotData = (lotInfo['lotData'] as Map<String, dynamic>?) ?? {};
      
      // Recreate the lot in the original item
      await db
          .collection('items')
          .doc(originalItemId)
          .collection('lots')
          .doc(lotId)
          .set(lotData);
      
      // Find and delete the merged lot from primary (it has a modified ID)
      final mergedLots = await db
          .collection('items')
          .doc(primaryId)
          .collection('lots')
          .where('originalLotId', isEqualTo: lotId)
          .get();
      
      for (final mergedLot in mergedLots.docs) {
        await mergedLot.reference.delete();
      }
    }
    
    // 3. Restore usage logs to point to original items
    for (final logInfo in updatedUsageLogs) {
      final logId = logInfo['logId'] as String;
      final originalItemId = logInfo['originalItemId'] as String;
      
      await db.collection('usage_logs').doc(logId).update({
        'itemId': originalItemId,
        'originalItemId': FieldValue.delete(),
        'mergedAt': FieldValue.delete(),
      });
    }
    
    // 4. Restore primary item's original barcodes and qty
    final originalBarcodes = undoData['primaryItemOriginalBarcodes'];
    final originalBarcode = undoData['primaryItemOriginalBarcode'];
    final originalQty = undoData['primaryItemOriginalQty'];
    
    await db.collection('items').doc(primaryId).update({
      'barcodes': originalBarcodes,
      'barcode': originalBarcode,
      'qtyOnHand': originalQty ?? 0,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
  
  Future<void> _undoDelete(FirebaseFirestore db, String type, Map<String, dynamic> undoData) async {
    // For item or lot deletion, restore from backup
    final backup = undoData['backup'] as Map<String, dynamic>?;
    if (backup == null) throw Exception('No backup data found');
    
    if (type == 'item.delete') {
      final itemId = undoData['itemId'] as String?;
      if (itemId != null) {
        await db.collection('items').doc(itemId).set(backup);
      }
    } else if (type == 'lot.delete') {
      final itemId = undoData['itemId'] as String?;
      final lotId = undoData['lotId'] as String?;
      if (itemId != null && lotId != null) {
        await db.collection('items').doc(itemId).collection('lots').doc(lotId).set(backup);
      }
    }
  }
  
  Future<void> _undoUpdate(FirebaseFirestore db, String type, Map<String, dynamic> undoData) async {
    final previousValues = undoData['previousValues'] as Map<String, dynamic>?;
    if (previousValues == null) throw Exception('No previous values found');
    
    if (type == 'item.update') {
      final itemId = undoData['itemId'] as String?;
      if (itemId != null) {
        await db.collection('items').doc(itemId).update(previousValues);
      }
    } else if (type == 'lot.update' || type == 'lot.adjust') {
      final itemId = undoData['itemId'] as String?;
      final lotId = undoData['lotId'] as String?;
      if (itemId != null && lotId != null) {
        await db.collection('items').doc(itemId).collection('lots').doc(lotId).update(previousValues);
      }
    }
  }

  Query<Map<String, dynamic>> _buildQuery() {
    // Always fetch all logs and filter client-side to avoid needing composite indexes
    return FirebaseFirestore.instance
        .collection('audit_logs')
        .orderBy('createdAt', descending: true)
        .limit(500);
  }

  void _showFilterDialog(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) => Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outline.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Text('Filter by Type', style: Theme.of(context).textTheme.titleLarge),
                    const Spacer(),
                    if (_selectedTypes.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          setSheetState(() => _selectedTypes.clear());
                          setState(() {});
                        },
                        child: const Text('Clear All'),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Category list
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: AuditLogTypes.categories.entries.map((entry) {
                    final category = entry.key;
                    final types = entry.value;
                    final selectedInCategory = types.where((t) => _selectedTypes.contains(t)).length;
                    
                    return ExpansionTile(
                      title: Text(category),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (selectedInCategory > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: cs.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '$selectedInCategory',
                                style: TextStyle(color: cs.onPrimaryContainer, fontSize: 12),
                              ),
                            ),
                          const SizedBox(width: 8),
                          const Icon(Icons.expand_more),
                        ],
                      ),
                      children: types.map((type) {
                        final isSelected = _selectedTypes.contains(type);
                        return CheckboxListTile(
                          title: Text(AuditLogTypes.displayName(type)),
                          subtitle: Text(type, style: TextStyle(fontSize: 11, color: cs.outline)),
                          value: isSelected,
                          onChanged: (checked) {
                            setSheetState(() {
                              if (checked == true) {
                                _selectedTypes.add(type);
                              } else {
                                _selectedTypes.remove(type);
                              }
                            });
                            setState(() {});
                          },
                        );
                      }).toList(),
                    );
                  }).toList(),
                ),
              ),
              // Apply button
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(_selectedTypes.isEmpty ? 'Show All' : 'Apply Filter (${_selectedTypes.length})'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuditLogTile extends StatelessWidget {
  final String docId;
  final String type;
  final String? operatorName;
  final Timestamp? createdAt;
  final Map<String, dynamic> details;
  final Map<String, dynamic>? undoData;
  final bool canUndo;
  final VoidCallback? onUndo;

  const _AuditLogTile({
    required this.docId,
    required this.type,
    required this.operatorName,
    required this.createdAt,
    required this.details,
    this.undoData,
    this.canUndo = false,
    this.onUndo,
  });

  @override
  Widget build(BuildContext context) {
    final dateTime = createdAt?.toDate();
    final formattedDate = dateTime != null
        ? DateFormat('MMM dd, yyyy • HH:mm').format(dateTime)
        : 'Unknown time';

    final icon = _getIconForType(type);
    final color = _getColorForType(type);
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.2),
          child: Icon(icon, color: color),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                AuditLogTypes.displayName(type),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            if (canUndo && undoData != null)
              IconButton(
                icon: Icon(Icons.undo, size: 20, color: cs.primary),
                tooltip: 'Undo this action',
                onPressed: onUndo,
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'By: ${operatorName ?? 'Unknown'} • $formattedDate',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              _formatDetails(details),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        onTap: () => _showDetailsDialog(context),
      ),
    );
  }

  IconData _getIconForType(String type) {
    if (type.contains('create') || type.contains('created')) return Icons.add_circle;
    if (type.contains('delete')) return Icons.delete;
    if (type.contains('update') || type.contains('adjust') || type.contains('audit')) return Icons.edit;
    if (type.contains('archive')) return Icons.archive;
    if (type.contains('unarchive')) return Icons.unarchive;
    if (type.contains('checkout')) return Icons.output;
    if (type.contains('checkin')) return Icons.input;
    if (type.contains('restock') || type.contains('add_stock')) return Icons.add_shopping_cart;
    if (type.contains('waste')) return Icons.delete_sweep;
    if (type.contains('barcode') || type.contains('scan')) return Icons.qr_code;
    if (type.contains('merge')) return Icons.merge;
    if (type.contains('quickUse')) return Icons.flash_on;
    if (type.contains('session')) return Icons.shopping_cart;
    if (type.contains('library')) return Icons.medical_services;
    if (type.contains('undo')) return Icons.undo;
    if (type.startsWith('item.')) return Icons.inventory;
    if (type.startsWith('lot.')) return Icons.warehouse;
    if (type.startsWith('config')) return Icons.settings;
    return Icons.history;
  }

  Color _getColorForType(String type) {
    if (type.contains('create') || type.contains('created')) return Colors.green;
    if (type.contains('delete')) return Colors.red;
    if (type.contains('waste')) return Colors.red.shade300;
    if (type.contains('update') || type.contains('edit') || type.contains('adjust')) return Colors.blue;
    if (type.contains('archive')) return Colors.orange;
    if (type.contains('unarchive')) return Colors.teal;
    if (type.contains('checkout')) return Colors.purple;
    if (type.contains('checkin')) return Colors.indigo;
    if (type.contains('restock') || type.contains('add_stock')) return Colors.lightGreen;
    if (type.contains('merge')) return Colors.deepPurple;
    if (type.contains('quickUse')) return Colors.amber;
    if (type.contains('undo')) return Colors.cyan;
    return Colors.grey;
  }

  String _formatDetails(Map<String, dynamic> details) {
    final parts = <String>[];

    // Prefer showing name over ID
    if (details.containsKey('name') && details['name'] != null) {
      final name = details['name'].toString();
      parts.add('Item: $name');
    } else if (details.containsKey('itemName') && details['itemName'] != null) {
      final name = details['itemName'].toString();
      parts.add('Item: $name');
    } else if (details.containsKey('itemId') && details['itemId'] != null) {
      // Only show ID if no name is available
      final id = details['itemId'].toString();
      parts.add('Item ID: ${id.length > 8 ? '${id.substring(0, 8)}...' : id}');
    }
    
    // Library item name
    if (details.containsKey('libraryItemName') && details['libraryItemName'] != null) {
      parts.add('Kit: ${details['libraryItemName']}');
    }
    
    // Lot code
    if (details.containsKey('lotCode') && details['lotCode'] != null) {
      parts.add('Lot: ${details['lotCode']}');
    }
    
    // Quantity info
    if (details.containsKey('qty')) {
      parts.add('Qty: ${details['qty']}');
    } else if (details.containsKey('qtyUsed')) {
      parts.add('Used: ${details['qtyUsed']}');
    } else if (details.containsKey('qtyRemaining')) {
      parts.add('Remaining: ${details['qtyRemaining']}');
    } else if (details.containsKey('qtyAdded')) {
      parts.add('Added: ${details['qtyAdded']}');
    }
    
    // Barcode
    if (details.containsKey('barcode') && details['barcode'] != null) {
      final bc = details['barcode'].toString();
      parts.add('Barcode: ${bc.length > 12 ? '${bc.substring(0, 12)}...' : bc}');
    }
    
    // Checked out to
    if (details.containsKey('checkedOutTo') && details['checkedOutTo'] != null) {
      parts.add('To: ${details['checkedOutTo']}');
    }
    
    // Reason
    if (details.containsKey('reason') && details['reason'] != null) {
      parts.add('Reason: ${details['reason']}');
    }

    return parts.isNotEmpty ? parts.join(' • ') : 'No details';
  }

  void _showDetailsDialog(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    showDialog(
      context: context,
      builder: (context) => Theme(
        data: Theme.of(context),
        child: AlertDialog(
          title: Row(
            children: [
              Icon(_getIconForType(type), color: _getColorForType(type)),
              const SizedBox(width: 8),
              Expanded(child: Text(AuditLogTypes.displayName(type))),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _DetailRow(label: 'Type', value: type),
                _DetailRow(label: 'Operator', value: operatorName ?? 'Unknown'),
                _DetailRow(
                  label: 'Time',
                  value: createdAt?.toDate() != null
                      ? DateFormat('MMM dd, yyyy HH:mm:ss').format(createdAt!.toDate())
                      : 'Unknown',
                ),
                const Divider(height: 24),
                Text('Details:', style: TextStyle(fontWeight: FontWeight.bold, color: cs.primary)),
                const SizedBox(height: 8),
                ...details.entries.map((entry) => _DetailRow(
                  label: _formatKey(entry.key),
                  value: _formatValue(entry.value),
                )),
                if (details.isEmpty)
                  Text('No additional details', style: TextStyle(color: cs.onSurfaceVariant, fontStyle: FontStyle.italic)),
                if (canUndo && undoData != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: cs.onPrimaryContainer, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'This action can be undone',
                            style: TextStyle(fontSize: 12, color: cs.onPrimaryContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (canUndo && undoData != null)
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  onUndo?.call();
                },
                child: const Text('Undo'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
  
  String _formatKey(String key) {
    // Convert camelCase to Title Case
    final result = key.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (m) => '${m.group(1)} ${m.group(2)}',
    );
    return result[0].toUpperCase() + result.substring(1);
  }
  
  String _formatValue(dynamic value) {
    if (value == null) return 'N/A';
    if (value is Timestamp) {
      return DateFormat('MMM dd, yyyy HH:mm').format(value.toDate());
    }
    if (value is List) {
      return value.join(', ');
    }
    if (value is Map) {
      return value.entries.map((e) => '${e.key}: ${e.value}').join(', ');
    }
    return value.toString();
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(color: cs.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}
