// lib/features/items/quick_use_sheet.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:scout/utils/audit.dart';

import '../../data/lookups_service.dart';
import '../../models/option_item.dart';

enum ForUseType { staff, patient }

// Unit types for adaptive UI
enum UnitType {
  count('Count', ['each', 'pieces', 'items', 'boxes', 'cans', 'bottles', 'tubes']),
  weight('Weight', ['grams', 'kg', 'lbs', 'ounces', 'pounds']),
  length('Length', ['meters', 'feet', 'yards', 'inches', 'cm']),
  area('Area', ['sq meters', 'sq feet', 'sheets', 'reams']),
  volume('Volume', ['liters', 'ml', 'gallons', 'cups', 'fl oz']);

  const UnitType(this.displayName, this.commonUnits);
  final String displayName;
  final List<String> commonUnits;
}

// ---- Lot model (local) ----
class LotInfo {
  final String id;
  final String baseUnit;
  final num qtyRemaining;
  final String? lotCode;
  final DateTime? expiresAt;
  final DateTime? openAt;
  final int? expiresAfterOpenDays;
  LotInfo({
    required this.id,
    required this.baseUnit,
    required this.qtyRemaining,
    this.lotCode,
    this.expiresAt,
    this.openAt,
    this.expiresAfterOpenDays,
  });
}

