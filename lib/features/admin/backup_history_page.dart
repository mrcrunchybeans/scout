import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class BackupHistoryPage extends StatefulWidget {
  const BackupHistoryPage({super.key});

  @override
  State<BackupHistoryPage> createState() => _BackupHistoryPageState();
}

class _BackupHistoryPageState extends State<BackupHistoryPage> {
  bool _loading = true;
  List<QueryDocumentSnapshot> _backups = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBackups();
  }

  Future<void> _loadBackups() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final db = FirebaseFirestore.instance;
      final snapshot = await db
          .collection('backups')
          .orderBy('timestamp', descending: true)
          .get();

      setState(() {
        _backups = snapshot.docs;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _deleteBackup(String backupId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Backup'),
        content: const Text('Are you sure you want to delete this backup? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final db = FirebaseFirestore.instance;
      await db.collection('backups').doc(backupId).delete();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup deleted successfully')),
      );

      // Reload backups
      await _loadBackups();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete backup: $e')),
      );
    }
  }

  Future<void> _runCleanup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Run Cleanup'),
        content: const Text('This will delete all backups older than 30 days. Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Run Cleanup'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loading = true);

    try {
      final functions = FirebaseFunctions.instance;
      final result = await functions.httpsCallable('cleanupOldBackups').call();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cleanup completed: ${result.data}')),
      );

      // Reload backups
      await _loadBackups();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to run cleanup: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatBackupSize(Map<String, dynamic> collections) {
    int totalDocs = 0;
    collections.forEach((_, docs) {
      if (docs is Map) {
        totalDocs += docs.length;
      }
    });
    return '$totalDocs documents';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Backup History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadBackups,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.cleaning_services),
            onPressed: _runCleanup,
            tooltip: 'Run Cleanup',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text('Error loading backups: $_error'),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _loadBackups,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _backups.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.backup, size: 48, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('No backups found'),
                          Text('Create your first backup to get started'),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _backups.length,
                      itemBuilder: (context, index) {
                        final backup = _backups[index];
                        final data = backup.data() as Map<String, dynamic>;
                        final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
                        final createdBy = data['createdBy'] as String?;
                        final collections = data['collections'] as Map<String, dynamic>?;
                        final isAutomated = data['type'] == 'automated';

                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          child: ListTile(
                            leading: Icon(
                              isAutomated ? Icons.schedule : Icons.backup,
                              color: isAutomated ? Colors.blue : Colors.green,
                            ),
                            title: Text(
                              timestamp?.toString() ?? 'Unknown time',
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (createdBy != null)
                                  Text('Created by: $createdBy'),
                                if (collections != null)
                                  Text('Size: ${_formatBackupSize(collections)}'),
                                Text(
                                  isAutomated ? 'Automated backup' : 'Manual backup',
                                  style: TextStyle(
                                    color: isAutomated ? Colors.blue : Colors.green,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) {
                                switch (value) {
                                  case 'delete':
                                    _deleteBackup(backup.id);
                                    break;
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete, color: Colors.red),
                                      SizedBox(width: 8),
                                      Text('Delete'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}