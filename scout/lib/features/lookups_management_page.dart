// lib/features/lookups_management_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/option_item.dart';

class LookupsManagementPage extends StatefulWidget {
  const LookupsManagementPage({super.key});

  @override
  State<LookupsManagementPage> createState() => _LookupsManagementPageState();
}

class _LookupsManagementPageState extends State<LookupsManagementPage> {

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Manage Lookups'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Departments'),
              Tab(text: 'Grants'),
              Tab(text: 'Locations'),
              Tab(text: 'Interventions'),
              Tab(text: 'Flag Thresholds'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _LookupManager(collection: 'departments', title: 'Departments'),
            _LookupManager(collection: 'grants', title: 'Grants'),
            _LookupManager(collection: 'locations', title: 'Locations'),
            _InterventionManager(),
            _FlagThresholdsManager(),
          ],
        ),
      ),
    );
  }
}

class _LookupManager extends StatefulWidget {
  final String collection;
  final String title;

  const _LookupManager({required this.collection, required this.title});

  @override
  State<_LookupManager> createState() => _LookupManagerState();
}

class _LookupManagerState extends State<_LookupManager> {
  final _db = FirebaseFirestore.instance;
  bool _showInactive = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text(
                'Manage ${widget.title}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const Spacer(),
              TextButton.icon(
                icon: Icon(_showInactive ? Icons.visibility_off : Icons.visibility),
                label: Text(_showInactive ? 'Hide Inactive' : 'Show Inactive'),
                onPressed: () => setState(() => _showInactive = !_showInactive),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: Text('Add ${widget.title}'),
                onPressed: () => _showAddDialog(),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _db
                .collection(widget.collection)
                .orderBy('name')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }

              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snapshot.data!.docs.where((doc) {
                if (_showInactive) return true;
                final data = doc.data() as Map<String, dynamic>;
                return data['active'] != false;
              }).toList();

              if (docs.isEmpty) {
                return Center(
                  child: Text(
                    'No ${widget.title.toLowerCase()} found',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                );
              }

              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data() as Map<String, dynamic>;
                  return _buildLookupItem(doc.id, data);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLookupItem(String id, Map<String, dynamic> data) {
    final name = data['name'] as String? ?? 'Unknown';
    final code = data['code'] as String? ?? '';
    final active = data['active'] != false;
    final kind = data['kind'] as String?; // For locations

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        title: Text(name),
        subtitle: Row(
          children: [
            if (code.isNotEmpty) ...[
              Text('Code: $code'),
              const SizedBox(width: 16),
            ],
            if (kind != null) ...[
              Text('Type: $kind'),
              const SizedBox(width: 16),
            ],
            Text(active ? 'Active' : 'Inactive',
                style: TextStyle(
                  color: active ? Colors.green : Colors.red,
                  fontWeight: FontWeight.bold,
                )),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _showEditDialog(id, data),
              tooltip: 'Edit',
            ),
            IconButton(
              icon: Icon(active ? Icons.visibility_off : Icons.visibility),
              onPressed: () => _toggleActive(id, active),
              tooltip: active ? 'Deactivate' : 'Activate',
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _showDeleteDialog(id, name),
              tooltip: 'Delete',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddDialog() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _LookupDialog(
        title: 'Add ${widget.title}',
        collection: widget.collection,
      ),
    );

    if (result != null && mounted) {
      try {
        await _db.collection(widget.collection).add({
          ...result,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'active': true,
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${widget.title} added successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error adding ${widget.title}: $e')),
          );
        }
      }
    }
  }

  Future<void> _showEditDialog(String id, Map<String, dynamic> currentData) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _LookupDialog(
        title: 'Edit ${widget.title}',
        collection: widget.collection,
        initialData: currentData,
      ),
    );

    if (result != null && mounted) {
      try {
        await _db.collection(widget.collection).doc(id).update({
          ...result,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${widget.title} updated successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating ${widget.title}: $e')),
          );
        }
      }
    }
  }

  Future<void> _toggleActive(String id, bool currentlyActive) async {
    try {
      await _db.collection(widget.collection).doc(id).update({
        'active': !currentlyActive,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${widget.title} ${currentlyActive ? 'deactivated' : 'activated'}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating ${widget.title}: $e')),
        );
      }
    }
  }

  Future<void> _showDeleteDialog(String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Item'),
        content: Text('Are you sure you want to delete "$name"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await _db.collection(widget.collection).doc(id).delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${widget.title} deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting ${widget.title}: $e')),
          );
        }
      }
    }
  }
}

class _LookupDialog extends StatefulWidget {
  final String title;
  final String collection;
  final Map<String, dynamic>? initialData;

