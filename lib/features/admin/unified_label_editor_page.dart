import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../services/label_export_service.dart';

class UnifiedLabelEditorPage extends StatefulWidget {
  const UnifiedLabelEditorPage({super.key});

  @override
  State<UnifiedLabelEditorPage> createState() => _UnifiedLabelEditorPageState();
}

class _UnifiedLabelEditorPageState extends State<UnifiedLabelEditorPage> {
  final _db = FirebaseFirestore.instance;
  bool _loading = true;
  bool _saving = false;
  
  // Layout design
  Map<String, dynamic> _layout = {};
  String? _selectedField;
  
  // Field visibility toggles
  bool _showLotCode = true;
  bool _showItemName = true;
  bool _showVariety = true;
  bool _showGrant = true;
  bool _showExpiration = true;
  bool _showQrCode = true;
  bool _showLogo = true;
  bool _showDatePrinted = true;
  
  // Style settings
  final _lotFontSize = TextEditingController();
  final _itemFontSize = TextEditingController();
  final _varietyFontSize = TextEditingController();
  final _grantFontSize = TextEditingController();
  final _expirationFontSize = TextEditingController();
  final _padding = TextEditingController();
  final _qrSize = TextEditingController();
  bool _showExpirationPill = true;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final doc = await _db.collection('config').doc('labels').get();
      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _layout = data['design'] as Map<String, dynamic>? ?? _getDefaultLayout();
          
          // Load visibility settings
          final visibility = data['visibility'] as Map<String, dynamic>?;
          if (visibility != null) {
            _showLotCode = visibility['lotCode'] ?? true;
            _showItemName = visibility['itemName'] ?? true;
            _showVariety = visibility['variety'] ?? true;
            _showGrant = visibility['grant'] ?? true;
            _showExpiration = visibility['expiration'] ?? true;
            _showQrCode = visibility['qrCode'] ?? true;
            _showLogo = visibility['logo'] ?? true;
            _showDatePrinted = visibility['datePrinted'] ?? true;
          }
          
          // Load style settings
          _lotFontSize.text = (data['lotIdFontSize'] ?? 14).toString();
          _itemFontSize.text = (data['itemNameFontSize'] ?? 6).toString();
          _varietyFontSize.text = (data['varietyFontSize'] ?? 7).toString();
          _grantFontSize.text = (data['grantFontSize'] ?? 6).toString();
          _expirationFontSize.text = (data['expirationFontSize'] ?? 7).toString();
          _padding.text = (data['padding'] ?? 3.0).toString();
          _qrSize.text = (data['qrCodeSize'] ?? 35.0).toString();
          _showExpirationPill = data['showExpirationPill'] ?? true;
          
