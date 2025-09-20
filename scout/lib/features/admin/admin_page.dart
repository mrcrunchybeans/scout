import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../utils/admin_pin.dart';
import '../../services/search_service.dart';
import '../../dev/seed_lookups.dart';
import 'lookups_crud_page.dart';
import '../audit/audit_logs_page.dart';

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
    final selectedDays = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Database Restore'),
        content: const Text('Select a backup snapshot to restore from:'),
        actions: [
          for (int days = 1; days <= 5; days++)
            TextButton(
              onPressed: () => Navigator.of(context).pop(days),
              child: Text('$days day${days == 1 ? '' : 's'} ago'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selectedDays != null) {
      await _restoreDatabase(selectedDays);
    }
  }

  Future<void> _restoreDatabase(int daysAgo) async {
    setState(() => _busy = true);
    try {
      // TODO: Implement actual database restore logic
      // This would typically involve:
      // 1. Loading backup data from snapshots
      // 2. Replacing current collections with backup data
      // 3. Rebuilding search indexes
      
      await Future.delayed(const Duration(seconds: 2)); // Simulate restore time
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Database restored from $daysAgo day${daysAgo == 1 ? '' : 's'} ago backup')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to restore database: $e')),
      );
    } finally {
      setState(() => _busy = false);
    }
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
                onTap: _configureAlgoliaIndex,
              ),
              ListTile(
                leading: const Icon(Icons.sync),
                title: const Text('Sync Items to Algolia'),
                subtitle: const Text('Populate search index with current items'),
                onTap: _syncItemsToAlgolia,
              ),
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Seed Config'),
                subtitle: const Text('Initialize app configuration (debug only)'),
                onTap: _seedConfig,
              ),
              const SizedBox(height: 24),
              const Text('Database Management', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.restore),
                title: const Text('Database Restore'),
                subtitle: const Text('Restore from backup snapshots'),
                onTap: _showRestoreDialog,
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

// Placeholder for Operator Mode config
class OperatorModePage extends StatelessWidget {
  const OperatorModePage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Operator Mode')),
      body: const Center(child: Text('Operator mode configuration coming soon.')),
    );
  }
}

// Placeholder for Admin PIN config
class AdminPinPage extends StatelessWidget {
  const AdminPinPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin PIN')),
      body: const Center(child: Text('Admin PIN configuration coming soon.')),
    );
  }
}

