// lib/features/items/bulk_inventory_entry_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../widgets/scanner_sheet.dart';
import '../../widgets/usb_wedge_scanner.dart';
import '../../utils/audit.dart';
import '../../data/product_enrichment_service.dart';

class BulkInventoryEntryPage extends StatefulWidget {
  const BulkInventoryEntryPage({super.key});

  @override
  State<BulkInventoryEntryPage> createState() => _BulkInventoryEntryPageState();
}

class _BulkInventoryEntryPageState extends State<BulkInventoryEntryPage> {
  final _db = FirebaseFirestore.instance;
  final _barcodeController = TextEditingController();
  final _barcodeFocus = FocusNode();

  // Scanned items with quantities to add
  final Map<String, BulkEntryItem> _pendingItems = {};
  bool _isProcessing = false;
  final List<String> _createdBatchCodes = [];
  int _batchCounter = 0;

  String _generateBatchCode() {
    final now = DateTime.now();
    final yy = now.year.toString().substring(2); // Last 2 digits of year
    final mm = now.month.toString().padLeft(2, '0'); // Month with leading zero
    // Use sequential counter for uniqueness (001, 002, 003, etc.)
    _batchCounter++;
    final xxx = _batchCounter.toString().padLeft(3, '0');
    return '$yy$mm-$xxx';
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _barcodeFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bulk Inventory Entry'),
        actions: [
          if (_pendingItems.isNotEmpty)
            TextButton(
              onPressed: _isProcessing ? null : _processAllEntries,
              child: Text('Process All (${_pendingItems.length})'),
            ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _showScannerSheet,
            tooltip: 'Scan barcode',
          ),
        ],
      ),
      body: Column(
        children: [
          // Scan input area
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Column(
              children: [
                TextField(
                  controller: _barcodeController,
                  focusNode: _barcodeFocus,
                  decoration: InputDecoration(
                    labelText: 'Scan or enter barcode',
                    border: const OutlineInputBorder(),
                    prefixIcon: IconButton(
                      icon: const Icon(Icons.qr_code),
                      onPressed: _showScannerSheet,
                      tooltip: 'Scan barcode',
                    ),
                  ),
                  onSubmitted: _handleBarcode,
                ),
                const SizedBox(height: 8),
                UsbWedgeScanner(
                  enabled: true,
                  allow: (_) => _barcodeFocus.hasFocus || _barcodeController.text.isEmpty,
                  onCode: _handleBarcode,
                ),
              ],
            ),
          ),

          // Pending items list
          Expanded(
            child: _pendingItems.isEmpty
                ? _buildEmptyState()
                : _buildPendingItemsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 80,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'Scan items to add to inventory',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Use barcode scanner or enter barcodes manually',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPendingItemsList() {
    return ListView.builder(
      itemCount: _pendingItems.length,
      itemBuilder: (context, index) {
        final entry = _pendingItems.values.elementAt(index);
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: entry.isNew ? Colors.green : Colors.blue,
              child: Icon(
                entry.isNew ? Icons.add : Icons.inventory,
                color: Colors.white,
              ),
            ),
            title: Row(
              children: [
                Expanded(child: Text(entry.itemName)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    entry.batchCode ?? 'No Code',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Text('${entry.barcode} • ${entry.quantity} ${entry.baseUnit}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.label),
                  tooltip: 'Edit batch code',
                  onPressed: () => _editBatchCode(entry),
                ),
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => _editQuantity(entry),
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () => _removeItem(entry.barcode),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleBarcode(String barcode) async {
    if (barcode.isEmpty || _pendingItems.containsKey(barcode)) return;

    setState(() => _isProcessing = true);

    try {
      // Check if item exists
      final itemQuery = await _db
          .collection('items')
          .where('barcode', isEqualTo: barcode)
          .limit(1)
          .get();

      if (itemQuery.docs.isNotEmpty) {
        final itemDoc = itemQuery.docs.first;
        final itemData = itemDoc.data();
        itemData['id'] = itemDoc.id;

        final entry = BulkEntryItem(
          barcode: barcode,
          itemId: itemDoc.id,
          itemName: itemData['name'] ?? 'Unknown Item',
          baseUnit: itemData['baseUnit'] ?? 'each',
          isNew: false,
          quantity: 1, // Default to 1, user can edit
          batchCode: _generateBatchCode(),
        );

        setState(() {
          _pendingItems[barcode] = entry;
        });
      } else {
        // New item - show quick add dialog
        await _showQuickAddNewItemDialog(barcode);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error checking barcode: $e')),
        );
      }
    } finally {
      setState(() => _isProcessing = false);
      _barcodeController.clear();
    }
  }

  Future<void> _showQuickAddNewItemDialog(String barcode) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => QuickAddNewItemDialog(barcode: barcode),
    );

    if (result != null && mounted) {
      final entry = BulkEntryItem(
        barcode: barcode,
        itemId: '', // Will be set after creation
        itemName: result['name'],
        baseUnit: result['baseUnit'],
        isNew: true,
        quantity: result['quantity'],
        newItemData: result,
        batchCode: _generateBatchCode(),
      );

      setState(() {
        _pendingItems[barcode] = entry;
      });
    }
  }

  Future<void> _editQuantity(BulkEntryItem entry) async {
    final result = await showDialog<double>(
      context: context,
      builder: (context) => EditQuantityDialog(
        currentQuantity: entry.quantity,
        baseUnit: entry.baseUnit,
        itemName: entry.itemName,
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _pendingItems[entry.barcode] = entry.copyWith(quantity: result);
      });
    }
  }

  void _removeItem(String barcode) {
    setState(() {
      _pendingItems.remove(barcode);
    });
  }

  Future<void> _editBatchCode(BulkEntryItem entry) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => EditBatchCodeDialog(
        currentCode: entry.batchCode ?? '',
        itemName: entry.itemName,
      ),
    );

    if (result != null && result.isNotEmpty && mounted) {
      setState(() {
        _pendingItems[entry.barcode] = entry.copyWith(batchCode: result);
      });
    }
  }

