import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../data/lookups_service.dart';
import '../../models/option_item.dart';

enum UseType { staff, patient, both }

class NewItemPage extends StatefulWidget {
  const NewItemPage({super.key});
  @override
  State<NewItemPage> createState() => _NewItemPageState();
}

class _NewItemPageState extends State<NewItemPage> {
  final _db = FirebaseFirestore.instance;
  final _lookups = LookupsService();
  final _form = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _category = TextEditingController();
  final _unit = TextEditingController(text: 'each');
  final _qtyOnHand = TextEditingController(text: '0');
  final _minQty = TextEditingController(text: '0');
  final _barcode = TextEditingController();

  List<OptionItem>? _locs;
  List<OptionItem>? _grants;
  OptionItem? _homeLoc;
  OptionItem? _grant;
  UseType _useType = UseType.both;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadLookups();
  }

  Future<void> _loadLookups() async {
    final results = await Future.wait([_lookups.locations(), _lookups.grants()]);
    if (!mounted) return;
    setState(() {
      _locs = results[0];
      _grants = results[1];
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final now = FieldValue.serverTimestamp();
      final ref = _db.collection('items').doc();
      await ref.set({
        'name': _name.text.trim(),
        'category': _category.text.trim().isEmpty ? null : _category.text.trim(),
        'unit': _unit.text.trim().isEmpty ? 'each' : _unit.text.trim(),
        'qtyOnHand': num.tryParse(_qtyOnHand.text.trim()) ?? 0,
        'minQty': num.tryParse(_minQty.text.trim()) ?? 0,
        'maxQty': null,
        'useType': _useType.name, // staff/patient/both
        'grantId': _grant?.id,
        'departmentId': null,
        'homeLocationId': _homeLoc?.id,
        'expiresAt': null,
        'lastUsedAt': null,
        'tags': <String>[],
        'barcode': _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
        'imageUrl': null,
        'createdAt': now,
        'updatedAt': now,
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _unit.dispose();
    _qtyOnHand.dispose();
    _minQty.dispose();
    _barcode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loading = _locs == null || _grants == null;

    return Scaffold(
      appBar: AppBar(title: const Text('New Item')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _name,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Name *'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _category,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Category'),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _unit,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Unit'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _qtyOnHand,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Qty on hand'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _minQty,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Min qty (reorder)'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<OptionItem>(
                    initialValue: _homeLoc,
                    items: _locs!.map((o) => DropdownMenuItem(value: o, child: Text(o.name))).toList(),
                    onChanged: (v) => setState(() => _homeLoc = v),
                    decoration: const InputDecoration(labelText: 'Home location'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<OptionItem>(
                    initialValue: _grant,
                    items: _grants!.map((o) => DropdownMenuItem(value: o, child: Text(o.name))).toList(),
                    onChanged: (v) => setState(() => _grant = v),
                    decoration: const InputDecoration(labelText: 'Default grant (optional)'),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<UseType>(
                    segments: const [
                      ButtonSegment(value: UseType.staff, label: Text('Staff')),
                      ButtonSegment(value: UseType.patient, label: Text('Patient')),
                      ButtonSegment(value: UseType.both, label: Text('Both')),
                    ],
                    selected: {_useType},
                    onSelectionChanged: (s) => setState(() => _useType = s.first),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _barcode,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(labelText: 'Barcode / QR (optional)'),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save),
                    label: const Text('Save'),
                  ),
                ],
              ),
            ),
    );
  }
}
