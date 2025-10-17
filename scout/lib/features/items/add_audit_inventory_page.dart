// lib/features/items/add_audit_inventory_page.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../widgets/scanner_sheet.dart';
import '../../widgets/usb_wedge_scanner.dart';
import '../../utils/audit.dart';
import '../../data/product_enrichment_service.dart';
import 'new_item_page.dart';

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
  final _nameController = TextEditingController();
  final _nameFocus = FocusNode();

  String? _scannedBarcode;
  Map<String, dynamic>? _existingItem;
  Map<String, dynamic>? _productInfo;
  InventoryAction? _action;
  bool _isLoading = false;
  bool _searchByName = false; // Toggle between barcode and name search
  List<Map<String, dynamic>> _nameSearchResults = [];
  Timer? _nameSearchDebounceTimer;

  @override
  void dispose() {
    _barcodeController.dispose();
    _barcodeFocus.dispose();
    _nameController.dispose();
    _nameFocus.dispose();
    _nameSearchDebounceTimer?.cancel();
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
        // Fetch product info from APIs for new items
        final productInfo = await ProductEnrichmentService.fetchProductInfo(barcode);

        setState(() {
          _productInfo = productInfo;
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

  Future<void> _handleNameSearch(String name) async {
    // Cancel any existing timer
    _nameSearchDebounceTimer?.cancel();
    
    if (name.isEmpty) {
      setState(() => _nameSearchResults = []);
      return;
    }

    // Start a new timer with 300ms delay
    _nameSearchDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      _performNameSearch(name);
    });
  }

  Future<void> _performNameSearch(String name) async {
    setState(() => _isLoading = true);

    try {
      // Search items by name (case-insensitive partial match)
      // Fetch all items and filter client-side for case-insensitive search
      final query = await _db
          .collection('items')
          .limit(100) // Fetch more items to filter client-side
          .get();

      final nameLower = name.toLowerCase();
      final results = query.docs
          .where((doc) {
            final data = doc.data();
            final itemName = (data['name'] as String?) ?? '';
            final isArchived = data['archived'] == true;
            return itemName.toLowerCase().contains(nameLower) && !isArchived;
          })
          .take(10) // Limit to 10 results after filtering
          .map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          })
          .toList();

      setState(() {
        _nameSearchResults = results;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error searching by name: $e')),
        );
      }
    }
  }

  void _selectItemFromSearch(Map<String, dynamic> item) {
    debugPrint('AddAuditInventoryPage: Selected item ${item['id']} - ${item['name']}');
    setState(() {
      _existingItem = item;
      _action = InventoryAction.auditExisting;
      _nameSearchResults = [];
      _searchByName = false;
    });
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

    // Show add new item flow
    if (_action == InventoryAction.addNew) {
      return _buildAddNewItem();
    }

    // Show audit existing item flow
    if (_action == InventoryAction.auditExisting && _existingItem != null) {
      return _buildAuditExistingItem();
    }

    // Default: show search/scan prompt
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
            'Find an item to add new inventory or audit existing stock',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 32),

          // Search mode toggle
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment<bool>(
                value: false,
                label: Text('Barcode'),
                icon: Icon(Icons.qr_code),
              ),
              ButtonSegment<bool>(
                value: true,
                label: Text('Name'),
                icon: Icon(Icons.search),
              ),
            ],
            selected: {_searchByName},
            onSelectionChanged: (Set<bool> selected) {
              setState(() {
                _searchByName = selected.first;
                _nameSearchResults = [];
                _barcodeController.clear();
                _nameController.clear();
              });
            },
          ),

          const SizedBox(height: 24),

          // Search input based on mode
          if (_searchByName) ...[
            TextField(
              controller: _nameController,
              focusNode: _nameFocus,
              decoration: const InputDecoration(
                labelText: 'Search by item name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _handleNameSearch,
            ),
            const SizedBox(height: 16),
            // Name search results
            if (_nameSearchResults.isNotEmpty) ...[
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _nameSearchResults.length,
                  itemBuilder: (context, index) {
                    final item = _nameSearchResults[index];
                    return ListTile(
                      title: Text(item['name'] ?? 'Unknown'),
                      subtitle: Text('Barcode: ${item['barcode'] ?? 'N/A'}'),
                      onTap: () => _selectItemFromSearch(item),
                    );
                  },
                ),
              ),
            ],
          ] else ...[
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
            const SizedBox(height: 16),
            UsbWedgeScanner(
              enabled: true,
              allow: (_) => _barcodeFocus.hasFocus || _barcodeController.text.isEmpty,
              onCode: _handleBarcode,
            ),
          ],

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
          child: NewItemPage(initialBarcode: _scannedBarcode, productInfo: _productInfo),
        ),
      ],
    );
  }

  Widget _buildAuditExistingItem() {
    final item = _existingItem!;
    final itemId = item['id'] as String;
    final itemName = item['name'] as String? ?? 'Unknown Item';
    final currentQty = (item['qtyOnHand'] as num?)?.toDouble() ?? 0.0;

    debugPrint('_buildAuditExistingItem: itemId=$itemId, name=$itemName, qtyOnHand=$currentQty');
    debugPrint('_buildAuditExistingItem: Full item data: $item');

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
                    if (_scannedBarcode != null) Text('Barcode: $_scannedBarcode'),
                    if (item['barcode'] != null && _scannedBarcode == null) 
                      Text('Barcode: ${item['barcode']}'),
                    Text('Total quantity: $currentQty ${item['baseUnit'] ?? 'units'}'),
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
    debugPrint('_AuditOptions: Building for itemId=${widget.itemId}');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Current Batches',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),

        // Display all lots
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _db
              .collection('items')
              .doc(widget.itemId)
              .collection('lots')
              .snapshots(), // Remove orderBy to avoid index issues, will sort client-side
          builder: (context, snapshot) {
            debugPrint('_AuditOptions: StreamBuilder update - hasData=${snapshot.hasData}, hasError=${snapshot.hasError}, docsCount=${snapshot.data?.docs.length}');
            if (snapshot.hasError) {
              debugPrint('_AuditOptions: Error loading lots: ${snapshot.error}');
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Error loading batches: ${snapshot.error}'),
                ),
              );
            }

            if (!snapshot.hasData) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }

            final lots = snapshot.data!.docs;
            debugPrint('_AuditOptions: Loaded ${lots.length} lots for item ${widget.itemId}');
            
            // Filter to only active lots (not archived)
            final activeLots = lots.where((doc) {
              final data = doc.data();
              return data['archived'] != true;
            }).toList();

            debugPrint('_AuditOptions: ${activeLots.length} active lots after filtering');

            if (activeLots.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey),
                      const SizedBox(height: 8),
                      const Text(
                        'No batches found',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const Text('All inventory should be contained within batches.'),
                    ],
                  ),
                ),
              );
            }

            // Sort lots: null expiration dates last
            activeLots.sort((a, b) {
              final aExp = a.data()['expiresAt'];
              final bExp = b.data()['expiresAt'];
              if (aExp == null && bExp == null) return 0;
              if (aExp == null) return 1;
              if (bExp == null) return -1;
              return (aExp as Timestamp).compareTo(bExp as Timestamp);
            });

            return Column(
              children: activeLots.map((lotDoc) => _buildLotCard(lotDoc)).toList(),
            );
          },
        ),

        const SizedBox(height: 24),
        const Text(
          'Quick Actions',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),

        // Quick quantity adjustment (legacy - should use batch operations instead)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Bulk Quantity Adjustment',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Warning: This adjusts total quantity directly. Use batch operations above for proper inventory tracking.',
                  style: TextStyle(color: Colors.orange, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _qtyController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'New total quantity',
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
                        onPressed: _isProcessing ? null : _adjustTotalQuantity,
                        child: const Text('Adjust Total'),
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

  Widget _buildLotCard(QueryDocumentSnapshot<Map<String, dynamic>> lotDoc) {
    final data = lotDoc.data();
    final lotCode = data['lotCode'] as String? ?? lotDoc.id.substring(0, 6);
    final qtyRemaining = (data['qtyRemaining'] as num?)?.toDouble() ?? 0.0;
    final qtyInitial = (data['qtyInitial'] as num?)?.toDouble() ?? 0.0;
    final baseUnit = data['baseUnit'] as String? ?? 'each';

    final expTs = data['expiresAt'];
    final expiresAt = expTs is Timestamp ? expTs.toDate() : null;
    final now = DateTime.now();
    final isExpired = expiresAt != null && expiresAt.isBefore(now);
    final isExpiringSoon = expiresAt != null &&
        expiresAt.isBefore(now.add(const Duration(days: 7))) &&
        expiresAt.isAfter(now);

    final openTs = data['openAt'];
    final isOpened = openTs is Timestamp;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Lot $lotCode',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                if (isExpired)
                  const Chip(
                    label: Text('EXPIRED', style: TextStyle(color: Colors.white, fontSize: 10)),
                    backgroundColor: Colors.red,
                    padding: EdgeInsets.symmetric(horizontal: 4),
                  )
                else if (isExpiringSoon)
                  const Chip(
                    label: Text('EXPIRING SOON', style: TextStyle(color: Colors.white, fontSize: 10)),
                    backgroundColor: Colors.orange,
                    padding: EdgeInsets.symmetric(horizontal: 4),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Remaining: $qtyRemaining / $qtyInitial $baseUnit',
              style: TextStyle(
                color: qtyRemaining == 0 ? Colors.red : null,
                fontWeight: qtyRemaining == 0 ? FontWeight.bold : null,
              ),
            ),
            if (expiresAt != null) ...[
              const SizedBox(height: 4),
              Text(
                'Expires: ${MaterialLocalizations.of(context).formatFullDate(expiresAt)}',
                style: TextStyle(
                  color: isExpired ? Colors.red : isExpiringSoon ? Colors.orange : null,
                  fontWeight: isExpired || isExpiringSoon ? FontWeight.bold : null,
                ),
              ),
            ],
            if (isOpened) ...[
              const SizedBox(height: 4),
              const Text('Status: Opened', style: TextStyle(color: Colors.blue)),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.add_circle, color: Colors.green),
                    label: const Text('Add Stock'),
                    onPressed: () => _addToLot(lotDoc),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.green,
                      side: const BorderSide(color: Colors.green),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.remove_circle, color: Colors.red),
                    label: const Text('Waste'),
                    onPressed: qtyRemaining > 0 ? () => _wasteFromLot(lotDoc) : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.edit),
                    label: const Text('Update'),
                    onPressed: () => _updateLot(lotDoc),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addToLot(QueryDocumentSnapshot<Map<String, dynamic>> lotDoc) async {
    final data = lotDoc.data();
    final lotCode = data['lotCode'] as String? ?? lotDoc.id.substring(0, 6);
    final qtyRemaining = (data['qtyRemaining'] as num?)?.toDouble() ?? 0.0;
    final baseUnit = data['baseUnit'] as String? ?? 'each';

    final addController = TextEditingController();

    final result = await showDialog<double>(
      context: context,
      builder: (context) => Theme(
        data: Theme.of(context),
        child: AlertDialog(
          title: Text('Add Stock to Lot $lotCode'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Current remaining: $qtyRemaining $baseUnit'),
              const SizedBox(height: 16),
              TextField(
                controller: addController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Amount to add',
                  suffixText: baseUnit,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final addAmount = double.tryParse(addController.text);
                if (addAmount != null && addAmount > 0) {
                  Navigator.pop(context, addAmount);
                }
              },
              child: const Text('Add Stock'),
            ),
          ],
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() => _isProcessing = true);

      try {
        final newQtyRemaining = qtyRemaining + result;
        final lotRef = _db.collection('items').doc(widget.itemId).collection('lots').doc(lotDoc.id);

        // Update lot quantity
        await lotRef.update({
          'qtyRemaining': newQtyRemaining,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Recalculate total item quantity
        await _updateTotalQuantity();

        // Log audit
        await Audit.log('lot.add_stock', {
          'itemId': widget.itemId,
          'itemName': widget.itemName,
          'lotId': lotDoc.id,
          'lotCode': lotCode,
          'addedAmount': result,
          'remainingAfterAdd': newQtyRemaining,
          'baseUnit': baseUnit,
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Added $result $baseUnit to lot $lotCode')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error adding to lot: $e')),
          );
        }
      } finally {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _wasteFromLot(QueryDocumentSnapshot<Map<String, dynamic>> lotDoc) async {
    final data = lotDoc.data();
    final lotCode = data['lotCode'] as String? ?? lotDoc.id.substring(0, 6);
    final qtyRemaining = (data['qtyRemaining'] as num?)?.toDouble() ?? 0.0;
    final baseUnit = data['baseUnit'] as String? ?? 'each';

    final wasteController = TextEditingController();
    final reasonController = TextEditingController();

    final result = await showDialog<double>(
      context: context,
      builder: (context) => Theme(
        data: Theme.of(context),
        child: AlertDialog(
          title: Text('Waste from Lot $lotCode'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Current remaining: $qtyRemaining $baseUnit'),
              const SizedBox(height: 16),
              TextField(
                controller: wasteController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Amount to waste',
                  suffixText: baseUnit,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                  hintText: 'e.g., expired, damaged, used for testing',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final wasteAmount = double.tryParse(wasteController.text);
                if (wasteAmount != null && wasteAmount > 0 && wasteAmount <= qtyRemaining) {
                  Navigator.pop(context, wasteAmount);
                }
              },
              child: const Text('Waste'),
            ),
          ],
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() => _isProcessing = true);

      try {
        final newQtyRemaining = qtyRemaining - result;
        final lotRef = _db.collection('items').doc(widget.itemId).collection('lots').doc(lotDoc.id);

        // Update lot quantity
        await lotRef.update({
          'qtyRemaining': newQtyRemaining,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Recalculate total item quantity
        await _updateTotalQuantity();

        // Log audit
        await Audit.log('lot.waste', {
          'itemId': widget.itemId,
          'itemName': widget.itemName,
          'lotId': lotDoc.id,
          'lotCode': lotCode,
          'wastedAmount': result,
          'remainingAfterWaste': newQtyRemaining,
          'baseUnit': baseUnit,
          'reason': reasonController.text.trim().isEmpty ? null : reasonController.text.trim(),
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Wasted $result $baseUnit from lot $lotCode')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error wasting from lot: $e')),
          );
        }
      } finally {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _updateLot(QueryDocumentSnapshot<Map<String, dynamic>> lotDoc) async {
    final data = lotDoc.data();
    final lotCode = data['lotCode'] as String? ?? lotDoc.id.substring(0, 6);
    final qtyRemaining = (data['qtyRemaining'] as num?)?.toDouble() ?? 0.0;
    final baseUnit = data['baseUnit'] as String? ?? 'each';

    final qtyController = TextEditingController(text: qtyRemaining.toString());
    DateTime? expiresAt = data['expiresAt'] is Timestamp ? (data['expiresAt'] as Timestamp).toDate() : null;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => Theme(
        data: Theme.of(context),
        child: AlertDialog(
          title: Text('Update Lot $lotCode'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Remaining quantity',
                  suffixText: baseUnit,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Expiration date'),
                subtitle: Text(expiresAt == null
                  ? 'None'
                  : MaterialLocalizations.of(context).formatFullDate(expiresAt!)),
                trailing: TextButton.icon(
                  icon: const Icon(Icons.edit_calendar),
                  label: const Text('Pick'),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: expiresAt ?? DateTime.now(),
                      firstDate: DateTime(DateTime.now().year - 1),
                      lastDate: DateTime(DateTime.now().year + 3),
                    );
                    if (picked != null) {
                      expiresAt = picked;
                      // Force rebuild of dialog
                      (context as Element).markNeedsBuild();
                    }
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final newQty = double.tryParse(qtyController.text);
                if (newQty != null && newQty >= 0) {
                  Navigator.pop(context, true);
                }
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      setState(() => _isProcessing = true);

      try {
        final newQty = double.tryParse(qtyController.text)!;
        final lotRef = _db.collection('items').doc(widget.itemId).collection('lots').doc(lotDoc.id);

        // Update lot
        await lotRef.update({
          'qtyRemaining': newQty,
          'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Recalculate total item quantity
        await _updateTotalQuantity();

        // Log audit
        await Audit.log('lot.update_audit', {
          'itemId': widget.itemId,
          'itemName': widget.itemName,
          'lotId': lotDoc.id,
          'lotCode': lotCode,
          'oldQtyRemaining': qtyRemaining,
          'newQtyRemaining': newQty,
          'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
          'baseUnit': baseUnit,
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Updated lot $lotCode')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating lot: $e')),
          );
        }
      } finally {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _updateTotalQuantity() async {
    // Calculate total quantity from all non-archived lots
    final lotsSnapshot = await _db
        .collection('items')
        .doc(widget.itemId)
        .collection('lots')
        .get();

    double totalQty = 0;
    
    // Filter to only active lots (not archived) and calculate total
    for (final lotDoc in lotsSnapshot.docs) {
      final data = lotDoc.data();
      if (data['archived'] != true) {
        final qty = (data['qtyRemaining'] as num?)?.toDouble() ?? 0.0;
        totalQty += qty;
      }
    }

    // Update item total
    await _db.collection('items').doc(widget.itemId).update({
      'qtyOnHand': totalQty,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _adjustTotalQuantity() async {
    final newQtyText = _qtyController.text.trim();
    if (newQtyText.isEmpty) return;

    final newQty = double.tryParse(newQtyText);
    if (newQty == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid number')),
      );
      return;
    }

    // Show warning about bulk adjustment
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => Theme(
        data: Theme.of(context),
        child: AlertDialog(
          title: const Text('Bulk Quantity Adjustment'),
          content: const Text(
            'This will adjust the total quantity directly without affecting individual batches. '
            'For proper inventory tracking, use the batch waste/update operations above.\n\n'
            'Continue with bulk adjustment?'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );

    if (proceed != true) return;

    setState(() => _isProcessing = true);

    try {
      // Calculate the adjustment amount
      final adjustment = newQty - widget.currentQty;

      // Create audit log
      await Audit.log('inventory_bulk_adjust', {
        'itemId': widget.itemId,
        'itemName': widget.itemName,
        'oldQty': widget.currentQty,
        'newQty': newQty,
        'adjustment': adjustment,
        'baseUnit': widget.baseUnit,
        'note': 'Bulk adjustment - individual batch quantities not affected',
      });

      // Update the item quantity directly (this creates inconsistency with batch totals)
      await _db.collection('items').doc(widget.itemId).update({
        'qtyOnHand': newQty,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Total quantity adjusted to $newQty ${widget.baseUnit}'),
            backgroundColor: Colors.orange,
          ),
        );
        _qtyController.clear();
        widget.onAction(); // Refresh the parent
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adjusting quantity: $e')),
        );
      }
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _addNewLot() {
    // Navigate to item detail page with lots tab selected
    GoRouter.of(context).push('/items/${widget.itemId}').then((_) => widget.onAction());
  }

  void _viewItemDetails() {
    GoRouter.of(context).push('/items/${widget.itemId}');
  }
}