  Future<void> _processAllEntries() async {
    if (_pendingItems.isEmpty) return;

    setState(() => _isProcessing = true);
    _createdBatchCodes.clear();

    try {
      // Process new items first
      final newItems = _pendingItems.values.where((item) => item.isNew).toList();
      for (final item in newItems) {
        if (item.newItemData == null || item.batchCode == null) continue;

        // Create the new item
        final itemRef = _db.collection('items').doc();
        await itemRef.set({
          ...item.newItemData!,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Update the entry with the new item ID
        item.itemId = itemRef.id;
        _createdBatchCodes.add(item.batchCode!);

        // Create initial lot with the pre-assigned batch code
        final lotRef = itemRef.collection('lots').doc();
        await lotRef.set({
          'lotCode': item.batchCode,
          'qtyRemaining': item.quantity,
          'baseUnit': item.baseUnit,
          'expiresAt': null,
          'openAt': null,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Log audit
        await Audit.log('item.created', {
          'itemId': itemRef.id,
          'itemName': item.itemName,
          'barcode': item.barcode,
          'initialQuantity': item.quantity,
          'baseUnit': item.baseUnit,
          'batchCode': item.batchCode,
        });
      }

      // Process existing items
      final existingItems = _pendingItems.values.where((item) => !item.isNew).toList();
      for (final item in existingItems) {
        if (item.batchCode == null) continue;

        // Add to existing item quantity
        await _db.collection('items').doc(item.itemId).update({
          'qtyOnHand': FieldValue.increment(item.quantity),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        _createdBatchCodes.add(item.batchCode!);

        // Create a new lot for the added quantity with the pre-assigned batch code
        final lotRef = _db.collection('items').doc(item.itemId).collection('lots').doc();
        await lotRef.set({
          'lotCode': item.batchCode,
          'qtyRemaining': item.quantity,
          'baseUnit': item.baseUnit,
          'expiresAt': null,
          'openAt': null,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Log audit
        await Audit.log('inventory.bulk_add', {
          'itemId': item.itemId,
          'itemName': item.itemName,
          'barcode': item.barcode,
          'addedQuantity': item.quantity,
          'baseUnit': item.baseUnit,
          'batchCode': item.batchCode,
        });
      }

      if (mounted) {
        // Show success message with batch codes
        _showBatchCodesDialog();

        // Clear the list
        setState(() {
          _pendingItems.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error processing entries: $e')),
        );
      }
    } finally {
      setState(() => _isProcessing = false);
    }
  }  void _showBatchCodesDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Batch Codes Created'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${_createdBatchCodes.length} batches created:'),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _createdBatchCodes.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '• ${_createdBatchCodes[index]}',
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showScannerSheet() async {
    final scannedCode = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const ScannerSheet(
        title: 'Scan Item Barcode',
      ),
    );

    if (scannedCode != null) {
      _handleBarcode(scannedCode);
    }
  }
}

class BulkEntryItem {
  final String barcode;
  String itemId;
  final String itemName;
  final String baseUnit;
  final bool isNew;
  double quantity;
  final Map<String, dynamic>? newItemData;
  String? batchCode;

  BulkEntryItem({
    required this.barcode,
    required this.itemId,
    required this.itemName,
    required this.baseUnit,
    required this.isNew,
    required this.quantity,
    this.newItemData,
    this.batchCode,
  });

  BulkEntryItem copyWith({double? quantity, String? batchCode}) {
    return BulkEntryItem(
      barcode: barcode,
      itemId: itemId,
      itemName: itemName,
      baseUnit: baseUnit,
      isNew: isNew,
      quantity: quantity ?? this.quantity,
      newItemData: newItemData,
      batchCode: batchCode ?? this.batchCode,
    );
  }
}

class QuickAddNewItemDialog extends StatefulWidget {
  final String barcode;

  const QuickAddNewItemDialog({super.key, required this.barcode});

  @override
  State<QuickAddNewItemDialog> createState() => _QuickAddNewItemDialogState();
}

class _QuickAddNewItemDialogState extends State<QuickAddNewItemDialog> {
  final _nameController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  String _baseUnit = 'each';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _enrichProductInfo();
  }

  Future<void> _enrichProductInfo() async {
    setState(() => _isLoading = true);
    try {
      final info = await ProductEnrichmentService.fetchProductInfo(widget.barcode);
      if (info != null && info['name'] != null && mounted) {
        setState(() {
          _nameController.text = info['name'];
        });
      }
    } catch (e) {
      // Ignore errors, user can still enter manually
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add New Item'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Barcode: ${widget.barcode}'),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: 'Item Name',
              border: const OutlineInputBorder(),
              suffixIcon: _isLoading ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ) : null,
            ),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _quantityController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Quantity',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: _baseUnit,
                items: const [
                  DropdownMenuItem(value: 'each', child: Text('each')),
                  DropdownMenuItem(value: 'box', child: Text('box')),
                  DropdownMenuItem(value: 'pack', child: Text('pack')),
                  DropdownMenuItem(value: 'bottle', child: Text('bottle')),
                  DropdownMenuItem(value: 'tube', child: Text('tube')),
                ],
                onChanged: (value) => setState(() => _baseUnit = value ?? 'each'),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Add Item'),
        ),
      ],
    );
  }

  void _submit() {
    final name = _nameController.text.trim();
    final quantity = double.tryParse(_quantityController.text.trim()) ?? 1;

    if (name.isEmpty) return;

    Navigator.of(context).pop({
      'name': name,
      'barcode': widget.barcode,
      'baseUnit': _baseUnit,
      'category': 'Grocery', // Default category
      'qtyOnHand': quantity,
      'minQty': 1,
      'archived': false,
      'quantity': quantity, // For bulk entry
    });
  }
}

class EditQuantityDialog extends StatefulWidget {
  final double currentQuantity;
  final String baseUnit;
  final String itemName;

