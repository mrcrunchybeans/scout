export 'budget_page_mobile.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class BudgetPage extends StatelessWidget {
  const BudgetPage({super.key});

  @override
  Widget build(BuildContext context) {
    const budgetUrl = 'https://scout-budget.littleempathy.com';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Team Budget'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const BudgetHelpPage()),
              );
            },
            tooltip: 'Help',
          ),
        ],
      ),
      body: WebView(
        initialUrl: budgetUrl,
        javascriptMode: JavascriptMode.unrestricted,
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
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'How to Use Actual Budget',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'Actual Budget is a collaborative tool for managing team finances, tracking spending, and planning budgets.\n',
              style: TextStyle(fontSize: 16),
            ),
            const Text(
              'To get started:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('- Click the "Open Actual Budget" button to launch the app.'),
            const Text('- Log in or create an account if prompted.'),
            const Text('- Follow your team workflow for entering transactions, reviewing budgets, and collaborating.'),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () async {
                const url = 'https://actualbudget.org/docs/';
                final uri = Uri.parse(url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: const Text(
                'See the official Actual Budget documentation for more help.',
                style: TextStyle(color: Colors.blue, decoration: TextDecoration.underline),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
