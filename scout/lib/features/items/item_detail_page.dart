import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../utils/audit.dart';
// Helper to normalize barcodes
String _normalizeBarcode(String s) =>
  s.replaceAll(RegExp(r'[^0-9A-Za-z]'), '').trim();

// Helper to generate lot codes in YYMM-XXX format (easy to write, unique)
String _generateLotCode(String productCode) {
  final now = DateTime.now();
  final yy = now.year.toString().substring(2); // Last 2 digits of year
  final mm = now.month.toString().padLeft(2, '0'); // Month with leading zero
  // Use last 3 digits of milliseconds for uniqueness (000-999)
  final unique = now.millisecondsSinceEpoch % 1000;
  final xxx = unique.toString().padLeft(3, '0');
  return '$yy$mm-$xxx';
}

class ItemDetailPage extends StatelessWidget {
  final String itemId;
  final String itemName;
  const ItemDetailPage({super.key, required this.itemId, required this.itemName});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(itemName),
          bottom: const TabBar(tabs: [
            Tab(text: 'Details'),
            Tab(text: 'Manage Lots'),
          ]),
        ),
        body: TabBarView(
          children: [
            _ItemSummaryTab(itemId: itemId),
            _LotsTab(itemId: itemId),
          ],
        ),
      ),
    );
  }
}

class _ItemSummaryTab extends StatelessWidget {
  final String itemId;
  const _ItemSummaryTab({required this.itemId});

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final ref = db.collection('items').doc(itemId);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (ctx, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final data = snap.data!.data() ?? {};
        final qty = (data['qtyOnHand'] ?? 0) as num;
        final minQty = (data['minQty'] ?? 0) as num;
        final baseUnit = (data['baseUnit'] ?? 'each') as String;
        final flags = [
          if (data['flagLow'] == true) 'LOW',
          if (data['flagExcess'] == true) 'EXCESS',
          if (data['flagStale'] == true) 'STALE',
          if (data['flagExpiringSoon'] == true) 'EXPIRING',
        ].join(' • ');
        final ts = data['earliestExpiresAt'];
        final exp = (ts is Timestamp) ? ts.toDate() : null;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('On hand: $qty $baseUnit • Min: $minQty'),
            const SizedBox(height: 8),
            if (exp != null) Text('Earliest expiration: ${MaterialLocalizations.of(context).formatFullDate(exp)}'),
            const SizedBox(height: 8),
            if (flags.isNotEmpty)
              Wrap(spacing: 8, children: flags.split(' • ').map((f) => Chip(label: Text(f))).toList()),

            // --- Barcode chip editor ---
            const SizedBox(height: 16),
            Text('Barcodes', style: Theme.of(context).textTheme.titleMedium),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final b in (data['barcodes'] as List?)?.cast<String>() ?? const <String>[])
                  InputChip(
                    label: Text(b),
                    onDeleted: () async {
                      await ref.set(
                        Audit.updateOnly({'barcodes': FieldValue.arrayRemove([b])}),
                        SetOptions(merge: true),
                      );
                      await Audit.log('item.barcode.remove', {'itemId': ref.id, 'barcode': b});
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _RowAddBarcode(ref: ref),
          ],
        );
      },
    );
  }
}

class _LotsTab extends StatelessWidget {
  final String itemId;
  const _LotsTab({required this.itemId});

  @override
  Widget build(BuildContext context) {
    return _LotsTabContent(itemId: itemId);
  }
}

class _LotsTabContent extends StatefulWidget {
  final String itemId;
  const _LotsTabContent({required this.itemId});

  @override
  State<_LotsTabContent> createState() => _LotsTabContentState();
}