  const EditQuantityDialog({
    super.key,
    required this.currentQuantity,
    required this.baseUnit,
    required this.itemName,
  });

  @override
  State<EditQuantityDialog> createState() => _EditQuantityDialogState();
}

class _EditQuantityDialogState extends State<EditQuantityDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentQuantity.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit Quantity - ${widget.itemName}'),
      content: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Quantity',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ),
          const SizedBox(width: 12),
          Text(widget.baseUnit),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final quantity = double.tryParse(_controller.text.trim());
            if (quantity != null && quantity > 0) {
              Navigator.of(context).pop(quantity);
            }
          },
          child: const Text('Update'),
        ),
      ],
    );
  }
}

class EditBatchCodeDialog extends StatefulWidget {
  final String currentCode;
  final String itemName;

  const EditBatchCodeDialog({
    super.key,
    required this.currentCode,
    required this.itemName,
  });

  @override
  State<EditBatchCodeDialog> createState() => _EditBatchCodeDialogState();
}

class _EditBatchCodeDialogState extends State<EditBatchCodeDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentCode);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit Batch Code - ${widget.itemName}'),
      content: TextField(
        controller: _controller,
        decoration: const InputDecoration(
          labelText: 'Batch Code',
          border: OutlineInputBorder(),
          hintText: 'e.g., 2509-001',
        ),
        autofocus: true,
        style: const TextStyle(fontFamily: 'monospace'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final code = _controller.text.trim();
            if (code.isNotEmpty) {
              Navigator.of(context).pop(code);
            }
          },
          child: const Text('Update'),
        ),
      ],
    );
  }
}
