import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../data/lookups_service.dart';
import '../../models/option_item.dart';

// Audit helper
import '../../utils/audit.dart';

// Optional: USB wedge capture (keyboard-emulating scanners)
import '../../widgets/usb_wedge_scanner.dart';

// Use the bottom-sheet scanner
import '../../widgets/scanner_sheet.dart';

import '../../data/product_enrichment_service.dart';

enum UseType { staff, patient, both }

enum UnitType {
  count('Count', ['each', 'pieces', 'items', 'boxes', 'cans', 'bottles', 'tubes']),
  weight('Weight', ['grams', 'kg', 'lbs', 'ounces', 'pounds']),
  length('Length', ['meters', 'feet', 'yards', 'inches', 'cm']),
  area('Area', ['sq meters', 'sq feet', 'sheets', 'reams']),
  volume('Volume', ['liters', 'ml', 'gallons', 'cups', 'fl oz']);

  const UnitType(this.displayName, this.commonUnits);
  final String displayName;
  final List<String> commonUnits;
}

class NewItemPage extends StatefulWidget {
  final String? initialBarcode; // optional prefill
  final Map<String, dynamic>? productInfo; // optional product info from APIs
  final String? itemId; // for editing existing items
  final Map<String, dynamic>? existingItem; // existing item data for editing
  
  const NewItemPage({
    super.key, 
    this.initialBarcode, 
    this.productInfo,
    this.itemId,
    this.existingItem,
  });

  @override
  State<NewItemPage> createState() => _NewItemPageState();
}

class _NewItemPageState extends State<NewItemPage> {
  final _db = FirebaseFirestore.instance;
  final _lookups = LookupsService();
  final _form = GlobalKey<FormState>();

  final _name = TextEditingController();
  String _category = '';
  final _baseUnit = TextEditingController(text: 'each');
  final _qtyOnHand = TextEditingController(text: '0');
  final _minQty = TextEditingController(text: '0');
  final _barcode = TextEditingController();
  final _barcodeFocus = FocusNode();

  List<OptionItem>? _locs;
  List<OptionItem>? _grants;
  List<String> _categories = [];
  OptionItem? _homeLoc;
  OptionItem? _grant;
  UseType _useType = UseType.both;
  UnitType _unitType = UnitType.count;

  bool _saving = false;

  String _generateBatchCode() {
    final now = DateTime.now();
    final yy = now.year.toString().substring(2); // Last two digits of year
    final mm = now.month.toString().padLeft(2, '0'); // Month with leading zero
    final monthKey = '$yy$mm';
    
    // For new items, just use a simple counter starting from A
    // In a production app, you might want to track this globally or per month
    final letter = 'A'; // Simple default for new items
    return '$monthKey$letter';
  }

  @override
  void initState() {
    super.initState();
    
    // Handle editing existing item
    if (widget.existingItem != null) {
      final item = widget.existingItem!;
      _name.text = item['name'] ?? '';
      _category = item['category'] ?? '';
      _baseUnit.text = item['baseUnit'] ?? 'each';
      _qtyOnHand.text = (item['qtyOnHand'] ?? 0).toString();
      _minQty.text = (item['minQty'] ?? 0).toString();
      _barcode.text = item['barcode'] ?? '';
      
      // Handle additional fields
      if (item['homeLocationId'] != null) {
        // Will be resolved after lookups load
      }
      if (item['grantId'] != null) {
        // Will be resolved after lookups load
      }
      _useType = item['useType'] != null ? 
        UseType.values.firstWhere((e) => e.name == item['useType'], orElse: () => UseType.both) : UseType.both;
    } else {
      // Handle new item creation
      final prefill = widget.initialBarcode ?? '';
      if (prefill.isNotEmpty) {
        _barcode.text = prefill;
        _barcode.selection = TextSelection(baseOffset: 0, extentOffset: prefill.length);
      }

      // Prefill with product info from APIs
      if (widget.productInfo != null) {
        final info = widget.productInfo!;
        if (info['name'] != null && _name.text.isEmpty) {
          _name.text = info['name'];
        }
        if (info['category'] != null && _category.isEmpty) {
          _category = info['category'];
        }
        if (info['brand'] != null && _category.isEmpty) {
          _category = info['brand']; // Use brand as category if no category
        }
      }
    }

    _loadLookups();
  }

