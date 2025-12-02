// ignore: avoid_web_libraries_in_flutter
import 'dart:ui_web' as ui;
import 'dart:html' as html;
import 'package:flutter/material.dart';

const String _budgetUrl = 'https://budget.littleempathy.com';

bool _iframeRegistered = false;

// Register the iframe view factory for web
void _registerBudgetIframe() {
  if (_iframeRegistered) return;
  _iframeRegistered = true;
  
  ui.platformViewRegistry.registerViewFactory(
    'budget-iframe',
    (int viewId) {
      final iframe = html.IFrameElement()
        ..src = _budgetUrl
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..setAttribute('allow', 'fullscreen; picture-in-picture; clipboard-write');
      return iframe;
    },
  );
}

class BudgetPage extends StatefulWidget {
  const BudgetPage();

  @override
  State<BudgetPage> createState() => _BudgetPageState();
}

class _BudgetPageState extends State<BudgetPage> {
  @override
  void initState() {
    super.initState();
    _registerBudgetIframe();
  }

  @override
  Widget build(BuildContext context) {
    // Auto-open budget in new window
    WidgetsBinding.instance.addPostFrameCallback((_) {
      html.window.open(_budgetUrl, 'budget', 'width=1400,height=900,resizable=yes,scrollbars=yes,location=yes');
      Navigator.of(context).pop();
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Team Budget'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              const Text('Opening Budget in new window...'),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Password: spiritualcare',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade900,
                          ),
                        ),
                        Text(
                          'Use this to unlock the budget file',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BudgetHelpPage extends StatelessWidget {
  const BudgetHelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Budget Help'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Team Budget Help',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          const Text(
            'The Team Budget tool helps manage spending and allocations for spiritual care resources and interventions.',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_outline, color: Colors.blue.shade700, size: 32),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Budget Password',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'spiritualcare',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Use this password to unlock the budget file',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Official Documentation',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.open_in_new),
            label: const Text('Actual Budget Documentation'),
            onPressed: () {
              html.window.open('https://actualbudget.org/docs/', 'budget_docs');
            },
          ),
        ],
      ),
    );
  }
}
