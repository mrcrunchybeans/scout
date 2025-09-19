import 'package:flutter/material.dart';

import 'lookups_crud_page.dart';

class AdminPage extends StatelessWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin / Config')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Configuration', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.badge),
            title: const Text('Operator mode'),
            subtitle: const Text('Choose how operator names are collected & cached'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const OperatorModePage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.lock),
            title: const Text('Admin PIN'),
            subtitle: const Text('Change the PIN (move to Firestore later)'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AdminPinPage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.storage),
            title: const Text('Lookups (Departments, Grants, Locations)'),
            subtitle: const Text('Manage dropdown data'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const LookupsCrudPage(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// Placeholder for Operator Mode config
class OperatorModePage extends StatelessWidget {
  const OperatorModePage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Operator Mode')),
      body: const Center(child: Text('Operator mode configuration coming soon.')),
    );
  }
}

// Placeholder for Admin PIN config
class AdminPinPage extends StatelessWidget {
  const AdminPinPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin PIN')),
      body: const Center(child: Text('Admin PIN configuration coming soon.')),
    );
  }
}

