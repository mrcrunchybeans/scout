import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/lookups_service.dart';
import '../../models/option_item.dart';

class LookupsCrudPage extends StatefulWidget {
  const LookupsCrudPage({super.key});

  @override
  State<LookupsCrudPage> createState() => _LookupsCrudPageState();
}

class _LookupsCrudPageState extends State<LookupsCrudPage> {
  final _lookups = LookupsService();
  late Future<List<OptionItem>> _departments;
  late Future<List<OptionItem>> _grants;
  late Future<List<OptionItem>> _locations;
  late Future<List<OptionItem>> _categories;

  @override
  void initState() {
    super.initState();
    _departments = _lookups.departments();
    _grants = _lookups.grants();
    _locations = _lookups.locations();
    _categories = _lookups.categories();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Lookups')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection('Departments', _departments),
          const SizedBox(height: 16),
          _buildSection('Grants', _grants),
          const SizedBox(height: 16),
          _buildSection('Locations', _locations),
          const SizedBox(height: 16),
          _buildSection('Categories', _categories),
        ],
      ),
    );
  }

  Widget _buildSection(String title, Future<List<OptionItem>> future) {
    return FutureBuilder<List<OptionItem>>(
      future: future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
          );
        }
        final items = snapshot.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...items.map((item) => ListTile(
                  title: Text(item.name),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () async {
                      final newName = await showDialog<String>(
                        context: context,
                        builder: (ctx) {
                          final controller = TextEditingController(text: item.name);
                          return AlertDialog(
                            title: Text('Edit $title'),
                            content: TextField(
                              controller: controller,
                              autofocus: true,
                              decoration: const InputDecoration(labelText: 'Name'),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                                child: const Text('Save'),
                              ),
                            ],
                          );
                        },
                      );
                      if (newName != null && newName.isNotEmpty && newName != item.name) {
                        // Update in Firestore
                        final col = title.toLowerCase();
                        await FirebaseFirestore.instance.collection(col).doc(item.id).set({
                          'name': newName,
                          'active': true,
                        }, SetOptions(merge: true));
                        setState(() {
                          if (title == 'Departments') _departments = _lookups.departments();
                          if (title == 'Grants') _grants = _lookups.grants();
                          if (title == 'Locations') _locations = _lookups.locations();
                        });
                      }
                        },
                      ),
                      if (title == 'Categories')
                        IconButton(
                          icon: const Icon(Icons.delete_forever),
                          tooltip: 'Deactivate category',
                          onPressed: () async {
                                final rootCtx = context;
                                final confirm = await showDialog<bool>(
                                  context: rootCtx,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Deactivate category'),
                                    content: Text('Are you sure you want to deactivate "${item.name}"? This will hide it from suggestion lists but keep historical data intact.'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Deactivate')),
                                    ],
                                  ),
                                );

                                if (confirm == true) {
                                  try {
                                    await FirebaseFirestore.instance.collection('categories').doc(item.id).set({
                                      'active': false,
                                      'updatedAt': FieldValue.serverTimestamp(),
                                    }, SetOptions(merge: true));
                                    if (rootCtx.mounted) setState(() => _categories = _lookups.categories());
                                    if (rootCtx.mounted) ScaffoldMessenger.of(rootCtx).showSnackBar(const SnackBar(content: Text('Category deactivated')));
                                  } catch (e) {
                                    if (rootCtx.mounted) ScaffoldMessenger.of(rootCtx).showSnackBar(SnackBar(content: Text('Failed to deactivate: $e')));
                                  }
                                }
                              },
                        ),
                    ],
                  ),
                )),
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: Text('Add $title'),
              onPressed: () async {
                final newName = await showDialog<String>(
                  context: context,
                  builder: (ctx) {
                    final controller = TextEditingController();
                    return AlertDialog(
                      title: Text('Add $title'),
                      content: TextField(
                        controller: controller,
                        autofocus: true,
                        decoration: const InputDecoration(labelText: 'Name'),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                          child: const Text('Add'),
                        ),
                      ],
                    );
                  },
                );
                if (newName != null && newName.isNotEmpty) {
                  final col = title.toLowerCase();
                  await FirebaseFirestore.instance.collection(col).add({
                    'name': newName,
                    'active': true,
                  });
                  setState(() {
                    if (title == 'Departments') _departments = _lookups.departments();
                    if (title == 'Grants') _grants = _lookups.grants();
                    if (title == 'Locations') _locations = _lookups.locations();
                  });
                }
              },
            ),
          ],
        );
      },
    );
  }
}