          _loading = false;
        });
        return;
      }
    } catch (e) {
      debugPrint('Error loading label config: $e');
    }
    
    setState(() {
      _layout = _getDefaultLayout();
      _lotFontSize.text = '14';
      _itemFontSize.text = '6';
      _varietyFontSize.text = '7';
      _grantFontSize.text = '6';
      _expirationFontSize.text = '7';
      _padding.text = '3.0';
      _qrSize.text = '35.0';
      _loading = false;
    });
  }

  Map<String, dynamic> _getDefaultLayout() {
    return {
      'lotId': {'x': 0.02, 'y': 0.15, 'w': 0.55, 'h': 0.18},
      'itemName': {'x': 0.02, 'y': 0.35, 'w': 0.55, 'h': 0.15},
      'variety': {'x': 0.02, 'y': 0.52, 'w': 0.55, 'h': 0.12},
      'grant': {'x': 0.02, 'y': 0.66, 'w': 0.55, 'h': 0.10},
      'expiration': {'x': 0.02, 'y': 0.05, 'w': 0.35, 'h': 0.08},
      'qr': {'x': 0.62, 'y': 0.15, 'w': 0.36, 'h': 0.60},
      'logo': {'x': 0.02, 'y': 0.82, 'w': 0.15, 'h': 0.12},
      'datePrinted': {'x': 0.62, 'y': 0.78, 'w': 0.36, 'h': 0.08},
    };
  }

  Future<void> _saveConfig() async {
    setState(() => _saving = true);
    try {
      await _db.collection('config').doc('labels').set({
        'design': _layout,
        'visibility': {
          'lotCode': _showLotCode,
          'itemName': _showItemName,
          'variety': _showVariety,
          'grant': _showGrant,
          'expiration': _showExpiration,
          'qrCode': _showQrCode,
          'logo': _showLogo,
          'datePrinted': _showDatePrinted,
        },
        'lotIdFontSize': double.tryParse(_lotFontSize.text) ?? 14,
        'itemNameFontSize': double.tryParse(_itemFontSize.text) ?? 6,
        'varietyFontSize': double.tryParse(_varietyFontSize.text) ?? 7,
        'grantFontSize': double.tryParse(_grantFontSize.text) ?? 6,
        'expirationFontSize': double.tryParse(_expirationFontSize.text) ?? 7,
        'padding': double.tryParse(_padding.text) ?? 3.0,
        'qrCodeSize': double.tryParse(_qrSize.text) ?? 35.0,
        'showExpirationPill': _showExpirationPill,
      }, SetOptions(merge: true));
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Label configuration saved successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _generateTestLabel() async {
    try {
      await _saveConfig(); // Save current settings first
      
      final lots = [
        {
          'id': 'test-lot-1',
          'lotCode': 'TEST-12345',
          'itemId': 'test-item',
          'itemName': 'Sample Item Name',
          'variety': 'Dark Chocolate',
          'grantName': 'Sample Grant',
          'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 90))),
        }
      ];
      
      await LabelExportService.exportLabels(lots, template: null, startIndex: 0);
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Test label generated and downloaded')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to generate test label: $e')),
      );
    }
  }

  void _resetToDefaults() {
    setState(() {
      _layout = _getDefaultLayout();
      _showLotCode = true;
      _showItemName = true;
      _showVariety = true;
      _showGrant = true;
      _showExpiration = true;
      _showQrCode = true;
      _showLogo = true;
      _showDatePrinted = true;
      _lotFontSize.text = '14';
      _itemFontSize.text = '6';
      _varietyFontSize.text = '7';
      _grantFontSize.text = '6';
      _expirationFontSize.text = '7';
      _padding.text = '3.0';
      _qrSize.text = '35.0';
      _showExpirationPill = true;
    });
  }

  Map<String, dynamic> _ensureField(String key) {
    final field = _layout[key] as Map<String, dynamic>? ?? {
      'x': 0.1,
      'y': 0.1,
      'w': 0.4,
      'h': 0.15
    };
    _layout[key] = field;
    return field;
  }

  Widget _buildFieldBlock(String key, String label, Color color, bool isVisible) {
    if (!isVisible) return const SizedBox.shrink();
    
    final field = _ensureField(key);
    final canvasW = 400.0;
    final canvasH = 150.0;
    
    return Positioned(
      left: (field['x'] as num).toDouble() * canvasW,
      top: (field['y'] as num).toDouble() * canvasH,
      width: (field['w'] as num).toDouble() * canvasW,
      height: (field['h'] as num).toDouble() * canvasH,
      child: GestureDetector(
        onTap: () => setState(() => _selectedField = key),
        onPanUpdate: (details) {
          setState(() {
            final newX = ((field['x'] as num).toDouble() + details.delta.dx / canvasW)
                .clamp(0.0, 1.0 - (field['w'] as num).toDouble());
            final newY = ((field['y'] as num).toDouble() + details.delta.dy / canvasH)
                .clamp(0.0, 1.0 - (field['h'] as num).toDouble());
            field['x'] = newX;
            field['y'] = newY;
          });
        },
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: _selectedField == key ? Colors.orange : color,
              width: _selectedField == key ? 2.5 : 1.5,
            ),
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Stack(
            children: [
              Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: _selectedField == key ? FontWeight.bold : FontWeight.normal,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              // Resize handle
              Positioned(
                right: 0,
                bottom: 0,
                child: GestureDetector(
                  onPanUpdate: (d) {
                    setState(() {
                      final newW = ((field['w'] as num).toDouble() + d.delta.dx / canvasW)
                          .clamp(0.05, 1.0 - (field['x'] as num).toDouble());
                      final newH = ((field['h'] as num).toDouble() + d.delta.dy / canvasH)
                          .clamp(0.05, 1.0 - (field['y'] as num).toDouble());
                      field['w'] = newW;
                      field['h'] = newH;
                    });
                  },
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade600),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Icon(Icons.drag_handle, size: 12, color: Colors.grey.shade600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Label Editor'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: 'Save',
              onPressed: _saveConfig,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reset to defaults',
            onPressed: _resetToDefaults,
          ),
          IconButton(
            icon: const Icon(Icons.preview),
            tooltip: 'Generate test label',
            onPressed: _generateTestLabel,
          ),
        ],
      ),
      body: Row(
        children: [
          // Left panel: Settings
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.grey.shade50,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Field visibility section
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Field Visibility', style: Theme.of(context).textTheme.titleLarge),
                            const Divider(),
                            CheckboxListTile(
                              title: const Text('Lot Code'),
                              value: _showLotCode,
                              onChanged: (v) => setState(() => _showLotCode = v ?? true),
                            ),
                            CheckboxListTile(
                              title: const Text('Item Name'),
                              value: _showItemName,
                              onChanged: (v) => setState(() => _showItemName = v ?? true),
                            ),
                            CheckboxListTile(
                              title: const Text('Variety'),
                              value: _showVariety,
                              onChanged: (v) => setState(() => _showVariety = v ?? true),
                            ),
                            CheckboxListTile(
                              title: const Text('Grant'),
                              value: _showGrant,
                              onChanged: (v) => setState(() => _showGrant = v ?? true),
                            ),
                            CheckboxListTile(
                              title: const Text('Expiration Date'),
                              value: _showExpiration,
                              onChanged: (v) => setState(() => _showExpiration = v ?? true),
                            ),
                            CheckboxListTile(
                              title: const Text('QR Code'),
                              value: _showQrCode,
                              onChanged: (v) => setState(() => _showQrCode = v ?? true),
                            ),
                            CheckboxListTile(
                              title: const Text('Logo'),
                              value: _showLogo,
                              onChanged: (v) => setState(() => _showLogo = v ?? true),
                            ),
                            CheckboxListTile(
                              title: const Text('Date Printed'),
                              value: _showDatePrinted,
                              onChanged: (v) => setState(() => _showDatePrinted = v ?? true),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Style settings section
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Font Sizes', style: Theme.of(context).textTheme.titleLarge),
                            const Divider(),
                            TextField(
                              controller: _lotFontSize,
                              decoration: const InputDecoration(labelText: 'Lot Code Font Size'),
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _itemFontSize,
                              decoration: const InputDecoration(labelText: 'Item Name Font Size'),
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _varietyFontSize,
                              decoration: const InputDecoration(labelText: 'Variety Font Size'),
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _grantFontSize,
                              decoration: const InputDecoration(labelText: 'Grant Font Size'),
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _expirationFontSize,
                              decoration: const InputDecoration(labelText: 'Expiration Font Size'),
                              keyboardType: TextInputType.number,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Other settings
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Other Settings', style: Theme.of(context).textTheme.titleLarge),
                            const Divider(),
                            TextField(
                              controller: _padding,
                              decoration: const InputDecoration(labelText: 'Padding (points)'),
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _qrSize,
                              decoration: const InputDecoration(labelText: 'QR Code Size (points)'),
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: 8),
                            CheckboxListTile(
                              title: const Text('Show Expiration as Pill/Chip'),
                              value: _showExpirationPill,
                              onChanged: (v) => setState(() => _showExpirationPill = v ?? true),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    // Selected field properties
                    if (_selectedField != null) ...[
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Selected: $_selectedField', style: Theme.of(context).textTheme.titleLarge),
                              const Divider(),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: TextEditingController(
                                        text: (_ensureField(_selectedField!)['x'] as num).toStringAsFixed(3),
                                      ),
                                      decoration: const InputDecoration(labelText: 'X'),
                                      keyboardType: TextInputType.number,
                                      onSubmitted: (v) {
                                        final val = double.tryParse(v);
                                        if (val != null) {
                                          setState(() => _ensureField(_selectedField!)['x'] = val.clamp(0.0, 1.0));
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: TextEditingController(
                                        text: (_ensureField(_selectedField!)['y'] as num).toStringAsFixed(3),
                                      ),
                                      decoration: const InputDecoration(labelText: 'Y'),
                                      keyboardType: TextInputType.number,
                                      onSubmitted: (v) {
                                        final val = double.tryParse(v);
                                        if (val != null) {
                                          setState(() => _ensureField(_selectedField!)['y'] = val.clamp(0.0, 1.0));
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: TextEditingController(
                                        text: (_ensureField(_selectedField!)['w'] as num).toStringAsFixed(3),
                                      ),
                                      decoration: const InputDecoration(labelText: 'Width'),
                                      keyboardType: TextInputType.number,
                                      onSubmitted: (v) {
                                        final val = double.tryParse(v);
                                        if (val != null) {
                                          setState(() => _ensureField(_selectedField!)['w'] = val.clamp(0.05, 1.0));
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: TextEditingController(
                                        text: (_ensureField(_selectedField!)['h'] as num).toStringAsFixed(3),
                                      ),
                                      decoration: const InputDecoration(labelText: 'Height'),
                                      keyboardType: TextInputType.number,
                                      onSubmitted: (v) {
                                        final val = double.tryParse(v);
                                        if (val != null) {
                                          setState(() => _ensureField(_selectedField!)['h'] = val.clamp(0.05, 1.0));
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          
          // Right panel: Visual editor
          Expanded(
            flex: 3,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(
                    'Label Preview & Layout',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Drag fields to reposition • Drag bottom-right corner to resize • Click to select',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Center(
                      child: Container(
                        width: 400,
                        height: 150,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Stack(
                          children: [
                            _buildFieldBlock('lotId', 'LOT CODE', Colors.blue, _showLotCode),
                            _buildFieldBlock('itemName', 'ITEM NAME', Colors.green, _showItemName),
                            _buildFieldBlock('variety', 'VARIETY', Colors.purple, _showVariety),
                            _buildFieldBlock('grant', 'GRANT', Colors.orange, _showGrant),
                            _buildFieldBlock('expiration', 'EXPIRATION', Colors.red, _showExpiration),
                            _buildFieldBlock('qr', 'QR CODE', Colors.brown, _showQrCode),
                            _buildFieldBlock('logo', 'LOGO', Colors.teal, _showLogo),
                            _buildFieldBlock('datePrinted', 'DATE', Colors.indigo, _showDatePrinted),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Avery 5160 Label Size: 2.625" × 1" (189pt × 72pt)',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _lotFontSize.dispose();
    _itemFontSize.dispose();
    _varietyFontSize.dispose();
    _grantFontSize.dispose();
    _expirationFontSize.dispose();
    _padding.dispose();
    _qrSize.dispose();
    super.dispose();
  }
}
