// lib/features/items/mobile_barcode_scanner_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class MobileBarcodeScannerPage extends StatefulWidget {
  final String sessionId;

  const MobileBarcodeScannerPage({
    super.key,
    required this.sessionId,
  });

  @override
  State<MobileBarcodeScannerPage> createState() => _MobileBarcodeScannerPageState();
}

class _MobileBarcodeScannerPageState extends State<MobileBarcodeScannerPage> {
  final _db = FirebaseFirestore.instance;
  int _scanCount = 0;
  String? _lastScan;
  bool _isScanning = false;
  MobileScannerController? _controller;
  final Set<String> _recentScans = {};

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isScanning) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Scanning...'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _stopScanning,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.flashlight_on),
              onPressed: () => _controller?.toggleTorch(),
            ),
            IconButton(
              icon: const Icon(Icons.cameraswitch),
              onPressed: () => _controller?.switchCamera(),
            ),
          ],
        ),
        body: Stack(
          children: [
            MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.black.withOpacity(0.7),
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Scans sent: $_scanCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_lastScan != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Last: $_lastScan',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _stopScanning,
                      child: const Text('Stop Scanning'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mobile Scanner'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Icon(Icons.qr_code_scanner, size: 64, color: Colors.blue),
                    const SizedBox(height: 16),
                    Text(
                      'Session: ${widget.sessionId.substring(0, 8)}...',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Scans sent: $_scanCount',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (_lastScan != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Last: $_lastScan',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _startScanning,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Start Scanning'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Scan barcodes on your phone and they will appear on your computer.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  void _startScanning() {
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
    );
    setState(() => _isScanning = true);
  }

  void _stopScanning() {
    _controller?.dispose();
    _controller = null;
    _recentScans.clear();
    setState(() => _isScanning = false);
  }

  void _onDetect(BarcodeCapture capture) {
    final barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final code = barcode.rawValue?.trim();
      if (code != null && code.isNotEmpty && !_recentScans.contains(code)) {
        _recentScans.add(code);
        _sendBarcode(code);
        // Remove from recent scans after 2 seconds to allow re-scanning
        Future.delayed(const Duration(seconds: 2), () {
          _recentScans.remove(code);
        });
        break;
      }
    }
  }

  Future<void> _sendBarcode(String barcode) async {
    try {
      // Vibrate for feedback
      HapticFeedback.mediumImpact();
      
      await _db
          .collection('scanner_sessions')
          .doc(widget.sessionId)
          .collection('scans')
          .add({
        'barcode': barcode,
        'timestamp': FieldValue.serverTimestamp(),
        'processed': false,
      });

      setState(() {
        _scanCount++;
        _lastScan = barcode;
      });
    } catch (e) {
      HapticFeedback.heavyImpact();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    }
  }
}
