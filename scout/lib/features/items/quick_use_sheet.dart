import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../data/lookups_service.dart';
import '../../models/option_item.dart';

enum ForUseType { staff, patient }

class QuickUseSheet extends StatefulWidget {
  final String itemId;
  final String itemName;
  const QuickUseSheet({super.key, required this.itemId, required this.itemName});

  @override
  State<QuickUseSheet> createState() => _QuickUseSheetState();
}

class _QuickUseSheetState extends State<QuickUseSheet> {
  final _db = FirebaseFirestore.instance;
  final _lookups = LookupsService();

  int qty = 1;
  ForUseType? _forUse;
  OptionItem? _intervention;
  List<OptionItem>? _interventions;

  final _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _lookups.interventions();
    if (!mounted) return;
    setState(() => _interventions = list);
  }

  Future<void> _logUse() async {
    final itemRef = _db.collection('items').doc(widget.itemId);
    final usageRef = _db.collection('usage_logs').doc();

    await _db.runTransaction((tx) async {
      final snap = await tx.get(itemRef);
      if (!snap.exists) throw Exception('Item not found');
      final data = snap.data() as Map<String, dynamic>;
      final currentQty = (data['qtyOnHand'] ?? 0) as num;
      final newQty = currentQty - qty;
      if (newQty < 0) throw Exception('Insufficient stock');

      tx.update(itemRef, {
        'qtyOnHand': newQty,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastUsedAt': FieldValue.serverTimestamp(),
      });

      tx.set(usageRef, {
        'itemId': widget.itemId,
        'qtyUsed': qty,
        'usedAt': FieldValue.serverTimestamp(),
        'interventionId': _intervention?.id,    // NEW: what it was used for
        'forUseType': _forUse?.name,            // 'staff' | 'patient'
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'userId': null,
        // keep room for future: departmentId, grantId (derive from intervention if needed)
      });
    });
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loading = _interventions == null;
    final canSubmit = !loading && _intervention != null && qty > 0;

    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: loading
          ? const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.itemName, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),

                // Qty chips (+ Custom)
                Wrap(
                  spacing: 8,
                  children: <Widget>[
                    for (final n in [1, 2, 5])
                      ChoiceChip(
                        label: Text('-$n'),
                        selected: qty == n,
                        onSelected: (_) => setState(() => qty = n),
                      ),
                    ActionChip(
                      label: const Text('Custom'),
                      onPressed: () async {
                        final v = await showDialog<int>(
                          context: context,
                          builder: (_) => const _NumberDialog(),
                        );
                        if (!context.mounted) return;
                        if (v != null && v > 0) setState(() => qty = v);
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Intervention (required)
                DropdownButtonFormField<OptionItem>(
                  initialValue: _intervention,
                  items: _interventions!
                      .map((o) => DropdownMenuItem(value: o, child: Text(o.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _intervention = v),
                  decoration: const InputDecoration(labelText: 'Intervention *'),
                  validator: (_) => _intervention == null ? 'Required' : null,
                ),

                const SizedBox(height: 8),

                // ForUseType (staff/patient) — optional
                SegmentedButton<ForUseType>(
                  segments: const [
                    ButtonSegment(value: ForUseType.staff, label: Text('Staff')),
                    ButtonSegment(value: ForUseType.patient, label: Text('Patient')),
                  ],
                  selected: _forUse == null ? <ForUseType>{} : <ForUseType>{_forUse!},
                  onSelectionChanged: (s) => setState(() => _forUse = s.isEmpty ? null : s.first),
                  emptySelectionAllowed: true,
                  multiSelectionEnabled: false,
                ),

                const SizedBox(height: 8),

                // Optional notes
                TextField(
                  controller: _notes,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    hintText: 'e.g., patient room, unit, or context',
                  ),
                ),

                const SizedBox(height: 16),

                // Log use
                FilledButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text('Log use'),
                  onPressed: canSubmit
                      ? () async {
                          final ctx = context;
                          try {
                            await _logUse();
                            if (!ctx.mounted) return;
                            Navigator.of(ctx).pop(true);
                          } catch (e) {
                            if (!ctx.mounted) return;
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text('Error: $e')),
                            );
                          }
                        }
                      : null,
                ),
              ],
            ),
    );
  }
}

class _NumberDialog extends StatefulWidget {
  const _NumberDialog();
  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  final c = TextEditingController(text: '1');
  @override
  void dispose() { c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Quantity used'),
      content: TextField(
        controller: c,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(prefixText: '-'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final v = int.tryParse(c.text.trim());
            Navigator.pop<int>(context, (v == null || v < 1) ? 1 : v);
          },
          child: const Text('Done'),
        ),
      ],
    );
  }
}
