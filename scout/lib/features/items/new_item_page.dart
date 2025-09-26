import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';

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
  final TextEditingController _categoryController = TextEditingController();
  final _baseUnit = TextEditingController(text: 'each');
  final _qtyOnHand = TextEditingController(text: '0');
  final _minQty = TextEditingController(text: '0');
  final _barcode = TextEditingController();
  final _barcodeFocus = FocusNode();

  // Multiple barcodes support
  final List<TextEditingController> _barcodeControllers = [];
  final List<FocusNode> _barcodeFocusNodes = [];

  // Lot management fields
  final _lotCode = TextEditingController();
  DateTime? _lotExpirationDate;
  bool _hasExpiration = false;

  List<OptionItem>? _locs;
  List<OptionItem>? _grants;
  List<String> _categories = [];
  OptionItem? _homeLoc;
  OptionItem? _grant;
  UseType _useType = UseType.both;
  UnitType _unitType = UnitType.count;

  bool _saving = false;

  void _addBarcodeField({String? initialValue}) {
    final controller = TextEditingController(text: initialValue ?? '');
    final focusNode = FocusNode();
    _barcodeControllers.add(controller);
    _barcodeFocusNodes.add(focusNode);
  }

  void _removeBarcodeField(int index) {
    if (_barcodeControllers.length > 1) {
      _barcodeControllers[index].dispose();
      _barcodeFocusNodes[index].dispose();
      _barcodeControllers.removeAt(index);
      _barcodeFocusNodes.removeAt(index);
    }
  }

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
    
    // Initialize with at least one barcode field
    _addBarcodeField();
    
    // Handle editing existing item
    if (widget.existingItem != null) {
      final item = widget.existingItem!;
      _name.text = item['name'] ?? '';
      _category = item['category'] ?? '';
      _baseUnit.text = item['baseUnit'] ?? 'each';
      _qtyOnHand.text = (item['qtyOnHand'] ?? 0).toString();
      _minQty.text = (item['minQty'] ?? 0).toString();
      
      // Handle existing barcodes
      final existingBarcodes = (item['barcodes'] as List?)?.cast<String>() ?? [];
      if (existingBarcodes.isNotEmpty) {
        // Clear default empty field and add existing barcodes
        _barcodeControllers.clear();
        _barcodeFocusNodes.clear();
        for (final barcode in existingBarcodes) {
          _addBarcodeField(initialValue: barcode);
        }
      } else if (item['barcode'] != null) {
        // Handle legacy single barcode field
        _barcodeControllers[0].text = item['barcode'];
      }
      
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
        _barcodeControllers[0].text = prefill;
        _barcodeFocusNodes[0].requestFocus();
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
    // Initialize controller
  _categoryController.text = _category;
  
  // Initialize lot code
  _lotCode.text = _generateBatchCode();
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
      _categoryController.text = _category;
      
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

  /// Load categories from the dedicated `categories` lookup collection when
  /// available. Fall back to scanning items for existing categories if the
  /// lookup collection is empty or unavailable (keeps backwards compatibility).
  /// Load categories from the dedicated `categories` lookup collection.
  ///
  /// This intentionally prefers the lookup collection. If the lookup fetch
  /// fails, we return an empty list to avoid surprising behavior.
  Future<List<String>> _loadCategories() async {
    try {
      final lookupItems = await _lookups.categories();
      final names = lookupItems.map((o) => o.name).toSet().toList();
      names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return names;
    } catch (e) {
      // If lookup service fails, return empty list — keep suggestions quiet
      debugPrint('Failed to load categories lookup: $e');
      return <String>[];
    }
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

  // Create a filesystem/ID-safe slug for category names (lowercase, replace spaces with dashes)
  String _categorySlug(String name) {
    final cleaned = name.trim().toLowerCase();
    // Replace non-alphanumeric with dash, collapse multiple dashes
    final slug = cleaned.replaceAll(RegExp(r"[^a-z0-9]+"), '-').replaceAll(RegExp(r'-+'), '-');
    return slug.isEmpty ? DateTime.now().millisecondsSinceEpoch.toString() : slug;
  }

  void _acceptCode(String code) async {
    // Find the first empty barcode field, or the focused one
    int targetIndex = -1;
    
    // First check if any field is focused
    for (int i = 0; i < _barcodeFocusNodes.length; i++) {
      if (_barcodeFocusNodes[i].hasFocus) {
        targetIndex = i;
        break;
      }
    }
    
    // If no field is focused, find the first empty one
    if (targetIndex == -1) {
      for (int i = 0; i < _barcodeControllers.length; i++) {
        if (_barcodeControllers[i].text.isEmpty) {
          targetIndex = i;
          break;
        }
      }
    }
    
    // If still no target, use the first field
    if (targetIndex == -1) {
      targetIndex = 0;
    }
    
    setState(() {
      _barcodeControllers[targetIndex].text = code;
      _barcodeControllers[targetIndex].selection = TextSelection(baseOffset: 0, extentOffset: code.length);
    });
    FocusScope.of(context).requestFocus(_barcodeFocusNodes[targetIndex]);

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
    
    // Additional validation for lot fields
    if (_hasExpiration && _lotExpirationDate == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an expiration date or uncheck "Has expiration date"')),
      );
      return;
    }
    
    // Capture the BuildContext to use after async gaps
    final rootCtx = context;
    setState(() => _saving = true);
    try {
      // Collect all non-empty barcodes
      final barcodes = _barcodeControllers
          .map((controller) => controller.text.trim())
          .where((barcode) => barcode.isNotEmpty)
          .toList();
      
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

        // barcodes: array of all barcodes
        if (barcodes.isNotEmpty) 'barcodes': barcodes,
        // Keep legacy single barcode field for backward compatibility (first barcode)
        if (barcodes.isNotEmpty) 'barcode': barcodes.first,
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
          batchCode = _lotCode.text.trim().isNotEmpty ? _lotCode.text.trim() : _generateBatchCode();
          final lotRef = ref.collection('lots').doc();
          await lotRef.set({
            'lotCode': batchCode,
            'qtyRemaining': qtyOnHand,
            'baseUnit': _baseUnit.text.trim().isEmpty ? 'each' : _baseUnit.text.trim(),
            'expiresAt': _hasExpiration && _lotExpirationDate != null ? Timestamp.fromDate(_lotExpirationDate!) : null,
            'openAt': null,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }

        await Audit.log('item.create', {
          'itemId': ref.id,
          'name': _name.text.trim(),
          if (barcodes.isNotEmpty) 'barcodes': barcodes,
          if (batchCode != null) 'batchCode': batchCode,
        });
      }

    if (!rootCtx.mounted) return;
      final savedCategory = _category.trim();
          if (savedCategory.isNotEmpty) {
            final exists = _categories.any((c) => c.toLowerCase() == savedCategory.toLowerCase());
            if (!exists) {
              // Persist a new category document in the `categories` lookup collection
              try {
                final slug = _categorySlug(savedCategory);
                final docRef = _db.collection('categories').doc(slug);

                // Upsert the category document by slug (idempotent)
                await docRef.set({
                  'name': savedCategory,
                  'active': true,
                  'createdAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));
              } catch (_) {
                // Non-fatal: fall back to adding in-memory so suggestions work
              }

              setState(() {
                _categories.add(savedCategory);
                _categories.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
              });
            }
          }
          if (rootCtx.mounted) Navigator.pop(rootCtx, true);
    } catch (e) {
      if (!rootCtx.mounted) return;
      ScaffoldMessenger.of(rootCtx).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    } finally {
      if (rootCtx.mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Don't block on lookups - show form immediately and populate dropdowns as data loads
    return Scaffold(
      appBar: AppBar(title: Text(widget.itemId != null ? 'Edit Item' : 'New Item')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // USB wedge: capture into the first empty barcode field, or the focused one
            UsbWedgeScanner(
              allow: (_) {
                // Allow if any barcode field is focused
                if (_barcodeFocusNodes.any((node) => node.hasFocus)) return true;
                // Or if the first barcode field is empty
                return _barcodeControllers.isNotEmpty && _barcodeControllers[0].text.isEmpty;
              },
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

                  TypeAheadField<String>(
                    controller: _categoryController,
                    hideOnEmpty: false,
                    builder: (context, controller, focusNode) {
                      return TextField(
                        controller: controller,
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
                    suggestionsCallback: (pattern) {
                      if (pattern.isEmpty) {
                        return _categories.take(10).toList(); // Limit to 10 when showing all
                      }

                      final query = pattern.toLowerCase();
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

                      return matches.take(8).toList(); // Limit suggestions
                    },
                    itemBuilder: (context, String suggestion) {
                      return ListTile(
                        title: Text(suggestion),
                      );
                    },
                    onSelected: (String suggestion) {
                      setState(() {
                        _category = suggestion;
                        // Ensure the visible text field is updated when a suggestion is picked
                        _categoryController.text = suggestion;
                        // Auto-suggest unit type based on category
                        final suggestedType = _suggestUnitTypeForCategory(suggestion);
                        if (suggestedType != _unitType) {
                          _unitType = suggestedType;
                          // Update unit suggestion if it's still generic
                          if (_baseUnit.text == 'each' || _baseUnit.text.isEmpty ||
                              !_unitType.commonUnits.contains(_baseUnit.text)) {
                            _baseUnit.text = _unitType.commonUnits.first;
                          }
                        }
                      });
                    },
                    decorationBuilder: (context, child) {
                      return Material(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        elevation: 4.0,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 200),
                          child: child,
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

                  TypeAheadField<String>(
                    controller: TextEditingController(text: _baseUnit.text),
                    builder: (context, controller, focusNode) {
                      return TextFormField(
                        controller: controller,
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
                    suggestionsCallback: (pattern) {
                      final options = _unitType.commonUnits.where((unit) =>
                        unit.toLowerCase().contains(pattern.toLowerCase())
                      ).toList();
                      if (options.isEmpty && pattern.isNotEmpty) {
                        // Allow custom units but show suggestions
                        return _unitType.commonUnits;
                      }
                      return options;
                    },
                    itemBuilder: (context, String suggestion) {
                      return ListTile(
                        title: Text(suggestion),
                      );
                    },
                    onSelected: (String selection) {
                      setState(() {
                        _baseUnit.text = selection;
                      });
                    },
                    decorationBuilder: (context, child) {
                      return Material(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        elevation: 4.0,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 200),
                          child: child,
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
                  const SizedBox(height: 16),

                  // Lot Management Section
                  Text(
                    'Initial Lot Information',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),

                  TextFormField(
                    controller: _lotCode,
                    textInputAction: TextInputAction.next,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                    decoration: const InputDecoration(
                      labelText: 'Lot Code / Batch Number',
                      hintText: 'Auto-generated, or enter custom',
                    ),
                  ),
                  const SizedBox(height: 8),

                  Row(
                    children: [
                      Expanded(
                        child: CheckboxListTile(
                          title: const Text('Has expiration date'),
                          value: _hasExpiration,
                          onChanged: (value) {
                            setState(() {
                              _hasExpiration = value ?? false;
                              if (!value!) {
                                _lotExpirationDate = null;
                              }
                            });
                          },
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                    ],
                  ),

                  if (_hasExpiration)
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _lotExpirationDate ?? DateTime.now().add(const Duration(days: 365)),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365 * 10)), // 10 years from now
                        );
                        if (picked != null) {
                          setState(() => _lotExpirationDate = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Expiration Date',
                          suffixIcon: Icon(Icons.calendar_today),
                        ),
                        child: Text(
                          _lotExpirationDate != null
                              ? '${_lotExpirationDate!.month}/${_lotExpirationDate!.day}/${_lotExpirationDate!.year}'
                              : 'Tap to select date',
                          style: TextStyle(
                            color: _lotExpirationDate != null
                                ? Theme.of(context).colorScheme.onSurface
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),

                  if (_hasExpiration)
                    const SizedBox(height: 8),

                  const SizedBox(height: 16),

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

                  // Multiple Barcodes Section
                  Text(
                    'Barcodes / QR Codes',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Dynamic barcode fields
                  ...List.generate(_barcodeControllers.length, (index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _barcodeControllers[index],
                              focusNode: _barcodeFocusNodes[index],
                              textInputAction: TextInputAction.done,
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                              decoration: InputDecoration(
                                labelText: 'Barcode / QR ${index + 1}${index == 0 ? ' (optional)' : ''}',
                                prefixIcon: IconButton(
                                  tooltip: 'Scan',
                                  icon: const Icon(Icons.qr_code),
                                  onPressed: () async {
                                    // capture the exact BuildContext you'll use after the await
                                    final rootCtx = context;

                                    final code = await showModalBottomSheet<String>(
                                      context: rootCtx,
                                      isScrollControlled: true,
                                      builder: (_) => ScannerSheet(
                                        title: 'Scan barcode ${index + 1}',
                                      ),
                                    );

                                    // Guard the same context var you'll pass to ScaffoldMessenger
                                    if (!rootCtx.mounted) return;
                                    if (code == null || code.isEmpty) return;

                                    setState(() {
                                      _barcodeControllers[index].text = code;
                                    });
                                    ScaffoldMessenger.of(rootCtx).showSnackBar(
                                      SnackBar(content: Text('Scanned: $code')),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                          if (_barcodeControllers.length > 1)
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () => setState(() => _removeBarcodeField(index)),
                              tooltip: 'Remove barcode',
                            ),
                        ],
                      ),
                    );
                  }),

                  // Add barcode button
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _addBarcodeField()),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Another Barcode'),
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

  @override
  void dispose() {
    _name.dispose();
    _categoryController.dispose();
    _baseUnit.dispose();
    _qtyOnHand.dispose();
    _minQty.dispose();
    _barcode.dispose();
    _barcodeFocus.dispose();
    _lotCode.dispose();
    // Dispose barcode controllers and focus nodes
    for (final controller in _barcodeControllers) {
      controller.dispose();
    }
    for (final focusNode in _barcodeFocusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }
}