  const _LookupDialog({
    required this.title,
    required this.collection,
    this.initialData,
  });

  @override
  State<_LookupDialog> createState() => _LookupDialogState();
}

class _LookupDialogState extends State<_LookupDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  String? _kind; // For locations

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _nameController.text = widget.initialData!['name'] ?? '';
      _codeController.text = widget.initialData!['code'] ?? '';
      _kind = widget.initialData!['kind'];
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value?.trim().isEmpty ?? true) {
                  return 'Name is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _codeController,
              decoration: const InputDecoration(
                labelText: 'Code (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            if (widget.collection == 'locations') ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _kind,
                decoration: const InputDecoration(
                  labelText: 'Type',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'storage', child: Text('Storage')),
                  DropdownMenuItem(value: 'unit', child: Text('Unit')),
                  DropdownMenuItem(value: 'mobile', child: Text('Mobile')),
                ],
                onChanged: (value) => setState(() => _kind = value),
                validator: (value) {
                  if (value == null) {
                    return 'Type is required for locations';
                  }
                  return null;
                },
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final result = {
      'name': _nameController.text.trim(),
      'code': _codeController.text.trim().isEmpty ? null : _codeController.text.trim(),
      if (_kind != null) 'kind': _kind,
    };

    Navigator.pop(context, result);
  }
}

class _InterventionManager extends StatefulWidget {
  const _InterventionManager();

  @override
  State<_InterventionManager> createState() => _InterventionManagerState();
}

class _InterventionManagerState extends State<_InterventionManager> {
  final _db = FirebaseFirestore.instance;
  bool _showInactive = false;
  List<OptionItem> _grants = [];

  @override
  void initState() {
    super.initState();
    _loadGrants();
  }

  Future<void> _loadGrants() async {
    final grantsSnap = await _db.collection('grants').where('active', isEqualTo: true).get();
    setState(() {
      _grants = grantsSnap.docs.map((doc) {
        final data = doc.data();
        return OptionItem(doc.id, data['name'] ?? 'Unknown');
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Text(
                'Manage Interventions',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              TextButton.icon(
                icon: Icon(_showInactive ? Icons.visibility_off : Icons.visibility),
                label: Text(_showInactive ? 'Hide Inactive' : 'Show Inactive'),
                onPressed: () => setState(() => _showInactive = !_showInactive),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add Intervention'),
                onPressed: () => _showAddDialog(),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _db
                .collection('interventions')
                .orderBy('name')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }

              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snapshot.data!.docs.where((doc) {
                if (_showInactive) return true;
                final data = doc.data() as Map<String, dynamic>;
                return data['active'] != false;
              }).toList();

              if (docs.isEmpty) {
                return const Center(
                  child: Text('No interventions found'),
                );
              }

              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data() as Map<String, dynamic>;
                  return _buildInterventionItem(doc.id, data);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildInterventionItem(String id, Map<String, dynamic> data) {
    final name = data['name'] as String? ?? 'Unknown';
    final code = data['code'] as String? ?? '';
    final defaultGrantId = data['defaultGrantId'] as String?;
    final active = data['active'] != false;

    final defaultGrantName = _grants
        .where((g) => g.id == defaultGrantId)
        .map((g) => g.name)
        .firstOrNull ?? 'None';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        title: Text(name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (code.isNotEmpty) Text('Code: $code'),
            Text('Default Grant: $defaultGrantName'),
            Text(
              active ? 'Active' : 'Inactive',
              style: TextStyle(
                color: active ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _showEditDialog(id, data),
              tooltip: 'Edit',
            ),
            IconButton(
              icon: Icon(active ? Icons.visibility_off : Icons.visibility),
              onPressed: () => _toggleActive(id, active),
              tooltip: active ? 'Deactivate' : 'Activate',
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _showDeleteDialog(id, name),
              tooltip: 'Delete',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddDialog() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _InterventionDialog(grants: _grants),
    );

    if (result != null && mounted) {
      try {
        await _db.collection('interventions').add({
          ...result,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'active': true,
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Intervention added successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error adding intervention: $e')),
          );
        }
      }
    }
  }

  Future<void> _showEditDialog(String id, Map<String, dynamic> currentData) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _InterventionDialog(
        grants: _grants,
        initialData: currentData,
      ),
    );

    if (result != null && mounted) {
      try {
        await _db.collection('interventions').doc(id).update({
          ...result,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Intervention updated successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating intervention: $e')),
          );
        }
      }
    }
  }

  Future<void> _toggleActive(String id, bool currentlyActive) async {
    try {
      await _db.collection('interventions').doc(id).update({
        'active': !currentlyActive,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Intervention ${currentlyActive ? 'deactivated' : 'activated'}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating intervention: $e')),
        );
      }
    }
  }

  Future<void> _showDeleteDialog(String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Intervention'),
        content: Text('Are you sure you want to delete "$name"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await _db.collection('interventions').doc(id).delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Intervention deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting intervention: $e')),
          );
        }
      }
    }
  }
}

class _InterventionDialog extends StatefulWidget {
  final List<OptionItem> grants;
  final Map<String, dynamic>? initialData;

