import 'package:flutter/material.dart';

Future<bool> confirmAdminPin(BuildContext context) async {
  final c = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Admin PIN'),
      content: TextField(
        controller: c,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'Enter PIN'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, c.text == '1234'), child: const Text('Unlock')),
      ],
    ),
  );
  return ok ?? false;
}