  Future<void> _loadLookups() async {
    final results = await Future.wait([
      _lookups.locations(),
      _lookups.grants(),
      _loadCategories(),
    ]);
    if (!mounted) return;
    setState(() {
      _locs = results[0] as List<OptionItem>;
      _grants = results[1] as List<OptionItem>;
      _categories = results[2] as List<String>;
      
      // Resolve IDs for existing item
      if (widget.existingItem != null) {
        final item = widget.existingItem!;
        if (item['homeLocationId'] != null && _locs != null) {
          try {
            _homeLoc = _locs!.firstWhere(
              (loc) => loc.id == item['homeLocationId'],
            );
          } catch (_) {
            // Location not found, keep as null
          }
        }
        if (item['grantId'] != null && _grants != null) {
          try {
            _grant = _grants!.firstWhere(
              (grant) => grant.id == item['grantId'],
            );
          } catch (_) {
            // Grant not found, keep as null
          }
        }
      }
    });
  }

  Future<List<String>> _loadCategories() async {
    final snap = await _db.collection('items').where('archived', isEqualTo: false).get();
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

  UnitType _suggestUnitTypeForCategory(String category) {
    final lowerCategory = category.toLowerCase();
    
    // Craft supplies and paper products
    if (lowerCategory.contains('paper') || lowerCategory.contains('cardstock') || 
        lowerCategory.contains('fabric') || lowerCategory.contains('yarn') ||
        lowerCategory.contains('thread') || lowerCategory.contains('bead') ||
        lowerCategory.contains('ribbon') || lowerCategory.contains('craft')) {
      return UnitType.length; // Often measured by length/yard
    }
    
    // Food and beverages (countable items)
    if (lowerCategory.contains('food') || lowerCategory.contains('beverage') ||
        lowerCategory.contains('snack') || lowerCategory.contains('canned') ||
        lowerCategory.contains('packaged')) {
      return UnitType.count;
    }
    
    // Bulk items
    if (lowerCategory.contains('flour') || lowerCategory.contains('sugar') ||
        lowerCategory.contains('rice') || lowerCategory.contains('grain') ||
        lowerCategory.contains('bulk')) {
      return UnitType.weight;
    }
    
    // Cleaning supplies
    if (lowerCategory.contains('cleaning') || lowerCategory.contains('chemical') ||
        lowerCategory.contains('liquid')) {
      return UnitType.volume;
    }
    
    // Default to count for most items
    return UnitType.count;
  }

  void _acceptCode(String code) async {
    setState(() {
      _barcode.text = code;
      _barcode.selection = TextSelection(baseOffset: 0, extentOffset: code.length);
    });
    FocusScope.of(context).requestFocus(_barcodeFocus);

    // If name is empty, try to enrich from external APIs
    if (_name.text.trim().isEmpty) {
      final info = await ProductEnrichmentService.fetchProductInfo(code);
      if (info != null && info['name'] != null && mounted) {
        setState(() {
          _name.text = info['name'];
          if (info['category'] != null && info['category'].isNotEmpty) {
            _category = info['category'];
            // Auto-suggest unit type based on enriched category
            final suggestedType = _suggestUnitTypeForCategory(_category);
            _unitType = suggestedType;
            // Suggest appropriate unit
            if (_baseUnit.text == 'each' || _baseUnit.text.isEmpty) {
              _baseUnit.text = _unitType.commonUnits.first;
            }
          }
        });
      }
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final code = _barcode.text.trim();
      final qtyOnHand = num.tryParse(_qtyOnHand.text.trim()) ?? 0;
      
      final itemData = Audit.attach({
        'name': _name.text.trim(),
        'category': _category.trim().isEmpty ? null : _category.trim(),
        'baseUnit': _baseUnit.text.trim().isEmpty ? 'each' : _baseUnit.text.trim(),
        // keep legacy 'unit' in sync if other code still reads it
        'unit': _baseUnit.text.trim().isEmpty ? 'each' : _baseUnit.text.trim(),
        'unitType': _unitType.name, // count | weight | length | area | volume
        'qtyOnHand': qtyOnHand,
        'minQty': num.tryParse(_minQty.text.trim()) ?? 0,
        'maxQty': null,
        'useType': _useType.name, // staff | patient | both
        'grantId': _grant?.id,
        'departmentId': null,
        'homeLocationId': _homeLoc?.id,
        'expiresAt': null,
        'lastUsedAt': null,
        'tags': <String>[],
        'imageUrl': null,

        // barcode: single + array
        if (code.isNotEmpty) 'barcode': code,
        if (code.isNotEmpty) 'barcodes': FieldValue.arrayUnion([code]),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (widget.itemId != null) {
        // Update existing item
        await _db.collection('items').doc(widget.itemId).update(itemData);
        
        await Audit.log('item.update', {
          'itemId': widget.itemId,
          'name': _name.text.trim(),
          'changes': itemData,
        });
      } else {
        // Create new item
        final ref = _db.collection('items').doc();
        itemData['createdAt'] = FieldValue.serverTimestamp();
        
        await ref.set(itemData, SetOptions(merge: true));

        // Create initial lot if qtyOnHand > 0
        String? batchCode;
        if (qtyOnHand > 0) {
          batchCode = _generateBatchCode();
          final lotRef = ref.collection('lots').doc();
          await lotRef.set({
            'lotCode': batchCode,
            'qtyRemaining': qtyOnHand,
            'baseUnit': _baseUnit.text.trim().isEmpty ? 'each' : _baseUnit.text.trim(),
            'expiresAt': null,
            'openAt': null,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }

        await Audit.log('item.create', {
          'itemId': ref.id,
          'name': _name.text.trim(),
          if (code.isNotEmpty) 'barcode': code,
          if (batchCode != null) 'batchCode': batchCode,
        });
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _baseUnit.dispose();
    _qtyOnHand.dispose();
    _minQty.dispose();
    _barcode.dispose();
    _barcodeFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loading = _locs == null || _grants == null;

    return Scaffold(
      appBar: AppBar(title: Text(widget.itemId != null ? 'Edit Item' : 'New Item')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // USB wedge: only capture into barcode if field is focused or empty
                  UsbWedgeScanner(
                    allow: (_) => _barcodeFocus.hasFocus || _barcode.text.isEmpty,
                    onCode: _acceptCode,
                  ),

                  TextFormField(
                    controller: _name,
                    textInputAction: TextInputAction.next,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                    decoration: const InputDecoration(labelText: 'Name *'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 8),

                  Autocomplete<String>(
                    initialValue: TextEditingValue(text: _category),
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      if (textEditingValue.text.isEmpty) {
                        return _categories;
                      }
                      return _categories.where((String option) {
                        return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                      });
                    },
                    onSelected: (String selection) {
                      _category = selection;
                      // Auto-suggest unit type based on category
                      final suggestedType = _suggestUnitTypeForCategory(selection);
                      if (suggestedType != _unitType) {
                        setState(() => _unitType = suggestedType);
                        // Update unit suggestion if it's still generic
                        if (_baseUnit.text == 'each' || _baseUnit.text.isEmpty || 
                            !_unitType.commonUnits.contains(_baseUnit.text)) {
                          _baseUnit.text = _unitType.commonUnits.first;
                        }
                      }
                    },
                    fieldViewBuilder: (BuildContext context, TextEditingController textEditingController, FocusNode focusNode, VoidCallback onFieldSubmitted) {
                      return TextFormField(
                        controller: textEditingController,
                        focusNode: focusNode,
                        textInputAction: TextInputAction.next,
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                        decoration: const InputDecoration(labelText: 'Category'),
                        onChanged: (value) {
                          _category = value;
                          // Auto-suggest unit type for manually typed categories too
                          if (value.isNotEmpty) {
                            final suggestedType = _suggestUnitTypeForCategory(value);
                            if (suggestedType != _unitType) {
                              setState(() => _unitType = suggestedType);
                              // Update unit suggestion if it's still generic
                              if (_baseUnit.text == 'each' || _baseUnit.text.isEmpty || 
                                  !_unitType.commonUnits.contains(_baseUnit.text)) {
                                _baseUnit.text = _unitType.commonUnits.first;
                              }
                            }
                          }
                        },
                      );
                    },
                    optionsViewBuilder: (BuildContext context, AutocompleteOnSelected<String> onSelected, Iterable<String> options) {
                      final colorScheme = Theme.of(context).colorScheme;
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          color: colorScheme.surfaceContainerHighest,
                          elevation: 4.0,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 200),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (BuildContext context, int index) {
                                final String option = options.elementAt(index);
                                return InkWell(
                                  onTap: () => onSelected(option),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Text(
                                      option,
                                      style: TextStyle(color: colorScheme.onSurface),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),

                  DropdownButtonFormField<UnitType>(
                    initialValue: _unitType,
                    items: UnitType.values.map((type) => DropdownMenuItem(
                      value: type,
                      child: Text(
                        type.displayName,
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                      ),
                    )).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _unitType = value);
                        // Suggest a common unit for this type if current unit is generic
                        if (_baseUnit.text == 'each' || _baseUnit.text.isEmpty) {
                          _baseUnit.text = _unitType.commonUnits.first;
                        }
                      }
                    },
                    decoration: const InputDecoration(labelText: 'Unit Type'),
                    dropdownColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  const SizedBox(height: 8),

                  Autocomplete<String>(
                    initialValue: TextEditingValue(text: _baseUnit.text),
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      final options = _unitType.commonUnits.where((unit) =>
                        unit.toLowerCase().contains(textEditingValue.text.toLowerCase())
                      ).toList();
                      if (options.isEmpty && textEditingValue.text.isNotEmpty) {
                        // Allow custom units but show suggestions
                        return _unitType.commonUnits;
                      }
                      return options;
                    },
                    onSelected: (String selection) {
                      _baseUnit.text = selection;
                    },
                    fieldViewBuilder: (BuildContext context, TextEditingController textEditingController, FocusNode focusNode, VoidCallback onFieldSubmitted) {
                      return TextFormField(
                        controller: textEditingController,
                        focusNode: focusNode,
                        textInputAction: TextInputAction.next,
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                        decoration: InputDecoration(
                          labelText: 'Base unit (e.g., ${_unitType.commonUnits.take(3).join(", ")})',
                        ),
                        onChanged: (value) {
                          _baseUnit.text = value;
                        },
                      );
                    },
                    optionsViewBuilder: (BuildContext context, AutocompleteOnSelected<String> onSelected, Iterable<String> options) {
                      final colorScheme = Theme.of(context).colorScheme;
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          color: colorScheme.surfaceContainerHighest,
                          elevation: 4.0,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 200),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (BuildContext context, int index) {
                                final String option = options.elementAt(index);
                                return InkWell(
                                  onTap: () => onSelected(option),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Text(
                                      option,
                                      style: TextStyle(color: colorScheme.onSurface),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),

                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _qtyOnHand,
                          keyboardType: TextInputType.number,
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                          decoration: const InputDecoration(labelText: 'Qty on hand'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _minQty,
                          keyboardType: TextInputType.number,
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                          decoration: const InputDecoration(labelText: 'Min qty (reorder)'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  DropdownButtonFormField<OptionItem>(
                    initialValue: _homeLoc,
                    items: (_locs ?? [])
                        .map((o) => DropdownMenuItem(
                          value: o, 
                          child: Text(
                            o.name,
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                          ),
                        ))
                        .toList(),
                    onChanged: (v) => setState(() => _homeLoc = v),
                    decoration: const InputDecoration(labelText: 'Home location'),
                    dropdownColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  const SizedBox(height: 8),

                  DropdownButtonFormField<OptionItem>(
                    initialValue: _grant,
                    items: (_grants ?? [])
                        .map((o) => DropdownMenuItem(
                          value: o, 
                          child: Text(
                            o.name,
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                          ),
                        ))
                        .toList(),
                    onChanged: (v) => setState(() => _grant = v),
                    decoration: const InputDecoration(labelText: 'Default grant (optional)'),
                    dropdownColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  const SizedBox(height: 8),

                  SegmentedButton<UseType>(
                    segments: const [
                      ButtonSegment(value: UseType.staff, label: Text('Staff')),
                      // ButtonSegment(value: UseType.patient, label: Text('Patient')),
                      ButtonSegment(value: UseType.both, label: Text('Both')),
                    ],
                    selected: {_useType},
                    onSelectionChanged: (s) => setState(() => _useType = s.first),
                  ),
                  const SizedBox(height: 8),

                  // Barcode with scan button — uses ScannerSheet
                  TextFormField(
                    controller: _barcode,
                    focusNode: _barcodeFocus,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: 'Barcode / QR (optional)',
                      prefixIcon: IconButton(
                        tooltip: 'Scan',
                        icon: const Icon(Icons.qr_code),
                        onPressed: () async {
  // capture the exact BuildContext you’ll use after the await
  final rootCtx = context;

  final code = await showModalBottomSheet<String>(
    context: rootCtx,
    isScrollControlled: true,
    builder: (_) => const ScannerSheet(
      title: 'Scan barcode for new item',
    ),
  );

  // Guard the same context var you’ll pass to ScaffoldMessenger
  if (!rootCtx.mounted) return;
  if (code == null || code.isEmpty) return;

  _acceptCode(code);
  ScaffoldMessenger.of(rootCtx).showSnackBar(
    SnackBar(content: Text('Scanned: $code')),
  );
},

                      ),
                    ),
                  ),

                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save),
                    label: const Text('Save'),
                  ),
                ],
              ),
            ),
    );
  }
}
