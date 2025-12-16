// lib/services/cart_print_service.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Service for generating printable cart session checklists.
/// Creates a clean, printer-friendly HTML document for counting items.
class CartPrintService {
  /// Generate and print a cart checklist with items.
  static void printCartChecklist({
    required List<CartChecklistItem> items,
    String? interventionName,
    String? location,
    String? notes,
    bool isClosed = false,
  }) {
    final now = DateTime.now();
    final dateStr = DateFormat('EEEE, MMMM d, yyyy').format(now);
    final timeStr = DateFormat('h:mm a').format(now);

    // Build complete HTML document as string
    final htmlContent = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Cart Session Checklist</title>
  <style>
    @page {
      margin: 0.5in;
      size: letter portrait;
    }
    
    body {
      font-family: Arial, sans-serif;
      font-size: 10pt;
      line-height: 1.3;
      color: #000;
      margin: 0;
      padding: 0;
    }
    
    .header {
      border-bottom: 2px solid #00CBA9;
      padding-bottom: 8pt;
      margin-bottom: 12pt;
    }
    
    .title {
      font-size: 18pt;
      font-weight: bold;
      color: #1F2F32;
      margin: 0 0 4pt 0;
    }
    
    .subtitle {
      font-size: 9pt;
      color: #5A6C71;
      margin: 0;
    }
    
    .info-section {
      background: #F9FAFB;
      border: 1px solid #DDE6E9;
      border-radius: 4px;
      padding: 8pt;
      margin-bottom: 12pt;
    }
    
    .info-row {
      margin-bottom: 3pt;
      font-size: 9pt;
    }
    
    .info-row:last-child {
      margin-bottom: 0;
    }
    
    .info-label {
      font-weight: bold;
      color: #1F2F32;
      display: inline-block;
      width: 80pt;
    }
    
    .info-value {
      color: #5A6C71;
    }
    
    .instructions {
      background: #FFF3CD;
      border: 1px solid #FFC107;
      border-radius: 4px;
      padding: 6pt;
      margin-bottom: 12pt;
      font-size: 9pt;
    }
    
    .instructions-title {
      font-weight: bold;
      color: #856404;
      margin: 0 0 3pt 0;
    }
    
    .instructions-text {
      margin: 0;
      color: #856404;
    }
    
    table {
      width: 100%;
      border-collapse: collapse;
      margin-bottom: 12pt;
    }
    
    thead {
      background: #00CBA9;
      color: white;
    }
    
    th {
      text-align: left;
      padding: 6pt 6pt;
      font-weight: bold;
      font-size: 9pt;
      border: 1px solid #009B84;
    }
    
    td {
      padding: 6pt 6pt;
      border: 1px solid #DDE6E9;
      vertical-align: middle;
      font-size: 9pt;
    }
    
    tbody tr:nth-child(even) {
      background: #F9FAFB;
    }
    
    .item-name {
      font-weight: 500;
      color: #1F2F32;
    }
    
    .item-details {
      font-size: 8pt;
      color: #5A6C71;
      margin-top: 2pt;
    }
    
    .checkbox {
      width: 14pt;
      height: 14pt;
      border: 2px solid #5A6C71;
      border-radius: 2px;
      display: inline-block;
      vertical-align: middle;
    }
    
    .count-column {
      width: 60pt;
      text-align: center;
    }
    
    .checkbox-column {
      width: 35pt;
      text-align: center;
    }
    
    .footer {
      margin-top: 12pt;
      padding-top: 8pt;
      border-top: 1px solid #DDE6E9;
      font-size: 8pt;
      color: #5A6C71;
    }
    
    .signature-section {
      margin-top: 16pt;
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
      margin-bottom: 6pt;
      font-size: 9pt;
    }
    
    .signature-line .line {
      border-bottom: 1px solid #1F2F32;
      height: 20pt;
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
    <div class="title">Cart Session Checklist</div>
    <div class="subtitle">Inventory Count Verification</div>
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
    <div class="instructions-title">Instructions:</div>
    <p class="instructions-text">${isClosed ? 'Session complete. Review quantities used below.' : 'Before session: Count items going onto cart and write in "Before" column. After session: Count leftover items and write in "After" column. Check box when done.'}</p>
  </div>
  
  <table>
    <thead>
      <tr>
        <th class="checkbox-column">✓</th>
        <th>Item Name & Lot</th>
        <th class="count-column">Before</th>
        <th class="count-column">After</th>
        ${isClosed ? '<th class="count-column">Used</th>' : ''}
      </tr>
    </thead>
    <tbody>
      ${_generateItemRows(items, isClosed)}
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
    window.onload = function() {
      window.print();
    };
  </script>
</body>
</html>
''';

    // Create a blob URL and open it
    final blob = html.Blob([htmlContent], 'text/html');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.window.open(url, '_blank');
    
    // Clean up the URL after a short delay
    Future.delayed(const Duration(seconds: 2), () {
      html.Url.revokeObjectUrl(url);
    });
  }

  /// Generate HTML table rows for items.
  static String _generateItemRows(List<CartChecklistItem> items, bool isClosed) {
    final buffer = StringBuffer();

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final details = <String>[];

      if (item.barcode != null && item.barcode!.isNotEmpty) {
        details.add('Barcode: ${item.barcode}');
      }
      details.add('${_formatQty(item.quantity)} ${item.unit}');
      
      // Show lot code prominently in the item name if present
      final displayName = item.lotCode != null 
          ? '${_escapeHtml(item.name)} [Lot: ${item.lotCode}]'
          : _escapeHtml(item.name);

      // For closed sessions, show actual data; for open, show blanks
      final beforeValue = isClosed ? _formatQty(item.quantity) : '_______';
      final afterValue = isClosed && item.endQty != null ? _formatQty(item.endQty!) : '_______';
      final usedValue = isClosed && item.usedQty != null ? _formatQty(item.usedQty!) : '';

      buffer.writeln('''
      <tr>
        <td class="checkbox-column">
          <span class="checkbox"></span>
        </td>
        <td>
          <div class="item-name">${i + 1}. $displayName</div>
          ${details.isNotEmpty ? '<div class="item-details">${_escapeHtml(details.join(' • '))}</div>' : ''}
        </td>
        <td class="count-column">
          $beforeValue
        </td>
        <td class="count-column">
          $afterValue
        </td>
        ${isClosed ? '<td class="count-column">$usedValue</td>' : ''}
      </tr>
      ''');
    }
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
  final num? endQty;    // For closed sessions
  final num? usedQty;   // For closed sessions

  const CartChecklistItem({
    required this.name,
    required this.quantity,
    required this.unit,
    this.lotCode,
    this.barcode,
    this.endQty,
    this.usedQty,
  });
}
