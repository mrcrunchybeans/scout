import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:scout/utils/audit.dart';

class TimeTrackingSettingsPage extends StatefulWidget {
  const TimeTrackingSettingsPage({super.key});

  @override
  State<TimeTrackingSettingsPage> createState() => _TimeTrackingSettingsPageState();
}

class _TimeTrackingSettingsPageState extends State<TimeTrackingSettingsPage> {
  final _db = FirebaseFirestore.instance;
  final _urlController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final doc = await _db.collection('config').doc('timeTracking').get();
      if (!mounted) return;
      
      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _enabled = data['enabled'] as bool? ?? false;
          _urlController.text = data['url'] as String? ?? '';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading settings: $e')),
        );
      }
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _busy = true);
    try {
      final data = {
        'enabled': _enabled,
        'url': _urlController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await _db.collection('config').doc('timeTracking').set(
        Audit.updateOnly(data),
        SetOptions(merge: true),
      );

      await Audit.log('config.timeTracking.update', {
        'enabled': _enabled,
        'hasUrl': _urlController.text.trim().isNotEmpty,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Time tracking settings saved')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving settings: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Time Tracking Settings'),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )),
            )
          else
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saveSettings,
              tooltip: 'Save settings',
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Time Tracking Integration',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Configure external time tracking system integration for staff care sessions.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('Enable Time Tracking'),
                      subtitle: const Text('Show time tracking button in session summaries'),
                      value: _enabled,
                      onChanged: (value) => setState(() => _enabled = value),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _urlController,
                      enabled: _enabled,
                      decoration: const InputDecoration(
                        labelText: 'Time Tracking URL',
                        helperText: 'URL to redirect users for time tracking (changes year to year)',
                        prefixIcon: Icon(Icons.link),
                        border: OutlineInputBorder(),
                      ),
                      validator: _enabled ? (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'URL is required when time tracking is enabled';
                        }
                        final uri = Uri.tryParse(value.trim());
                        if (uri == null || (!uri.hasScheme || (!uri.scheme.startsWith('http')))) {
                          return 'Please enter a valid URL (starting with http:// or https://)';
                        }
                        return null;
                      } : null,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),
                    if (_enabled && _urlController.text.trim().isNotEmpty)
                      Card(
                        color: Theme.of(context).colorScheme.surfaceVariant,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    size: 16,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Preview',
                                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Users will be redirected to:',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _urlController.text.trim(),
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontFamily: 'monospace',
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.lightbulb_outline,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Usage Information',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '• When enabled, a "Record Time" button will appear in cart session summaries\n'
                      '• Users can click this button to navigate to your time tracking system\n'
                      '• This is useful for recording staff care time spent on interventions\n'
                      '• The URL can be updated annually or as your system changes',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}