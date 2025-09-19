import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

class ScannerSheet extends StatefulWidget {
  final String title;
  const ScannerSheet({super.key, this.title = 'Scan item barcode or lot QR'});

  @override
  State<ScannerSheet> createState() => _ScannerSheetState();
}

class _ScannerSheetState extends State<ScannerSheet> {
  bool _handled = false;
  bool _showHelp = false;           // show camera help if preview doesn't start
  Timer? _helpTimer;

  @override
  void initState() {
    super.initState();
    // If we still haven’t scanned/started in ~2 seconds, show help UI.
    _helpTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && !_handled) setState(() => _showHelp = true);
    });
  }

  @override
  void dispose() {
    _helpTimer?.cancel();
    super.dispose();
  }

  void _accept(String? raw) {
    final code = raw?.trim();
    if (_handled || code == null || code.isEmpty) return;
    _handled = true;
    if (mounted) Navigator.of(context).pop(code);
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
    if (!mounted) return;
    if (code != null && code.isNotEmpty) Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPad = 16.0 + MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Text(widget.title, style: theme.textTheme.titleLarge),
              const Spacer(),
            ]),
            const SizedBox(height: 12),

            // Square preview that never overflows
            Flexible(
              child: Center(
                child: LayoutBuilder(
                  builder: (ctx, box) {
                    final side = math.min(box.maxWidth, box.maxHeight);
                    return SizedBox(
                      width: side,
                      height: side,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ReaderWidget(
                              // Broad + forgiving
                              codeFormat: Format.any,
                              tryHarder: true,
                              tryInverted: true,
                              scanDelay: const Duration(milliseconds: 120),

                              // Called on every successful decode
                              onScan: (result) {
                                // As soon as we get any result, hide the help
                                if (!_handled && _showHelp) {
                                  setState(() => _showHelp = false);
                                }
                                _accept(result.text);
                              },

                              // Optional: give the user built-in controls (gallery, flip, torch)
                              showGallery: true,
                              showToggleCamera: true,
                            ),

                            // Subtle frame
                            IgnorePointer(
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: theme.colorScheme.primary.withValues(alpha:0.35),
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),

                            // Help overlay if the camera didn’t start
                            if (_showHelp && !_handled)
                              Container(
                                color: theme.colorScheme.surface.withValues(alpha:0.65),
                                padding: const EdgeInsets.all(16),
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 420),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.videocam_off, size: 36),
                                        const SizedBox(height: 12),
                                        Text(
                                          'Can’t access the camera',
                                          style: theme.textTheme.titleMedium,
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          '• Allow camera permission in the browser\n'
                                          '• Make sure no other app/tab is using the camera\n'
                                          '• Use HTTPS (or localhost) for camera access\n'
                                          '• On iPhone/iPad use Safari (WebKit)',
                                          style: theme.textTheme.bodySmall,
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 12),
                                        OutlinedButton.icon(
                                          icon: const Icon(Icons.refresh),
                                          label: const Text('Try again'),
                                          onPressed: () {
                                            setState(() => _showHelp = false);
                                            // ReaderWidget restarts automatically on rebuild
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            const SizedBox(height: 12),
            Text(
              'Point your camera at a barcode.\nNo camera? Enter manually.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.keyboard),
              label: const Text('Enter code manually'),
              onPressed: _typeManually,
            ),
          ],
        ),
      ),
    );
  }
}