class _LotsTabContentState extends State<_LotsTabContent> {
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final lotsQ = db.collection('items').doc(widget.itemId).collection('lots')
      .where('archived', isEqualTo: _showArchived ? true : null) // Show archived or active lots
      .orderBy('expiresAt', descending: false) // FEFO; nulls last (Firestore sorts nulls first—handle in UI)
      .limit(200);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _showArchived ? 'Archived Lots' : 'Lots (FEFO)',
                  style: Theme.of(context).textTheme.titleMedium
                )
              ),
              TextButton.icon(
                icon: Icon(_showArchived ? Icons.visibility_off : Icons.archive),
                label: Text(_showArchived ? 'Show Active' : 'Show Archived'),
                onPressed: () => setState(() => _showArchived = !_showArchived),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add lot'),
                onPressed: () => _showAddLotSheet(context, widget.itemId),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: lotsQ.snapshots(),
            builder: (ctx, snap) {
              if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              // Push null-expiry lots to the end for FEFO UX
              final docs = snap.data!.docs.toList()
                ..sort((a, b) {
                  DateTime? ea, eb;
                  final ta = a.data()['expiresAt'], tb = b.data()['expiresAt'];
                  ea = (ta is Timestamp) ? ta.toDate() : null;
                  eb = (tb is Timestamp) ? tb.toDate() : null;
                  if (ea == null && eb == null) return 0;
                  if (ea == null) return 1; // null last
                  if (eb == null) return -1;
                  return ea.compareTo(eb); // soonest first
                });

              if (docs.isEmpty) {
                return Center(
                  child: Text(
                    _showArchived
                      ? 'No archived lots.'
                      : 'No lots yet. Add one to start tracking expiration and remaining.'
                  )
                );
              }

              return ListView.separated(
                itemCount: docs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) => _LotRow(
                  itemId: widget.itemId,
                  lotDoc: docs[i],
                  isArchived: _showArchived,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LotRow extends StatelessWidget {
  final String itemId;
  final QueryDocumentSnapshot<Map<String, dynamic>> lotDoc;
  final bool isArchived;
  const _LotRow({required this.itemId, required this.lotDoc, this.isArchived = false});

  @override
  Widget build(BuildContext context) {
    final d = lotDoc.data();
    final baseUnit = (d['baseUnit'] ?? 'each') as String;
    final qtyInitial = (d['qtyInitial'] ?? 0) as num;
    final qtyRemaining = (d['qtyRemaining'] ?? 0) as num;
    final expTs = d['expiresAt'];  final exp = (expTs is Timestamp) ? expTs.toDate() : null;
    final openTs = d['openAt'];    final opened = openTs is Timestamp;
    final afterOpen = d['expiresAfterOpenDays'] as int?;
    final receivedTs = d['receivedAt']; final received = (receivedTs is Timestamp) ? receivedTs.toDate() : null;

    final sub = <String>[
      'Remaining: $qtyRemaining / $qtyInitial $baseUnit',
      if (exp != null) 'Exp: ${MaterialLocalizations.of(context).formatFullDate(exp)}',
      if (opened) 'Opened',
      if (afterOpen != null && afterOpen > 0) 'Use within $afterOpen days after open',
      if (received != null) 'Received: ${MaterialLocalizations.of(context).formatFullDate(received)}',
    ].join(' • ');

    final lotCode = (d['lotCode'] ?? lotDoc.id.substring(0, 6)) as String;

    return ListTile(
      title: Text('${isArchived ? '[ARCHIVED] ' : ''}Lot $lotCode'),
      subtitle: Text(sub),
      trailing: PopupMenuButton<String>(
        onSelected: (key) async {
          if (!context.mounted) return;
          switch (key) {
            case 'adjust': await showAdjustSheet(context, itemId, lotDoc.id, qtyRemaining, opened); break;
            case 'edit':   await _showEditLotSheet(context, itemId, lotDoc.id, d); break;
            case 'archive': await _showArchiveLotDialog(context, itemId, lotDoc.id, d); break;
            case 'unarchive': await _showUnarchiveLotDialog(context, itemId, lotDoc.id, d); break;
            case 'delete': await _showDeleteLotDialog(context, itemId, lotDoc.id, d); break;
            case 'qr':     _showQrStub(context, lotDoc.id); break;
          }
        },
        itemBuilder: (_) => [
          if (!isArchived) ...[
            const PopupMenuItem(value: 'adjust', child: Text('Adjust remaining')),
            const PopupMenuItem(value: 'edit',   child: Text('Edit dates/rules')),
            const PopupMenuItem(value: 'archive', child: Text('Archive lot')),
          ] else ...[
            const PopupMenuItem(value: 'unarchive', child: Text('Unarchive lot')),
          ],
          const PopupMenuItem(value: 'delete', child: Text('Delete lot')),
          const PopupMenuItem(value: 'qr',     child: Text('Scan/QR (stub)')),
        ],
      ),
    );
  }
}

// Widget for adding a barcode
class _RowAddBarcode extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>> ref;
  const _RowAddBarcode({required this.ref});
  @override
  State<_RowAddBarcode> createState() => _RowAddBarcodeState();
}

class _RowAddBarcodeState extends State<_RowAddBarcode> {
  final _c = TextEditingController();
  bool _saving = false;

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _c,
            decoration: const InputDecoration(
              labelText: 'Add barcode',
              hintText: 'Type or paste',
            ),
            onSubmitted: (_) => _add(),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _saving ? null : _add,
          child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                         : const Text('Add'),
        ),
      ],
    );
  }

  Future<void> _add() async {
    final raw = _c.text;
    final code = _normalizeBarcode(raw);
    if (code.isEmpty) return;
    setState(() => _saving = true);
    try {
      final doc = await widget.ref.get();
      final barcodes = doc.data()?['barcodes'] as List? ?? [];
      final wasEmpty = barcodes.isEmpty;
      await widget.ref.set(
        Audit.updateOnly({
          'barcodes': FieldValue.arrayUnion([code]),
          if (wasEmpty) 'barcode': code, // set primary if empty
        }),
        SetOptions(merge: true),
      );
      await Audit.log('item.attach_barcode', {
        'itemId': widget.ref.id,
        'code': code,
        'addedToArray': true,
        'setPrimaryIfEmpty': wasEmpty,
      });
      _c.clear();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

Future<void> _showAddLotSheet(BuildContext context, String itemId) async {
  final db = FirebaseFirestore.instance;

    final itemDoc = await db.collection('items').doc(itemId).get();
  if (!itemDoc.exists || !context.mounted) return;
  final itemData = itemDoc.data()!;
  final productCode = itemData['code'] as String? ?? itemId.substring(0, 4).toUpperCase();
  final suggestedLotCode = _generateLotCode(productCode);

  final cQtyInit = TextEditingController();
  final cQtyRemain = TextEditingController();
  final cLotCode = TextEditingController(text: suggestedLotCode);
  DateTime? receivedAt = DateTime.now();
  DateTime? expiresAt;
  int? expiresAfterOpenDays;
  String baseUnit = 'each';

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (bottomSheetContext, bottomSheetSetState) {
          Future<DateTime?> pickDate(DateTime? initial) => showDatePicker(
            context: bottomSheetContext,
            initialDate: initial ?? DateTime.now(),
            firstDate: DateTime(DateTime.now().year - 1),
            lastDate: DateTime(DateTime.now().year + 3),
          );

          return Padding(
            padding: EdgeInsets.only(
              left: 16, right: 16, top: 16,
              bottom: 16 + MediaQuery.of(bottomSheetContext).viewInsets.bottom,
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                Text('Add lot', style: Theme.of(bottomSheetContext).textTheme.titleLarge),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: baseUnit,
                  items: const ['each','quart','ml','g','serving','scoop']
                    .map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                  onChanged: (v) => bottomSheetSetState(() => baseUnit = v ?? 'each'),
                  decoration: const InputDecoration(labelText: 'Base unit'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: cQtyInit,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Initial quantity'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: cQtyRemain,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Starting remaining (optional)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: cLotCode,
                  decoration: InputDecoration(
                    labelText: 'Lot code',
                    hintText: suggestedLotCode,
                    helperText: 'Auto-generated in YYMM-XXX format (e.g., 2509-001)',
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Received date'),
                  subtitle: Text(receivedAt == null
                    ? 'None'
                    : MaterialLocalizations.of(bottomSheetContext).formatFullDate(receivedAt!)),
                  trailing: TextButton.icon(
                    icon: const Icon(Icons.edit_calendar),
                    label: const Text('Pick'),
                    onPressed: () async {
                      final picked = await pickDate(receivedAt);
                      if (picked != null) {
                        bottomSheetSetState(() => receivedAt = picked);
                      }
                    },
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Expiration (optional)'),
                  subtitle: Text(expiresAt == null
                    ? 'None'
                    : MaterialLocalizations.of(bottomSheetContext).formatFullDate(expiresAt!)),
                  trailing: TextButton.icon(
                    icon: const Icon(Icons.event),
                    label: const Text('Pick'),
                    onPressed: () async {
                      final picked = await pickDate(expiresAt);
                      if (picked != null) {
                        bottomSheetSetState(() => expiresAt = picked);
                      }
                    },
                  ),
                ),
                TextField(
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Days after open (optional)',
                    helperText: 'Use within N days after opening',
                  ),
                  onChanged: (s) => expiresAfterOpenDays = int.tryParse(s),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('Save lot'),
                  onPressed: () async {
                    final qi = num.tryParse(cQtyInit.text) ?? 0;
                    final qr = (cQtyRemain.text.trim().isEmpty)
                      ? qi
                      : (num.tryParse(cQtyRemain.text) ?? qi);
                    final ref = db.collection('items').doc(itemId).collection('lots').doc();
                    await ref.set(
                      Audit.attach({
                        'lotCode': cLotCode.text.trim().isEmpty ? null : cLotCode.text.trim(),
                        'baseUnit': baseUnit,
                        'qtyInitial': qi,
                        'qtyRemaining': qr,
                        'receivedAt': receivedAt != null ? Timestamp.fromDate(receivedAt!) : null,
                        'expiresAt':  expiresAt  != null ? Timestamp.fromDate(expiresAt!)  : null,
                        'openAt': null,
                        'expiresAfterOpenDays': expiresAfterOpenDays,
                      }),
                    );
                    await Audit.log('lot.create', {
                      'itemId': itemId,
                      'lotId': ref.id,
                      'qtyInitial': qi,
                      'qtyRemaining': qr,
                    });
                    if (bottomSheetContext.mounted) {
                      Navigator.pop(bottomSheetContext);
                    }
                  },
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

Future<void> _showEditLotSheet(
  BuildContext context, String itemId, String lotId, Map<String, dynamic> d
) async {
  final db = FirebaseFirestore.instance;
  
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (bottomSheetContext, bottomSheetSetState) {
          DateTime? expiresAt = (d['expiresAt'] is Timestamp) ? (d['expiresAt'] as Timestamp).toDate() : null;
          DateTime? openAt     = (d['openAt']   is Timestamp) ? (d['openAt']   as Timestamp).toDate() : null;
          int? afterOpenDays   = d['expiresAfterOpenDays'] as int?;

          Future<DateTime?> pick(DateTime? init) => showDatePicker(
            context: bottomSheetContext,
            initialDate: init ?? DateTime.now(),
            firstDate: DateTime(DateTime.now().year - 1),
            lastDate: DateTime(DateTime.now().year + 3),
          );

          return Padding(
            padding: EdgeInsets.only(
              left: 16, right: 16, top: 16,
              bottom: 16 + MediaQuery.of(bottomSheetContext).viewInsets.bottom,
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                Text('Edit lot', style: Theme.of(bottomSheetContext).textTheme.titleLarge),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Expiration'),
                  subtitle: Text(expiresAt == null
                    ? 'None'
                    : MaterialLocalizations.of(bottomSheetContext).formatFullDate(expiresAt)),
                  trailing: TextButton.icon(
                    icon: const Icon(Icons.edit_calendar), label: const Text('Pick'),
                    onPressed: () async {
                      final picked = await pick(expiresAt);
                      if (picked != null) {
                        bottomSheetSetState(() => expiresAt = picked);
                      }
                    },
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Opened at'),
                  subtitle: Text(openAt == null
                    ? 'None'
                    : MaterialLocalizations.of(bottomSheetContext).formatFullDate(openAt)),
                  trailing: TextButton.icon(
                    icon: const Icon(Icons.edit_calendar), label: const Text('Pick'),
                    onPressed: () async {
                      final picked = await pick(openAt);
                      if (picked != null) {
                        bottomSheetSetState(() => openAt = picked);
                      }
                    },
                  ),
                ),
                TextField(
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Days after open (optional)'),
                  controller: TextEditingController(text: afterOpenDays?.toString() ?? ''),
                  onChanged: (s) => afterOpenDays = int.tryParse(s),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('Save'),
                  onPressed: () async {
                    final ref = db.collection('items').doc(itemId).collection('lots').doc(lotId);
                    await ref.set(
                      Audit.updateOnly({
                        'expiresAt':  expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
                        'openAt':     openAt   != null ? Timestamp.fromDate(openAt!)   : null,
                        'expiresAfterOpenDays': afterOpenDays,
                      }),
                      SetOptions(merge: true),
                    );
                    await Audit.log('lot.update', {
                      'itemId': itemId,
                      'lotId': lotId,
                      'expiresAt':  expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
                      'openAt':     openAt   != null ? Timestamp.fromDate(openAt!)   : null,
                      'expiresAfterOpenDays': afterOpenDays,
                    });
                    if (bottomSheetContext.mounted) {
                      Navigator.pop(bottomSheetContext);
                    }
                  },
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

Future<void> showAdjustSheet(
  BuildContext context, String itemId, String lotId, num currentRemaining, bool alreadyOpened
) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return _AdjustSheetContent(
        itemId: itemId,
        lotId: lotId,
        currentRemaining: currentRemaining,
        alreadyOpened: alreadyOpened,
      );
    },
  );
}

class _AdjustSheetContent extends StatefulWidget {
  final String itemId;
  final String lotId;
  final num currentRemaining;
  final bool alreadyOpened;

  const _AdjustSheetContent({
    required this.itemId,
    required this.lotId,
    required this.currentRemaining,
    required this.alreadyOpened,
  });

  @override
  State<_AdjustSheetContent> createState() => _AdjustSheetContentState();
}

class _AdjustSheetContentState extends State<_AdjustSheetContent> {
  late final TextEditingController cDelta;
  late String reason;
  late DateTime usedAt;
  final db = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    cDelta = TextEditingController();
    reason = 'use';
    usedAt = DateTime.now();
  }

  @override
  void dispose() {
    cDelta.dispose();
    super.dispose();
  }

  Future<DateTime?> pick(DateTime init) => showDatePicker(
    context: context,
    initialDate: init,
    firstDate: DateTime(DateTime.now().year - 1),
    lastDate: DateTime(DateTime.now().year + 1),
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text('Adjust remaining (− for use, + for correction)', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text('Current remaining: ${widget.currentRemaining}'),
          const SizedBox(height: 8),
          TextField(
            controller: cDelta,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(prefixText: '', labelText: 'Delta (e.g., -2)'),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: reason,
            items: const [
              DropdownMenuItem(value: 'use', child: Text('Used')),
              DropdownMenuItem(value: 'waste', child: Text('Waste/expired')),
              DropdownMenuItem(value: 'correction', child: Text('Manual correction')),
            ],
            onChanged: (v) => setState(() => reason = v ?? 'use'),
            decoration: const InputDecoration(labelText: 'Reason'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('When'),
            subtitle: Text(MaterialLocalizations.of(context).formatFullDate(usedAt)),
            trailing: TextButton.icon(
              icon: const Icon(Icons.edit_calendar), label: const Text('Pick'),
              onPressed: () async {
                final d = await pick(usedAt);
                if (d != null) {
                  setState(() => usedAt = d);
                }
              },
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            icon: const Icon(Icons.check),
            label: const Text('Apply'),
            onPressed: () async {
              final delta = num.tryParse(cDelta.text.trim()) ?? 0;
              if (delta == 0) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a non-zero adjustment amount')),
                  );
                }
                return;
              }

              try {
                final lotRef = db.collection('items').doc(widget.itemId).collection('lots').doc(widget.lotId);
                await db.runTransaction((tx) async {
                  final snap = await tx.get(lotRef);
                  final data = snap.data() ?? {};
                  final rem = (data['qtyRemaining'] ?? 0) as num;
                  final newRem = rem + delta;
                  if (newRem < 0) throw Exception('Cannot reduce quantity below 0');

                  final patch = <String, dynamic>{
                    'qtyRemaining': newRem,
                    'updatedAt': FieldValue.serverTimestamp(),
                  };
                  if (delta < 0 && (data['openAt'] == null) && !widget.alreadyOpened) {
                    patch['openAt'] = Timestamp.fromDate(usedAt);
                  }
                  tx.set(lotRef, Audit.updateOnly(patch), SetOptions(merge: true));

                  // Create adjustment record within the transaction
                  final adjustmentRef = db.collection('items').doc(widget.itemId)
                    .collection('lot_adjustments').doc();
                  tx.set(adjustmentRef, {
                    'lotId': widget.lotId,
                    'delta': delta,
                    'reason': reason,
                    'at': Timestamp.fromDate(usedAt),
                    'createdAt': FieldValue.serverTimestamp(),
                  });
                });

                // Log audit outside transaction (audit logs are append-only)
                await Audit.log('lot.adjust', {
                  'itemId': widget.itemId,
                  'lotId': widget.lotId,
                  'delta': delta,
                  'reason': reason,
                  'previousRemaining': widget.currentRemaining,
                  'newRemaining': widget.currentRemaining + delta,
                  'at': Timestamp.fromDate(usedAt),
                });

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Lot adjusted by $delta')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error adjusting lot: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }
}

void _showQrStub(BuildContext context, String lotId) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('QR / Scan'),
      content: Text('Stub: scan/QR not wired yet.\nLot ID: $lotId'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    ),
  );
}

Future<void> _showArchiveLotDialog(BuildContext context, String itemId, String lotId, Map<String, dynamic> lotData) async {
  final lotCode = lotData['lotCode'] ?? lotId;
  final qtyRemaining = (lotData['qtyRemaining'] ?? 0) as num;

  final result = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Archive Lot'),
      content: Text(
        'Archive lot "$lotCode"? This will hide the lot from active inventory but keep it for historical records.\n\n'
        'Remaining quantity: $qtyRemaining\n\n'
        'You can unarchive lots later if needed.'
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Archive'),
        ),
      ],
    ),
  );

  if (result == true && context.mounted) {
    final db = FirebaseFirestore.instance;
    final lotRef = db.collection('items').doc(itemId).collection('lots').doc(lotId);

    await lotRef.set(
      Audit.updateOnly({
        'archived': true,
        'archivedAt': FieldValue.serverTimestamp(),
      }),
      SetOptions(merge: true),
    );

    await Audit.log('lot.archive', {
      'itemId': itemId,
      'lotId': lotId,
      'lotCode': lotCode,
      'qtyRemaining': qtyRemaining,
    });
  }
}

Future<void> _showUnarchiveLotDialog(BuildContext context, String itemId, String lotId, Map<String, dynamic> lotData) async {
  final lotCode = lotData['lotCode'] ?? lotId;
  final qtyRemaining = (lotData['qtyRemaining'] ?? 0) as num;

  final result = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Unarchive Lot'),
      content: Text(
        'Unarchive lot "$lotCode"? This will restore the lot to active inventory.\n\n'
        'Remaining quantity: $qtyRemaining\n\n'
        'The lot will be available for use again.'
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Unarchive'),
        ),
      ],
    ),
  );

  if (result == true && context.mounted) {
    final db = FirebaseFirestore.instance;
    final lotRef = db.collection('items').doc(itemId).collection('lots').doc(lotId);

    await lotRef.set(
      Audit.updateOnly({
        'archived': FieldValue.delete(), // Remove the archived field
        'archivedAt': FieldValue.delete(),
      }),
      SetOptions(merge: true),
    );

    await Audit.log('lot.unarchive', {
      'itemId': itemId,
      'lotId': lotId,
      'lotCode': lotCode,
      'qtyRemaining': qtyRemaining,
    });
  }
}

Future<void> _showDeleteLotDialog(BuildContext context, String itemId, String lotId, Map<String, dynamic> lotData) async {
  final lotCode = lotData['lotCode'] ?? lotId;
  final qtyRemaining = (lotData['qtyRemaining'] ?? 0) as num;

  // Prevent deleting lots with remaining inventory
  if (qtyRemaining > 0) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot delete lot with remaining inventory. Adjust quantity to 0 first.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
    return;
  }

  final result = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Delete Lot'),
      content: Text(
        'Permanently delete lot "$lotCode"? This action cannot be undone.\n\n'
        '⚠️ Warning: This will permanently remove all data for this lot.'
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete Permanently'),
        ),
      ],
    ),
  );

  if (result == true && context.mounted) {
    final db = FirebaseFirestore.instance;
    final lotRef = db.collection('items').doc(itemId).collection('lots').doc(lotId);

    try {
      // Debug: Check if lot exists before delete
      final doc = await lotRef.get();
      if (!doc.exists) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Lot no longer exists')),
          );
        }
        return;
      }

      await lotRef.delete();

      // Debug: Verify deletion
      final verifyDoc = await lotRef.get();
      if (verifyDoc.exists) {
        throw Exception('Delete failed - lot still exists after delete operation');
      }

      await Audit.log('lot.delete', {
        'itemId': itemId,
        'lotId': lotId,
        'lotCode': lotCode,
        'qtyRemaining': qtyRemaining,
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lot "$lotCode" deleted successfully')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting lot: $e')),
        );
      }
    }
  }
}