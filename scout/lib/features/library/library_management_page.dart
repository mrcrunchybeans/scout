import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:scout/models/library_item.dart';
import 'package:scout/utils/audit.dart';
import 'package:scout/utils/operator_store.dart';

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
            (item.serialNumber?.toLowerCase().contains(searchTerm) ?? false) ||
            (item.checkedOutBy?.toLowerCase().contains(searchTerm) ?? false);
      }).toList();
    }

    // Apply overdue filter
    if (_showOverdueOnly) {
      filtered = filtered.where((item) => item.isOverdue).toList();
    }

    return filtered;
  }

  Future<void> _showAddItemDialog() async {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final categoryController = TextEditingController();
    final barcodeController = TextEditingController();
    final serialController = TextEditingController();
    final locationController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
                TextFormField(
                  controller: categoryController,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    hintText: 'e.g., Electronics, Equipment',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: barcodeController,
                  decoration: const InputDecoration(
                    labelText: 'Barcode',
                    hintText: 'Barcode number',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: serialController,
                  decoration: const InputDecoration(
                    labelText: 'Serial Number',
                    hintText: 'Serial or asset number',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: locationController,
                  decoration: const InputDecoration(
                    labelText: 'Default Location',
                    hintText: 'Storage location',
                  ),
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
    );

    if (result == true && mounted) {
      try {
        final now = Timestamp.now();
        final data = Audit.attach({
          'name': nameController.text.trim(),
          'status': LibraryItemStatus.available.value,
          'createdAt': now,
        });

        if (descController.text.trim().isNotEmpty) {
          data['description'] = descController.text.trim();
        }
        if (categoryController.text.trim().isNotEmpty) {
          data['category'] = categoryController.text.trim();
        }
        if (barcodeController.text.trim().isNotEmpty) {
          data['barcode'] = barcodeController.text.trim();
        }
        if (serialController.text.trim().isNotEmpty) {
          data['serialNumber'] = serialController.text.trim();
        }
        if (locationController.text.trim().isNotEmpty) {
          data['location'] = locationController.text.trim();
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
      text: OperatorStore.name.value ?? '',
    );
    final notesController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    DateTime? dueDate;

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
                      labelText: 'Borrower Name *',
                      hintText: 'Who is checking this out?',
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    autofocus: true,
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Due Date (optional)'),
                    subtitle: Text(
                      dueDate != null ? '${dueDate!.month}/${dueDate!.day}/${dueDate!.year}' : 'No due date set',
                    ),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: dueDate ?? DateTime.now().add(const Duration(days: 7)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setState(() => dueDate = picked);
                      }
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
        });

        if (dueDate != null) {
          data['dueDate'] = Timestamp.fromDate(dueDate!);
        }
        if (notesController.text.trim().isNotEmpty) {
          data['notes'] = notesController.text.trim();
        }

        await _db.collection('library_items').doc(item.id).update(data);

        await Audit.log('library.checkout', {
          'itemId': item.id,
          'itemName': item.name,
          'borrower': borrowerController.text.trim(),
          'dueDate': dueDate?.toIso8601String(),
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item checked out successfully')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to check out item: $e')),
        );
      }
    }
  }

  Future<void> _showCheckInDialog(LibraryItem item) async {
    final notesController = TextEditingController();
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
                if (item.isOverdue)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'OVERDUE',
                      style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                    ),
                  ),
                const SizedBox(height: 16),
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
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Check In'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      try {
        final data = Audit.attach({
          'status': LibraryItemStatus.available.value,
          'checkedOutBy': null,
          'checkedOutAt': null,
          'dueDate': null,
        });

        if (notesController.text.trim().isNotEmpty) {
          data['notes'] = notesController.text.trim();
        }

        await _db.collection('library_items').doc(item.id).update(data);

        await Audit.log('library.checkin', {
          'itemId': item.id,
          'itemName': item.name,
          'wasOverdue': item.isOverdue,
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item checked in successfully')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to check in item: $e')),
        );
      }
    }
  }

  Future<void> _showEditDialog(LibraryItem item) async {
    final nameController = TextEditingController(text: item.name);
    final descController = TextEditingController(text: item.description ?? '');
    final categoryController = TextEditingController(text: item.category ?? '');
    final barcodeController = TextEditingController(text: item.barcode ?? '');
    final serialController = TextEditingController(text: item.serialNumber ?? '');
    final locationController = TextEditingController(text: item.location ?? '');
    LibraryItemStatus selectedStatus = item.status;
    final formKey = GlobalKey<FormState>();

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
                  TextFormField(
                    controller: categoryController,
                    decoration: const InputDecoration(labelText: 'Category'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: barcodeController,
                    decoration: const InputDecoration(labelText: 'Barcode'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: serialController,
                    decoration: const InputDecoration(labelText: 'Serial Number'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: locationController,
                    decoration: const InputDecoration(labelText: 'Location'),
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

        final cat = categoryController.text.trim();
        data['category'] = cat.isEmpty ? null : cat;

        final barcode = barcodeController.text.trim();
        data['barcode'] = barcode.isEmpty ? null : barcode;

        final serial = serialController.text.trim();
        data['serialNumber'] = serial.isEmpty ? null : serial;

        final loc = locationController.text.trim();
        data['location'] = loc.isEmpty ? null : loc;

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

  Widget _buildItemCard(LibraryItem item) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () => _showEditDialog(item),
        child: Padding(
          padding: const EdgeInsets.all(16),
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
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  if (item.category != null) _buildInfoChip(Icons.category, item.category!),
                  if (item.barcode != null) _buildInfoChip(Icons.qr_code, item.barcode!),
                  if (item.serialNumber != null) _buildInfoChip(Icons.tag, item.serialNumber!),
                  if (item.location != null) _buildInfoChip(Icons.location_on, item.location!),
                ],
              ),
              if (item.status == LibraryItemStatus.checkedOut) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: item.isOverdue ? Colors.red[50] : Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.person,
                            size: 16,
                            color: item.isOverdue ? Colors.red : Colors.blue,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Checked out by: ${item.checkedOutBy ?? "Unknown"}',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: item.isOverdue ? Colors.red[900] : Colors.blue[900],
                            ),
                          ),
                        ],
                      ),
                      if (item.checkedOutAt != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Since: ${_formatDate(item.checkedOutAt!.toDate())}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                      if (item.dueDate != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              item.isOverdue ? Icons.warning : Icons.event,
                              size: 14,
                              color: item.isOverdue ? Colors.red : Colors.grey[700],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Due: ${_formatDate(item.dueDate!.toDate())}',
                              style: TextStyle(
                                fontSize: 12,
                                color: item.isOverdue ? Colors.red[900] : Colors.grey[700],
                                fontWeight: item.isOverdue ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            if (item.isOverdue) ...[
                              const SizedBox(width: 8),
                              const Text(
                                'OVERDUE',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (item.status == LibraryItemStatus.available)
                    ElevatedButton.icon(
                      onPressed: () => _showCheckOutDialog(item),
                      icon: const Icon(Icons.logout, size: 18),
                      label: const Text('Check Out'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  if (item.status == LibraryItemStatus.checkedOut)
                    ElevatedButton.icon(
                      onPressed: () => _showCheckInDialog(item),
                      icon: const Icon(Icons.login, size: 18),
                      label: const Text('Check In'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => _showEditDialog(item),
                    tooltip: 'Edit',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _deleteItem(item),
                    tooltip: 'Delete',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddItemDialog,
            tooltip: 'Add Item',
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
                    hintText: 'Search items...',
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
                        label: const Text('Overdue'),
                        selected: _showOverdueOnly,
                        avatar: _showOverdueOnly ? const Icon(Icons.warning, size: 18) : null,
                        onSelected: (_) {
                          setState(() => _showOverdueOnly = !_showOverdueOnly);
                        },
                      ),
                    ],
                  ),
                ),
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
                          'No items found',
                          style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _showAddItemDialog,
                          child: const Text('Add your first item'),
                        ),
                      ],
                    ),
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
        tooltip: 'Add Item',
        child: const Icon(Icons.add),
      ),
    );
  }
}
