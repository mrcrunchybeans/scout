import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ScannerSheet extends StatefulWidget {
  final String title;
  const ScannerSheet({super.key, this.title = 'Scan a barcode'});

  @override
  State<ScannerSheet> createState() => _ScannerSheetState();
}

class _ScannerSheetState extends State<ScannerSheet> {
  CameraFacing _cameraFacing = CameraFacing.back;
  MobileScannerController? controller;
  bool _controllerInitialized = false;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _initializeController();
  }

  Future<void> _initializeController() async {
    try {
      controller = MobileScannerController(
        detectionSpeed: DetectionSpeed.unrestricted,
        facing: CameraFacing.back,
        torchEnabled: false,
        formats: const <BarcodeFormat>[
          BarcodeFormat.aztec,
          BarcodeFormat.codabar,
          BarcodeFormat.code39,
          BarcodeFormat.code93,
          BarcodeFormat.code128,
          BarcodeFormat.dataMatrix,
          BarcodeFormat.ean8,
          BarcodeFormat.ean13,
          BarcodeFormat.itf,
          BarcodeFormat.pdf417,
          BarcodeFormat.qrCode,
          BarcodeFormat.upcA,
          BarcodeFormat.upcE,
        ],
      );
      _controllerInitialized = true;
      if (mounted) setState(() {});
    } catch (e) {
      // Camera initialization failed (likely permission issues on iOS Safari)
      _controllerInitialized = false;
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture cap) {
    if (_handled || cap.barcodes.isEmpty || controller == null) return;
    for (final b in cap.barcodes) {
      final raw = b.rawValue?.trim();
      if (raw != null && raw.isNotEmpty) {
        _handled = true;
        if (mounted) Navigator.of(context).pop(raw);
        return;
      }
    }
  }

  Future<void> _typeManually() async {
    final code = await showDialog<String>(
      context: context,
      builder: (_) {
        final c = TextEditingController();
        return AlertDialog(
          title: const Text('Enter code'),
          content: TextField(
            controller: c,
            decoration: const InputDecoration(
              labelText: 'Barcode or SCOUT lot QR text',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Use')),
          ],
        );
      },
    );
    if (code != null && code.isNotEmpty && mounted) {
      Navigator.of(context).pop(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(widget.title, style: theme.textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Flip camera',
                    icon: const Icon(Icons.cameraswitch),
                    onPressed: controller != null ? () {
                      controller!.switchCamera();
                      setState(() {
                        _cameraFacing =
                            _cameraFacing == CameraFacing.back ? CameraFacing.front : CameraFacing.back;
                      });
                    } : null,
                  ),
                  IconButton(
                    tooltip: 'Toggle torch',
                    icon: const Icon(Icons.flashlight_on),
                    onPressed: controller != null ? () => controller!.toggleTorch() : null,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Square preview; mirror visually only if using the front camera
              AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Builder(
                    builder: (_) {
                      final mirror = (_cameraFacing == CameraFacing.front);
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          Transform(
                            alignment: Alignment.center,
                            transform: mirror
                                ? (Matrix4.identity()..rotateY(math.pi))
                                : Matrix4.identity(),
                            child: _controllerInitialized && controller != null
                                ? MobileScanner(
                                    controller: controller!,
                                    fit: BoxFit.cover,
                                    onDetect: _onDetect,
                                  )
                                : Center(
                                    child: _controllerInitialized
                                        ? const Text('Camera not available\nUse manual entry below')
                                        : const CircularProgressIndicator(),
                                  ),
                          ),
                          IgnorePointer(
                            ignoring: true,
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.white.withValues(alpha:0.7),
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 12),
              Text(
                'Point your camera at a barcode.\nNo camera? Enter code manually.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.keyboard),
                label: const Text('Enter code manually'),
                onPressed: _typeManually,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
