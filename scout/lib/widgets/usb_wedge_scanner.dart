import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
// Use package:web for web interop instead of deprecated dart:html
// ignore: avoid_web_libraries_in_flutter
import 'package:web/web.dart' as html;

/// Captures fast keyboard bursts from USB barcode scanners on Web.
class UsbWedgeScanner extends StatefulWidget {
  final bool enabled;
  final Duration interCharTimeout;
  final int minLength;
  final bool Function(String code)? allow;
  final void Function(String code) onCode;

  const UsbWedgeScanner({
    super.key,
    required this.onCode,
    this.enabled = true,
    this.interCharTimeout = const Duration(milliseconds: 80),
    this.minLength = 4,
    this.allow,
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
