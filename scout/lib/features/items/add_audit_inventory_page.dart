// lib/features/items/add_audit_inventory_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../widgets/scanner_sheet.dart';
import '../../widgets/usb_wedge_scanner.dart';
import '../../utils/audit.dart';
import 'new_item_page.dart';
import 'item_detail_page.dart';

enum InventoryAction { addNew, auditExisting }

class AddAuditInventoryPage extends StatefulWidget {
  const AddAuditInventoryPage({super.key});

  @override
  State<AddAuditInventoryPage> createState() => _AddAuditInventoryPageState();
}

class _AddAuditInventoryPageState extends State<AddAuditInventoryPage> {
  final _db = FirebaseFirestore.instance;
  final _barcodeController = TextEditingController();
  final _barcodeFocus = FocusNode();

  String? _scannedBarcode;
  Map<String, dynamic>? _existingItem;
  InventoryAction? _action;
  bool _isLoading = false;

  @override
  void dispose() {
    _barcodeController.dispose();
    _barcodeFocus.dispose();
    super.dispose();
  }

  Future<void> _handleBarcode(String barcode) async {
    if (barcode.isEmpty) return;

    setState(() {
      _scannedBarcode = barcode;
      _isLoading = true;
      _existingItem = null;
      _action = null;
    });

    try {
      // Check if item exists by barcode
      final itemQuery = await _db
          .collection('items')
          .where('barcode', isEqualTo: barcode)
          .limit(1)
          .get();

      if (itemQuery.docs.isNotEmpty) {
        final itemDoc = itemQuery.docs.first;
        final itemData = itemDoc.data();
        itemData['id'] = itemDoc.id;

        setState(() {
          _existingItem = itemData;
          _action = InventoryAction.auditExisting;
        });
      } else {
        setState(() {
          _action = InventoryAction.addNew;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error checking barcode: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add/Audit Inventory'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => _showScannerSheet(),
            tooltip: 'Scan barcode',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_scannedBarcode == null) {
      return _buildInitialScanPrompt();
    }

    if (_action == InventoryAction.addNew) {
      return _buildAddNewItem();
    }

    if (_action == InventoryAction.auditExisting && _existingItem != null) {
      return _buildAuditExistingItem();
    }

    return _buildInitialScanPrompt();
  }

  Widget _buildInitialScanPrompt() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.qr_code_scanner, size: 80, color: Colors.grey),
          const SizedBox(height: 24),
          const Text(
            'Scan an item barcode to add new inventory or audit existing stock',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _barcodeController,
            focusNode: _barcodeFocus,
            decoration: InputDecoration(
              labelText: 'Or enter barcode manually',
              border: const OutlineInputBorder(),
              prefixIcon: IconButton(
                icon: const Icon(Icons.qr_code),
                onPressed: _showScannerSheet,
                tooltip: 'Scan barcode',
              ),
            ),
            onSubmitted: _handleBarcode,
          ),
          const SizedBox(height: 16),
          UsbWedgeScanner(
            enabled: true,
            allow: (_) => _barcodeFocus.hasFocus || _barcodeController.text.isEmpty,
            onCode: _handleBarcode,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan Barcode'),
            onPressed: _showScannerSheet,
          ),
        ],
      ),
    );
  }

  Widget _buildAddNewItem() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Row(
            children: [
              const Icon(Icons.add_circle, color: Colors.green),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'New Item Detected',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text('Barcode: $_scannedBarcode'),
                    const Text('This item doesn\'t exist in inventory yet.'),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: NewItemPage(initialBarcode: _scannedBarcode),
        ),
      ],
    );
  }

  Widget _buildAuditExistingItem() {
    final item = _existingItem!;
    final itemId = item['id'] as String;
    final itemName = item['name'] as String? ?? 'Unknown Item';
    final currentQty = (item['qtyOnHand'] as num?)?.toDouble() ?? 0.0;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: Row(
            children: [
              const Icon(Icons.inventory, color: Colors.blue),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Existing Item Found',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(itemName, style: const TextStyle(fontSize: 18)),
                    Text('Barcode: $_scannedBarcode'),
                    Text('Current quantity: $currentQty ${item['baseUnit'] ?? 'units'}'),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _AuditOptions(
            itemId: itemId,
            itemName: itemName,
            currentQty: currentQty,
            baseUnit: item['baseUnit'] as String? ?? 'each',
            onAction: () => setState(() {
              _scannedBarcode = null;
              _existingItem = null;
              _action = null;
            }),
          ),
        ),
      ],
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

    if (scannedCode != null && scannedCode.isNotEmpty) {
      _handleBarcode(scannedCode);
    }
  }
}

class _AuditOptions extends StatefulWidget {
  final String itemId;
  final String itemName;
  final double currentQty;
  final String baseUnit;
  final VoidCallback onAction;

  const _AuditOptions({
    required this.itemId,
    required this.itemName,
    required this.currentQty,
    required this.baseUnit,
    required this.onAction,
  });

  @override
  State<_AuditOptions> createState() => _AuditOptionsState();
}

class _AuditOptionsState extends State<_AuditOptions> {
  final _db = FirebaseFirestore.instance;
  final _qtyController = TextEditingController();
  bool _isProcessing = false;

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'What would you like to do?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 24),

        // Quick quantity adjustment
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Adjust Quantity',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text('Enter the new total quantity:'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _qtyController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'New quantity',
                          hintText: '${widget.currentQty}',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(widget.baseUnit),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: _isProcessing ? null : _adjustQuantity,
                        child: const Text('Update Quantity'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Add new lot
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Add New Lot/Batch',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text('Add a new batch of this item with expiration date and lot number.'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add Lot'),
                  onPressed: _addNewLot,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // View item details
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'View Item Details',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text('View and manage lots, history, and item settings.'),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.info),
                  label: const Text('View Details'),
                  onPressed: _viewItemDetails,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),

        // Scan another item
        Center(
          child: OutlinedButton(
            onPressed: widget.onAction,
            child: const Text('Scan Another Item'),
          ),
        ),
      ],
    );
  }

  Future<void> _adjustQuantity() async {
    final newQtyText = _qtyController.text.trim();
    if (newQtyText.isEmpty) return;

    final newQty = double.tryParse(newQtyText);
    if (newQty == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid number')),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      // Calculate the adjustment amount
      final adjustment = newQty - widget.currentQty;

      // Create audit log
      await Audit.log('inventory_audit', {
        'itemId': widget.itemId,
        'itemName': widget.itemName,
        'oldQty': widget.currentQty,
        'newQty': newQty,
        'adjustment': adjustment,
        'baseUnit': widget.baseUnit,
      });

      // Update the item quantity
      await _db.collection('items').doc(widget.itemId).update({
        'qtyOnHand': newQty,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Quantity updated to $newQty ${widget.baseUnit}')),
        );
        _qtyController.clear();
        widget.onAction(); // Refresh the parent
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating quantity: $e')),
        );
      }
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _addNewLot() {
    // Navigate to item detail page with lots tab selected
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ItemDetailPage(
          itemId: widget.itemId,
          itemName: widget.itemName,
        ),
      ),
    ).then((_) => widget.onAction()); // Refresh when returning
  }

  void _viewItemDetails() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ItemDetailPage(
          itemId: widget.itemId,
          itemName: widget.itemName,
        ),
      ),
    );
  }
}
