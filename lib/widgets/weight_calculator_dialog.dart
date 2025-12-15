// lib/widgets/weight_calculator_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Dialog for calculating quantity from weight measurements.
/// Useful for items sold/stored by weight (e.g., truffles, bulk items).
class WeightCalculatorDialog extends StatefulWidget {
  final String itemName;
  final num? initialQty;
  final String unit;

  const WeightCalculatorDialog({
    super.key,
    required this.itemName,
    this.initialQty,
    this.unit = 'each',
  });

  @override
  State<WeightCalculatorDialog> createState() => _WeightCalculatorDialogState();
}

class _WeightCalculatorDialogState extends State<WeightCalculatorDialog> {
  final _totalWeightController = TextEditingController();
  final _unitWeightController = TextEditingController();
  final _totalWeightFocus = FocusNode();
  final _unitWeightFocus = FocusNode();
  
  String _weightUnit = 'g'; // g, kg, oz, lb
  num? _calculatedQty;
  
  @override
  void initState() {
    super.initState();
    _totalWeightController.addListener(_recalculate);
    _unitWeightController.addListener(_recalculate);
  }
  
  @override
  void dispose() {
    _totalWeightController.dispose();
    _unitWeightController.dispose();
    _totalWeightFocus.dispose();
    _unitWeightFocus.dispose();
    super.dispose();
  }
  
  void _recalculate() {
    final totalStr = _totalWeightController.text.trim();
    final unitStr = _unitWeightController.text.trim();
    
    if (totalStr.isEmpty || unitStr.isEmpty) {
      setState(() => _calculatedQty = null);
      return;
    }
    
    final total = num.tryParse(totalStr);
    final unit = num.tryParse(unitStr);
    
    if (total != null && unit != null && unit > 0) {
      setState(() => _calculatedQty = total / unit);
    } else {
      setState(() => _calculatedQty = null);
    }
  }
  
  String _formatQty(num qty) {
    if (qty % 1 == 0) {
      return qty.toInt().toString();
    }
    // Show up to 2 decimal places, remove trailing zeros
    final formatted = qty.toStringAsFixed(2);
    return formatted.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.calculate, color: cs.primary),
          const SizedBox(width: 8),
          const Expanded(child: Text('Calculate by Weight')),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Item name
              Text(
                widget.itemName,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Calculate quantity from weight measurements',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Total weight input
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _totalWeightController,
                      focusNode: _totalWeightFocus,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Total Weight',
                        hintText: 'e.g., 1256',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.scale),
                        filled: true,
                        fillColor: cs.surfaceContainerHighest,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Weight unit dropdown
                  DropdownButton<String>(
                    value: _weightUnit,
                    items: const [
                      DropdownMenuItem(value: 'g', child: Text('g')),
                      DropdownMenuItem(value: 'kg', child: Text('kg')),
                      DropdownMenuItem(value: 'oz', child: Text('oz')),
                      DropdownMenuItem(value: 'lb', child: Text('lb')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _weightUnit = value);
                      }
                    },
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // Unit weight input
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _unitWeightController,
                      focusNode: _unitWeightFocus,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Weight per Unit',
                        hintText: 'e.g., 12.5',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.inventory_2),
                        filled: true,
                        fillColor: cs.surfaceContainerHighest,
                      ),
                      onSubmitted: (_) {
                        if (_calculatedQty != null) {
                          Navigator.pop(context, _calculatedQty);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('$_weightUnit/${widget.unit}'),
                ],
              ),
              
              const SizedBox(height: 24),
              
              // Calculation result
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _calculatedQty != null 
                      ? cs.primaryContainer 
                      : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _calculatedQty != null 
                        ? cs.primary.withValues(alpha: 0.3) 
                        : cs.outline.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      'Calculated Quantity',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _calculatedQty != null 
                          ? '${_formatQty(_calculatedQty!)} ${widget.unit}'
                          : '—',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: _calculatedQty != null 
                            ? cs.onPrimaryContainer 
                            : cs.onSurfaceVariant,
                      ),
                    ),
                    if (_calculatedQty != null && _totalWeightController.text.isNotEmpty && _unitWeightController.text.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${_totalWeightController.text} $_weightUnit ÷ ${_unitWeightController.text} $_weightUnit = ${_formatQty(_calculatedQty!)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Example/hint
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lightbulb_outline, size: 16, color: cs.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Example: 1256g total ÷ 12.5g/each = 100 items',
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _calculatedQty != null
              ? () => Navigator.pop(context, _calculatedQty)
              : null,
          child: const Text('Use Quantity'),
        ),
      ],
    );
  }
}

/// Show the weight calculator dialog and return the calculated quantity.
/// Returns null if the user cancels.
Future<num?> showWeightCalculator({
  required BuildContext context,
  required String itemName,
  num? initialQty,
  String unit = 'each',
}) async {
  return await showDialog<num>(
    context: context,
    builder: (context) => WeightCalculatorDialog(
      itemName: itemName,
      initialQty: initialQty,
      unit: unit,
    ),
  );
}
