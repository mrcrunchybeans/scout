import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
// Helper to normalize barcodes
String _normalizeBarcode(String s) =>
  s.replaceAll(RegExp(r'[^0-9A-Za-z]'), '').trim();

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
                      await ref.set({
                        'barcodes': FieldValue.arrayRemove([b]),
                        'updatedAt': FieldValue.serverTimestamp(),
                      }, SetOptions(merge: true));
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
    final db = FirebaseFirestore.instance;
    final lotsQ = db.collection('items').doc(itemId).collection('lots')
      .orderBy('expiresAt', descending: false) // FEFO; nulls last (Firestore sorts nulls first—handle in UI)
      .limit(200);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(child: Text('Lots (FEFO)', style: Theme.of(context).textTheme.titleMedium)),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add lot'),
                onPressed: () => _showAddLotSheet(context, itemId),
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
                return const Center(child: Text('No lots yet. Add one to start tracking expiration and remaining.'));
              }

              return ListView.separated(
                itemCount: docs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) => _LotRow(itemId: itemId, lotDoc: docs[i]),
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
  const _LotRow({required this.itemId, required this.lotDoc});

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

    return ListTile(
      title: Text('Lot ${lotDoc.id.substring(0, 6)}…'),
      subtitle: Text(sub),
      trailing: PopupMenuButton<String>(
        onSelected: (key) async {
          switch (key) {
            case 'adjust': await _showAdjustSheet(context, itemId, lotDoc.id, qtyRemaining, opened); break;
            case 'edit':   await _showEditLotSheet(context, itemId, lotDoc.id, d); break;
            case 'qr':     _showQrStub(context, lotDoc.id); break;
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'adjust', child: Text('Adjust remaining')),
          PopupMenuItem(value: 'edit',   child: Text('Edit dates/rules')),
          PopupMenuItem(value: 'qr',     child: Text('Scan/QR (stub)')),
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
      await widget.ref.set({
        'barcodes': FieldValue.arrayUnion([code]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _c.clear();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

Future<void> _showAddLotSheet(BuildContext context, String itemId) async {
  final db = FirebaseFirestore.instance;
  final cQtyInit = TextEditingController();
  final cQtyRemain = TextEditingController();
  DateTime? receivedAt = DateTime.now();
  DateTime? expiresAt;
  int? expiresAfterOpenDays;
  String baseUnit = 'each';

  Future<DateTime?> pickDate(DateTime? initial) => showDatePicker(
    context: context,
    initialDate: initial ?? DateTime.now(),
    firstDate: DateTime(DateTime.now().year - 1),
    lastDate: DateTime(DateTime.now().year + 3),
  );

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) {
      return Padding(
        padding: EdgeInsets.only(
          left: 16, right: 16, top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            Text('Add lot', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: baseUnit,
              items: const ['each','quart','ml','g','serving','scoop']
                .map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
              onChanged: (v) => baseUnit = v ?? 'each',
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
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Received date'),
              subtitle: Text(receivedAt == null
                ? 'None'
                : MaterialLocalizations.of(context).formatFullDate(receivedAt!)),
              trailing: TextButton.icon(
                icon: const Icon(Icons.edit_calendar),
                label: const Text('Pick'),
                onPressed: () async { receivedAt = await pickDate(receivedAt); (context as Element).markNeedsBuild(); },
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Expiration (optional)'),
              subtitle: Text(expiresAt == null
                ? 'None'
                : MaterialLocalizations.of(context).formatFullDate(expiresAt!)),
              trailing: TextButton.icon(
                icon: const Icon(Icons.event),
                label: const Text('Pick'),
                onPressed: () async { expiresAt = await pickDate(expiresAt); (context as Element).markNeedsBuild(); },
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
                await ref.set({
                  'baseUnit': baseUnit,
                  'qtyInitial': qi,
                  'qtyRemaining': qr,
                  'receivedAt': receivedAt != null ? Timestamp.fromDate(receivedAt!) : null,
                  'expiresAt':  expiresAt  != null ? Timestamp.fromDate(expiresAt!)  : null,
                  'openAt': null,
                  'expiresAfterOpenDays': expiresAfterOpenDays,
                  'createdAt': FieldValue.serverTimestamp(),
                  'updatedAt': FieldValue.serverTimestamp(),
                });
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ],
        ),
      );
    },
  );
}

Future<void> _showEditLotSheet(
  BuildContext context, String itemId, String lotId, Map<String, dynamic> d
) async {
  final db = FirebaseFirestore.instance;
  DateTime? expiresAt = (d['expiresAt'] is Timestamp) ? (d['expiresAt'] as Timestamp).toDate() : null;
  DateTime? openAt     = (d['openAt']   is Timestamp) ? (d['openAt']   as Timestamp).toDate() : null;
  int? afterOpenDays   = d['expiresAfterOpenDays'] as int?;

  Future<DateTime?> pick(DateTime? init) => showDatePicker(
    context: context,
    initialDate: init ?? DateTime.now(),
    firstDate: DateTime(DateTime.now().year - 1),
    lastDate: DateTime(DateTime.now().year + 3),
  );

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) {
      return Padding(
        padding: EdgeInsets.only(
          left: 16, right: 16, top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            Text('Edit lot', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Expiration'),
              subtitle: Text(expiresAt == null
                ? 'None'
                : MaterialLocalizations.of(context).formatFullDate(expiresAt!)),
              trailing: TextButton.icon(
                icon: const Icon(Icons.edit_calendar), label: const Text('Pick'),
                onPressed: () async { expiresAt = await pick(expiresAt); (context as Element).markNeedsBuild(); },
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Opened at'),
              subtitle: Text(openAt == null
                ? 'None'
                : MaterialLocalizations.of(context).formatFullDate(openAt!)),
              trailing: TextButton.icon(
                icon: const Icon(Icons.edit_calendar), label: const Text('Pick'),
                onPressed: () async { openAt = await pick(openAt); (context as Element).markNeedsBuild(); },
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
                await ref.set({
                  'expiresAt':  expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
                  'openAt':     openAt   != null ? Timestamp.fromDate(openAt!)   : null,
                  'expiresAfterOpenDays': afterOpenDays,
                  'updatedAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ],
        ),
      );
    },
  );
}

Future<void> _showAdjustSheet(
  BuildContext context, String itemId, String lotId, num currentRemaining, bool alreadyOpened
) async {
  final db = FirebaseFirestore.instance;
  final cDelta = TextEditingController();
  String reason = 'use';
  DateTime usedAt = DateTime.now();

  Future<DateTime?> pick(DateTime init) => showDatePicker(
    context: context,
    initialDate: init,
    firstDate: DateTime(DateTime.now().year - 1),
    lastDate: DateTime(DateTime.now().year + 1),
  );

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) {
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
            Text('Current remaining: $currentRemaining'),
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
              onChanged: (v) => reason = v ?? 'use',
              decoration: const InputDecoration(labelText: 'Reason'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('When'),
              subtitle: Text(MaterialLocalizations.of(context).formatFullDate(usedAt)),
              trailing: TextButton.icon(
                icon: const Icon(Icons.edit_calendar), label: const Text('Pick'),
                onPressed: () async { final d = await pick(usedAt); if (d!=null) { usedAt = d; (context as Element).markNeedsBuild(); } },
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: const Icon(Icons.check),
              label: const Text('Apply'),
              onPressed: () async {
                final delta = num.tryParse(cDelta.text.trim()) ?? 0;
                final lotRef = db.collection('items').doc(itemId).collection('lots').doc(lotId);
                await db.runTransaction((tx) async {
                  final snap = await tx.get(lotRef);
                  final data = snap.data() ?? {};
                  final rem = (data['qtyRemaining'] ?? 0) as num;
                  final newRem = rem + delta;
                  if (newRem < 0) throw Exception('Cannot go below 0');
                  final patch = <String, dynamic>{
                    'qtyRemaining': newRem,
                    'updatedAt': FieldValue.serverTimestamp(),
                  };
                  // First time it’s used: set openAt if delta is negative and not opened before
                  if (delta < 0 && (data['openAt'] == null) && !alreadyOpened) {
                    patch['openAt'] = Timestamp.fromDate(usedAt);
                  }
                  tx.set(lotRef, patch, SetOptions(merge: true));
                });

                // Optional: write an audit entry
                await db.collection('items').doc(itemId)
                  .collection('lot_adjustments').add({
                    'lotId': lotId,
                    'delta': delta,
                    'reason': reason,
                    'at': Timestamp.fromDate(usedAt),
                    'createdAt': FieldValue.serverTimestamp(),
                  });

                if (context.mounted) Navigator.pop(context);
              },
            ),
          ],
        ),
      );
    },
  );
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
