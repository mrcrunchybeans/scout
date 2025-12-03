import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:scout/features/admin/admin_pin_page.dart';
import 'package:scout/features/admin/backup_history_page.dart';
import 'package:scout/features/admin/backup_settings_page.dart';
import 'package:scout/features/admin/time_tracking_settings_page.dart';
import 'package:scout/features/audit/audit_logs_page.dart';
import 'package:scout/features/csv_import_export_page.dart';
import 'package:scout/features/lookups_management_page.dart';
import 'package:scout/features/admin/operator_mode_page.dart';
import 'package:scout/features/admin/restore_dialog.dart';
import 'package:scout/features/admin/label_config_page.dart';
import 'package:scout/features/admin/label_designer_page.dart';
import 'package:scout/features/admin/recalculate_lot_codes_page.dart';
import 'package:scout/features/admin/diagnose_lot_codes_page.dart';
import 'package:scout/features/admin/merge_operators_page.dart';
import 'package:scout/features/library/library_management_page.dart';
import 'package:scout/services/search_service.dart';
import 'package:scout/utils/admin_pin.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final SearchService _searchService = SearchService(FirebaseFirestore.instance);
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadBackups();
  }

  List<Map<String, dynamic>> _backups = [];

  Future<void> _loadBackups() async {
    try {
      final db = FirebaseFirestore.instance;
      final snapshot = await db.collection('backups').orderBy('timestamp', descending: true).limit(10).get();
      setState(() {
        _backups = snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load backups: $e')),
      );
    }
  }

  Future<void> _seedConfig() async {
    setState(() => _busy = true);
    try {
      final db = FirebaseFirestore.instance;

      // Seed basic config
      await db.collection('config').doc('app').set({
        'operatorMode': 'prompt',
        'adminPin': '2468',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Seed lookups if they don't exist
      // Note: ensureDefaultLookups method doesn't exist, seeding is handled elsewhere

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuration seeded successfully')),
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

  Future<void> _recalculateItemAggregates() async {
    setState(() => _busy = true);
    try {
      await _searchService.recalculateAllItemAggregates();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Item aggregates recalculated successfully')),
      );
      // Navigate back to dashboard to refresh the counts
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to recalculate item aggregates: $e')),
      );
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _createBackup() async {
    setState(() => _busy = true);
    try {
      final db = FirebaseFirestore.instance;
      final user = FirebaseAuth.instance.currentUser;

      // Get all collections to backup
      final collections = [
        'items',
        'lots',
        'departments',
        'grants',
        'locations',
        'interventions',
        'flagThresholds',
        'categories',
        'config',
        'auditLogs',
      ];

      final backupData = <String, dynamic>{
        'timestamp': FieldValue.serverTimestamp(),
        'createdBy': user?.email ?? 'Unknown',
        'collections': <String, dynamic>{},
      };

      // Backup each collection
      for (final collectionName in collections) {
        final snapshot = await db.collection(collectionName).get();
        final documents = <String, dynamic>{};

        for (final doc in snapshot.docs) {
          documents[doc.id] = _serializeDocument(doc.data());
        }

        backupData['collections'][collectionName] = documents;
      }

      // Save backup
      await db.collection('backups').add(backupData);

      // Reload backups list
      await _loadBackups();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup created successfully')),
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

  // Serialize Firestore types to JSON-compatible format
  Map<String, dynamic> _serializeDocument(Map<String, dynamic> data) {
    final result = <String, dynamic>{};

    for (final entry in data.entries) {
      final key = entry.key;
      final value = entry.value;

      if (value is Timestamp) {
        result[key] = {'_type': 'timestamp', '_value': value.toDate().toIso8601String()};
      } else if (value is GeoPoint) {
        result[key] = {
          '_type': 'geopoint',
          '_value': {'latitude': value.latitude, 'longitude': value.longitude}
        };
      } else if (value is Map<String, dynamic>) {
        result[key] = _serializeDocument(value);
      } else if (value is List) {
        result[key] = value.map((item) {
          if (item is Map<String, dynamic>) {
            return _serializeDocument(item);
          }
          return item;
        }).toList();
      } else {
        result[key] = value;
      }
    }

    return result;
  }

  Future<void> _showRestoreDialog() async {
    if (_backups.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No backups available')),
      );
      return;
    }

    final selectedBackup = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Backup to Restore'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _backups.length,
            itemBuilder: (context, index) {
              final backup = _backups[index];
              final timestamp = backup['timestamp'] as Timestamp;
              final createdBy = backup['createdBy'] as String?;
              final collections = backup['collections'] as Map<String, dynamic>;

              return ListTile(
                title: Text('Backup ${index + 1}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Created: ${timestamp.toDate().toString()}'),
                    if (createdBy != null) Text('By: $createdBy'),
                    Text('${collections.length} collections'),
                  ],
                ),
                onTap: () => Navigator.of(context).pop(backup),
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
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => RestoreDialog(
          backupId: selectedBackup['id'],
          backupData: selectedBackup,
          performRestore: _performRestore,
        ),
      );
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
              // Welcome/Summary Section
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.admin_panel_settings, color: Theme.of(context).primaryColor),
                          const SizedBox(width: 12),
                          Text(
                            'Administration Panel',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Manage system configuration, data, and advanced operations. '
                        'Developer tools are highlighted in colored sections.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.grey[600],
                            ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // System Configuration Section
              _buildSectionHeader('System Configuration', Icons.settings_system_daydream),
              Card(
                elevation: 1,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.badge),
                      title: const Text('Operator Mode'),
                      subtitle: const Text('Configure how operator names are collected'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const OperatorModePage()),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.lock),
                      title: const Text('Admin PIN'),
                      subtitle: const Text('Change the admin access PIN'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const AdminPinPage()),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.label),
                      title: const Text('Label Configuration'),
                      subtitle: const Text('Configure label layout and QR settings'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const LabelConfigPage()),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.brush),
                      title: const Text('Label Designer (prototype)'),
                      subtitle: const Text('Drag elements to design label layout'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const LabelDesignerPage()),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.schedule),
                      title: const Text('Time Tracking'),
                      subtitle: const Text('Configure time tracking URL for staff care'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const TimeTrackingSettingsPage()),
                        );
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Data Management Section
              _buildSectionHeader('Data Management', Icons.storage),
              Card(
                elevation: 1,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.library_books),
                      title: const Text('Library Management'),
                      subtitle: const Text('Check in/out reusable items and equipment'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const LibraryManagementPage(),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.list),
                      title: const Text('Manage Lookups'),
                      subtitle: const Text('Departments, Grants, Locations, Categories, Interventions'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const LookupsManagementPage(),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.import_export),
                      title: const Text('CSV Import/Export'),
                      subtitle: const Text('Bulk import/export items and lots'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const CsvImportExportPage(),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.history),
                      title: const Text('Audit Logs'),
                      subtitle: const Text('View all inventory operations and changes'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const AuditLogsPage()),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.merge),
                      title: const Text('Merge Operator Names'),
                      subtitle: const Text('Combine duplicate user names across the app'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const MergeOperatorsPage()),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.calculate, color: Theme.of(context).colorScheme.primary),
                      title: Text('Recalculate Lot Codes',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                      subtitle: Text('Standardize lot codes to YYMM-XXX format',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
                      trailing: Icon(Icons.chevron_right,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                      onTap: () async {
                        if (await AdminPin.ensureDeveloper(context)) {
                          if (!context.mounted) return;
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const RecalculateLotCodesPage()),
                          );
                        }
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.search, color: Theme.of(context).colorScheme.secondary),
                      title:
                          Text('Diagnose Lot Codes', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                      subtitle: Text('Check for duplicate lot codes within items',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
                      trailing: Icon(Icons.chevron_right,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const DiagnoseLotCodesPage()),
                        );
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Search & Indexing Section (Developer Only)
              _buildSectionHeader('Search & Indexing', Icons.search, isDeveloper: true),
              Card(
                elevation: 1,
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.tune, color: Theme.of(context).colorScheme.primary),
                      title: Text('Configure Algolia Index',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                      subtitle: Text('Set up search facets and indexing',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
                      trailing: Icon(Icons.chevron_right,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                      onTap: () async {
                        if (await AdminPin.ensureDeveloper(context)) {
                          _configureAlgoliaIndex();
                        }
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.sync, color: Theme.of(context).colorScheme.primary),
                      title: Text('Sync Items to Algolia',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                      subtitle: Text('Populate search index with current items',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
                      trailing: Icon(Icons.chevron_right,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                      onTap: () async {
                        if (await AdminPin.ensureDeveloper(context)) {
                          _syncItemsToAlgolia();
                        }
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.calculate, color: Colors.green),
                      title: Text('Recalculate Item Flags',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                      subtitle: Text('Update expired/low stock flags for all items',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
                      trailing: Icon(Icons.chevron_right,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                      onTap: () async {
                        if (await AdminPin.ensureDeveloper(context)) {
                          _recalculateItemAggregates();
                        }
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Database Operations Section (Developer Only)
              _buildSectionHeader('Database Operations', Icons.storage, isDeveloper: true),
              Card(
                elevation: 1,
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.history, color: Colors.orange),
                      title: Text('Backup History', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                      subtitle: Text('View and manage backup snapshots',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
                      trailing: Icon(Icons.chevron_right,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const BackupHistoryPage()),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.settings, color: Colors.orange),
                      title: Text('Backup Settings', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                      subtitle: Text('Configure backup retention and policies',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
                      trailing: Icon(Icons.chevron_right,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const BackupSettingsPage()),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.restore, color: Colors.orange),
                      title: Text('Database Restore', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                      subtitle: Text('Restore from backup snapshots',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
                      trailing: Icon(Icons.chevron_right,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                      onTap: () async {
                        if (await AdminPin.ensureDeveloper(context)) {
                          _showRestoreDialog();
                        }
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.backup, color: Colors.orange),
                      title: Text('Create Backup', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                      subtitle: Text('Create a new database backup',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
                      trailing: Icon(Icons.chevron_right,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                      onTap: () async {
                        if (await AdminPin.ensureDeveloper(context)) {
                          _createBackup();
                        }
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Development Tools Section (Developer Only)
              _buildSectionHeader('Development Tools', Icons.developer_mode, isDeveloper: true),
              Card(
                elevation: 1,
                child: ListTile(
                  leading: Icon(Icons.bug_report, color: Colors.red),
                  title: Text('Seed Config', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                  subtitle: Text('Initialize app configuration (debug only)',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
                  trailing:
                      Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                  onTap: () async {
                    if (await AdminPin.ensureDeveloper(context)) {
                      _seedConfig();
                    }
                  },
                ),
              ),

              const SizedBox(height: 32), // Extra space at bottom
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

  Widget _buildSectionHeader(String title, IconData icon, {bool isDeveloper = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 24, color: isDeveloper ? Colors.red.shade700 : Theme.of(context).primaryColor),
          const SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: isDeveloper ? Colors.red.shade700 : Theme.of(context).primaryColor,
            ),
          ),
          if (isDeveloper) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade300),
              ),
              child: Text(
                'DEVELOPER ONLY',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade800,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
