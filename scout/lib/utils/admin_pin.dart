import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class _AdminConfig {
  final String pin;
  final int ttlHours;
  final DateTime fetchedAt;

  _AdminConfig(this.pin, this.ttlHours, this.fetchedAt);

  bool get isExpired {
    final expiry = fetchedAt.add(Duration(hours: ttlHours));
    return DateTime.now().isAfter(expiry);
  }
}

Future<String> _fetchAdminPin() async {
  try {
    final doc = await FirebaseFirestore.instance.collection('config').doc('app').get();
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      final pin = data['adminPin'] as String?;
      final ttlHours = (data['pinTtlHours'] as num?)?.toInt() ?? 12;

      if (pin != null && pin.isNotEmpty) {
        // Cache the config
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('admin_pin', pin);
        await prefs.setInt('admin_pin_ttl_hours', ttlHours);
        await prefs.setInt('admin_pin_fetched_at', DateTime.now().millisecondsSinceEpoch);

        return pin;
      }
    }
  } catch (e) {
    // Fall back to cache or default
  }

  // Try cache first
  final prefs = await SharedPreferences.getInstance();
  final cachedPin = prefs.getString('admin_pin');
  final cachedTtlHours = prefs.getInt('admin_pin_ttl_hours') ?? 12;
  final cachedFetchedAtMs = prefs.getInt('admin_pin_fetched_at');

  if (cachedPin != null && cachedFetchedAtMs != null) {
    final cachedFetchedAt = DateTime.fromMillisecondsSinceEpoch(cachedFetchedAtMs);
    final config = _AdminConfig(cachedPin, cachedTtlHours, cachedFetchedAt);

    if (!config.isExpired) {
      return cachedPin;
    }
  }

  // Default fallback
  return '2468';
}

Future<bool> confirmAdminPin(BuildContext context) async {
  final c = TextEditingController();

  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => Theme(
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
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final pin = await _fetchAdminPin();
              if (c.text == pin) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('admin_unlocked', true);
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop(true);
              } else {
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop(false);
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

class AdminPin {
  static Future<bool> ensure(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('admin_unlocked') == true) return true;
    if (!context.mounted) return false;
    return await confirmAdminPin(context);
  }

  static Future<bool> isAuthed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('admin_unlocked') == true;
  }

  static Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('admin_unlocked', false);
  }
}
