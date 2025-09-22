import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/admin_pin.dart';
import '../../services/search_service.dart';
import '../../dev/seed_lookups.dart';
import 'lookups_crud_page.dart';
import '../audit/audit_logs_page.dart';
import 'backup_history_page.dart';
import 'backup_settings_page.dart';
import '../csv_import_export_page.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final _searchService = SearchService(
    FirebaseFirestore.instance,
    const SearchConfig(
      strategy: SearchStrategy.external,
      enableAlgolia: true,
      algoliaAppId: 'COMHTF4QM1',
      algoliaSearchApiKey: '86a6aa6baaa3bbfc8e5e75c0c272fa00',
      algoliaWriteApiKey: '3ca7664f0aaf7555ab3c43bd179d17d8',
      algoliaIndexName: 'scout_items',
    ),
  );
  bool _busy = false;

  Future<void> _configureAlgoliaIndex() async {
    setState(() => _busy = true);
    try {
      await _searchService.configureAlgoliaIndex();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Algolia index configured successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to configure Algolia index: $e')),
      );
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _createBackup() async {
    setState(() => _busy = true);
    try {
      final functions = FirebaseFunctions.instance;
      final result = await functions.httpsCallable('createManualBackup').call();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup created successfully: ${result.data['message']}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create backup: $e')),
      );
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _seedConfig() async {
    setState(() => _busy = true);
    try {
      await seedConfig();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Config seeded successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to seed config: $e')),
      );
    } finally {
      setState(() => _busy = false);
    }
  }
  @override
  void initState() {
    super.initState();
    _redirectIfNotAuthed();
  }

  Future<void> _redirectIfNotAuthed() async {
    // If someone navigated here directly without unlocking on Dashboard,
    // quietly bounce back. No dialog on this page.
    final authed = await AdminPin.isAuthed();
    if (!mounted) return;
    if (!authed) {
      // optional: show a brief message before leaving
      // ScaffoldMessenger.of(context).showSnackBar(
      //   const SnackBar(content: Text('Admin PIN required')),
      // );
      Navigator.of(context).pop();
    }
  }

  Future<void> _syncItemsToAlgolia() async {
    setState(() => _busy = true);
    try {
      await _searchService.syncItemsToAlgolia();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Items synced to Algolia successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to sync items to Algolia: $e')),
      );
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _showRestoreDialog() async {
    setState(() => _busy = true);
    try {
      final db = FirebaseFirestore.instance;

      // Get available backups
      final backupsSnapshot = await db
          .collection('backups')
          .orderBy('timestamp', descending: true)
          .limit(10)
          .get();

      if (!mounted) return;

      // Show backup selection dialog first
      final selectedBackup = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Select Backup'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: backupsSnapshot.docs.length,
              itemBuilder: (context, index) {
                final backupDoc = backupsSnapshot.docs[index];
                final backupData = backupDoc.data();
                final timestamp = (backupData['timestamp'] as Timestamp?)?.toDate();
                final createdBy = backupData['createdBy'] as String?;

                return ListTile(
                  title: Text(timestamp?.toString() ?? 'Unknown time'),
                  subtitle: createdBy != null ? Text('Created by: $createdBy') : null,
                  onTap: () => Navigator.of(context).pop(backupDoc.id),
                );
              },
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

      if (selectedBackup != null) {
        // Get the selected backup data
        final backupDoc = await db.collection('backups').doc(selectedBackup).get();
        if (!backupDoc.exists) {
          throw Exception('Selected backup not found');
        }

        final backupData = backupDoc.data()!;

        if (!mounted) return;

        // Show the restore dialog with collection selection
        await showDialog(
          context: context,
          builder: (context) => RestoreDialog(
            backupId: selectedBackup,
            backupData: backupData,
            performRestore: _performRestore,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load backups: $e')),
      );
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _performRestore(String backupId, [List<String>? selectedCollections]) async {
    final db = FirebaseFirestore.instance;
    
    // Get backup data
    final backupDoc = await db.collection('backups').doc(backupId).get();
    if (!backupDoc.exists) throw Exception('Backup not found');
    
    final backupData = backupDoc.data()!;
    final allCollections = backupData['collections'] as Map<String, dynamic>;
    
    // Filter collections if selective restore
    final collectionsToRestore = selectedCollections != null
        ? Map.fromEntries(allCollections.entries.where((e) => selectedCollections.contains(e.key)))
        : allCollections;
    
    // Clear existing data and restore from backup
    final batch = db.batch();
    
    // Clear and restore each collection
    for (final entry in collectionsToRestore.entries) {
      final collectionName = entry.key;
      final documents = entry.value as Map<String, dynamic>;
      
      // Clear existing collection (we'll delete all documents)
      final existingDocs = await db.collection(collectionName).get();
      for (final doc in existingDocs.docs) {
        batch.delete(doc.reference);
      }
      
      // Restore documents from backup
      for (final docEntry in documents.entries) {
        final docId = docEntry.key;
        final docData = docEntry.value as Map<String, dynamic>;
        // Convert serialized types back to Firestore types
        final convertedData = _convertFromSerialized(docData);
        batch.set(db.collection(collectionName).doc(docId), convertedData);
      }
    }
    
    // Commit the batch
    await batch.commit();
    
    // Rebuild search index if items were restored
    if (collectionsToRestore.containsKey('items')) {
      try {
        await _searchService.syncItemsToAlgolia();
      } catch (e) {
        // Don't fail the restore if search sync fails
        debugPrint('Warning: Failed to sync search index after restore: $e');
      }
    }
  }

  // Convert serialized Firestore types back to Firestore types
  Map<String, dynamic> _convertFromSerialized(Map<String, dynamic> data) {
    final result = <String, dynamic>{};
    
    for (final entry in data.entries) {
      final key = entry.key;
      final value = entry.value;
      
      if (value is Map<String, dynamic> && value.containsKey('_type')) {
        switch (value['_type']) {
          case 'timestamp':
            result[key] = Timestamp.fromDate(DateTime.parse(value['_value'] as String));
            break;
          case 'geopoint':
            final geoData = value['_value'] as Map<String, dynamic>;
            result[key] = GeoPoint(geoData['latitude'] as double, geoData['longitude'] as double);
            break;
          default:
            result[key] = value;
        }
      } else if (value is Map<String, dynamic>) {
        result[key] = _convertFromSerialized(value);
      } else if (value is List) {
        result[key] = value.map((item) {
          if (item is Map<String, dynamic>) {
            return _convertFromSerialized(item);
          }
          return item;
        }).toList();
      } else {
        result[key] = value;
      }
    }
    
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin / Config'),
        actions: [
          // (Optional) quick way to sign out admin
          // IconButton(
          //   tooltip: 'Sign out admin',
          //   icon: const Icon(Icons.logout),
          //   onPressed: () async {
          //     await AdminPin.signOut();
          //     if (!mounted) return;
          //     Navigator.of(context).pop();
          //   },
          // ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Configuration', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.badge),
                title: const Text('Operator mode'),
                subtitle: const Text('Choose how operator names are collected & cached'),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const OperatorModePage()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.lock),
                title: const Text('Admin PIN'),
                subtitle: const Text('Change the PIN (move to Firestore later)'),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AdminPinPage()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.storage),
                title: const Text('Lookups (Departments, Grants, Locations)'),
                subtitle: const Text('Manage dropdown data'),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const LookupsCrudPage(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.import_export),
                title: const Text('CSV Import/Export'),
                subtitle: const Text('Bulk import/export items and lots'),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const CsvImportExportPage(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('Audit Logs'),
                subtitle: const Text('View all inventory operations and changes'),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AuditLogsPage()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.search),
                title: const Text('Configure Algolia Index'),
                subtitle: const Text('Set up search facets and indexing'),
                onTap: () async {
                  if (await AdminPin.ensureDeveloper(context)) {
                    _configureAlgoliaIndex();
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.sync),
                title: const Text('Sync Items to Algolia'),
                subtitle: const Text('Populate search index with current items'),
                onTap: () async {
                  if (await AdminPin.ensureDeveloper(context)) {
                    _syncItemsToAlgolia();
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Seed Config'),
                subtitle: const Text('Initialize app configuration (debug only)'),
                onTap: () async {
                  if (await AdminPin.ensureDeveloper(context)) {
                    _seedConfig();
                  }
                },
              ),
              const SizedBox(height: 24),
              const Text('Database Management', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('Backup History'),
                subtitle: const Text('View and manage backup snapshots'),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const BackupHistoryPage()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Backup Settings'),
                subtitle: const Text('Configure backup retention and policies'),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const BackupSettingsPage()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.restore),
                title: const Text('Database Restore'),
                subtitle: const Text('Restore from backup snapshots'),
                onTap: () async {
                  if (await AdminPin.ensureDeveloper(context)) {
                    _showRestoreDialog();
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.backup),
                title: const Text('Create Backup'),
                subtitle: const Text('Create a new database backup'),
                onTap: () async {
                  if (await AdminPin.ensureDeveloper(context)) {
                    _createBackup();
                  }
                },
              ),
            ],
          ),
          if (_busy)
            Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}

// Restore Dialog for selective collection restore
class RestoreDialog extends StatefulWidget {
  final String backupId;
  final Map<String, dynamic> backupData;
  final Future<void> Function(String, List<String>?) performRestore;

  const RestoreDialog({
    super.key,
    required this.backupId,
    required this.backupData,
    required this.performRestore,
  });

  @override
  State<RestoreDialog> createState() => _RestoreDialogState();
}

class _RestoreDialogState extends State<RestoreDialog> {
  final Set<String> _selectedCollections = {};
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    // Pre-select all collections by default
    final collections = widget.backupData['collections'] as Map<String, dynamic>;
    _selectedCollections.addAll(collections.keys);
  }

  @override
  Widget build(BuildContext context) {
    final collections = widget.backupData['collections'] as Map<String, dynamic>;
    final createdAt = widget.backupData['timestamp'] as Timestamp;
    final createdBy = widget.backupData['createdBy'] as String?;

    return AlertDialog(
      title: const Text('Restore Database'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Backup created: ${createdAt.toDate().toString()}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (createdBy != null)
              Text(
                'Created by: $createdBy',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 16),
            const Text(
              'Select collections to restore:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ...collections.keys.map((collectionName) {
              final docCount = (collections[collectionName] as Map<String, dynamic>).length;
              return CheckboxListTile(
                title: Text('$collectionName ($docCount documents)'),
                value: _selectedCollections.contains(collectionName),
                onChanged: (selected) {
                  setState(() {
                    if (selected == true) {
                      _selectedCollections.add(collectionName);
                    } else {
                      _selectedCollections.remove(collectionName);
                    }
                  });
                },
              );
            }),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Warning: This will permanently replace the selected collections with backup data. This action cannot be undone.',
                      style: TextStyle(color: Colors.orange, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _restoring ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _restoring || _selectedCollections.isEmpty
              ? null
              : _performRestore,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: _restoring
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Restore Selected'),
        ),
      ],
    );
  }

  Future<void> _performRestore() async {
    setState(() => _restoring = true);
    try {
      await widget.performRestore(widget.backupId, _selectedCollections.toList());
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Database restored successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to restore database: $e')),
      );
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }
}

// Operator Mode Configuration Page
class OperatorModePage extends StatefulWidget {
  const OperatorModePage({super.key});

  @override
  State<OperatorModePage> createState() => _OperatorModePageState();
}

class _OperatorModePageState extends State<OperatorModePage> {
  String _operatorMode = 'prompt'; // Default to current behavior
  String _defaultOperatorName = '';
  List<String> _operatorList = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final db = FirebaseFirestore.instance;
      final doc = await db.collection('config').doc('app').get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _operatorMode = data['operatorMode'] as String? ?? 'prompt';
          _defaultOperatorName = data['defaultOperatorName'] as String? ?? '';
          _operatorList = List<String>.from(data['operatorList'] as List<dynamic>? ?? []);
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load config: $e')),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveConfig() async {
    setState(() => _saving = true);
    try {
      final db = FirebaseFirestore.instance;
      await db.collection('config').doc('app').set({
        'operatorMode': _operatorMode,
        'defaultOperatorName': _defaultOperatorName,
        'operatorList': _operatorList,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Operator mode configuration saved')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save config: $e')),
      );
    } finally {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Operator Mode')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Operator Mode'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _saveConfig,
              child: const Text('Save'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'How should operator names be collected?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Column(
            children: [
              RadioMenuButton<String>(
                value: 'prompt',
                groupValue: _operatorMode,
                onChanged: (value) => setState(() => _operatorMode = value!),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Always prompt'),
                    Text('Ask for operator name each time the app is opened', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              RadioMenuButton<String>(
                value: 'default',
                groupValue: _operatorMode,
                onChanged: (value) => setState(() => _operatorMode = value!),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Use default name'),
                    Text('Use a predefined operator name for all operations', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              RadioMenuButton<String>(
                value: 'list',
                groupValue: _operatorMode,
                onChanged: (value) => setState(() => _operatorMode = value!),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Select from list'),
                    Text('Choose from a predefined list of operators', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              RadioMenuButton<String>(
                value: 'disabled',
                groupValue: _operatorMode,
                onChanged: (value) => setState(() => _operatorMode = value!),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Disabled'),
                    Text('Don\'t track operator names', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_operatorMode == 'default') ...[
            const Text(
              'Default Operator Name',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Default operator name',
                hintText: 'e.g. SCOUT System',
              ),
              controller: TextEditingController(text: _defaultOperatorName),
              onChanged: (value) => _defaultOperatorName = value,
            ),
          ],
          if (_operatorMode == 'list') ...[
            const Text(
              'Operator List',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ..._operatorList.map((operator) => ListTile(
              title: Text(operator),
              trailing: IconButton(
                icon: const Icon(Icons.delete),
                onPressed: () => setState(() => _operatorList.remove(operator)),
              ),
            )),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Add operator'),
              onTap: _addOperator,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _addOperator() async {
    final controller = TextEditingController();
    final operator = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Operator'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Operator name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (operator != null && operator.isNotEmpty && !_operatorList.contains(operator)) {
      setState(() => _operatorList.add(operator));
    }
  }
}

// Admin PIN Configuration Page
class AdminPinPage extends StatefulWidget {
  const AdminPinPage({super.key});

  @override
  State<AdminPinPage> createState() => _AdminPinPageState();
}

class _AdminPinPageState extends State<AdminPinPage> {
  final _currentPinController = TextEditingController();
  final _newPinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentPin();
  }

  @override
  void dispose() {
    _currentPinController.dispose();
    _newPinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentPin() async {
    // Just load to ensure we can access the config
    try {
      final db = FirebaseFirestore.instance;
      await db.collection('config').doc('app').get();
      // We don't need to store the PIN, we'll fetch it when validating
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load PIN configuration: $e')),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _changePin() async {
    final currentPin = _currentPinController.text.trim();
    final newPin = _newPinController.text.trim();
    final confirmPin = _confirmPinController.text.trim();

    // Validate current PIN by fetching from Firestore directly
    String actualCurrentPin = '2468'; // fallback
    try {
      final db = FirebaseFirestore.instance;
      final doc = await db.collection('config').doc('app').get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        actualCurrentPin = data['adminPin'] as String? ?? '2468';
      }
    } catch (e) {
      // If we can't fetch, show error
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to verify current PIN: $e')),
      );
      return;
    }

    if (currentPin != actualCurrentPin) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Current PIN is incorrect')),
      );
      return;
    }

    // Validate new PIN
    if (newPin.length < 4) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New PIN must be at least 4 characters')),
      );
      return;
    }

    if (newPin != confirmPin) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New PIN and confirmation do not match')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final db = FirebaseFirestore.instance;
      await db.collection('config').doc('app').set({
        'adminPin': newPin,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Clear the cache so the new PIN takes effect
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('admin_pin');
      await prefs.remove('admin_pin_ttl_hours');
      await prefs.remove('admin_pin_fetched_at');

      setState(() {
        _currentPinController.clear();
        _newPinController.clear();
        _confirmPinController.clear();
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Admin PIN changed successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to change PIN: $e')),
      );
    } finally {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin PIN')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin PIN'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _changePin,
              child: const Text('Change PIN'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Change Admin PIN',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _currentPinController,
            decoration: const InputDecoration(
              labelText: 'Current PIN',
              hintText: 'Enter current admin PIN',
            ),
            obscureText: true,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _newPinController,
            decoration: const InputDecoration(
              labelText: 'New PIN',
              hintText: 'Enter new admin PIN (at least 4 characters)',
            ),
            obscureText: true,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _confirmPinController,
            decoration: const InputDecoration(
              labelText: 'Confirm New PIN',
              hintText: 'Re-enter new admin PIN',
            ),
            obscureText: true,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info, color: Colors.blue),
                    SizedBox(width: 8),
                    Text(
                      'Security Note',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  'Changing the admin PIN will require all users to enter the new PIN the next time they access admin features. The PIN is stored securely in Firestore.',
                  style: TextStyle(color: Colors.blue, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

