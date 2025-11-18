import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
// Use package:web for web interop instead of deprecated dart:html
// ignore: avoid_web_libraries_in_flutter
import 'package:web/web.dart' as html;
import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/product_enrichment_service.dart';

/// Enhanced USB wedge scanner with audio feedback and multi-source lookup
class EnhancedUsbWedgeScanner extends StatefulWidget {
  final bool enabled;
  final Duration interCharTimeout;
  final int minLength;
  final bool Function(String code)? allow;
  final void Function(String code, Map<String, dynamic>? lookupResult) onCode;

  const EnhancedUsbWedgeScanner({
    super.key,
    required this.onCode,
    this.enabled = true,
    this.interCharTimeout = const Duration(milliseconds: 80),
    this.minLength = 4,
    this.allow,
  });

  @override
  State<EnhancedUsbWedgeScanner> createState() => _EnhancedUsbWedgeScannerState();
}

class _EnhancedUsbWedgeScannerState extends State<EnhancedUsbWedgeScanner> {
  final StringBuffer _buf = StringBuffer();
  Timer? _flush;

  bool get _focusedInEditable {
    if (!kIsWeb) return false;
    final el = html.document.activeElement;
    final tag = (el?.tagName ?? '').toLowerCase();
    final editableTag = tag == 'input' || tag == 'textarea' || tag == 'select';
    final contentEditable = (el?.getAttribute('contenteditable') ?? '').toLowerCase() == 'true';
    return editableTag || contentEditable;
  }

  void _restartFlush() {
    _flush?.cancel();
    _flush = Timer(widget.interCharTimeout, _finish);
  }

  Future<void> _finish() async {
    final code = _buf.toString();
    _buf.clear();
    if (code.length >= widget.minLength && (widget.allow?.call(code) ?? true)) {
      if (kIsWeb) {
        _playBeep();
      }

      // Perform multi-source lookup
      Map<String, dynamic>? lookupResult;
      try {
        // First check local items
        final itemQuery = await FirebaseFirestore.instance
            .collection('items')
            .where('barcode', isEqualTo: code)
            .limit(1)
            .get();

        if (itemQuery.docs.isNotEmpty) {
          final itemData = itemQuery.docs.first.data();
          lookupResult = {
            'found': true,
            'source': 'local',
            'itemId': itemQuery.docs.first.id,
            'name': itemData['name'] ?? 'Unknown Item',
            'baseUnit': itemData['baseUnit'] ?? 'each',
          };
        } else {
          // Try external lookup
          final externalInfo = await ProductEnrichmentService.fetchProductInfo(code);
          if (externalInfo != null) {
            lookupResult = {
              'found': true,
              'source': externalInfo['source'] ?? 'external',
              'name': externalInfo['name'],
              'category': externalInfo['category'],
              'brand': externalInfo['brand'],
            };
          } else {
            lookupResult = {
              'found': false,
              'source': 'none',
            };
          }
        }
      } catch (e) {
        lookupResult = {
          'found': false,
          'source': 'error',
          'error': e.toString(),
        };
      }

      widget.onCode(code, lookupResult);
    }
  }

  void _playBeep() {
    if (!kIsWeb) return;
    try {
      final audioContext = html.AudioContext();
      final oscillator = audioContext.createOscillator();
      final gainNode = audioContext.createGain();

      oscillator.connect(gainNode);
      gainNode.connect(audioContext.destination);

      oscillator.frequency.value = 800; // 800 Hz beep
      gainNode.gain.value = 0.1; // Low volume

      oscillator.start();
      oscillator.stop(audioContext.currentTime + 0.1); // 100ms beep
    } catch (e) {
      // Ignore audio errors
    }
  }

  void _onKeyDown(html.KeyboardEvent e) {
    if (!widget.enabled || _focusedInEditable) return;
    final k = e.key;
    if (k.length == 1) {
      _buf.write(k);
      _restartFlush();
      return;
    }
    if (k == 'Enter' || k == 'Tab') {
      e.preventDefault();
      _flush?.cancel();
      _finish();
    }
  }

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      html.window.onKeyDown.listen(_onKeyDown);
    }
  }

  @override
  void dispose() {
    _flush?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Captures fast keyboard bursts from USB barcode scanners on Web.
class UsbWedgeScanner extends StatefulWidget {
  final bool enabled;
  final Duration interCharTimeout;
  final int minLength;
  final bool Function(String code)? allow;
  final void Function(String code) onCode;
  final bool audioFeedback;

  const UsbWedgeScanner({
    super.key,
    required this.onCode,
    this.enabled = true,
    this.interCharTimeout = const Duration(milliseconds: 80),
    this.minLength = 4,
    this.allow,
    this.audioFeedback = true,
  });

  @override
  State<UsbWedgeScanner> createState() => _UsbWedgeScannerState();
}

class _UsbWedgeScannerState extends State<UsbWedgeScanner> {
  final StringBuffer _buf = StringBuffer();
  Timer? _flush;
  StreamSubscription<html.KeyboardEvent>? _sub;

  bool get _focusedInEditable {
    if (!kIsWeb) return false;
    final el = html.document.activeElement;
    final tag = (el?.tagName ?? '').toLowerCase();
    final editableTag = tag == 'input' || tag == 'textarea' || tag == 'select';
    final contentEditable = (el?.getAttribute('contenteditable') ?? '').toLowerCase() == 'true';
    return editableTag || contentEditable;
  }

  void _restartFlush() {
    _flush?.cancel();
    _flush = Timer(widget.interCharTimeout, _finish);
  }

  void _finish() {
    final code = _buf.toString();
    _buf.clear();
    if (code.length >= widget.minLength && (widget.allow?.call(code) ?? true)) {
      widget.onCode(code);
      if (widget.audioFeedback && kIsWeb) {
        _playBeep();
      }
    }
  }

  void _playBeep() {
    if (!kIsWeb) return;
    try {
      final audioContext = html.AudioContext();
      final oscillator = audioContext.createOscillator();
      final gainNode = audioContext.createGain();

      oscillator.connect(gainNode);
      gainNode.connect(audioContext.destination);

      oscillator.frequency.value = 800; // 800 Hz beep
      gainNode.gain.value = 0.1; // Low volume

      oscillator.start();
      oscillator.stop(audioContext.currentTime + 0.1); // 100ms beep
    } catch (e) {
      // Ignore audio errors
    }
  }

  void _onKeyDown(html.KeyboardEvent e) {
    if (!widget.enabled || _focusedInEditable) return;
    final k = e.key;
    if (k.length == 1) {
      _buf.write(k);
      _restartFlush();
      return;
    }
    if (k == 'Enter' || k == 'Tab') {
      e.preventDefault();
      _flush?.cancel();
      _finish();
    }
  }

  @override
  void initState() {
    super.initState();
    if (kIsWeb) _sub = html.window.onKeyDown.listen(_onKeyDown);
  }

  @override
  void dispose() {
    _flush?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