  const _InterventionDialog({required this.grants, this.initialData});

  @override
  State<_InterventionDialog> createState() => _InterventionDialogState();
}

class _InterventionDialogState extends State<_InterventionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  String? _defaultGrantId;

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _nameController.text = widget.initialData!['name'] ?? '';
      _codeController.text = widget.initialData!['code'] ?? '';
      _defaultGrantId = widget.initialData!['defaultGrantId'];
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Intervention'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value?.trim().isEmpty ?? true) {
                  return 'Name is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _codeController,
              decoration: const InputDecoration(
                labelText: 'Code (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _defaultGrantId,
              decoration: const InputDecoration(
                labelText: 'Default Grant',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('None')),
                ...widget.grants.map((grant) => DropdownMenuItem(
                  value: grant.id,
                  child: Text(grant.name),
                )),
              ],
              onChanged: (value) => setState(() => _defaultGrantId = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final result = {
      'name': _nameController.text.trim(),
      'code': _codeController.text.trim().isEmpty ? null : _codeController.text.trim(),
      'defaultGrantId': _defaultGrantId,
    };

    Navigator.pop(context, result);
  }
}

class _FlagThresholdsManager extends StatefulWidget {
  const _FlagThresholdsManager();

  @override
  State<_FlagThresholdsManager> createState() => _FlagThresholdsManagerState();
}

class _FlagThresholdsManagerState extends State<_FlagThresholdsManager> {
  final _db = FirebaseFirestore.instance;
  final _staleDaysController = TextEditingController();
  final _excessFactorController = TextEditingController();
  final _expiringDaysController = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  Future<void> _loadCurrentSettings() async {
    try {
      final doc = await _db.collection('config').doc('flags').get();
      if (doc.exists) {
        final data = doc.data()!;
        _staleDaysController.text = (data['staleDays'] ?? 45).toString();
        _excessFactorController.text = (data['excessFactor'] ?? 3).toString();
        _expiringDaysController.text = (data['expiringDays'] ?? 14).toString();
      } else {
        // Default values
        _staleDaysController.text = '45';
        _excessFactorController.text = '3';
        _expiringDaysController.text = '14';
      }
    } catch (e) {
      // Use defaults on error
      _staleDaysController.text = '45';
      _excessFactorController.text = '3';
      _expiringDaysController.text = '14';
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _staleDaysController.dispose();
    _excessFactorController.dispose();
    _expiringDaysController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Flag Thresholds',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          const Text(
            'Configure the thresholds used for automatic inventory flagging. '
            'Changes will take effect immediately and may trigger Cloud Functions to recalculate flags.',
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Stale Items',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Items are flagged as "stale" if they haven\'t been used for this many days.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _staleDaysController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Days without use',
                      border: OutlineInputBorder(),
                      suffixText: 'days',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Excess Stock',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Items are flagged as "excess" when current stock exceeds this multiple of the minimum quantity.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _excessFactorController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Multiplier',
                      border: OutlineInputBorder(),
                      suffixText: '× minimum',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Expiring Soon',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Lots are flagged as "expiring soon" when they will expire within this many days.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _expiringDaysController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Days until expiration',
                      border: OutlineInputBorder(),
                      suffixText: 'days',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: FilledButton.icon(
              icon: const Icon(Icons.save),
              label: const Text('Save Thresholds'),
              onPressed: _saveThresholds,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveThresholds() async {
    final staleDays = int.tryParse(_staleDaysController.text.trim());
    final excessFactor = double.tryParse(_excessFactorController.text.trim());
    final expiringDays = int.tryParse(_expiringDaysController.text.trim());

    if (staleDays == null || staleDays <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid number of days for stale items')),
      );
      return;
    }

    if (excessFactor == null || excessFactor <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Excess factor must be greater than 1')),
      );
      return;
    }

    if (expiringDays == null || expiringDays <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid number of days for expiring items')),
      );
      return;
    }

    try {
      await _db.collection('config').doc('flags').set({
        'staleDays': staleDays,
        'excessFactor': excessFactor,
        'expiringDays': expiringDays,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Flag thresholds saved successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving thresholds: $e')),
        );
      }
    }
  }
}