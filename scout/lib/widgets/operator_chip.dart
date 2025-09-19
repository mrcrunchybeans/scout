// lib/widgets/operator_chip.dart
import 'package:flutter/material.dart';
import 'package:scout/main.dart' as main;

class OperatorChip extends StatelessWidget {
  const OperatorChip({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<String?>(
      valueListenable: main.OperatorStore.name,
      builder: (context, name, _) {
        final label = name?.isNotEmpty == true ? name! : 'Set operator';
        return InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () async {
            final controller = TextEditingController(text: name ?? '');
            final picked = await showDialog<String?>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Who’s using SCOUT?'),
                content: TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Your name',
                    hintText: 'e.g. Mephibosheth',
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel')),
                  if (name != null && name.isNotEmpty)
                    TextButton(
                      onPressed: () => Navigator.pop(context, ''),
                      child: const Text('Clear'),
                    ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, controller.text.trim()),
                    child: const Text('Save'),
                  ),
                ],
              ),
            );
            if (picked == null) return;
            await main.OperatorStore.set(picked.isEmpty ? null : picked);
            if (context.mounted && picked.isNotEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Hello, $picked')),
              );
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: cs.surfaceContainerHighest,
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.badge, size: 18),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(color: cs.onSurface)),
              ],
            ),
          ),
        );
      },
    );
  }
}
