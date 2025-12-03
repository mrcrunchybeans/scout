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
  
  /// Categories for grouping in the filter UI
  static const Map<String, List<String>> categories = {
    'Items': [itemCreate, itemCreated, itemUpdate, itemDelete, itemQuickUse, itemMerge, itemBarcodeAttach, itemBarcodeRemove],
    'Lots': [lotCreate, lotUpdate, lotAdjust, lotArchive, lotUnarchive, lotDelete, lotBarcodeScan, lotAddStock, lotWaste, lotUpdateAudit],
    'Inventory': [inventoryBulkAdd, inventoryBulkAdjust],
    'Library': [libraryItemCreate, libraryItemUpdate, libraryItemDelete, libraryCheckout, libraryCheckin, libraryRestock],
    'Sessions': [sessionSave, sessionClose],
    'Config': [configUpdate],
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
                type: data['type'] as String? ?? 'Unknown',
                operatorName: data['operatorName'] as String?,
                createdAt: data['createdAt'] as Timestamp?,
                details: data['data'] as Map<String, dynamic>? ?? {},
              );
            },
          );
        },
      ),
    );
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
  final String type;
  final String? operatorName;
  final Timestamp? createdAt;
  final Map<String, dynamic> details;

  const _AuditLogTile({
    required this.type,
    required this.operatorName,
    required this.createdAt,
    required this.details,
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
        title: Text(
          AuditLogTypes.displayName(type),
          style: Theme.of(context).textTheme.titleSmall,
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
                  Text('No additional details', style: TextStyle(color: cs.outline, fontStyle: FontStyle.italic)),
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
              style: TextStyle(color: cs.outline, fontWeight: FontWeight.w500),
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
