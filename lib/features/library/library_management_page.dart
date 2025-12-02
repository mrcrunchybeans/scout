import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:scout/models/library_item.dart';
import 'package:scout/utils/audit.dart';
import 'package:scout/utils/operator_store.dart';
import 'package:scout/data/lookups_service.dart';
import 'package:scout/models/option_item.dart';
import 'package:scout/widgets/image_picker_widget.dart';
import 'package:uuid/uuid.dart';

enum UseType { staff, patient, both }

class LibraryManagementPage extends StatefulWidget {
  const LibraryManagementPage({super.key});

  @override
  State<LibraryManagementPage> createState() => _LibraryManagementPageState();
}

class _LibraryManagementPageState extends State<LibraryManagementPage> {
  final _db = FirebaseFirestore.instance;
  final _searchController = TextEditingController();
  LibraryItemStatus? _filterStatus;
  bool _showOverdueOnly = false;
  bool _compactView = true;
  String? _filterGrantId;
  List<OptionItem> _grants = [];

  @override
  void initState() {
    super.initState();
    _loadGrants();
  }

  Future<void> _loadGrants() async {
    final grants = await LookupsService().grants();
    if (mounted) {
      setState(() => _grants = grants);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _showRestockDialog(LibraryItem item) async {
    final notesController = TextEditingController();
    final maxUsesController = TextEditingController(text: item.maxUses?.toString() ?? '');
    bool fullRestock = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Restock / Maintenance: ${item.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  value: fullRestock,
                  onChanged: (v) => setState(() => fullRestock = v),
                  title: const Text('Full restock (reset uses to 0)'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: maxUsesController,
                  decoration: const InputDecoration(
                    labelText: 'Set max uses (optional)',
                    hintText: 'e.g., 20',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (result != true) return;

    try {
      final data = Audit.attach({
        'notes': notesController.text.trim(),
      });

      if (fullRestock) {
        data['usageCount'] = 0;
        data['status'] = LibraryItemStatus.available.value;
      }

      final maxUsesText = maxUsesController.text.trim();
      if (maxUsesText.isNotEmpty) {
        final maxUses = int.tryParse(maxUsesText);
        if (maxUses != null && maxUses > 0) {
          data['maxUses'] = maxUses;
        }
      }

      await _db.collection('library_items').doc(item.id).update(data);

      await Audit.log('library.restock', {
        'itemId': item.id,
        'itemName': item.name,
        'restockedTo': fullRestock ? 'full' : maxUsesController.text.trim(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Item restocked/maintained')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to restock item: $e')),
      );
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _buildQuery() {
    Query<Map<String, dynamic>> query = _db.collection('library_items');

    // Apply status filter
    if (_filterStatus != null) {
      query = query.where('status', isEqualTo: _filterStatus!.value);
    }

    // Order by name
    query = query.orderBy('name');

    return query.snapshots();
  }

  List<LibraryItem> _filterItems(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final items = docs.map((doc) => LibraryItem.fromFirestore(doc)).toList();

    // Apply search filter
    final searchTerm = _searchController.text.trim().toLowerCase();
    var filtered = items;

    if (searchTerm.isNotEmpty) {
      filtered = filtered.where((item) {
        return item.name.toLowerCase().contains(searchTerm) ||
            (item.barcode?.toLowerCase().contains(searchTerm) ?? false) ||
            (item.checkedOutBy?.toLowerCase().contains(searchTerm) ?? false);
      }).toList();
    }

    // Apply restocking filter
    if (_showOverdueOnly) {
      filtered = filtered.where((item) => item.needsRestocking).toList();
    }

    // Apply grant filter
    if (_filterGrantId != null) {
      filtered = filtered.where((item) => item.grantId == _filterGrantId).toList();
    }

    return filtered;
  }

  Future<void> _showAddItemDialog() async {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final barcodeController = TextEditingController();
    final maxUsesController = TextEditingController();
    final restockThresholdController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    
    // Load dropdowns
    final lookups = LookupsService();
    final locations = await lookups.locations();
    final interventions = await lookups.interventions();
    final grants = await lookups.grants();
    
    String? selectedCategory;
    String? selectedLocation;
    String? selectedGrantId;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add Library Item'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name *',
                      hintText: 'e.g., Projector, Laptop, Camera',
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: descController,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      hintText: 'Additional details',
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedCategory,
                    decoration: const InputDecoration(
                      labelText: 'Category (Intervention)',
                      hintText: 'Select category',
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('-- None --'),
                      ),
                      ...interventions.map((item) => DropdownMenuItem<String>(
                        value: item.name,
                        child: Text(item.name),
                      )),
                    ],
                    onChanged: (value) {
                      setState(() {
                        selectedCategory = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: barcodeController,
                          decoration: const InputDecoration(
                            labelText: 'Barcode',
                            hintText: 'Barcode number',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () {
                          final uuid = const Uuid().v4().substring(0, 8).toUpperCase();
                          barcodeController.text = 'LIB-$uuid';
                        },
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('Generate'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: maxUsesController,
                    decoration: const InputDecoration(
                      labelText: 'Kit Capacity (Max Uses)',
                      hintText: 'e.g., 10 for a kit that serves 10 people',
                      helperText: 'Leave empty if item doesn\'t need restocking',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final val = int.tryParse(v.trim());
                      if (val == null || val <= 0) return 'Must be a positive number';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: restockThresholdController,
                    decoration: const InputDecoration(
                      labelText: 'Restock Alert Threshold',
                      hintText: 'e.g., 2 to flag when 2 or fewer uses remain',
                      helperText: 'Flag for restocking when remaining uses ≤ this value',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final val = int.tryParse(v.trim());
                      if (val == null || val < 0) return 'Must be 0 or positive';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedLocation,
                    decoration: const InputDecoration(
                      labelText: 'Default Location',
                      hintText: 'Select location',
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('-- None --'),
                      ),
                      ...locations.map((item) => DropdownMenuItem<String>(
                        value: item.name,
                        child: Text(item.name),
                      )),
                    ],
                    onChanged: (value) {
                      setState(() {
                        selectedLocation = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedGrantId,
                    decoration: const InputDecoration(
                      labelText: 'Grant / Budget',
                      hintText: 'Select grant',
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('-- None --'),
                      ),
                      ...grants.map((item) => DropdownMenuItem<String>(
                        value: item.id,
                        child: Text(item.name),
                      )),
                    ],
                    onChanged: (value) {
                      setState(() {
                        selectedGrantId = value;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context, true);
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      try {
        final now = Timestamp.now();
        final data = Audit.attach({
          'name': nameController.text.trim(),
          'status': LibraryItemStatus.available.value,
          'usageCount': 0,
          'createdAt': now,
        });

        if (descController.text.trim().isNotEmpty) {
          data['description'] = descController.text.trim();
        }
        if (selectedCategory != null) {
          data['category'] = selectedCategory;
        }
        if (barcodeController.text.trim().isNotEmpty) {
          data['barcode'] = barcodeController.text.trim();
        }
        if (maxUsesController.text.trim().isNotEmpty) {
          final maxUses = int.tryParse(maxUsesController.text.trim());
          if (maxUses != null && maxUses > 0) {
            data['maxUses'] = maxUses;
          }
        }
        if (restockThresholdController.text.trim().isNotEmpty) {
          final threshold = int.tryParse(restockThresholdController.text.trim());
          if (threshold != null && threshold >= 0) {
            data['restockThreshold'] = threshold;
          }
        }
        if (selectedLocation != null) {
          data['location'] = selectedLocation;
        }
        if (selectedGrantId != null) {
          data['grantId'] = selectedGrantId;
        }

        final docRef = await _db.collection('library_items').add(data);

        await Audit.log('library.item.create', {
          'itemId': docRef.id,
          'name': nameController.text.trim(),
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Library item added successfully')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add item: $e')),
        );
      }
    }
  }

  Future<void> _showCheckOutDialog(LibraryItem item) async {
    final borrowerController = TextEditingController(
      text: OperatorStore.name.value?.isNotEmpty == true ? OperatorStore.name.value! : '',
    );
    final notesController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    UseType selectedUseType = UseType.staff;
    
    // Load departments (units)
    final lookups = LookupsService();
    final departments = await lookups.departments();
    String? selectedLocation;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Check Out: ${item.name}'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: borrowerController,
                    decoration: const InputDecoration(
                      labelText: 'Staff Member *',
                      hintText: 'Who is using this kit?',
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    autofocus: true,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedLocation,
                    decoration: const InputDecoration(
                      labelText: 'Where will it be used?',
                      hintText: 'Select unit',
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('-- Not specified --'),
                      ),
                      ...departments.map((dept) => DropdownMenuItem<String>(
                        value: dept.name,
                        child: Text(dept.name),
                      )),
                    ],
                    onChanged: (value) {
                      setState(() {
                        selectedLocation = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Intended Use',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<UseType>(
                    segments: const [
                      ButtonSegment(value: UseType.staff, label: Text('Staff')),
                      ButtonSegment(value: UseType.patient, label: Text('Patient')),
                      ButtonSegment(value: UseType.both, label: Text('Both')),
                    ],
                    selected: {selectedUseType},
                    onSelectionChanged: (selection) {
                      setState(() {
                        selectedUseType = selection.first;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: notesController,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      hintText: 'Additional information',
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context, true);
                }
              },
              child: const Text('Check Out'),
            ),
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      try {
        final now = Timestamp.now();
        final data = Audit.attach({
          'status': LibraryItemStatus.checkedOut.value,
          'checkedOutBy': borrowerController.text.trim(),
          'checkedOutAt': now,
          'useType': selectedUseType.name,
        });

        if (selectedLocation != null) {
          data['usedAtLocation'] = selectedLocation;
        }
        if (notesController.text.trim().isNotEmpty) {
          data['notes'] = notesController.text.trim();
        }

        await _db.collection('library_items').doc(item.id).update(data);

        await Audit.log('library.checkout', {
          'itemId': item.id,
          'itemName': item.name,
          'borrower': borrowerController.text.trim(),
          'location': selectedLocation,
          'useType': selectedUseType.name,
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kit checked out successfully')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to check out kit: $e')),
        );
      }
    }
  }

  Future<void> _showCheckInDialog(LibraryItem item) async {
    final notesController = TextEditingController();
    final usesRemainingController = TextEditingController(
      text: item.remainingUses?.toString() ?? '',
    );
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Check In: ${item.name}'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Checked out by: ${item.checkedOutBy ?? "Unknown"}'),
                if (item.checkedOutAt != null)
                  Text(
                    'Since: ${_formatDate(item.checkedOutAt!.toDate())}',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                if (item.usedAtLocation != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Used at: ${item.usedAtLocation}',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
                const SizedBox(height: 16),
                StatefulBuilder(
                  builder: (context, setState) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: usesRemainingController,
                  decoration: InputDecoration(
                    labelText: 'Estimated Uses Remaining',
                    hintText: 'How many more uses left?',
                    helperText: 'Rough estimate is fine',
                    suffixIcon: const Icon(Icons.info_outline),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    final num = int.tryParse(v.trim());
                    if (num == null || num < 0) return 'Must be 0 or positive number';
                    return null;
                  },
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 8),
                      if (usesRemainingController.text.trim().isNotEmpty)
                        (() {
                          final parsed = int.tryParse(usesRemainingController.text.trim());
                          if (parsed == null) return const SizedBox();
                          if (item.maxUses != null) {
                            final previewUsage = (item.maxUses! - parsed) < 0 ? 0 : (item.maxUses! - parsed);
                            return Text('Preview: usage $previewUsage / ${item.maxUses}', style: TextStyle(color: Theme.of(context).colorScheme.primary));
                          } else {
                            final previewUsage = item.usageCount + 1;
                            final previewMax = previewUsage + parsed;
                            return Text('Preview: usage $previewUsage / $previewMax', style: TextStyle(color: Theme.of(context).colorScheme.primary));
                          }
                        })(),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    hintText: 'Condition, issues, etc.',
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Check In'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      try {
        // Increment usage count
        final newUsageCount = item.usageCount + 1;
        
        final data = Audit.attach({
          'status': LibraryItemStatus.available.value,
          'checkedOutBy': null,
          'checkedOutAt': null,
          'usedAtLocation': null,
          'usageCount': newUsageCount,
        });

        // Update remaining uses if provided
        final usesText = usesRemainingController.text.trim();
        if (usesText.isNotEmpty) {
          final usesRemaining = int.tryParse(usesText);
          if (usesRemaining != null) {
            if (item.maxUses != null) {
              // If we have a known maxUses, the user is telling us how many uses are
              // left now — so set the usage count to (maxUses - usesRemaining).
              // This lets a user correct the usage counter if they track per-use
              // rather than rely on the automatic +1 increment.
              var computedUsage = item.maxUses! - usesRemaining;
              if (computedUsage < 0) computedUsage = 0;
              data['usageCount'] = computedUsage;
            } else {
              // If maxUses is not set, infer it from the current check-in:
              // the total capacity == (current usage after this check-in) + remaining.
              final computedUsage = item.usageCount + 1;
              data['usageCount'] = computedUsage;
              data['maxUses'] = computedUsage + usesRemaining;
            }
          }
        }

        if (notesController.text.trim().isNotEmpty) {
          data['notes'] = notesController.text.trim();
        }

        await _db.collection('library_items').doc(item.id).update(data);

        await Audit.log('library.checkin', {
          'itemId': item.id,
          'itemName': item.name,
          'usageCount': newUsageCount,
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kit checked in successfully')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to check in kit: $e')),
        );
      }
    }
  }

  Future<void> _showEditDialog(LibraryItem item) async {
    final nameController = TextEditingController(text: item.name);
    final descController = TextEditingController(text: item.description ?? '');
    final barcodeController = TextEditingController(text: item.barcode ?? '');
    final maxUsesController = TextEditingController(text: item.maxUses?.toString() ?? '');
    final restockThresholdController = TextEditingController(text: item.restockThreshold?.toString() ?? '');
    LibraryItemStatus selectedStatus = item.status;
    final formKey = GlobalKey<FormState>();
    
    // Load dropdowns
    final lookups = LookupsService();
    final locations = await lookups.locations();
    final interventions = await lookups.interventions();
    
    String? selectedCategory = item.category;
    String? selectedLocation = item.location;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Edit Library Item'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Name *'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: descController,
                    decoration: const InputDecoration(labelText: 'Description'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedCategory,
                    decoration: const InputDecoration(
                      labelText: 'Category (Intervention)',
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('-- None --'),
                      ),
                      ...interventions.map((item) => DropdownMenuItem<String>(
                        value: item.name,
                        child: Text(item.name),
                      )),
                    ],
                    onChanged: (value) {
                      setState(() {
                        selectedCategory = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: barcodeController,
                          decoration: const InputDecoration(labelText: 'Barcode'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () {
                          final uuid = const Uuid().v4().substring(0, 8).toUpperCase();
                          barcodeController.text = 'LIB-$uuid';
                        },
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('Generate'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: maxUsesController,
                    decoration: const InputDecoration(
                      labelText: 'Kit Capacity (Max Uses)',
                      hintText: 'e.g., 10 for a kit that serves 10 people',
                      helperText: 'Leave empty if item doesn\'t need restocking',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final val = int.tryParse(v.trim());
                      if (val == null || val <= 0) return 'Must be a positive number';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: restockThresholdController,
                    decoration: const InputDecoration(
                      labelText: 'Restock Alert Threshold',
                      hintText: 'e.g., 2 to flag when 2 or fewer uses remain',
                      helperText: 'Flag for restocking when remaining uses ≤ this value',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final val = int.tryParse(v.trim());
                      if (val == null || val < 0) return 'Must be 0 or positive';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedLocation,
                    decoration: const InputDecoration(
                      labelText: 'Default Location',
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('-- None --'),
                      ),
                      ...locations.map((item) => DropdownMenuItem<String>(
                        value: item.name,
                        child: Text(item.name),
                      )),
                    ],
                    onChanged: (value) {
                      setState(() {
                        selectedLocation = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<LibraryItemStatus>(
                    value: selectedStatus,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: LibraryItemStatus.values.map((status) {
                      return DropdownMenuItem(
                        value: status,
                        child: Text(status.displayName),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => selectedStatus = value);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context, true);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      try {
        final data = Audit.attach({
          'name': nameController.text.trim(),
          'status': selectedStatus.value,
        });

        final desc = descController.text.trim();
        data['description'] = desc.isEmpty ? null : desc;

        data['category'] = selectedCategory;

        final barcode = barcodeController.text.trim();
        data['barcode'] = barcode.isEmpty ? null : barcode;

        final maxUsesStr = maxUsesController.text.trim();
        if (maxUsesStr.isNotEmpty) {
          final maxUses = int.tryParse(maxUsesStr);
          if (maxUses != null && maxUses > 0) {
            data['maxUses'] = maxUses;
          }
        } else {
          data['maxUses'] = null;
        }

        final restockThresholdStr = restockThresholdController.text.trim();
        if (restockThresholdStr.isNotEmpty) {
          final threshold = int.tryParse(restockThresholdStr);
          if (threshold != null && threshold >= 0) {
            data['restockThreshold'] = threshold;
          }
        } else {
          data['restockThreshold'] = null;
        }

        data['location'] = selectedLocation;

        await _db.collection('library_items').doc(item.id).update(data);

        await Audit.log('library.item.update', {
          'itemId': item.id,
          'name': nameController.text.trim(),
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Library item updated successfully')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update item: $e')),
        );
      }
    }
  }

  Future<void> _showItemActionsSheet(LibraryItem item) async {
    final canCheckOut = item.status == LibraryItemStatus.available;
    final canCheckIn = item.status == LibraryItemStatus.checkedOut;
    
    await showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: item.status.color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      item.status.displayName,
                      style: TextStyle(
                        color: item.status.color,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.name,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            if (item.checkedOutBy != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    const Icon(Icons.person, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text('With: ${item.checkedOutBy}', style: TextStyle(color: Colors.grey[700])),
                  ],
                ),
              ),
            if (item.maxUses != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Row(
                  children: [
                    Icon(
                      item.needsRestocking ? Icons.warning : Icons.inventory_2,
                      size: 16,
                      color: item.needsRestocking ? Colors.orange : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Uses: ${item.usageCount}/${item.maxUses}${item.needsRestocking ? " - NEEDS RESTOCKING" : ""}',
                      style: TextStyle(
                        color: item.needsRestocking ? Colors.orange[700] : Colors.grey[700],
                        fontWeight: item.needsRestocking ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            // Display images if available
            if (item.imageUrls.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: SizedBox(
                  height: 80,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: item.imageUrls.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: EdgeInsets.only(right: index < item.imageUrls.length - 1 ? 8 : 0),
                        child: GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                            _showImageViewer(item.imageUrls, index);
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              item.imageUrls[index],
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                              errorBuilder: (ctx, err, stack) => Container(
                                width: 80,
                                height: 80,
                                color: Colors.grey[300],
                                child: const Icon(Icons.broken_image),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            if (canCheckOut)
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.blue),
                title: const Text('Check Out'),
                subtitle: const Text('Take this kit for use'),
                onTap: () {
                  Navigator.pop(context);
                  _showCheckOutDialog(item);
                },
              ),
            if (canCheckIn)
              ListTile(
                leading: const Icon(Icons.login, color: Colors.green),
                title: const Text('Check In'),
                subtitle: const Text('Return this kit'),
                onTap: () {
                  Navigator.pop(context);
                  _showCheckInDialog(item);
                },
              ),
            ListTile(
              leading: const Icon(Icons.build, color: Colors.orange),
              title: const Text('Restock / Maintenance'),
              subtitle: const Text('Reset usage count or mark for maintenance'),
              onTap: () {
                Navigator.pop(context);
                _showRestockDialog(item);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit Details'),
              onTap: () {
                Navigator.pop(context);
                _showEditDialog(item);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text('Manage Images (${item.imageUrls.length})'),
              subtitle: const Text('Add or remove photos'),
              onTap: () {
                Navigator.pop(context);
                _showImagesDialog(item);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _deleteItem(item);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showImageViewer(List<String> imageUrls, int initialIndex) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(ctx),
            ),
          ),
          body: PageView.builder(
            controller: PageController(initialPage: initialIndex),
            itemCount: imageUrls.length,
            itemBuilder: (context, index) {
              return InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Center(
                  child: Image.network(
                    imageUrls[index],
                    fit: BoxFit.contain,
                    errorBuilder: (ctx, err, stack) => const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.broken_image, color: Colors.white54, size: 64),
                        SizedBox(height: 16),
                        Text('Failed to load image', style: TextStyle(color: Colors.white54)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _showImagesDialog(LibraryItem item) async {
    await showDialog(
      context: context,
      builder: (context) => _LibraryItemImagesDialog(
        item: item,
        onImagesUpdated: () {
          setState(() {}); // Trigger rebuild to reflect image changes
        },
      ),
    );
  }

  Future<void> _deleteItem(LibraryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Library Item'),
        content: Text('Are you sure you want to delete "${item.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await _db.collection('library_items').doc(item.id).delete();

        await Audit.log('library.item.delete', {
          'itemId': item.id,
          'name': item.name,
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Library item deleted')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete item: $e')),
        );
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }

  Widget _buildItemCard(LibraryItem item, {bool compact = false}) {
    // Determine the primary action based on status
    final bool canCheckOut = item.status == LibraryItemStatus.available;
    final bool canCheckIn = item.status == LibraryItemStatus.checkedOut;
    final bool needsRestock = item.needsRestocking;
    
    if (compact) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        color: needsRestock ? Colors.orange.shade50 : null,
        child: InkWell(
          onTap: () => _showItemActionsSheet(item),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // Status indicator
                Container(
                  width: 8,
                  height: 40,
                  decoration: BoxDecoration(
                    color: item.status.color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                // Name and info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            item.status.displayName,
                            style: TextStyle(
                              color: item.status.color,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (item.checkedOutBy != null) ...[
                            Text(' • ', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                            Expanded(
                              child: Text(
                                item.checkedOutBy!,
                                style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                          if (item.maxUses != null && item.checkedOutBy == null) ...[
                            Text(' • ', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                            Text(
                              '${item.remainingUses}/${item.maxUses} left',
                              style: TextStyle(
                                color: needsRestock ? Colors.orange[700] : Colors.grey[600],
                                fontSize: 12,
                                fontWeight: needsRestock ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // Quick action button
                if (canCheckOut)
                  FilledButton.tonal(
                    onPressed: () => _showCheckOutDialog(item),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: const Size(0, 36),
                    ),
                    child: const Text('Check Out'),
                  )
                else if (canCheckIn)
                  FilledButton(
                    onPressed: () => _showCheckInDialog(item),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: const Size(0, 36),
                      backgroundColor: Colors.green,
                    ),
                    child: const Text('Check In'),
                  )
                else if (item.status == LibraryItemStatus.maintenance)
                  FilledButton.tonal(
                    onPressed: () => _showRestockDialog(item),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: const Size(0, 36),
                    ),
                    child: const Text('Complete'),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.more_vert),
                    onPressed: () => _showItemActionsSheet(item),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: needsRestock ? Colors.orange.shade50 : null,
      child: InkWell(
        onTap: () => _showItemActionsSheet(item),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Status indicator bar
                  Container(
                    width: 4,
                    height: 50,
                    decoration: BoxDecoration(
                      color: item.status.color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (item.description != null)
                          Text(
                            item.description!,
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: item.status.color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: item.status.color),
                    ),
                    child: Text(
                      item.status.displayName,
                      style: TextStyle(
                        color: item.status.color,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Info chips
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  if (item.category != null) _buildInfoChip(Icons.category, item.category!),
                  if (item.barcode != null) _buildInfoChip(Icons.qr_code, item.barcode!),
                  if (item.location != null) _buildInfoChip(Icons.location_on, item.location!),
                  if (item.maxUses != null) 
                    _buildUsageChip(item.usageCount, item.maxUses!, needsRestock),
                ],
              ),
              // Checked out info
              if (item.status == LibraryItemStatus.checkedOut) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: needsRestock ? Colors.orange[50] : Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.person, size: 20, color: needsRestock ? Colors.orange[700] : Colors.blue[700]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.checkedOutBy ?? 'Unknown',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: needsRestock ? Colors.orange[900] : Colors.blue[900],
                              ),
                            ),
                            Row(
                              children: [
                                if (item.checkedOutAt != null)
                                  Text(
                                    'Since ${_formatDate(item.checkedOutAt!.toDate())}',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                                  ),
                                if (item.checkedOutAt != null && item.usedAtLocation != null)
                                  Text(' • ', style: TextStyle(color: Colors.grey[400])),
                                if (item.usedAtLocation != null)
                                  Expanded(
                                    child: Text(
                                      item.usedAtLocation!,
                                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              // Action buttons - prominent and clear
              Row(
                children: [
                  if (canCheckOut)
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _showCheckOutDialog(item),
                        icon: const Icon(Icons.logout),
                        label: const Text('Check Out'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  if (canCheckIn)
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _showCheckInDialog(item),
                        icon: const Icon(Icons.login),
                        label: const Text('Check In'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  if (item.status == LibraryItemStatus.maintenance)
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _showRestockDialog(item),
                        icon: const Icon(Icons.check_circle),
                        label: const Text('Complete Maintenance'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.orange,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  if (item.status == LibraryItemStatus.retired)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showEditDialog(item),
                        icon: const Icon(Icons.settings_backup_restore),
                        label: const Text('Reactivate'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  if (needsRestock && item.status != LibraryItemStatus.maintenance) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => _showRestockDialog(item),
                      icon: const Icon(Icons.build, color: Colors.orange),
                      label: const Text('Restock', style: TextStyle(color: Colors.orange)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.orange),
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.more_vert),
                    onPressed: () => _showItemActionsSheet(item),
                    tooltip: 'More options',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey[700]),
        ),
      ],
    );
  }

  Widget _buildUsageChip(int usageCount, int maxUses, bool needsRestocking) {
    final remaining = maxUses - usageCount;
    final color = needsRestocking ? Colors.orange : Colors.green;
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          needsRestocking ? Icons.warning : Icons.check_circle,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          '$remaining / $maxUses uses left',
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: needsRestocking ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Intervention Kits'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddItemDialog,
            tooltip: 'Add Kit',
          ),
          IconButton(
            icon: Icon(_compactView ? Icons.view_agenda : Icons.grid_view),
            tooltip: _compactView ? 'Detailed View' : 'Compact View',
            onPressed: () => setState(() => _compactView = !_compactView),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search and filters
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search kits...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() {
                                _searchController.clear();
                              });
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilterChip(
                        label: const Text('All'),
                        selected: _filterStatus == null,
                        onSelected: (_) {
                          setState(() => _filterStatus = null);
                        },
                      ),
                      const SizedBox(width: 8),
                      ...LibraryItemStatus.values.map((status) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(status.displayName),
                            selected: _filterStatus == status,
                            onSelected: (_) {
                              setState(() => _filterStatus = status);
                            },
                          ),
                        );
                      }),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('Needs Restocking'),
                        selected: _showOverdueOnly,
                        avatar: _showOverdueOnly ? const Icon(Icons.inventory_2, size: 18) : null,
                        onSelected: (_) {
                          setState(() => _showOverdueOnly = !_showOverdueOnly);
                        },
                      ),
                    ],
                  ),
                ),
                // Grant/Budget filter
                if (_grants.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        const Text('Grant: ', style: TextStyle(fontWeight: FontWeight.w500)),
                        const SizedBox(width: 8),
                        FilterChip(
                          label: const Text('All Grants'),
                          selected: _filterGrantId == null,
                          onSelected: (_) {
                            setState(() => _filterGrantId = null);
                          },
                        ),
                        const SizedBox(width: 8),
                        ..._grants.map((grant) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(grant.name),
                              selected: _filterGrantId == grant.id,
                              onSelected: (_) {
                                setState(() => _filterGrantId = _filterGrantId == grant.id ? null : grant.id);
                              },
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Items list
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _buildQuery(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error: ${snapshot.error}'),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final items = _filterItems(snapshot.data!.docs);

                if (items.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'No kits found',
                          style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: _showAddItemDialog,
                          icon: const Icon(Icons.add),
                          label: const Text('Add your first kit'),
                        ),
                      ],
                    ),
                  );
                }

                if (_compactView) {
                  // Compact list view - shows all kits in a simple list
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    itemCount: items.length,
                    itemBuilder: (context, index) => _buildItemCard(items[index], compact: true),
                  );
                }

                return ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    return _buildItemCard(items[index]);
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddItemDialog,
        tooltip: 'Add Kit',
        child: const Icon(Icons.add),
      ),
    );
  }
}

// Dialog for managing library item images
class _LibraryItemImagesDialog extends StatefulWidget {
  final LibraryItem item;
  final VoidCallback onImagesUpdated;

  const _LibraryItemImagesDialog({
    required this.item,
    required this.onImagesUpdated,
  });

  @override
  State<_LibraryItemImagesDialog> createState() => _LibraryItemImagesDialogState();
}

class _LibraryItemImagesDialogState extends State<_LibraryItemImagesDialog> {
  late List<String> _imageUrls;

  @override
  void initState() {
    super.initState();
    _imageUrls = List.from(widget.item.imageUrls);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.photo_library),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Images - ${widget.item.name}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: ImagePickerWidget(
          imageUrls: _imageUrls,
          folder: 'library_items',
          itemId: widget.item.id,
          onImagesChanged: (newUrls) async {
            setState(() {
              _imageUrls = List.from(newUrls);
            });

            // Update Firestore
            await FirebaseFirestore.instance
                .collection('library_items')
                .doc(widget.item.id)
                .update({
              'imageUrls': newUrls,
            });

            widget.onImagesUpdated();
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}