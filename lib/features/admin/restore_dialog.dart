import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

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