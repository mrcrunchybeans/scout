// lib/services/cart_print_service.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Type of checklist to print.
enum ChecklistType {
  /// Before session - count items to load onto cart
  preparation,
  /// After session - count leftover items
  leftover,
}

/// Service for generating printable cart session checklists.
/// Creates a clean, printer-friendly HTML document for counting items.
class CartPrintService {
  /// Generate and print a cart checklist with items.
  static void printCartChecklist({
    required List<CartChecklistItem> items,
    String? interventionName,
    String? location,
    String? notes,
    ChecklistType type = ChecklistType.preparation,
  }) {
    final printWindow = html.window.open('', '_blank');
    if (printWindow == null) return;
    
    // Cast to Window to access document
    if (printWindow is! html.Window) return;
    final doc = printWindow.document;

    final now = DateTime.now();
    final dateStr = DateFormat('EEEE, MMMM d, yyyy').format(now);
    final timeStr = DateFormat('h:mm a').format(now);
    
    final title = type == ChecklistType.preparation 
        ? 'Cart Preparation Checklist'
        : 'Cart Leftover Checklist';
    final instructions = type == ChecklistType.preparation
        ? 'Count each item before loading onto cart. Check the box and write the actual count.'
        : 'Count each leftover item after the session. Check the box and write the actual count.';
    final qtyColumnHeader = type == ChecklistType.preparation 
        ? 'Expected to Load' 
        : 'Expected Leftover';

    // Build HTML content
    final htmlContent = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>$title</title>
  <style>
    @page {
      margin: 0.75in;
      size: letter portrait;
    }
    
    body {
      font-family: Arial, sans-serif;
      font-size: 12pt;
      line-height: 1.4;
      color: #000;
      margin: 0;
      padding: 0;
    }
    
    .header {
      border-bottom: 3px solid #00CBA9;
      padding-bottom: 12pt;
      margin-bottom: 20pt;
    }
    
    .title {
      font-size: 24pt;
      font-weight: bold;
      color: #1F2F32;
      margin: 0 0 8pt 0;
    }
    
    .subtitle {
      font-size: 11pt;
      color: #5A6C71;
      margin: 0;
    }
    
    .info-section {
      background: #F9FAFB;
      border: 1px solid #DDE6E9;
      border-radius: 8px;
      padding: 12pt;
      margin-bottom: 20pt;
    }
    
    .info-row {
      margin-bottom: 6pt;
    }
    
    .info-row:last-child {
      margin-bottom: 0;
    }
    
    .info-label {
      font-weight: bold;
      color: #1F2F32;
      display: inline-block;
      width: 120pt;
    }
    
    .info-value {
      color: #5A6C71;
    }
    
    .instructions {
      background: #FFF3CD;
      border: 1px solid #FFC107;
      border-radius: 6px;
      padding: 10pt;
      margin-bottom: 20pt;
      font-size: 11pt;
    }
    
    .instructions-title {
      font-weight: bold;
      color: #856404;
      margin: 0 0 6pt 0;
    }
    
    .instructions-text {
      margin: 0;
      color: #856404;
    }
    
    table {
      width: 100%;
      border-collapse: collapse;
      margin-bottom: 20pt;
    }
    
    thead {
      background: #00CBA9;
      color: white;
    }
    
    th {
      text-align: left;
      padding: 10pt 8pt;
      font-weight: bold;
      font-size: 11pt;
      border: 1px solid #009B84;
    }
    
    td {
      padding: 12pt 8pt;
      border: 1px solid #DDE6E9;
      vertical-align: top;
    }
    
    tbody tr:nth-child(even) {
      background: #F9FAFB;
    }
    
    .item-name {
      font-weight: bold;
      color: #1F2F32;
      margin-bottom: 4pt;
    }
    
    .item-details {
      font-size: 10pt;
      color: #5A6C71;
    }
    
    .checkbox {
      width: 18pt;
      height: 18pt;
      border: 2px solid #5A6C71;
      border-radius: 3px;
      display: inline-block;
      margin-right: 8pt;
      vertical-align: middle;
    }
    
    .qty-column {
      width: 80pt;
      text-align: center;
      font-size: 14pt;
      font-weight: bold;
    }
    
    .checkbox-column {
      width: 60pt;
      text-align: center;
    }
    
    .footer {
      margin-top: 30pt;
      padding-top: 12pt;
      border-top: 2px solid #DDE6E9;
      font-size: 10pt;
      color: #5A6C71;
    }
    
    .signature-section {
      margin-top: 30pt;
      display: flex;
      justify-content: space-between;
    }
    
    .signature-line {
      width: 45%;
    }
    
    .signature-line label {
      font-weight: bold;
      color: #1F2F32;
      display: block;
      margin-bottom: 8pt;
    }
    
    .signature-line .line {
      border-bottom: 1px solid #1F2F32;
      height: 30pt;
    }
    
    @media print {
      body {
        print-color-adjust: exact;
        -webkit-print-color-adjust: exact;
      }
      
      .no-print {
        display: none;
      }
    }
  </style>
</head>
<body>
  <div class="header">
    <div class="title">$title</div>
    <div class="subtitle">Inventory Preparation & Count Verification</div>
  </div>
  
  <div class="info-section">
    <div class="info-row">
      <span class="info-label">Date:</span>
      <span class="info-value">$dateStr at $timeStr</span>
    </div>
    ${interventionName != null ? '<div class="info-row"><span class="info-label">Intervention:</span><span class="info-value">$interventionName</span></div>' : ''}
    ${location != null && location.isNotEmpty ? '<div class="info-row"><span class="info-label">Location/Unit:</span><span class="info-value">$location</span></div>' : ''}
    ${notes != null && notes.isNotEmpty ? '<div class="info-row"><span class="info-label">Notes:</span><span class="info-value">$notes</span></div>' : ''}
  </div>
  
  <div class="instructions">
    <div class="instructions-title">📋 Instructions for Intern/Staff:</div>
    <p class="instructions-text">$instructions</p>
  </div>
  
  <table>
    <thead>
      <tr>
        <th class="checkbox-column">✓</th>
        <th>Item</th>
        <th class="qty-column">$qtyColumnHeader</th>
        <th class="qty-column">Actual Count</th>
      </tr>
    </thead>
    <tbody>
      ${_generateItemRows(items)}
    </tbody>
  </table>
  
  <div class="footer">
    <strong>Total Items:</strong> ${items.length} items listed
  </div>
  
  <div class="signature-section">
    <div class="signature-line">
      <label>Prepared By:</label>
      <div class="line"></div>
    </div>
    <div class="signature-line">
      <label>Date/Time:</label>
      <div class="line"></div>
    </div>
  </div>
  
  <div style="margin-top: 20pt; text-align: center; color: #5A6C71; font-size: 9pt;">
    SCOUT - Spiritual Care Operations & Usage Tracker
  </div>
  
  <script>
    // Auto-print when page loads
    window.onload = function() {
      window.print();
    };
  </script>
</body>
</html>
''';

    doc.write(htmlContent);
    doc.close();
  }

  /// Generate HTML table rows for items.
  static String _generateItemRows(List<CartChecklistItem> items) {
    final buffer = StringBuffer();

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final details = <String>[];

      if (item.lotCode != null) {
        details.add('Lot: ${item.lotCode}');
      }
      if (item.barcode != null && item.barcode!.isNotEmpty) {
        details.add('Barcode: ${item.barcode}');
      }
      details.add('Unit: ${item.unit}');

      buffer.writeln('''
      <tr>
        <td class="checkbox-column">
          <span class="checkbox"></span>
        </td>
        <td>
          <div class="item-name">${i + 1}. ${_escapeHtml(item.name)}</div>
          ${details.isNotEmpty ? '<div class="item-details">${_escapeHtml(details.join(' • '))}</div>' : ''}
        </td>
        <td class="qty-column">${_formatQty(item.quantity)}</td>
        <td class="qty-column" style="border-bottom: 2px solid #5A6C71;">
          <!-- Write actual count here -->
        </td>
      </tr>
      ''');
    }

    return buffer.toString();
  }

  /// Escape HTML special characters.
  static String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  /// Format quantity for display.
  static String _formatQty(num qty) {
    if (qty % 1 == 0) {
      return qty.toInt().toString();
    }
    final formatted = qty.toStringAsFixed(2);
    return formatted
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}

/// Data model for a cart checklist item.
class CartChecklistItem {
  final String name;
  final num quantity;
  final String unit;
  final String? lotCode;
  final String? barcode;

  const CartChecklistItem({
    required this.name,
    required this.quantity,
    required this.unit,
    this.lotCode,
    this.barcode,
  });
}
