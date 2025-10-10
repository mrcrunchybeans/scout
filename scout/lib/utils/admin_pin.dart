import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Developer password - hardcoded and cannot be changed by users
const String _developerPassword = 'scoutdev2025';

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
              final input = c.text;
              final prefs = await SharedPreferences.getInstance();

              // Accept either current admin PIN or developer password for convenience
              if (input == pin || input == _developerPassword) {
                await prefs.setBool('admin_unlocked', true);
                // If developer password was used, also mark developer unlocked
                if (input == _developerPassword) {
                  await prefs.setBool('developer_unlocked', true);
                }
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

Future<bool> confirmDeveloperPassword(BuildContext context) async {
  final c = TextEditingController();

  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => Theme(
      data: Theme.of(context),
      child: AlertDialog(
        title: const Text('Developer Access'),
        content: TextField(
          controller: c,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Enter Developer Password'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (c.text == _developerPassword) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('developer_unlocked', true);
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop(true);
              } else {
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop(false);
              }
            },
            child: const Text('Access'),
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

  static Future<bool> ensureDeveloper(BuildContext context) async {
    // First ensure admin access
    if (!await ensure(context)) return false;
    // Then require developer password
    if (!context.mounted) return false;
    return await confirmDeveloperPassword(context);
  }

  static Future<bool> isAuthed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('admin_unlocked') == true;
  }

  static Future<bool> isDeveloperAuthed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('developer_unlocked') == true;
  }

  static Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('admin_unlocked', false);
    await prefs.setBool('developer_unlocked', false);
  }
}
