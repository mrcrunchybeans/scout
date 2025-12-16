// lib/features/items/bulk_inventory_entry_page.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../widgets/scanner_sheet.dart';
import '../../widgets/usb_wedge_scanner.dart';
import '../../widgets/weight_calculator_dialog.dart';
import 'package:scout/utils/audit.dart';
import '../../utils/lot_code.dart';
import '../../data/product_enrichment_service.dart';
import '../../data/lookups_service.dart';
import '../../models/option_item.dart';
import 'new_item_page.dart';
import '../../services/label_export_service.dart';

enum UseType { staff, patient, both }

class BulkInventoryEntryPage extends StatefulWidget {
  final String? preSelectedItemId;
  
  const BulkInventoryEntryPage({super.key, this.preSelectedItemId});

  @override
  State<BulkInventoryEntryPage> createState() => _BulkInventoryEntryPageState();
}

class _BulkInventoryEntryPageState extends State<BulkInventoryEntryPage> {
  final _db = FirebaseFirestore.instance;
  final _uuid = Uuid();
  final _barcodeController = TextEditingController();
  final _barcodeFocus = FocusNode();
  final _nameController = TextEditingController();
  final _nameFocus = FocusNode();

  // Scanned products with multiple barcodes and lots
  final Map<String, BulkProductEntry> _pendingProducts = {};
  bool _isProcessing = false;
  final List<String> _createdBatchCodes = [];
  bool _searchByName = false; // Toggle between barcode and name search
  List<Map<String, dynamic>> _nameSearchResults = [];
  Timer? _nameSearchDebounceTimer;

  // Remember last entered values for quick entry
  Map<String, dynamic>? _lastEnteredValues;

  // Mobile scanner session
  late final String _sessionId;
  StreamSubscription? _scannerSubscription;

