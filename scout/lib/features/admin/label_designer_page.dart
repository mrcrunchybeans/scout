import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../services/label_export_service.dart';

class LabelDesignerPage extends StatefulWidget {
  const LabelDesignerPage({super.key});

  @override
  State<LabelDesignerPage> createState() => _LabelDesignerPageState();
}

class _LabelDesignerPageState extends State<LabelDesignerPage> {
  final _db = FirebaseFirestore.instance;
  Map<String, dynamic> _layout = {};
  bool _loading = true;
  String? _selectedKey;

  @override
  void initState() {
    super.initState();
    _loadLayout();
  }

  Future<void> _loadLayout() async {
    try {
      final doc = await _db.collection('config').doc('labels').get();
      if (doc.exists) {
        setState(() {
          _layout = doc.data()?['design'] as Map<String, dynamic>? ?? {};
          _loading = false;
        });
        return;
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _saveLayout() async {
    await _db.collection('config').doc('labels').set({'design': _layout}, SetOptions(merge: true));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved label layout')));
  }

  void _resetDefaults() {
    setState(() {
      _layout = {
        'lotId': {'x': 0.02, 'y': 0.05, 'w': 0.55, 'h': 0.2},
        'itemName': {'x': 0.02, 'y': 0.27, 'w': 0.55, 'h': 0.36},
        'expiration': {'x': 0.02, 'y': 0.65, 'w': 0.55, 'h': 0.15},
        'qr': {'x': 0.62, 'y': 0.1, 'w': 0.36, 'h': 0.75},
      };
    });
  }

  Future<void> _generateTestLabel() async {
    final lots = [
      {
        'id': 'test-lot-1',
        'lotCode': 'LOT-001',
        'itemId': 'test-item-1',
        'itemName': 'Test Item (Designer Preview)',
        'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 90))),
      }
    ];

    // Use a LabelTemplate with the design applied via export service
    try {
      // Persist current layout so exporter can read it
      await _saveLayout();
      await LabelExportService.exportLabels(lots, template: null, startIndex: 0);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generated test label (download)')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to generate test label: $e')));
    }
  }

  // Helper: ensure a block exists with defaults
  Map<String, dynamic> _ensure(String key) {
    final state = _layout[key] as Map<String, dynamic>? ?? {'x': 0.05, 'y': 0.05, 'w': 0.4, 'h': 0.15};
    _layout[key] = state;
    return state;
  }

  // Build a draggable & resizable block in fractional coordinates
  Widget _buildBlock(String key, String label, {Color color = Colors.blue}) {
    final state = _ensure(key);
    return Positioned(
      left: state['x'] * 300,
      top: state['y'] * 100,
      width: state['w'] * 300,
      height: state['h'] * 100,
      child: GestureDetector(
        onTap: () => setState(() => _selectedKey = key),
        onPanUpdate: (details) {
          setState(() {
            state['x'] = ((state['x'] as num).toDouble() + details.delta.dx / 300).clamp(0.0, 1.0 - (state['w'] as num).toDouble());
            state['y'] = ((state['y'] as num).toDouble() + details.delta.dy / 100).clamp(0.0, 1.0 - (state['h'] as num).toDouble());
            _layout[key] = state;
          });
        },
        child: Container(
          decoration: BoxDecoration(border: Border.all(color: _selectedKey == key ? Colors.orange : color), color: color.withValues(alpha:0.06)),
          child: Stack(children: [
            Center(child: Text(label, style: const TextStyle(fontSize: 12))),
            // Resize handle (bottom-right)
            Positioned(
              right: 2,
              bottom: 2,
              child: GestureDetector(
                onPanUpdate: (d) {
                  setState(() {
                    state['w'] = ((state['w'] as num).toDouble() + d.delta.dx / 300).clamp(0.05, 1.0 - (state['x'] as num).toDouble());
                    state['h'] = ((state['h'] as num).toDouble() + d.delta.dy / 100).clamp(0.05, 1.0 - (state['y'] as num).toDouble());
                    _layout[key] = state;
                  });
                },
                child: Container(width: 12, height: 12, decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey))),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildNumericField(String field) {
    final key = _selectedKey!;
    final state = _ensure(key);
    final controller = TextEditingController(text: (state[field] as num).toString());
    return SizedBox(
      width: 80,
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: field, border: const OutlineInputBorder()),
        onSubmitted: (val) {
          final v = double.tryParse(val);
          if (v == null) return;
          setState(() {
            state[field] = v.clamp(0.0, 1.0);
            _layout[key] = state;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    // Canvas size is 300x100 for preview; stored layout uses fractional coords (0..1)
    final canvasW = 300.0;
    final canvasH = 100.0;

    // Build positioned children from layout (with defaults)
    final blocks = <Widget>[];
    blocks.add(_buildBlock('lotId', 'Lot ID', color: Colors.blue));
    blocks.add(_buildBlock('itemName', 'Item Name', color: Colors.green));
    blocks.add(_buildBlock('expiration', 'Expiration', color: Colors.purple));
    blocks.add(_buildBlock('qr', 'QR', color: Colors.red));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Label Designer (prototype)'),
        actions: [
          TextButton(onPressed: _saveLayout, child: const Text('Save', style: TextStyle(color: Colors.white))),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Drag blocks to design your label (prototype). Layout saved as fractional coords.'),
            const SizedBox(height: 12),
            Container(
              width: canvasW,
              height: canvasH,
              color: Colors.grey.shade50,
              child: Stack(children: blocks),
            ),
            const SizedBox(height: 12),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(onPressed: _saveLayout, icon: const Icon(Icons.save), label: const Text('Save')),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(onPressed: () { _resetDefaults(); }, icon: const Icon(Icons.refresh), label: const Text('Reset Defaults')),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(onPressed: _generateTestLabel, icon: const Icon(Icons.preview), label: const Text('Generate Test Label')),
                ],
              ),
              const SizedBox(height: 12),
              // Numeric editors for selected block
              if (_selectedKey != null) ...[
                const Divider(),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    children: [
                      Text('Selected: $_selectedKey'),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildNumericField('x'),
                          const SizedBox(width: 8),
                          _buildNumericField('y'),
                          const SizedBox(width: 8),
                          _buildNumericField('w'),
                          const SizedBox(width: 8),
                          _buildNumericField('h'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Text style controls
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 140,
                            child: TextField(
                              controller: TextEditingController(text: (_ensure(_selectedKey!)['fontSize'] ?? '').toString()),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(labelText: 'Font size', border: OutlineInputBorder()),
                              onSubmitted: (val) {
                                final v = double.tryParse(val);
                                if (v == null) return;
                                setState(() {
                                  _ensure(_selectedKey!)['fontSize'] = v;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            children: [
                              const Text('Bold'),
                              Checkbox(
                                  value: (_ensure(_selectedKey!)['bold'] ?? false) as bool,
                                  onChanged: (v) => setState(() => _ensure(_selectedKey!)['bold'] = v ?? false)),
                            ],
                          ),
                          const SizedBox(width: 8),
                          DropdownButton<String>(
                            value: (_ensure(_selectedKey!)['align'] as String?) ?? 'left',
                            items: const [
                              DropdownMenuItem(value: 'left', child: Text('Left')),
                              DropdownMenuItem(value: 'center', child: Text('Center')),
                              DropdownMenuItem(value: 'right', child: Text('Right')),
                            ],
                            onChanged: (v) => setState(() => _ensure(_selectedKey!)['align'] = v),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
          ],
        ),
      ),
    );
  }
}
