import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

class ScannerPage extends StatefulWidget {
  final String title;
  const ScannerPage({super.key, this.title = 'Scan item barcode or lot QR'});

  /// Call from anywhere:
  /// final code = await ScannerPage.open(context, title: 'Scan…');
  static Future<String?> open(BuildContext context, {String? title}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ScannerPage(title: title ?? 'Scan item barcode or lot QR'),
    );
  }

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  bool _handled = false;
  bool _showHelp = false;
  Timer? _helpTimer;

  @override
  void initState() {
    super.initState();
    // If a scan hasn't happened quickly, surface help (permissions/policy tips).
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

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(widget.title, style: theme.textTheme.titleLarge),
              const Spacer(),
              // Let ZXing show its own gallery/camera buttons; we also hint in the help overlay.
            ],
          ),
          const SizedBox(height: 12),

          // Square preview that won’t overflow
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
                            // Broad + forgiving decode settings
                            codeFormat: Format.any,
                            tryHarder: true,
                            tryInverted: true,
                            scanDelay: const Duration(milliseconds: 120),

                            // Built-in fallbacks
                            showGallery: true,
                            showToggleCamera: true,

                            // Successful decode
                            onScan: (res) {
                              if (!_handled && _showHelp) setState(() => _showHelp = false);
                              _accept(res.text);
                            },

                            // Surface getUserMedia errors (permissions / policy / iframe)
                            onMediaStreamError: (err) {
                              if (mounted) {
                                setState(() => _showHelp = true);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Camera error: $err')),
                                );
                              }
                            },
                          ),

                          // Subtle scan frame
                          IgnorePointer(
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: theme.colorScheme.primary.withOpacity(0.35),
                                  width: 2,
                                ),
                              ),
                            ),
                          ),

                          // Help overlay if camera didn’t start
                          if (_showHelp && !_handled)
                            Container(
                              color: theme.colorScheme.surface.withOpacity(0.65),
                              padding: const EdgeInsets.all(16),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 420),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.videocam_off, size: 36),
                                      const SizedBox(height: 12),
                                      Text('Can’t access the camera',
                                          style: theme.textTheme.titleMedium,
                                          textAlign: TextAlign.center),
                                      const SizedBox(height: 8),
                                      Text(
                                        '• Allow camera permission in the browser\n'
                                        '• Ensure no other tab/app is using the camera\n'
                                        '• Use HTTPS (or localhost)\n'
                                        '• On iPhone/iPad use Safari\n'
                                        '• Or tap the gallery button in the preview',
                                        style: theme.textTheme.bodySmall,
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 12),
                                      OutlinedButton.icon(
                                        icon: const Icon(Icons.refresh),
                                        label: const Text('Try again'),
                                        onPressed: () => setState(() => _showHelp = false),
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
    );
  }
}