  @override
  void initState() {
    super.initState();
    _sessionId = _uuid.v4();
    _listenForMobileScans();
    
    // If we have a preselected item, load it immediately
    if (widget.preSelectedItemId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadPreselectedItem(widget.preSelectedItemId!);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bulk Inventory Entry'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            final rootCtx = context;
            if (_pendingProducts.isNotEmpty) {
              final shouldLeave = await _showNavigationConfirmationDialog(rootCtx);
              if (!shouldLeave) return;
            }
            if (rootCtx.mounted) {
              Navigator.of(rootCtx).pop();
            }
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone_android),
            tooltip: 'Scan with Phone',
            onPressed: _showMobileScannerQR,
          ),
          if (_pendingProducts.isNotEmpty)
            TextButton(
              onPressed: _isProcessing ? null : _processAllEntries,
              child: Text('Process All (${_pendingProducts.length})'),
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

                const SizedBox(height: 16),

                // Search input based on mode
                if (_searchByName) ...[
                  TextField(
                    controller: _nameController,
                    focusNode: _nameFocus,

                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                    decoration: const InputDecoration(
                      labelText: 'Search by item name',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: _handleNameSearch,
                    onSubmitted: _handleNameSearchSubmit,
                  ),
                  const SizedBox(height: 8),
                  // Name search results
                  if (_nameSearchResults.isNotEmpty) ...[
                    Container(
                      constraints: const BoxConstraints(maxHeight: 150),
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
                            subtitle: Text('Barcode: ${item['barcode'] ?? 'N/A'} • Category: ${item['category'] ?? 'None'}'),
                            onTap: () => _selectItemFromSearch(item),
                            trailing: IconButton(
                              icon: const Icon(Icons.edit),
                              tooltip: 'Edit item details',
                              onPressed: () => _editItemDetails(item),
                            ),
                          );
                        },
                      ),
                    ),
                  ] else if (_nameController.text.trim().isNotEmpty && !_isProcessing) ...[
                    // No results found - offer to create new product
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.blue.shade50,
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'No products found with that name.',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            icon: const Icon(Icons.add),
                            label: Text('Create "${_nameController.text.trim()}"'),
                            onPressed: () => _showCreateNewProductDialog(_nameController.text.trim()),
                          ),
                        ],
                      ),
                    ),
                  ],
                ] else ...[
                  TextField(
                    controller: _barcodeController,
                    focusNode: _barcodeFocus,

                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
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
                    audioFeedback: true,
                  ),
                ],
              ],
            ),
          ),

          // Pending items list
          Expanded(
            child: _pendingProducts.isEmpty
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
      itemCount: _pendingProducts.length,
      itemBuilder: (context, index) {
        final product = _pendingProducts.values.elementAt(index);
        final totalQuantity = product.lots.fold<double>(0, (total, lot) => total + lot.quantity);
        
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: product.isNew ? Colors.green : Colors.blue,
              child: Icon(
                product.isNew ? Icons.add : Icons.inventory,
                color: Colors.white,
              ),
            ),
            title: Row(
              children: [
                Expanded(child: Text(product.itemName)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: product.isNew ? Colors.green : Colors.blue,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${product.lots.length} lot${product.lots.length == 1 ? '' : 's'}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Barcodes: ${product.barcodes.join(", ")}'),
                Text('Total: ${totalQuantity.toStringAsFixed(1)} ${product.baseUnit}'),
              ],
            ),
            children: [
              ...product.lots.asMap().entries.map((entry) {
                final lotIndex = entry.key;
                final lot = entry.value;
                return ListTile(
                  dense: true,
                  leading: const SizedBox(width: 24),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text('Lot ${lotIndex + 1}: ${lot.quantity.toStringAsFixed(1)} ${product.baseUnit}'),
                      ),
                      if (lot.batchCode != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            lot.batchCode!,
                            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                          ),
                        ),
                      if (lot.lotId != null)
                        const Icon(Icons.link, size: 16, color: Colors.blue),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _editLot(product, lotIndex),
                        tooltip: 'Edit lot',
                      ),
                      if (product.lots.length > 1)
                        IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () => _removeLot(product, lotIndex),
                          tooltip: 'Remove lot',
                        ),
                    ],
                  ),
                );
              }),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: product.isNew 
                          ? () => _showLotAdditionDialog(product)
                          : () => _showExistingBatchesDialog(product),
                        icon: const Icon(Icons.add),
                        label: const Text('Add Lot'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => _removeProduct(product.productKey),
                      tooltip: 'Remove product',
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleBarcode(String barcode) async {
    if (barcode.isEmpty) return;

    // Check if this barcode is already associated with a pending product
    final existingProduct = _pendingProducts.values.firstWhere(
      (product) => product.barcodes.contains(barcode),
      orElse: () => BulkProductEntry(productKey: '', itemId: '', itemName: '', baseUnit: '', isNew: false),
    );

    if (existingProduct.productKey.isNotEmpty) {
      // Barcode already scanned for this product, show lot addition dialog
      await _showLotAdditionDialog(existingProduct);
      return;
    }

    setState(() => _isProcessing = true);

    try {
      // Check if item exists in database
      final itemQuery = await _db
          .collection('items')
          .where('barcode', isEqualTo: barcode)
          .limit(1)
          .get();

      if (itemQuery.docs.isNotEmpty) {
        final itemDoc = itemQuery.docs.first;
        final itemData = itemDoc.data();
        itemData['id'] = itemDoc.id;

        // Check if we already have this product pending
        final productKey = itemDoc.id; // Use item ID as unique key
        if (_pendingProducts.containsKey(productKey)) {
          // Add barcode to existing product
          setState(() {
            _pendingProducts[productKey]!.addBarcode(barcode);
          });
          await _showExistingBatchesDialog(_pendingProducts[productKey]!);
        } else {
          // Create new product entry
          final product = BulkProductEntry(
            productKey: productKey, // Use item ID as unique key
            itemId: itemDoc.id,
            itemName: itemData['name'] ?? 'Unknown Item',
            baseUnit: itemData['baseUnit'] ?? 'each',
            isNew: false,
            barcodes: [barcode],
          );
          setState(() {
            _pendingProducts[productKey] = product;
          });
          await _showExistingBatchesDialog(product);
        }
      } else {
        // New item - try to fetch product info from APIs first
        final productInfo = await ProductEnrichmentService.fetchProductInfo(barcode);

        // Check if this barcode is already associated with a pending product
        final existingProduct = _pendingProducts.values.firstWhere(
          (product) => product.barcodes.contains(barcode),
          orElse: () => BulkProductEntry(productKey: '', itemId: '', itemName: '', baseUnit: '', isNew: false),
        );

        if (existingProduct.productKey.isNotEmpty) {
          // Barcode already scanned for this product, show lot addition dialog
          await _showLotAdditionDialog(existingProduct);
        } else {
          // Show quick add dialog for new product
          await _showQuickAddNewProductDialog(barcode, productInfo);
        }
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

  Future<void> _handleNameSearch(String name) async {
    // Cancel any existing timer
    _nameSearchDebounceTimer?.cancel();
    
    if (name.isEmpty) {
      setState(() => _nameSearchResults = []);
      return;
    }

    // Start a new timer with 500ms delay
    _nameSearchDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      _performNameSearch(name);
    });
  }

  Future<void> _performNameSearch(String name) async {
    setState(() => _isProcessing = true);

    try {
      // Search items by name (case-insensitive partial match)
      // Fetch more items and filter client-side for case-insensitive search
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
        _isProcessing = false;
      });
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error searching by name: $e')),
        );
      }
    }
  }

  Future<void> _handleNameSearchSubmit(String name) async {
    if (name.trim().isEmpty) return;

    final trimmedName = name.trim();

    // If we have search results, select the first one
    if (_nameSearchResults.isNotEmpty) {
      _selectItemFromSearch(_nameSearchResults.first);
      return;
    }

    // No results found - offer to create new product
    await _showCreateNewProductDialog(trimmedName);
  }

  Future<void> _showCreateNewProductDialog(String name) async {
    await _showQuickAddNewProductDialog(null, null, name);
  }

  void _selectItemFromSearch(Map<String, dynamic> item) async {
    debugPrint('BulkInventoryEntry: Selected item ${item['id']} - ${item['name']}');
    debugPrint('BulkInventoryEntry: Item barcode: ${item['barcode']}');
    final barcode = item['barcode'] ?? '';
    if (barcode.isEmpty) {
      debugPrint('BulkInventoryEntry: ERROR - Item has no barcode, cannot proceed');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This item has no barcode. Please add a barcode to the item first.')),
        );
      }
      return;
    }

    setState(() {
      _nameSearchResults = [];
      _searchByName = false;
    });

    // Process the selected item as if it was scanned
    debugPrint('BulkInventoryEntry: Processing barcode: $barcode');
    await _handleBarcode(barcode);
  }

  void _editItemDetails(Map<String, dynamic> item) async {
    final itemId = item['id'] as String?;
    if (itemId == null) return;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => NewItemPage(
          itemId: itemId,
          existingItem: item,
        ),
      ),
    );

    if (result == true && mounted) {
      // Item was updated, refresh the search results
      _handleNameSearch(_nameController.text);
    }
  }

  Future<void> _showLotAdditionDialog(BulkProductEntry product) async {
    final result = await showDialog<List<BulkLotEntry>>(
      context: context,
      builder: (context) => BulkLotAdditionDialog(
        product: product,
        generateBatchCode: (itemId) => generateNextLotCode(itemId: itemId),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        for (final lot in result) {
          product.addLot(lot);
        }
      });
    }
  }

  Future<void> _showExistingBatchesDialog(BulkProductEntry product) async {
    final result = await showDialog<List<BulkLotEntry>>(
      context: context,
      builder: (context) => ExistingBatchesDialog(
        product: product,
        generateBatchCode: (itemId) => generateNextLotCode(itemId: itemId),
      ),
    );

    if (result != null && mounted) {
      // Check if this is a signal to create new batch
      if (result.isNotEmpty && result.first.lotId == '__CREATE_NEW__') {
        // Show the lot addition dialog for creating new batches
        await _showLotAdditionDialog(product);
      } else {
        // Normal lot entries
        setState(() {
          for (final lot in result) {
            product.addLot(lot);
          }
        });
      }
    }
  }

  Future<void> _showQuickAddNewProductDialog(String? barcode, [Map<String, dynamic>? productInfo, String? name]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => QuickAddNewProductDialog(
        barcode: barcode, 
        name: name,
        productInfo: productInfo,
        prepopulatedValues: _lastEnteredValues,
      ),
    );

    if (result != null && mounted) {
      // Save the entered values for future prepopulation (excluding name and quantity)
      _lastEnteredValues = {
        'baseUnit': result['baseUnit'],
        'category': result['category'],
        'homeLocationId': result['homeLocationId'],
        'homeLocationName': result['homeLocationName'],
        'grantId': result['grantId'],
        'grantName': result['grantName'],
        'useType': result['useType'],
        'expiresAt': result['expiresAt'],
      };

      final productName = result['name'];
      final uniqueKey = _uuid.v4(); // Generate unique UUID for new items
      final generatedBarcode = barcode ?? _uuid.v4().substring(0, 8).toUpperCase(); // Generate short barcode if none provided
      final product = BulkProductEntry(
        productKey: uniqueKey, // Use UUID as unique key for new items
        itemId: '', // Will be set after creation
        itemName: productName,
        baseUnit: result['baseUnit'],
        isNew: true,
        newItemData: result,
        barcodes: [generatedBarcode],
      );

      // Add initial lot
      final initialLot = BulkLotEntry(
        quantity: result['quantity'],
        batchCode: previewLotCode(),
        expiresAt: result['expiresAt'],
      );
      product.addLot(initialLot);

      setState(() {
        _pendingProducts[uniqueKey] = product; // Use UUID as key
      });
    }
  }

  Future<void> _processAllEntries() async {
    if (_pendingProducts.isEmpty) return;

    setState(() => _isProcessing = true);
    _createdBatchCodes.clear();

    try {
      // Process each product
      for (final product in _pendingProducts.values) {
        if (product.isNew) {
          // Create new item first
          final itemRef = _db.collection('items').doc();
          final newItemData = product.newItemData!;
          await itemRef.set({
            'name': product.itemName,
            'category': newItemData['category'],
            'baseUnit': product.baseUnit,
            'unit': product.baseUnit, // Keep legacy field in sync
            'qtyOnHand': product.lots.fold(0.0, (total, lot) => total + lot.quantity),
            'minQty': 1, // Default minimum quantity
            'maxQty': null,
            'useType': newItemData['useType'] ?? 'both',
            'homeLocationId': newItemData['homeLocationId'],
            'grantId': newItemData['grantId'],
            'departmentId': null,
            'expiresAt': null,
            'lastUsedAt': null,
            'tags': <String>[],
            'imageUrl': null,
            'barcode': product.barcodes.first, // Use first barcode as primary
            'barcodes': FieldValue.arrayUnion(product.barcodes), // Store all barcodes
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });

          // Create lots for the new item
          // Only generate lot codes for lots that don't have one yet
          final lotsWithCodes = <BulkLotEntry>[];
          for (final lot in product.lots) {
            if (lot.batchCode == null) {
              final lotCode = await generateNextLotCode(itemId: itemRef.id);
              lotsWithCodes.add(lot.copyWith(batchCode: lotCode));
            } else {
              lotsWithCodes.add(lot);
            }
          }

          for (final lot in lotsWithCodes) {
            if (lot.batchCode == null) continue;

            final lotRef = itemRef.collection('lots').doc();
            await lotRef.set({
              'lotCode': lot.batchCode,
              'qtyRemaining': lot.quantity,
              'baseUnit': product.baseUnit,
              'expiresAt': lot.expiresAt != null
                  ? Timestamp.fromDate(lot.expiresAt!)
                  : null,
              'openAt': null,
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
              // Copy grant and location from new item data
              'grantId': newItemData['grantId'],
              'storageLocation': newItemData['homeLocationId'],
            });

            _createdBatchCodes.add(lot.batchCode!);
          }

          // Log audit for new item
          await Audit.log('item.created', {
            'itemId': itemRef.id,
            'itemName': product.itemName,
            'barcodes': product.barcodes,
            'initialQuantity': product.lots.fold(0.0, (total, lot) => total + lot.quantity),
            'baseUnit': product.baseUnit,
            'batchCodes': product.lots.map((lot) => lot.batchCode).where((code) => code != null).toList(),
          });
        } else {
          // Add to existing item
          final totalQuantity = product.lots.fold(0.0, (total, lot) => total + lot.quantity);

          // Fetch existing item data for grant/location defaults
          final existingItemDoc = await _db.collection('items').doc(product.itemId).get();
          final existingItemData = existingItemDoc.data() ?? {};

          // Update total item quantity
          await _db.collection('items').doc(product.itemId).update({
            'qtyOnHand': FieldValue.increment(totalQuantity),
            'updatedAt': FieldValue.serverTimestamp(),
          });

          // Create lots for the existing item
          for (final lot in product.lots) {
            if (lot.batchCode == null) continue;

            final lotRef = _db.collection('items').doc(product.itemId).collection('lots').doc();
            await lotRef.set({
              'lotCode': lot.batchCode,
              'qtyRemaining': lot.quantity,
              'baseUnit': product.baseUnit,
              'expiresAt': lot.expiresAt != null
                  ? Timestamp.fromDate(lot.expiresAt!)
                  : null,
              'openAt': null,
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
              // Copy grant and location from existing item
              'grantId': existingItemData['grantId'],
              'storageLocation': existingItemData['homeLocationId'],
            });

            _createdBatchCodes.add(lot.batchCode!);
          }

          // Log audit for existing item
          await Audit.log('inventory.bulk_add', {
            'itemId': product.itemId,
            'itemName': product.itemName,
            'barcodes': product.barcodes,
            'addedQuantity': totalQuantity,
            'baseUnit': product.baseUnit,
            'batchCodes': product.lots.map((lot) => lot.batchCode).where((code) => code != null).toList(),
          });
        }
      }

      if (mounted) {
        // Show success message with batch codes
        _showBatchCodesDialog();

        // Clear the list
        setState(() {
          _pendingProducts.clear();
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
  }

  Future<bool> _showNavigationConfirmationDialog(BuildContext dialogCtx) async {
    final result = await showDialog<bool>(
      context: dialogCtx,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved Changes'),
        content: Text(
          'You have ${_pendingProducts.length} pending product${_pendingProducts.length == 1 ? '' : 's'} that haven\'t been processed yet. '
          'Are you sure you want to leave? Your changes will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _editLot(BulkProductEntry product, int lotIndex) async {
    final lot = product.lots[lotIndex];
    final result = await showDialog<BulkLotEntry>(
      context: context,
      builder: (context) => EditLotDialog(
        lot: lot,
        productName: product.itemName,
        baseUnit: product.baseUnit,
      ),
    );

    if (result != null && mounted) {
      setState(() {
        product.lots[lotIndex] = result;
      });
    }
  }

  void _removeLot(BulkProductEntry product, int lotIndex) {
    setState(() {
      product.lots.removeAt(lotIndex);
      // If no lots left, remove the entire product
      if (product.lots.isEmpty) {
        _pendingProducts.remove(product.productKey);
      }
    });
  }

  void _removeProduct(String productKey) {
    setState(() {
      _pendingProducts.remove(productKey);
    });
  }

  void _showBatchCodesDialog() {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: colorScheme.surfaceTint,
        title: Text(
          'Batch Codes Created',
          style: TextStyle(color: colorScheme.onSurface),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_createdBatchCodes.length} batches created:',
                style: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.8)),
              ),
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
                        style: TextStyle(
                          fontFamily: 'monospace',
                          color: colorScheme.onSurface,
                        ),
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
            onPressed: () => _exportLabels(context),
            style: TextButton.styleFrom(
              foregroundColor: colorScheme.primary,
            ),
            child: const Text('Export Labels'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: colorScheme.onSurface.withValues(alpha: 0.8),
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportLabels(BuildContext context) async {
    Navigator.of(context).pop(); // Close the success dialog

    // Show dialog to select starting label position
    final startLabel = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export Labels'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Which label number would you like to start from?'),
            const SizedBox(height: 16),
            Text(
              'Avery 5160 sheets have 30 labels (3 columns × 10 rows).\n'
              'If reusing a partial sheet, start from the next available label.',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              decoration: const InputDecoration(
                labelText: 'Starting Label',
                border: OutlineInputBorder(),
              ),
              initialValue: 1,
              items: List.generate(30, (index) => index + 1)
                  .map((labelNum) => DropdownMenuItem(
                        value: labelNum,
                        child: Text('Label $labelNum'),
                      ))
                  .toList(),
              onChanged: (value) {
                Navigator.of(context).pop(value);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (startLabel == null) return; // User cancelled

    try {
      // Get all created items and their lots
      final itemIds = <String>[];
      for (final product in _pendingProducts.values) {
        itemIds.add(product.itemId);
            }

      if (itemIds.isEmpty) {
          final rootCtx = context;
          if (rootCtx.mounted) {
            ScaffoldMessenger.of(rootCtx).showSnackBar(
              const SnackBar(content: Text('No items found to export labels for')),
            );
          }
          return;
        }

      // Get lots data for the created items
      final lotsData = await LabelExportService.getLotsForItems(itemIds);

      if (lotsData.isEmpty) {
        final rootCtx = context;
        if (rootCtx.mounted) {
          ScaffoldMessenger.of(rootCtx).showSnackBar(
            const SnackBar(content: Text('No lots found for created items')),
          );
        }
        return;
      }

      // Export labels using the new service with startIndex (convert to 0-based)
      await LabelExportService.exportLabels(lotsData, startIndex: startLabel - 1);

      final rootCtx = context;
      if (rootCtx.mounted) {
        ScaffoldMessenger.of(rootCtx).showSnackBar(
          SnackBar(content: Text('Generated labels for ${lotsData.length} lots (starting from label $startLabel)')),
        );
      }
    } catch (e) {
      final rootCtx = context;
      if (rootCtx.mounted) {
        ScaffoldMessenger.of(rootCtx).showSnackBar(
          SnackBar(content: Text('Failed to export labels: $e')),
        );
      }
    }
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

  void _listenForMobileScans() {
    _scannerSubscription = _db
        .collection('scanner_sessions')
        .doc(_sessionId)
        .collection('scans')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        final scan = snapshot.docs.first;
        final barcode = scan.data()['barcode'] as String?;
        final processed = scan.data()['processed'] as bool? ?? false;
        
        if (barcode != null && !processed && mounted) {
          _handleBarcode(barcode);
          // Mark as processed
          scan.reference.update({'processed': true});
        }
      }
    });
  }

  Future<void> _loadPreselectedItem(String itemId) async {
    try {
      setState(() => _isProcessing = true);
      
      final itemDoc = await _db.collection('items').doc(itemId).get();
      if (!itemDoc.exists || !mounted) {
        setState(() => _isProcessing = false);
        return;
      }
      
      final itemData = itemDoc.data()!;
      final itemName = itemData['name'] ?? 'Unknown Item';
      final baseUnit = itemData['baseUnit'] ?? 'each';
      
      // Create a product entry for this item
      final product = BulkProductEntry(
        productKey: itemId,
        itemId: itemId,
        itemName: itemName,
        baseUnit: baseUnit,
        isNew: false,
        barcodes: [],
      );
      
      setState(() {
        _pendingProducts[itemId] = product;
        _isProcessing = false;
      });
      
      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ready to add lot for: $itemName'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error loading preselected item: $e');
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading item: $e')),
        );
      }
    }
  }

  void _showMobileScannerQR() {
    // Use custom domain for cleaner URLs
    final url = 'https://scout.littleempathy.com/mobile-scanner/$_sessionId';
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Scan with Phone'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Scan this QR code with your phone to use it as a barcode scanner:',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.white,
                child: QrImageView(
                  data: url,
                  version: QrVersions.auto,
                  size: 200.0,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Session: ${_sessionId.substring(0, 8)}...',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              const Text(
                'Scanned barcodes will appear on this page automatically.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
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
    );
  }

  @override
  void dispose() {
    _scannerSubscription?.cancel();
    _nameSearchDebounceTimer?.cancel();
    _barcodeController.dispose();
    _barcodeFocus.dispose();
    _nameController.dispose();
    _nameFocus.dispose();
    // Clean up session
    _db.collection('scanner_sessions').doc(_sessionId).delete();
    super.dispose();
  }
}

