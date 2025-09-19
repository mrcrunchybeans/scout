import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<bool> confirmAdminPin(BuildContext context) async {
  final c = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => Theme(
      data: Theme.of(context),
      child: AlertDialog(
        title: const Text('Admin PIN'),
        content: TextField(
          controller: c,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Enter PIN'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (c.text == '2468') {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('admin_unlocked', true);
                if (context.mounted) Navigator.pop(context, true);
              } else {
                if (context.mounted) Navigator.pop(context, false);
              }
            },
            child: const Text('Unlock'),
          ),
        ],
      ),
    ),
  );
  return ok ?? false;
}