// Optional alias so this still matches your Step 6 naming
typedef LotOption = LotInfo;

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

  // qty chips in the item's base unit
  num qty = 1;
  ForUseType? _forUse;

  // Interventions + default grants
  OptionItem? _intervention;
  List<OptionItem>? _interventions;
  final Map<String, String?> _interventionGrantById = {}; // interventionId -> defaultGrantId
  final Map<String, String> _grantNamesById = {};         // grantId -> grant name

  // Item base unit (how staff think/record usage), defaults to 'each'
  String _baseUnit = 'each';
  UnitType _unitType = UnitType.count;

  // Lots for this item (FEFO sorted)
  List<LotOption>? _lots;
  LotOption? _selectedLot;

  // Notes + date/time used
  final _notes = TextEditingController();
  DateTime _usedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  // ----------------- Loaders -----------------
  Future<List<LotOption>> _loadLots(String itemId) async {
    final q = await _db.collection('items').doc(itemId).collection('lots').get();
    final list = q.docs.map((d) {
      final m = d.data();
      return LotInfo(
        id: d.id,
        lotCode: m['lotCode'] as String?,
        baseUnit: (m['baseUnit'] ?? 'each') as String,
        qtyRemaining: (m['qtyRemaining'] ?? 0) as num,
        expiresAt: (m['expiresAt'] is Timestamp) ? (m['expiresAt'] as Timestamp).toDate() : null,
        openAt: (m['openAt'] is Timestamp) ? (m['openAt'] as Timestamp).toDate() : null,
        expiresAfterOpenDays: (m['expiresAfterOpenDays'] as num?)?.toInt(),
      );
    }).toList();

    DateTime? effectiveExpiry(LotInfo l) {
      final exp = l.expiresAt;
      final open = l.openAt;
      final after = l.expiresAfterOpenDays;
      if (open != null && after != null && after > 0) {
        final afterOpen = DateTime(open.year, open.month, open.day).add(Duration(days: after));
        if (exp != null) return afterOpen.isBefore(exp) ? afterOpen : exp;
        return afterOpen;
      }
      return exp;
    }

    // FEFO: earliest effective expiration first (nulls last)
    list.sort((a, b) {
      final ea = effectiveExpiry(a);
      final eb = effectiveExpiry(b);
      if (ea == null && eb == null) return 0;
      if (ea == null) return 1; // null last
      if (eb == null) return -1;
      return ea.compareTo(eb);
    });

    // Only show lots with remaining > 0
    return list.where((l) => l.qtyRemaining > 0).toList();
  }

  Future<void> _load() async {
    final fInterventions = _lookups.interventions();
    final fInterventionsColl =
        _db.collection('interventions').where('active', isEqualTo: true).get();
    final fGrants = _db.collection('grants').where('active', isEqualTo: true).get();
    final fItem = _db.collection('items').doc(widget.itemId).get();
    final fLots = _loadLots(widget.itemId);

    final results = await Future.wait([
      fInterventions,
      fInterventionsColl,
      fGrants,
      fItem,
      fLots,
    ]);

    if (!mounted) return;

    final interventionsList = results[0] as List<OptionItem>;
    final interventionsSnap = results[1] as QuerySnapshot<Map<String, dynamic>>;
    final grantsSnap = results[2] as QuerySnapshot<Map<String, dynamic>>;
    final itemSnap = results[3] as DocumentSnapshot<Map<String, dynamic>>;
    final lots = results[4] as List<LotOption>;

    // fill maps
    final Map<String, String?> mapIntToGrant = {};
    for (final d in interventionsSnap.docs) {
      final data = d.data();
      mapIntToGrant[d.id] = data['defaultGrantId'] as String?;
    }
    final Map<String, String> mapGrantNames = {};
    for (final d in grantsSnap.docs) {
      final data = d.data();
      mapGrantNames[d.id] = (data['name'] ?? '') as String;
    }

    final data = itemSnap.data() ?? {};
    final baseUnit = (data['baseUnit'] ?? 'each') as String;
    final unitTypeStr = (data['unitType'] ?? 'count') as String;
    final unitType = UnitType.values.firstWhere(
      (t) => t.name == unitTypeStr,
      orElse: () => UnitType.count,
    );

    setState(() {
      _interventions = interventionsList;
      _interventionGrantById
        ..clear()
        ..addAll(mapIntToGrant);
      _grantNamesById
        ..clear()
        ..addAll(mapGrantNames);
      _baseUnit = baseUnit;
      _unitType = unitType;

      _lots = lots;
      _selectedLot = lots.isNotEmpty ? lots.first : null; // FEFO default
    });
  }

  // ----------------- Helpers -----------------
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

  List<Widget> _getQuantityChips() {
    switch (_unitType) {
      case UnitType.count:
        return [1, 2, 5].map((n) => ChoiceChip(
          label: Text('-$n $_baseUnit'),
          selected: qty == n,
          onSelected: (_) => setState(() => qty = n),
        )).toList();
      
      case UnitType.weight:
        return [0.5, 1.0, 2.5].map((n) => ChoiceChip(
          label: Text('-$n $_baseUnit'),
          selected: qty == n,
          onSelected: (_) => setState(() => qty = n),
        )).toList();
      
      case UnitType.volume:
        return [0.25, 0.5, 1.0].map((n) => ChoiceChip(
          label: Text('-$n $_baseUnit'),
          selected: qty == n,
          onSelected: (_) => setState(() => qty = n),
        )).toList();
      
      case UnitType.length:
        return [0.5, 1.0, 2.0].map((n) => ChoiceChip(
          label: Text('-$n $_baseUnit'),
          selected: qty == n,
          onSelected: (_) => setState(() => qty = n),
        )).toList();
      
      case UnitType.area:
        return [0.5, 1.0, 2.0].map((n) => ChoiceChip(
          label: Text('-$n $_baseUnit'),
          selected: qty == n,
          onSelected: (_) => setState(() => qty = n),
        )).toList();
    }
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
      lastDate: DateTime.now(), // prevent future
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

    final picked = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    final now = DateTime.now();
    setState(() {
      _usedAt = picked.isAfter(now) ? now : picked;
    });
  }

  // ----------------- Save -----------------
  Future<void> _logUse() async {
    final itemRef = _db.collection('items').doc(widget.itemId);
    final usageRef = _db.collection('usage_logs').doc();
    final usedAtTs = Timestamp.fromDate(_usedAt);

    final hasLots = (_lots != null && _lots!.isNotEmpty);
    final lot = _selectedLot;

    if (hasLots && lot != null) {
      // Decrement chosen lot; set openAt on first use; write usage with lotId.
      // Item totals/flags are recomputed by Cloud Functions.
      final lotRef = itemRef.collection('lots').doc(lot.id);

      await _db.runTransaction((tx) async {
        final lotSnap = await tx.get(lotRef);
        if (!lotSnap.exists) throw Exception('Lot not found');
        final m = lotSnap.data() as Map<String, dynamic>;
        final rem = (m['qtyRemaining'] ?? 0) as num;
        final newRem = rem - qty;
        if (newRem < 0) throw Exception('Lot has only $rem $_baseUnit remaining');

        final patch = <String, dynamic>{
          'qtyRemaining': newRem,
        };
        if ((m['openAt'] == null) && qty > 0) {
          patch['openAt'] = usedAtTs;
        }
        tx.set(lotRef, Audit.updateOnly(patch), SetOptions(merge: true));

        tx.set(itemRef, Audit.updateOnly({
          'lastUsedAt': usedAtTs,
        }), SetOptions(merge: true));

        tx.set(usageRef, Audit.attach({
          'itemId': widget.itemId,
          'lotId': lot.id,
          'qtyUsed': qty,
          'unit': _baseUnit,
          'usedAt': usedAtTs,
          'interventionId': _intervention?.id,
          'grantId': _selectedGrantId(),
          'forUseType': _forUse?.name,
          'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        }));

        await Audit.log('item.quickUse', {
          'itemId': widget.itemId,
          'lotId': lot.id,
          'qtyUsed': qty,
          'unit': _baseUnit,
          'usedAt': usedAtTs,
          'interventionId': _intervention?.id,
          'grantId': _selectedGrantId(),
          'forUseType': _forUse?.name,
          'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        });
      });
    } else {
      // Back-compat path for items without lots yet.
      await _db.runTransaction((tx) async {
        final itemSnap = await tx.get(itemRef);
        if (!itemSnap.exists) throw Exception('Item not found');
        final data = itemSnap.data() as Map<String, dynamic>;
        final currentQty = (data['qtyOnHand'] ?? 0) as num;
        final newQty = currentQty - qty;
        if (newQty < 0) throw Exception('Insufficient stock');

        tx.update(itemRef, Audit.updateOnly({
          'qtyOnHand': newQty,
          'lastUsedAt': usedAtTs,
        }));

        tx.set(usageRef, Audit.attach({
          'itemId': widget.itemId,
          'qtyUsed': qty,
          'unit': _baseUnit,
          'usedAt': usedAtTs,
          'interventionId': _intervention?.id,
          'grantId': _selectedGrantId(),
          'forUseType': _forUse?.name,
          'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        }));

        await Audit.log('item.quickUse', {
          'itemId': widget.itemId,
          'qtyUsed': qty,
          'unit': _baseUnit,
          'usedAt': usedAtTs,
          'interventionId': _intervention?.id,
          'grantId': _selectedGrantId(),
          'forUseType': _forUse?.name,
          'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        });
      });
    }
  }

  // ----------------- UI -----------------
  @override
  Widget build(BuildContext context) {
    final loading = _interventions == null || _lots == null;
    final hasLots = (_lots?.isNotEmpty ?? false);
    final lotOk = hasLots ? _selectedLot != null : true;
    final canSubmit = !loading && _intervention != null && qty > 0 && lotOk;

    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: loading
          ? const SizedBox(height: 220, child: Center(child: CircularProgressIndicator()))
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.itemName, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),

                // Qty chips (+ Custom) in baseUnit - adaptive based on unit type
                Wrap(
                  spacing: 8,
                  children: <Widget>[
                    ..._getQuantityChips(),
                    ActionChip(
                      label: const Text('Custom'),
                      onPressed: () async {
                        final v = await showDialog<num>(
                          context: context,
                          builder: (_) => const _NumberDialog(isDecimal: true), // Always allow decimals
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

                // Grant badge (derived)
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

                // Lot dropdown (if item has lots)
                if (hasLots) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<LotOption>(
                    initialValue: _selectedLot,
                    items: _lots!
                        .map(
                          (l) => DropdownMenuItem(
                            value: l,
                            child: Text(
                              '${l.lotCode ?? l.id} • ${l.qtyRemaining} $_baseUnit'
                              '${l.expiresAt != null ? ' • exp ${MaterialLocalizations.of(context).formatShortDate(l.expiresAt!)}' : ''}',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _selectedLot = v),
                    decoration: InputDecoration(labelText: 'Lot ($_baseUnit)'),
                  ),
                ],

                const SizedBox(height: 8),

                // ForUseType (optional)
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

                // When it was used
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

                // Notes
                TextField(
                  controller: _notes,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    hintText: 'e.g., unit/room or context',
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
  const _NumberDialog({this.isDecimal = false});
  final bool isDecimal;
  
  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  final c = TextEditingController(text: '1');
  @override
  void dispose() { c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      backgroundColor: colorScheme.surface,
      surfaceTintColor: colorScheme.surfaceTint,
      title: Text(
        'Quantity used',
        style: TextStyle(color: colorScheme.onSurface),
      ),
      content: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true), // Always allow decimals
        style: TextStyle(color: colorScheme.onSurface),
        decoration: InputDecoration(
          prefixText: '-',
          filled: true,
          fillColor: colorScheme.surfaceContainerHighest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: colorScheme.outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(width: 1.5, color: colorScheme.primary),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            foregroundColor: colorScheme.onSurface.withValues(alpha: 0.8),
          ),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final v = double.tryParse(c.text.trim()); // Always parse as double
            Navigator.pop<num>(context, (v == null || v < 0.01) ? 1 : v);
          },
          child: const Text('Done'),
        ),
      ],
    );
  }
}