class BulkLotEntry {
  double quantity;
  String? batchCode;
  DateTime? expiresAt;
  String? lotId; // For adding to existing lots

  BulkLotEntry({
    required this.quantity,
    this.batchCode,
    this.expiresAt,
    this.lotId,
  });

  BulkLotEntry copyWith({
    double? quantity,
    String? batchCode,
    DateTime? expiresAt,
    String? lotId,
    bool clearExpiresAt = false,
  }) {
    return BulkLotEntry(
      quantity: quantity ?? this.quantity,
      batchCode: batchCode ?? this.batchCode,
      expiresAt: clearExpiresAt ? null : (expiresAt ?? this.expiresAt),
      lotId: lotId ?? this.lotId,
    );
  }
}

class BulkProductEntry {
  final String productKey; // Unique identifier: item ID for existing items, barcode for new items
  String itemId;
  final String itemName;
  final String baseUnit;
  final bool isNew;
  final Map<String, dynamic>? newItemData;
  final List<String> barcodes; // Multiple barcodes for same product
  final List<BulkLotEntry> lots; // Multiple lots for this product

  BulkProductEntry({
    required this.productKey,
    required this.itemId,
    required this.itemName,
    required this.baseUnit,
    required this.isNew,
    this.newItemData,
    List<String>? barcodes,
    List<BulkLotEntry>? lots,
  }) : 
    barcodes = barcodes ?? [],
    lots = lots ?? [];

