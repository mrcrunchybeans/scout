import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';


class AlgoliaConfigPage extends StatefulWidget {
  const AlgoliaConfigPage({super.key});

  @override
  State<AlgoliaConfigPage> createState() => _AlgoliaConfigPageState();
}

class _AlgoliaConfigPageState extends State<AlgoliaConfigPage> {
  final _db = FirebaseFirestore.instance;
  final _formKey = GlobalKey<FormState>();

  final _appId = TextEditingController();
  final _indexName = TextEditingController();
  final _writeKey = TextEditingController();
  bool _enable = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final doc = await _db.collection('config').doc('algolia').get();
    if (!mounted) return;
    if (doc.exists) {
      final data = doc.data()!;
      setState(() {
        _appId.text = (data['appId'] ?? '').toString();
        _indexName.text = (data['indexName'] ?? '').toString();
        _writeKey.text = (data['writeApiKey'] ?? '').toString();
        _enable = (data['enableAlgolia'] ?? false) as bool;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await _db.collection('config').doc('algolia').set({
        'appId': _appId.text.trim(),
        'indexName': _indexName.text.trim(),
        'writeApiKey': _writeKey.text.trim(),
        'enableAlgolia': _enable,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _configureIndex() async {
    setState(() => _busy = true);
    try {
      // Prefer server-side configure if available
      final fn = FirebaseFunctions.instance.httpsCallable('configureAlgoliaIndex');
      await fn();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Configured Algolia index')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Configure failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _triggerFullReindex() async {
    setState(() => _busy = true);
    try {
      final fn = FirebaseFunctions.instance.httpsCallable('triggerFullReindex');
      final res = await fn();
      final data = res.data as Map<String, dynamic>?;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reindex triggered: ${data?['totalIndexed'] ?? 'ok'}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reindex failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncSingleItem() async {
    // Simple prompt for item id
    final idCtrl = TextEditingController();
    final ok = await showDialog<bool?>(context: context, builder: (c) => AlertDialog(
      title: const Text('Sync single item'),
      content: TextField(controller: idCtrl, decoration: const InputDecoration(labelText: 'Item ID')),
      actions: [TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Sync'))],
    ));
    if (ok != true) return;
    final id = idCtrl.text.trim();
    if (id.isEmpty) return;
    setState(() => _busy = true);
    try {
      final fn = FirebaseFunctions.instance.httpsCallable('syncItemToAlgoliaCallable');
      await fn.call({'itemId': id});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item sync requested')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sync failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _statusStream() {
    return _db.collection('status').doc('algolia').snapshots();
  }

  @override
  void dispose() {
    _appId.dispose();
    _indexName.dispose();
    _writeKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Algolia Configuration')),
      body: Form(
        key: _formKey,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              TextFormField(
                controller: _appId,
                decoration: const InputDecoration(labelText: 'Algolia App ID'),
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _indexName,
                decoration: const InputDecoration(labelText: 'Index Name'),
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _writeKey,
                decoration: const InputDecoration(labelText: 'Write API Key'),
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _enable,
                onChanged: (v) => setState(() => _enable = v),
                title: const Text('Enable Algolia'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: _busy ? null : _save,
                    child: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _busy ? null : _configureIndex,
                    child: const Text('Configure Index'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _busy ? null : _triggerFullReindex,
                    child: const Text('Full Reindex'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _busy ? null : _syncSingleItem,
                    child: const Text('Sync Item...'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _statusStream(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) return const SizedBox();
                  final doc = snap.data;
                  if (doc == null || !doc.exists) return const Text('No Algolia status');
                  final data = doc.data()!;
                  final last = data['lastSyncAt'];
                  final lastErr = data['lastError'];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Last sync: ${last ?? "never"}'),
                      if (lastErr != null) Text('Last error: $lastErr', style: const TextStyle(color: Colors.red)),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
