import 'package:flutter/material.dart';

typedef AdminBodyBuilder = Widget Function(BuildContext context);

class AdminGate extends StatelessWidget {
  final String title;
  final String pin; // temporary local PIN
  final AdminBodyBuilder builder;
  const AdminGate({super.key, required this.title, required this.pin, required this.builder});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: ElevatedButton(
          child: const Text('Enter Admin PIN'),
          onPressed: () async {
            final ctx = context;
            final controller = TextEditingController();
            final ok = await showDialog<bool>(
              context: ctx,
              builder: (dCtx) => AlertDialog(
                title: const Text('Admin PIN'),
                content: TextField(
                  controller: controller,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: 'Enter PIN'),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancel')),
                  TextButton(onPressed: () => Navigator.pop(dCtx, controller.text == pin), child: const Text('OK')),
                ],
              ),
            );
            if (ok == true && ctx.mounted) {
              Navigator.of(ctx).pushReplacement(MaterialPageRoute(builder: (c) => builder(c)));
            }
          },
        ),
      ),
    );
  }
}