  void addBarcode(String barcode) {
    if (!barcodes.contains(barcode)) {
      barcodes.add(barcode);
    }
  }

  void addLot(BulkLotEntry lot) {
    lots.add(lot);
  }

  BulkProductEntry copyWith({
    String? itemId,
    List<String>? barcodes,
    List<BulkLotEntry>? lots,
  }) {
    return BulkProductEntry(
      productKey: productKey,
      itemId: itemId ?? this.itemId,
      itemName: itemName,
      baseUnit: baseUnit,
      isNew: isNew,
      newItemData: newItemData,
      barcodes: barcodes ?? this.barcodes,
      lots: lots ?? this.lots,
    );
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
  String? lotId; // For adding to existing lots

  BulkEntryItem({
    required this.barcode,
    required this.itemId,
    required this.itemName,
    required this.baseUnit,
    required this.isNew,
    required this.quantity,
    this.newItemData,
    this.batchCode,
    this.lotId,
  });

  BulkEntryItem copyWith({double? quantity, String? batchCode, String? lotId}) {
    return BulkEntryItem(
      barcode: barcode,
      itemId: itemId,
      itemName: itemName,
      baseUnit: baseUnit,
      isNew: isNew,
      quantity: quantity ?? this.quantity,
      newItemData: newItemData,
      batchCode: batchCode ?? this.batchCode,
      lotId: lotId ?? this.lotId,
    );
  }
}

class QuickAddNewItemDialog extends StatefulWidget {
  final String barcode;
  final Map<String, dynamic>? productInfo;

  const QuickAddNewItemDialog({super.key, required this.barcode, this.productInfo});

  @override
  State<QuickAddNewItemDialog> createState() => _QuickAddNewItemDialogState();
}

class _QuickAddNewItemDialogState extends State<QuickAddNewItemDialog> {
  final _nameController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  String _baseUnit = 'each';
  bool _isLoading = false;
  DateTime? _expiresAt;

  @override
  void initState() {
    super.initState();
    _enrichProductInfo();
  }

  Future<void> _enrichProductInfo() async {
    // Use provided product info if available
    if (widget.productInfo != null && widget.productInfo!['name'] != null) {
      setState(() {
        _nameController.text = widget.productInfo!['name'];
      });
      return;
    }

    // Otherwise fetch from API
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

  Future<void> _pickExpirationDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
    );
    if (picked != null) {
      setState(() => _expiresAt = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context),
      child: AlertDialog(
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
                  decoration: InputDecoration(
                    labelText: 'Quantity',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.calculate, size: 20),
                      tooltip: 'Calculate by weight',
                      onPressed: () async {
                        final calc = await showWeightCalculator(
                          context: context,
                          itemName: _nameController.text.trim(),
                          unit: _baseUnit,
                        );
                        if (calc != null) {
                          _quantityController.text = calc.toString();
                        }
                      },
                    ),
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
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickExpirationDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Expiration Date (optional)',
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.calendar_today),
              ),
              child: Text(
                _expiresAt == null
                    ? 'No expiration'
                    : MaterialLocalizations.of(context).formatFullDate(_expiresAt!),
              ),
            ),
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
    ),
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
      'expiresAt': _expiresAt,
    });
  }
}

class LotSelectionDialog extends StatefulWidget {
  final String itemId;
  final String itemName;
  final String baseUnit;
  final double defaultQuantity;

  const LotSelectionDialog({
    super.key,
    required this.itemId,
    required this.itemName,
    required this.baseUnit,
    required this.defaultQuantity,
  });

  @override
  State<LotSelectionDialog> createState() => _LotSelectionDialogState();
}

class _LotSelectionDialogState extends State<LotSelectionDialog> {
  final _db = FirebaseFirestore.instance;
  final _quantityController = TextEditingController();
  String? _selectedLotId;
  bool _createNewLot = true;

