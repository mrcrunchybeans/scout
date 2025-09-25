import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/label_export_service.dart';
import '../../widgets/label_sheet_preview.dart';

class LabelConfigPage extends StatefulWidget {
  const LabelConfigPage({super.key});

  @override
  State<LabelConfigPage> createState() => _LabelConfigPageState();
}

class _LabelConfigPageState extends State<LabelConfigPage> {
  final _db = FirebaseFirestore.instance;
  final _formKey = GlobalKey<FormState>();

  final _qrSize = TextEditingController();
  final _quietZone = TextEditingController();
  final _startIndex = TextEditingController();
  final _nudgeX = TextEditingController();
  final _nudgeY = TextEditingController();
  final _padding = TextEditingController();
  final _lotFont = TextEditingController();
  final _itemFont = TextEditingController();
  final _textSpacing = TextEditingController();
  final _cornerRadius = TextEditingController();
  final _dividerThickness = TextEditingController();
  final _textFlex = TextEditingController();
  final _qrFlex = TextEditingController();

  bool _showExpPill = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final doc = await _db.collection('config').doc('labels').get();
    if (!mounted) return;
    if (doc.exists) {
      final data = doc.data()!;
      setState(() {
        _qrSize.text = (data['qrCodeSize'] ?? LabelExportService.defaultTemplate.qrCodeSize).toString();
        _quietZone.text = (data['quietZone'] ?? LabelExportService.defaultTemplate.quietZone).toString();
        _startIndex.text = (data['startIndex'] ?? 0).toString();
        _nudgeX.text = (data['nudgeX'] ?? 0).toString();
        _nudgeY.text = (data['nudgeY'] ?? 0).toString();
        _padding.text = (data['padding'] ?? LabelExportService.defaultTemplate.padding).toString();
        _lotFont.text = (data['lotIdFontSize'] ?? LabelExportService.defaultTemplate.lotIdFontSize).toString();
        _itemFont.text = (data['itemNameFontSize'] ?? LabelExportService.defaultTemplate.itemNameFontSize).toString();
        _textSpacing.text = (data['textSpacing'] ?? LabelExportService.defaultTemplate.textSpacing).toString();
        _cornerRadius.text = (data['cornerRadius'] ?? LabelExportService.defaultTemplate.cornerRadius).toString();
        _dividerThickness.text = (data['dividerThickness'] ?? LabelExportService.defaultTemplate.dividerThickness).toString();
        _showExpPill = (data['showExpirationPill'] ?? LabelExportService.defaultTemplate.showExpirationPill) as bool;
        _textFlex.text = (data['textFlex'] ?? LabelExportService.defaultTemplate.textFlex).toString();
        _qrFlex.text = (data['qrFlex'] ?? LabelExportService.defaultTemplate.qrFlex).toString();
      });
    } else {
      setState(() {
        _qrSize.text = LabelExportService.defaultTemplate.qrCodeSize.toString();
        _quietZone.text = LabelExportService.defaultTemplate.quietZone.toString();
        _startIndex.text = '0';
        _nudgeX.text = '0';
        _nudgeY.text = '0';
        _padding.text = LabelExportService.defaultTemplate.padding.toString();
        _lotFont.text = LabelExportService.defaultTemplate.lotIdFontSize.toString();
        _itemFont.text = LabelExportService.defaultTemplate.itemNameFontSize.toString();
        _textSpacing.text = LabelExportService.defaultTemplate.textSpacing.toString();
        _cornerRadius.text = LabelExportService.defaultTemplate.cornerRadius.toString();
        _dividerThickness.text = LabelExportService.defaultTemplate.dividerThickness.toString();
        _showExpPill = LabelExportService.defaultTemplate.showExpirationPill;
        _textFlex.text = LabelExportService.defaultTemplate.textFlex.toString();
        _qrFlex.text = LabelExportService.defaultTemplate.qrFlex.toString();
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await _db.collection('config').doc('labels').set({
        'qrCodeSize': double.tryParse(_qrSize.text) ?? LabelExportService.defaultTemplate.qrCodeSize,
        'quietZone': double.tryParse(_quietZone.text) ?? LabelExportService.defaultTemplate.quietZone,
        'startIndex': int.tryParse(_startIndex.text) ?? 0,
        'nudgeX': double.tryParse(_nudgeX.text) ?? 0,
        'nudgeY': double.tryParse(_nudgeY.text) ?? 0,
        'padding': double.tryParse(_padding.text) ?? LabelExportService.defaultTemplate.padding,
        'lotIdFontSize': double.tryParse(_lotFont.text) ?? LabelExportService.defaultTemplate.lotIdFontSize,
        'itemNameFontSize': double.tryParse(_itemFont.text) ?? LabelExportService.defaultTemplate.itemNameFontSize,
        'textSpacing': double.tryParse(_textSpacing.text) ?? LabelExportService.defaultTemplate.textSpacing,
        'cornerRadius': double.tryParse(_cornerRadius.text) ?? LabelExportService.defaultTemplate.cornerRadius,
        'dividerThickness': double.tryParse(_dividerThickness.text) ?? LabelExportService.defaultTemplate.dividerThickness,
        'showExpirationPill': _showExpPill,
        'textFlex': int.tryParse(_textFlex.text) ?? LabelExportService.defaultTemplate.textFlex,
        'qrFlex': int.tryParse(_qrFlex.text) ?? LabelExportService.defaultTemplate.qrFlex,
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

  Future<int?> _askStartLabelNumber() async {
    int selectedZeroBased = 0;
    final textCtrl = TextEditingController(text: '1');

    return showDialog<int>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            void syncTextToGrid() {
              final n = int.tryParse(textCtrl.text) ?? 1;
              selectedZeroBased = n.clamp(1, 30) - 1;
            }

            return AlertDialog(
              title: const Text('Start label position'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Tap a slot or enter a number to choose where to start.'),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 260,
                    child: LabelSheetPreview(
                      selectedIndex: selectedZeroBased,
                      onSelected: (i) {
                        setState(() {
                          selectedZeroBased = i;
                          textCtrl.text = '${i + 1}';
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: textCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Label number (1–30)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(syncTextToGrid),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(selectedZeroBased),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _generateTest() async {
    final startIndex = await _askStartLabelNumber();
    if (startIndex == null) return;

    setState(() => _busy = true);
    try {
      final lots = [
        {'id': 'test', 'itemId': 'test-item', 'lotCode': 'TEST', 'itemName': 'Test'}
      ];
      final tpl = LabelTemplate(
        qrCodeSize: double.tryParse(_qrSize.text) ?? LabelExportService.defaultTemplate.qrCodeSize,
        quietZone: double.tryParse(_quietZone.text) ?? LabelExportService.defaultTemplate.quietZone,
        padding: double.tryParse(_padding.text) ?? LabelExportService.defaultTemplate.padding,
        lotIdFontSize: double.tryParse(_lotFont.text) ?? LabelExportService.defaultTemplate.lotIdFontSize,
        itemNameFontSize: double.tryParse(_itemFont.text) ?? LabelExportService.defaultTemplate.itemNameFontSize,
        textSpacing: double.tryParse(_textSpacing.text) ?? LabelExportService.defaultTemplate.textSpacing,
        cornerRadius: double.tryParse(_cornerRadius.text) ?? LabelExportService.defaultTemplate.cornerRadius,
        dividerThickness: double.tryParse(_dividerThickness.text) ?? LabelExportService.defaultTemplate.dividerThickness,
        showExpirationPill: _showExpPill,
        textFlex: int.tryParse(_textFlex.text) ?? LabelExportService.defaultTemplate.textFlex,
        qrFlex: int.tryParse(_qrFlex.text) ?? LabelExportService.defaultTemplate.qrFlex,
      );

      final nudgeX = double.tryParse(_nudgeX.text) ?? 0;
      final nudgeY = double.tryParse(_nudgeY.text) ?? 0;

      await LabelExportService.exportLabels(
        lots,
        template: tpl,
        startIndex: startIndex,
        nudgeX: nudgeX,
        nudgeY: nudgeY,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generated test label')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Generate failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _qrSize.dispose();
    _quietZone.dispose();
    _startIndex.dispose();
    _nudgeX.dispose();
    _nudgeY.dispose();
    _padding.dispose();
    _lotFont.dispose();
    _itemFont.dispose();
    _textSpacing.dispose();
    _cornerRadius.dispose();
    _dividerThickness.dispose();
    _textFlex.dispose();
    _qrFlex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Label Configuration')),
      body: Form(
        key: _formKey,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextFormField(
                  controller: _qrSize,
                  decoration: const InputDecoration(labelText: 'QR size (points)'),
                  validator: (v) => (v == null || double.tryParse(v) == null) ? 'Invalid' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _quietZone,
                  decoration: const InputDecoration(labelText: 'QR quiet zone (points)'),
                  validator: (v) => (v == null || double.tryParse(v) == null) ? 'Invalid' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _startIndex,
                  decoration: const InputDecoration(labelText: 'Default start index (0-29)'),
                  validator: (v) => (v == null || int.tryParse(v) == null) ? 'Invalid' : null,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _nudgeX,
                        decoration: const InputDecoration(labelText: 'Nudge X (points)'),
                        validator: (v) => (v == null || double.tryParse(v) == null) ? 'Invalid' : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _nudgeY,
                        decoration: const InputDecoration(labelText: 'Nudge Y (points)'),
                        validator: (v) => (v == null || double.tryParse(v) == null) ? 'Invalid' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _padding,
                  decoration: const InputDecoration(labelText: 'Padding (points)'),
                  validator: (v) => (v == null || double.tryParse(v) == null) ? 'Invalid' : null,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _lotFont,
                        decoration: const InputDecoration(labelText: 'Lot ID font size'),
                        validator: (v) => (v == null || double.tryParse(v) == null) ? 'Invalid' : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _itemFont,
                        decoration: const InputDecoration(labelText: 'Item name font size'),
                        validator: (v) => (v == null || double.tryParse(v) == null) ? 'Invalid' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _textSpacing,
                  decoration: const InputDecoration(labelText: 'Text spacing (points)'),
                  validator: (v) => (v == null || double.tryParse(v) == null) ? 'Invalid' : null,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _cornerRadius,
                        decoration: const InputDecoration(labelText: 'Corner radius'),
                        validator: (v) => (v == null || double.tryParse(v) == null) ? 'Invalid' : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _dividerThickness,
                        decoration: const InputDecoration(labelText: 'Divider thickness'),
                        validator: (v) => (v == null || double.tryParse(v) == null) ? 'Invalid' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: _showExpPill,
                  onChanged: (v) => setState(() => _showExpPill = v),
                  title: const Text('Show expiration pill'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _textFlex,
                        decoration: const InputDecoration(labelText: 'Text flex (int)'),
                        validator: (v) => (v == null || int.tryParse(v) == null) ? 'Invalid' : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _qrFlex,
                        decoration: const InputDecoration(labelText: 'QR flex (int)'),
                        validator: (v) => (v == null || int.tryParse(v) == null) ? 'Invalid' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: _busy ? null : _save,
                      child: _busy
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Save'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _busy ? null : _generateTest,
                      child: const Text('Generate Test Label'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
