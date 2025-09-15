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
  OptionItem? _loc;
  OptionItem? _grant;
  ForUseType? _forUse;

  List<OptionItem>? _locs;
  List<OptionItem>? _grants;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([_lookups.locations(), _lookups.grants()]);
    if (!mounted) return;
    setState(() {
      _locs = results[0];
      _grants = results[1];
    });
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
        'whereLocationId': _loc?.id,
        'grantId': _grant?.id,
        'forUseType': _forUse?.name, // 'staff' | 'patient'
        'userId': null,
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final loading = (_locs == null || _grants == null);
    final canSubmit = !loading && _loc != null && qty > 0;

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

                // Location
                DropdownButtonFormField<OptionItem>(
                  initialValue: _loc,
                  items: _locs!
                      .map((o) => DropdownMenuItem(value: o, child: Text(o.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _loc = v),
                  decoration: const InputDecoration(labelText: 'Where (location)'),
                ),

                const SizedBox(height: 8),

                // Grant
                DropdownButtonFormField<OptionItem>(
                  initialValue: _grant,
                  items: _grants!
                      .map((o) => DropdownMenuItem(value: o, child: Text(o.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _grant = v),
                  decoration: const InputDecoration(labelText: 'Grant (optional)'),
                ),

                const SizedBox(height: 8),

                // ForUseType (staff/patient)
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

                const SizedBox(height: 16),

                // Log use button (disabled until required fields chosen)
                FilledButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text('Log use'),
                  onPressed: canSubmit
                      ? () async {
                          final ctx = context; // capture same BuildContext
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
  void dispose() {
    c.dispose();
    super.dispose();
  }

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