  @override
  void initState() {
    super.initState();
    _quantityController.text = widget.defaultQuantity.toString();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context),
      child: AlertDialog(
        title: Text('Add Stock to ${widget.itemName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Choose where to add the stock:'),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: RadioMenuButton<bool>(
                    value: true,
                    groupValue: _createNewLot,
                    onChanged: (value) => setState(() {
                      _createNewLot = value ?? true;
                      _selectedLotId = null;
                    }),
                    child: const Text('Create New Lot'),
                  ),
                ),
                Expanded(
                  child: RadioMenuButton<bool>(
                    value: false,
                    groupValue: _createNewLot,
                    onChanged: (value) => setState(() => _createNewLot = value ?? true),
                    child: const Text('Add to Existing Lot'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!_createNewLot) ...[
              const Text('Select Lot:'),
              const SizedBox(height: 8),
              StreamBuilder<QuerySnapshot>(
                stream: _db
                    .collection('items')
                    .doc(widget.itemId)
                    .collection('lots')
                    .orderBy('expiresAt', descending: false)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Text('Error loading lots');
                  }

                  if (!snapshot.hasData) {
                    return const CircularProgressIndicator();
                  }

                  final lots = snapshot.data!.docs;
                  
                  // Filter to only active lots (not archived)
                  final activeLots = lots.where((doc) {
                    final data = doc.data() as Map<String, dynamic>?;
                    return data != null && data['archived'] != true;
                  }).toList();

                  if (activeLots.isEmpty) {
                    return const Text('No existing lots found. A new lot will be created.');
                  }

                  return DropdownButtonFormField<String>(
                    initialValue: _selectedLotId,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Select Lot',
                    ),
                    items: activeLots.map((lotDoc) {
                      final data = lotDoc.data() as Map<String, dynamic>;
                      final lotCode = data['lotCode'] as String? ?? lotDoc.id.substring(0, 6);
                      final qtyRemaining = (data['qtyRemaining'] as num?)?.toDouble() ?? 0.0;
                      final expTs = data['expiresAt'];
                      final expiresAt = expTs is Timestamp ? expTs.toDate() : null;

                      final displayText = "$lotCode (${qtyRemaining.toStringAsFixed(1)} ${widget.baseUnit})${expiresAt != null ? ' - Expires ${MaterialLocalizations.of(context).formatShortDate(expiresAt)}' : ''}";

                      return DropdownMenuItem(
                        value: lotDoc.id,
                        child: Text(displayText),
                      );
                    }).toList(),
                    onChanged: (value) => setState(() => _selectedLotId = value),
                  );
                },
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _quantityController,

              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Quantity to Add',
                suffixText: widget.baseUnit,
                border: const OutlineInputBorder(),
              ),
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
            child: const Text('Add Stock'),
          ),
        ],
      ),
    );
  }

  void _submit() {
    final quantity = double.tryParse(_quantityController.text.trim());
    if (quantity == null || quantity <= 0) return;

    if (!_createNewLot && _selectedLotId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a lot or choose to create a new one')),
      );
      return;
    }

    Navigator.of(context).pop({
      'quantity': quantity,
      'lotId': _createNewLot ? null : _selectedLotId,
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
    return Theme(
      data: Theme.of(context),
      child: AlertDialog(
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
    ),
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
    return Theme(
      data: Theme.of(context),
      child: AlertDialog(
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
    ),
    );
  }
}
class BulkLotAdditionDialog extends StatefulWidget {
  final BulkProductEntry product;
  final Future<String> Function(String itemId) generateBatchCode;

  const BulkLotAdditionDialog({
    super.key,
    required this.product,
    required this.generateBatchCode,
  });

  @override
  State<BulkLotAdditionDialog> createState() => _BulkLotAdditionDialogState();
}

class _BulkLotAdditionDialogState extends State<BulkLotAdditionDialog> {
  final List<BulkLotEntry> _lots = [];
  final List<TextEditingController> _quantityControllers = [];
  final List<TextEditingController> _batchCodeControllers = [];
  bool _createNewLot = false; // Start with "Add to Existing Lot" selected
  String? _selectedLotId;
  final _addToExistingQuantityController = TextEditingController(text: '1.0');

  @override
  void initState() {
    super.initState();
    // Don't add any lots initially - user will choose existing or create new
  }

  @override
  void dispose() {
    for (final controller in _quantityControllers) {
      controller.dispose();
    }
    for (final controller in _batchCodeControllers) {
      controller.dispose();
    }
    _addToExistingQuantityController.dispose();
    super.dispose();
  }

  Future<void> _addLot() async {
    String batchCode;
    
    if (widget.product.isNew || widget.product.itemId.isEmpty) {
      // For new products, generate a unique temporary batch code
      final now = DateTime.now();
      final yearMonth = '${now.year.toString().substring(2)}${now.month.toString().padLeft(2, '0')}';
      
      // Find the highest existing lot number to avoid duplicates
      // Check both the dialog's lots AND the product's existing lots
      int maxLotNumber = 0;
      
      // Check lots in this dialog
      for (final lot in _lots) {
        if (lot.batchCode != null && lot.batchCode!.contains('-')) {
          final parts = lot.batchCode!.split('-');
          if (parts.length == 2) {
            final num = int.tryParse(parts[1]);
            if (num != null && num > maxLotNumber) {
              maxLotNumber = num;
            }
          }
        }
      }
      
      // Check lots already on the product
      for (final lot in widget.product.lots) {
        if (lot.batchCode != null && lot.batchCode!.contains('-')) {
          final parts = lot.batchCode!.split('-');
          if (parts.length == 2) {
            final num = int.tryParse(parts[1]);
            if (num != null && num > maxLotNumber) {
              maxLotNumber = num;
            }
          }
        }
      }
      
      final lotNumber = (maxLotNumber + 1).toString().padLeft(3, '0');
      batchCode = '$yearMonth-$lotNumber';
    } else {
      // For existing products, generate from Firestore
      batchCode = await widget.generateBatchCode(widget.product.itemId);
    }
    
    setState(() {
      _lots.add(BulkLotEntry(quantity: 1.0, batchCode: batchCode));
      _quantityControllers.add(TextEditingController(text: '1.0'));
      _batchCodeControllers.add(TextEditingController(text: batchCode));
    });
  }

  void _removeLot(int index) {
    setState(() {
      _lots.removeAt(index);
      _quantityControllers[index].dispose();
      _batchCodeControllers[index].dispose();
      _quantityControllers.removeAt(index);
      _batchCodeControllers.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context),
      child: AlertDialog(
        title: Text('Add Lots to ${widget.product.itemName}'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 600,
            maxHeight: 600,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Text('Barcodes: ${widget.product.barcodes.join(", ")}'),
              const SizedBox(height: 16),
              const Text('Lot Options:', style: TextStyle(fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Expanded(
                    child: RadioMenuButton<bool>(
                      value: true,
                      groupValue: _createNewLot,
                      onChanged: (value) async {
                        setState(() {
                          _createNewLot = value ?? true;
                          _selectedLotId = null;
                        });
                        // Add first lot when switching to create mode
                        if (_createNewLot && _lots.isEmpty) {
                          await _addLot();
                        }
                      },
                      child: const Text('Create New Lots'),
                    ),
                  ),
                  Expanded(
                    child: RadioMenuButton<bool>(
                      value: false,
                      groupValue: _createNewLot,
                      onChanged: (value) => setState(() => _createNewLot = value ?? true),
                      child: const Text('Add to Existing Lot'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (!_createNewLot) ...[
                if (widget.product.itemId.isEmpty || widget.product.isNew)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('This is a new product with no existing lots.'),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: () async {
                          setState(() {
                            _createNewLot = true;
                          });
                          await _addLot();
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Create New Lot'),
                      ),
                    ],
                  )
                else ...[
                  const Text('Select Lot:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('items')
                        .doc(widget.product.itemId)
                        .collection('lots')
                        .orderBy('expiresAt', descending: false)
                        .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Text('Error loading lots');
                    }

                    if (!snapshot.hasData) {
                      return const CircularProgressIndicator();
                    }

                    final lots = snapshot.data!.docs;
                    
                    // Filter to only active lots (not archived)
                    final activeLots = lots.where((doc) {
                      final data = doc.data() as Map<String, dynamic>?;
                      return data != null && data['archived'] != true;
                    }).toList();

                    if (activeLots.isEmpty) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('No existing lots found.'),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                _createNewLot = true;
                              });
                              _addLot();
                            },
                            icon: const Icon(Icons.add),
                            label: const Text('Create New Lot'),
                          ),
                        ],
                      );
                    }

                    // Auto-select first lot if none selected
                    if (_selectedLotId == null && activeLots.isNotEmpty) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(() {
                            _selectedLotId = activeLots.first.id;
                          });
                        }
                      });
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DropdownButtonFormField<String>(
                          value: _selectedLotId,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'Select Lot',
                          ),
                          items: activeLots.map((lotDoc) {
                            final data = lotDoc.data() as Map<String, dynamic>;
                            final lotCode = data['lotCode'] as String? ?? lotDoc.id.substring(0, 6);
                            final qtyRemaining = (data['qtyRemaining'] as num?)?.toDouble() ?? 0.0;
                            final expTs = data['expiresAt'];
                            final expiresAt = expTs is Timestamp ? expTs.toDate() : null;

                            final displayText = "$lotCode (${qtyRemaining.toStringAsFixed(1)} ${widget.product.baseUnit})${expiresAt != null ? ' - Expires ${MaterialLocalizations.of(context).formatShortDate(expiresAt)}' : ''}";

                            return DropdownMenuItem(
                              value: lotDoc.id,
                              child: Text(displayText),
                            );
                          }).toList(),
                          onChanged: (value) => setState(() => _selectedLotId = value),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _addToExistingQuantityController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Quantity to Add',
                            suffixText: widget.product.baseUnit,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                ],
              ] else ...[
                const Text('Lots to Add:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ..._lots.asMap().entries.map((entry) {
                  final index = entry.key;
                  final lot = _lots[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12.0),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('Lot ${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              const Spacer(),
                              if (_lots.length > 1)
                                IconButton(
                                  icon: const Icon(Icons.delete),
                                  onPressed: () => _removeLot(index),
                                  tooltip: 'Remove lot',
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: _quantityControllers[index],
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: 'Quantity',
                                    suffixText: widget.product.baseUnit,
                                    border: const OutlineInputBorder(),
                                  ),
                                  onChanged: (value) {
                                    final qty = double.tryParse(value);
                                    if (qty != null) {
                                      setState(() {
                                        _lots[index] = _lots[index].copyWith(quantity: qty);
                                      });
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: _batchCodeControllers[index],
                                  decoration: const InputDecoration(
                                    labelText: 'Batch Code',
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (value) {
                                    setState(() {
                                      _lots[index] = _lots[index].copyWith(batchCode: value.isEmpty ? null : value);
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          InkWell(
                            onTap: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: lot.expiresAt ?? DateTime.now().add(const Duration(days: 365)),
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(const Duration(days: 3650)),
                              );
                              if (date != null) {
                                setState(() {
                                  _lots[index] = _lots[index].copyWith(expiresAt: date);
                                });
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Expiration Date (Optional)',
                                border: OutlineInputBorder(),
                                suffixIcon: Icon(Icons.calendar_today),
                              ),
                              child: Text(
                                lot.expiresAt != null
                                    ? MaterialLocalizations.of(context).formatShortDate(lot.expiresAt!)
                                    : 'No expiration date',
                                style: TextStyle(
                                  color: lot.expiresAt != null ? null : Colors.grey,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                TextButton.icon(
                  onPressed: () async {
                    try {
                      await _addLot();
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error adding lot: $e')),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add Another Lot'),
                ),
              ],
            ],
          ),
        ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _submit,
            child: const Text('Add Lots'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final lotsToAdd = <BulkLotEntry>[];

    if (!_createNewLot) {
      // Adding to existing lot
      if (_selectedLotId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a lot')),
        );
        return;
      }
      
      final qty = double.tryParse(_addToExistingQuantityController.text);
      if (qty == null || qty <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid quantity')),
        );
        return;
      }

      lotsToAdd.add(BulkLotEntry(
        quantity: qty,
        lotId: _selectedLotId,
      ));
    } else {
      // Creating new lots
      if (_lots.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please add at least one lot')),
        );
        return;
      }

      // Validate quantities
      if (_lots.any((lot) => lot.quantity <= 0)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All quantities must be greater than 0')),
        );
        return;
      }

      // Generate batch codes for new lots if not provided
      for (final lot in _lots) {
        if (lot.batchCode == null) {
          final batchCode = await widget.generateBatchCode(widget.product.itemId);
          lotsToAdd.add(lot.copyWith(batchCode: batchCode));
        } else {
          lotsToAdd.add(lot);
        }
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop(lotsToAdd);
  }
}

class QuickAddNewProductDialog extends StatefulWidget {
  final String? barcode;
  final String? name;
  final Map<String, dynamic>? productInfo;
  final Map<String, dynamic>? prepopulatedValues;

  const QuickAddNewProductDialog({
    super.key, 
    this.barcode, 
    this.name,
    this.productInfo,
    this.prepopulatedValues,
  });

  @override
  State<QuickAddNewProductDialog> createState() => _QuickAddNewProductDialogState();
}

class _QuickAddNewProductDialogState extends State<QuickAddNewProductDialog> {
  final _nameController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  String _baseUnit = 'each';
  bool _isLoading = false;
  final _lookups = LookupsService();

  // Additional fields
  String _category = '';
  List<String> _categories = [];
  List<OptionItem>? _locations;
  List<OptionItem>? _grants;
  OptionItem? _homeLocation;
  OptionItem? _defaultGrant;
  UseType _useType = UseType.both;
  DateTime? _expiresAt;

  // Prepopulated IDs to resolve after lookups load
  String? _prepopulatedHomeLocationId;
  String? _prepopulatedGrantId;

  @override
  void initState() {
    super.initState();
    
    // First, set values from product info (name, etc.)
    if (widget.productInfo != null) {
      _nameController.text = widget.productInfo!['name'] ?? '';
      _baseUnit = widget.productInfo!['baseUnit'] ?? 'each';
      _category = widget.productInfo!['category'] ?? '';
    } else if (widget.name != null) {
      _nameController.text = widget.name!;
    }
    
    // Then, apply prepopulated values (but don't override name and quantity)
    if (widget.prepopulatedValues != null) {
      final prepop = widget.prepopulatedValues!;
      _baseUnit = prepop['baseUnit'] ?? _baseUnit;
      _category = prepop['category'] ?? _category;
      _prepopulatedHomeLocationId = prepop['homeLocationId'];
      _prepopulatedGrantId = prepop['grantId'];
      _useType = prepop['useType'] != null ? 
        UseType.values.firstWhere((e) => e.name == prepop['useType'], orElse: () => UseType.both) : _useType;
      _expiresAt = prepop['expiresAt'];
    }
    
    _loadLookups();
  }

  Future<void> _loadLookups() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _lookups.locations(),
        _lookups.grants(),
        _loadCategories(),
      ]);
      if (mounted) {
        setState(() {
          _locations = results[0] as List<OptionItem>;
          _grants = results[1] as List<OptionItem>;
          _categories = results[2] as List<String>;
          
          // Resolve prepopulated IDs to OptionItem objects
          if (_prepopulatedHomeLocationId != null && _locations != null) {
            try {
              _homeLocation = _locations!.firstWhere(
                (loc) => loc.id == _prepopulatedHomeLocationId,
              );
            } catch (_) {
              // Location not found, keep as null
            }
          }
          if (_prepopulatedGrantId != null && _grants != null) {
            try {
              _defaultGrant = _grants!.firstWhere(
                (grant) => grant.id == _prepopulatedGrantId,
              );
            } catch (_) {
              // Grant not found, keep as null
            }
          }
          
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<List<String>> _loadCategories() async {
    final snap = await FirebaseFirestore.instance.collection('items').where('archived', isEqualTo: false).get();
    final categories = <String>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      final category = (data['category'] ?? '') as String;
      if (category.isNotEmpty) {
        categories.add(category);
      }
    }
    return categories.toList()..sort();
  }

  Future<void> _pickExpirationDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
    );
    if (picked != null) {
      setState(() => _expiresAt = picked);
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
    final loading = _locations == null || _grants == null;

    return Theme(
      data: Theme.of(context),
      child: AlertDialog(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add New Product${widget.barcode != null ? ' - ${widget.barcode}' : ''}'),
            if (widget.prepopulatedValues != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Pre-filled with previous entry',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),
        content: loading
            ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _nameController,

                      decoration: const InputDecoration(
                        labelText: 'Product Name *',
                        border: OutlineInputBorder(),
                      ),
                      autofocus: true,
                    ),
                    const SizedBox(height: 12),

                    Autocomplete<String>(
                      initialValue: TextEditingValue(text: _category),
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        if (textEditingValue.text.isEmpty) {
                          return _categories.take(10); // Limit to 10 when showing all
                        }
                        
                        final query = textEditingValue.text.toLowerCase();
                        final matches = _categories.where((String option) {
                          return option.toLowerCase().contains(query);
                        }).toList();
                        
                        // Sort: exact matches first, then starts with, then contains
                        matches.sort((a, b) {
                          final aLower = a.toLowerCase();
                          final bLower = b.toLowerCase();
                          
                          // Exact match gets highest priority
                          if (aLower == query) return -1;
                          if (bLower == query) return 1;
                          
                          // Starts with gets higher priority than just contains
                          final aStarts = aLower.startsWith(query);
                          final bStarts = bLower.startsWith(query);
                          if (aStarts && !bStarts) return -1;
                          if (bStarts && !aStarts) return 1;
                          
                          // Alphabetical otherwise
                          return a.compareTo(b);
                        });
                        
                        return matches.take(8); // Limit suggestions
                      },
                      onSelected: (String selection) {
                        setState(() => _category = selection);
                      },
                      fieldViewBuilder: (BuildContext context, TextEditingController textEditingController, FocusNode focusNode, VoidCallback onFieldSubmitted) {
                        return TextFormField(
                          controller: textEditingController,
                          focusNode: focusNode,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Category (optional)',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) => _category = value,
                        );
                      },
                    ),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _quantityController,

                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Initial Quantity *',
                              suffixText: _baseUnit,
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _baseUnit,
                            decoration: const InputDecoration(
                              labelText: 'Unit',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'each', child: Text('each')),
                              DropdownMenuItem(value: 'lbs', child: Text('lbs')),
                              DropdownMenuItem(value: 'kg', child: Text('kg')),
                              DropdownMenuItem(value: 'oz', child: Text('oz')),
                              DropdownMenuItem(value: 'g', child: Text('g')),
                              DropdownMenuItem(value: 'gal', child: Text('gal')),
                              DropdownMenuItem(value: 'L', child: Text('L')),
                              DropdownMenuItem(value: 'ml', child: Text('ml')),
                              DropdownMenuItem(value: 'cups', child: Text('cups')),
                              DropdownMenuItem(value: 'tbsp', child: Text('tbsp')),
                              DropdownMenuItem(value: 'tsp', child: Text('tsp')),
                            ],
                            onChanged: (value) => setState(() => _baseUnit = value ?? 'each'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    DropdownButtonFormField<OptionItem>(
                      initialValue: _homeLocation,
                      decoration: const InputDecoration(
                        labelText: 'Home Location (optional)',
                        border: OutlineInputBorder(),
                      ),
                      items: (_locations ?? [])
                          .map((loc) => DropdownMenuItem(
                            value: loc,
                            child: Text(loc.name),
                          ))
                          .toList(),
                      onChanged: (value) => setState(() => _homeLocation = value),
                    ),
                    const SizedBox(height: 12),

                    DropdownButtonFormField<OptionItem>(
                      initialValue: _defaultGrant,
                      decoration: const InputDecoration(
                        labelText: 'Default Grant (optional)',
                        border: OutlineInputBorder(),
                      ),
                      items: (_grants ?? [])
                          .map((grant) => DropdownMenuItem(
                            value: grant,
                            child: Text(grant.name),
                          ))
                          .toList(),
                      onChanged: (value) => setState(() => _defaultGrant = value),
                    ),
                    const SizedBox(height: 12),

                    SegmentedButton<UseType>(
                      segments: const [
                        ButtonSegment(value: UseType.staff, label: Text('Staff')),
                        ButtonSegment(value: UseType.patient, label: Text('Patient')),
                        ButtonSegment(value: UseType.both, label: Text('Both')),
                      ],
                      selected: {_useType},
                      onSelectionChanged: (selection) => setState(() => _useType = selection.first),
                    ),
                    const SizedBox(height: 12),

                    InkWell(
                      onTap: _pickExpirationDate,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Expiration Date (optional)',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.calendar_today),
                        ),
                        child: Text(
                          _expiresAt == null
                              ? 'No expiration'
                              : MaterialLocalizations.of(context).formatShortDate(_expiresAt!),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        actions: [
          TextButton(
            onPressed: loading ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          if (widget.prepopulatedValues != null)
            TextButton(
              onPressed: () {
                setState(() {
                  // Clear prepopulated values
                  _baseUnit = 'each';
                  _category = '';
                  _homeLocation = null;
                  _defaultGrant = null;
                  _useType = UseType.both;
                  _expiresAt = null;
                  _prepopulatedHomeLocationId = null;
                  _prepopulatedGrantId = null;
                });
              },
              child: const Text('Clear Pre-filled'),
            ),
          FilledButton(
            onPressed: loading ? null : _submit,
            child: _isLoading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Add Product'),
          ),
        ],
      ),
    );
  }

  void _submit() async {
    final name = _nameController.text.trim();
    final quantity = double.tryParse(_quantityController.text.trim());

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product name is required')),
      );
      return;
    }

    if (quantity == null || quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quantity must be greater than 0')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Check if product with this name already exists
      final existingQuery = await FirebaseFirestore.instance
          .collection('items')
          .where('name', isEqualTo: name)
          .limit(1)
          .get();

      if (existingQuery.docs.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('A product with name "$name" already exists')),
          );
        }
        return;
      }

      if (mounted) {
        Navigator.of(context).pop({
          'name': name,
          'baseUnit': _baseUnit,
          'quantity': quantity,
          'barcode': widget.barcode,
          'category': _category.isNotEmpty ? _category : null,
          'homeLocationId': _homeLocation?.id,
          'homeLocationName': _homeLocation?.name,
          'grantId': _defaultGrant?.id,
          'grantName': _defaultGrant?.name,
          'useType': _useType.name,
          'expiresAt': _expiresAt,
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}

class EditLotDialog extends StatefulWidget {
  final BulkLotEntry lot;
  final String productName;
  final String baseUnit;

  const EditLotDialog({
    super.key,
    required this.lot,
    required this.productName,
    required this.baseUnit,
  });

  @override
  State<EditLotDialog> createState() => _EditLotDialogState();
}

class _EditLotDialogState extends State<EditLotDialog> {
  late final TextEditingController _quantityController;
  late final TextEditingController _batchCodeController;
  late DateTime? _expiresAt;

  @override
  void initState() {
    super.initState();
    _quantityController = TextEditingController(text: widget.lot.quantity.toString());
    _batchCodeController = TextEditingController(text: widget.lot.batchCode ?? '');
    _expiresAt = widget.lot.expiresAt;
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _batchCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      backgroundColor: colorScheme.surface,
      surfaceTintColor: colorScheme.surfaceTint,
      title: Text(
        'Edit Lot - ${widget.productName}',
        style: TextStyle(color: colorScheme.onSurface),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _quantityController,

            decoration: InputDecoration(
              labelText: 'Quantity (${widget.baseUnit})',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.calculate, size: 20),
                tooltip: 'Calculate by weight',
                onPressed: () async {
                  final calc = await showWeightCalculator(
                    context: context,
                    itemName: widget.productName,
                    initialQty: widget.lot.quantity,
                    unit: widget.baseUnit,
                  );
                  if (calc != null) {
                    _quantityController.text = calc.toString();
                  }
                },
              ),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _batchCodeController,

            decoration: const InputDecoration(
              labelText: 'Batch Code',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  _expiresAt != null
                      ? 'Expires: ${MaterialLocalizations.of(context).formatShortDate(_expiresAt!)}'
                      : 'No expiration date set',
                  style: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.7)),
                ),
              ),
              TextButton(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _expiresAt ?? DateTime.now().add(const Duration(days: 365)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
                  );
                  if (picked != null) {
                    setState(() => _expiresAt = picked);
                  }
                },
                child: const Text('Set Date'),
              ),
              if (_expiresAt != null)
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() => _expiresAt = null),
                  tooltip: 'Clear expiration date',
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
          child: const Text('Update Lot'),
        ),
      ],
    );
  }

  void _submit() {
    final quantity = double.tryParse(_quantityController.text.trim());
    final batchCode = _batchCodeController.text.trim();

    if (quantity == null || quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quantity must be greater than 0')),
      );
      return;
    }

    if (batchCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Batch code is required')),
      );
      return;
    }

    Navigator.of(context).pop(
      BulkLotEntry(
        quantity: quantity,
        batchCode: batchCode,
        expiresAt: _expiresAt,
      ),
    );
  }
}

