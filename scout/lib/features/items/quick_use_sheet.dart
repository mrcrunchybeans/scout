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

  // Interventions (simple OptionItem list for dropdown)
  OptionItem? _intervention;
  List<OptionItem>? _interventions;

  // interventionId -> defaultGrantId
  final Map<String, String?> _interventionGrantById = {};
  // grantId -> grant name
  final Map<String, String> _grantNamesById = {};

  // Optional notes
  final _notes = TextEditingController();

  // NEW: date/time the item was used (defaults to now)
  DateTime _usedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Load interventions (names/ids for dropdown)
    final interventionsList = await _lookups.interventions();

    // Load defaultGrantId per intervention
    final interventionsSnap = await _db
        .collection('interventions')
        .where('active', isEqualTo: true)
        .get();

    // Load grant names for the badge
    final grantsSnap = await _db
        .collection('grants')
        .where('active', isEqualTo: true)
        .get();

    if (!mounted) return;
    setState(() {
      _interventions = interventionsList;

      for (final d in interventionsSnap.docs) {
        final data = d.data();
        _interventionGrantById[d.id] = data['defaultGrantId'] as String?;
      }
      for (final d in grantsSnap.docs) {
        final data = d.data();
        _grantNamesById[d.id] = (data['name'] ?? '') as String;
      }
    });
  }

  String? _selectedGrantId() {
    final id = _intervention?.id;
    if (id == null) return null;
    return _interventionGrantById[id];
  }

  String? _selectedGrantName() {
    final gid = _selectedGrantId();
    if (gid == null) return null;
    return _grantNamesById[gid] ?? gid;
  }

  String _formatUsedAt(BuildContext context) {
    final l = MaterialLocalizations.of(context);
    final dateStr = l.formatFullDate(_usedAt);
    final timeStr = TimeOfDay.fromDateTime(_usedAt).format(context);
    return '$dateStr • $timeStr';
  }

  Future<void> _pickUsedAt() async {
    final ctx = context;
    final initialDate = _usedAt;
    final date = await showDatePicker(
      context: ctx,
      initialDate: initialDate,
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime(DateTime.now().year + 1),
    );
    if (date == null) return;
    if (!ctx.mounted) return;

    final initialTime = TimeOfDay.fromDateTime(initialDate);
    final time = await showTimePicker(
      context: ctx,
      initialTime: initialTime,
    );
    if (time == null) return;
    if (!ctx.mounted) return;

    setState(() {
      _usedAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
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
        'lastUsedAt': Timestamp.fromDate(_usedAt), // reflect actual use time
      });

      tx.set(usageRef, {
        'itemId': widget.itemId,
        'qtyUsed': qty,
        'usedAt': Timestamp.fromDate(_usedAt), // <-- use selected date/time
        'interventionId': _intervention?.id,
        'forUseType': _forUse?.name, // 'staff' | 'patient'
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'grantId': _selectedGrantId(), // auto-filled from intervention
        'userId': null,
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
                ),

                // Grant badge (read-only, derived)
                if (_selectedGrantId() != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.local_atm, size: 18),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        ),
                        child: Text(
                          'Grant: ${_selectedGrantName()}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],

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

                // NEW: When it was used
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event),
                  title: const Text('When'),
                  subtitle: Text(_formatUsedAt(context)),
                  trailing: TextButton.icon(
                    onPressed: _pickUsedAt,
                    icon: const Icon(Icons.edit_calendar),
                    label: const Text('Change'),
                  ),
                  onTap: _pickUsedAt,
                ),

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