class ExistingBatchesDialog extends StatefulWidget {
  final BulkProductEntry product;
  final Future<String> Function(String itemId) generateBatchCode;

  const ExistingBatchesDialog({
    super.key,
    required this.product,
    required this.generateBatchCode,
  });

  @override
  State<ExistingBatchesDialog> createState() => _ExistingBatchesDialogState();
}

class _ExistingBatchesDialogState extends State<ExistingBatchesDialog> {
  final _db = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    debugPrint('ExistingBatchesDialog: Building for itemId=${widget.product.itemId}, itemName=${widget.product.itemName}');
    
    // Check if we have a valid itemId
    if (widget.product.itemId.isEmpty) {
      debugPrint('ExistingBatchesDialog: ERROR - Empty itemId');
      return Theme(
        data: Theme.of(context),
        child: AlertDialog(
          title: Text('Error - ${widget.product.itemName}'),
          content: const Text('This product does not have a valid item ID. Please try again.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }

    return Theme(
      data: Theme.of(context),
      child: AlertDialog(
        title: Text('Existing Batches - ${widget.product.itemName}'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(
            maxHeight: 500,
            maxWidth: 600,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Barcodes: ${widget.product.barcodes.join(", ")}'),
                const SizedBox(height: 16),
                const Text('Current Batches:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                StreamBuilder<QuerySnapshot>(
                stream: _db
                    .collection('items')
                    .doc(widget.product.itemId)
                    .collection('lots')
                    .snapshots(), // Remove archived filter to avoid index issues
                builder: (context, snapshot) {
                  debugPrint('ExistingBatchesDialog: StreamBuilder update - hasData=${snapshot.hasData}, hasError=${snapshot.hasError}, docsCount=${snapshot.data?.docs.length}');
                  
                  if (snapshot.hasError) {
                    debugPrint('ExistingBatchesDialog: Error loading lots: ${snapshot.error}');
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Icon(Icons.error, color: Colors.red, size: 48),
                          const SizedBox(height: 16),
                          Text(
                            'Error loading batches: ${snapshot.error}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                    );
                  }

                  if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  final batches = snapshot.data?.docs ?? [];
                  
                  // Filter out archived batches client-side
                  final activeBatches = batches.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return data['archived'] != true;
                  }).toList();
                  
                  debugPrint('ExistingBatchesDialog: Loaded ${batches.length} total batches, ${activeBatches.length} active');

                  if (activeBatches.isEmpty) {
                    debugPrint('ExistingBatchesDialog: No active batches found for this item');
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'No existing batches found for this product.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: activeBatches.length,
                      itemBuilder: (context, index) {
                        final batchDoc = activeBatches[index];
                        final data = batchDoc.data() as Map<String, dynamic>;
                        final lotCode = data['lotCode'] as String? ?? batchDoc.id.substring(0, 6);
                        final qtyRemaining = (data['qtyRemaining'] as num?)?.toDouble() ?? 0.0;
                        final expTs = data['expiresAt'];
                        final expiresAt = expTs is Timestamp ? expTs.toDate() : null;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Batch: $lotCode',
                                            style: const TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                          Text(
                                            'Quantity: ${qtyRemaining.toStringAsFixed(1)} ${widget.product.baseUnit}',
                                          ),
                                          if (expiresAt != null)
                                            Text(
                                              'Expires: ${MaterialLocalizations.of(context).formatShortDate(expiresAt)}',
                                            ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      children: [
                                        ElevatedButton.icon(
                                          onPressed: () => _addToBatch(batchDoc.id, lotCode, qtyRemaining),
                                          icon: const Icon(Icons.add),
                                          label: const Text('Add to Batch'),
                                          style: ElevatedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        OutlinedButton.icon(
                                          onPressed: () => _editBatch(batchDoc.id, data),
                                          icon: const Icon(Icons.edit),
                                          label: const Text('Edit Batch'),
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                },
              ),
                const SizedBox(height: 16),
                Center(
                  child: ElevatedButton.icon(
                    onPressed: _createNewBatch,
                    icon: const Icon(Icons.add_circle),
                    label: const Text('Create New Batch'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.secondary,
                      foregroundColor: Theme.of(context).colorScheme.onSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _addToBatch(String lotId, String lotCode, double currentQty) async {
    final result = await showDialog<double>(
      context: context,
      builder: (context) => AddToBatchDialog(
        lotCode: lotCode,
        currentQty: currentQty,
        baseUnit: widget.product.baseUnit,
      ),
    );

    if (result != null && mounted) {
      Navigator.of(context).pop([
        BulkLotEntry(
          quantity: result,
          lotId: lotId,
        ),
      ]);
    }
  }

  void _editBatch(String lotId, Map<String, dynamic> batchData) async {
    final lotCode = batchData['lotCode'] as String? ?? 'Unknown';
    final currentQty = (batchData['qtyRemaining'] ?? 0) as num;
    final expiresAtRaw = batchData['expiresAt'];
    DateTime? expiresAt;
    if (expiresAtRaw is Timestamp) {
      expiresAt = expiresAtRaw.toDate();
    }
    final baseUnit = batchData['baseUnit'] as String? ?? 'each';

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => EditBatchDialog(
        lotCode: lotCode,
        currentQty: currentQty.toDouble(),
        currentExpiresAt: expiresAt,
        baseUnit: baseUnit,
      ),
    );

    if (result != null && mounted) {
      try {
        final newQty = result['quantity'] as double;
        final newExpiresAt = result['expiresAt'] as DateTime?;
        
        // Calculate quantity difference for item update
        final qtyDiff = newQty - currentQty.toDouble();

        // Get references
        final lotRef = FirebaseFirestore.instance
            .collection('items')
            .doc(widget.product.itemId)
            .collection('lots')
            .doc(lotId);

        // Update lot
        final updateData = <String, dynamic>{
          'qtyRemaining': newQty,
          'updatedAt': FieldValue.serverTimestamp(),
        };
        
        // Only update expiresAt if it changed
        if (newExpiresAt != expiresAt) {
          updateData['expiresAt'] = newExpiresAt;
        }
        
        await lotRef.update(updateData);

        // Update item's total quantity if it changed
        if (qtyDiff != 0) {
          await FirebaseFirestore.instance
              .collection('items')
              .doc(widget.product.itemId)
              .update({
            'qtyOnHand': FieldValue.increment(qtyDiff),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Batch $lotCode updated successfully')),
          );
          Navigator.of(context).pop(); // Close the dialog
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating batch: $e')),
          );
        }
      }
    }
  }

  void _createNewBatch() async {
    // Return a special signal to create new batch
    Navigator.of(context).pop([
      BulkLotEntry(
        quantity: 1.0, // Default quantity
        lotId: '__CREATE_NEW__', // Special signal
      ),
    ]);
  }
}

class AddToBatchDialog extends StatefulWidget {
  final String lotCode;
  final double currentQty;
  final String baseUnit;

  const AddToBatchDialog({
    super.key,
    required this.lotCode,
    required this.currentQty,
    required this.baseUnit,
  });

  @override
  State<AddToBatchDialog> createState() => _AddToBatchDialogState();
}

class _AddToBatchDialogState extends State<AddToBatchDialog> {
  final _quantityController = TextEditingController(text: '1');

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Add to Batch ${widget.lotCode}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Current quantity: ${widget.currentQty.toStringAsFixed(1)} ${widget.baseUnit}'),
          const SizedBox(height: 16),
          TextField(
            controller: _quantityController,
            keyboardType: TextInputType.number,

            decoration: InputDecoration(
              labelText: 'Quantity to Add',
              suffixText: widget.baseUnit,
              border: const OutlineInputBorder(),
            ),
            autofocus: true,
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
          child: const Text('Add to Batch'),
        ),
      ],
    );
  }

  void _submit() {
    final quantity = double.tryParse(_quantityController.text.trim());
    if (quantity != null && quantity > 0) {
      Navigator.of(context).pop(quantity);
    }
  }
}

class EditBatchDialog extends StatefulWidget {
  final String lotCode;
  final double currentQty;
  final DateTime? currentExpiresAt;
  final String baseUnit;

  const EditBatchDialog({
    super.key,
    required this.lotCode,
    required this.currentQty,
    this.currentExpiresAt,
    required this.baseUnit,
  });

  @override
  State<EditBatchDialog> createState() => _EditBatchDialogState();
}

class _EditBatchDialogState extends State<EditBatchDialog> {
  late final TextEditingController _quantityController;
  DateTime? _expiresAt;

  @override
  void initState() {
    super.initState();
    _quantityController = TextEditingController(
      text: widget.currentQty.toStringAsFixed(1),
    );
    _expiresAt = widget.currentExpiresAt;
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit Batch ${widget.lotCode}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _quantityController,
            keyboardType: TextInputType.number,

            decoration: InputDecoration(
              labelText: 'Quantity Remaining',
              suffixText: widget.baseUnit,
              border: const OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Expiration Date'),
            subtitle: Text(
              _expiresAt != null
                  ? DateFormat.yMd().format(_expiresAt!)
                  : 'No expiration date set',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_expiresAt != null)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'Clear expiration date',
                    onPressed: () {
                      setState(() {
                        _expiresAt = null;
                      });
                    },
                  ),
                IconButton(
                  icon: const Icon(Icons.calendar_today),
                  tooltip: 'Set expiration date',
                  onPressed: _pickExpirationDate,
                ),
              ],
            ),
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
          child: const Text('Save Changes'),
        ),
      ],
    );
  }

  Future<void> _pickExpirationDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)), // 10 years
    );
    if (picked != null) {
      setState(() {
        _expiresAt = picked;
      });
    }
  }

  void _submit() {
    final quantity = double.tryParse(_quantityController.text.trim());
    if (quantity != null && quantity > 0) {
      Navigator.of(context).pop({
        'quantity': quantity,
        'expiresAt': _expiresAt,
      });
    }
  }
}
