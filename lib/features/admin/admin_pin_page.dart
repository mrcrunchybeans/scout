import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdminPinPage extends StatefulWidget {
  const AdminPinPage({super.key});

  @override
  State<AdminPinPage> createState() => _AdminPinPageState();
}

class _AdminPinPageState extends State<AdminPinPage> {
  final _currentPinController = TextEditingController();
  final _newPinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentPin();
  }

  @override
  void dispose() {
    _currentPinController.dispose();
    _newPinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentPin() async {
    // Just load to ensure we can access the config
    try {
      final db = FirebaseFirestore.instance;
      await db.collection('config').doc('app').get();
      // We don't need to store the PIN, we'll fetch it when validating
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load PIN configuration: $e')),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _changePin() async {
    final currentPin = _currentPinController.text.trim();
    final newPin = _newPinController.text.trim();
    final confirmPin = _confirmPinController.text.trim();

    // Validate current PIN by fetching from Firestore directly
    String actualCurrentPin = '2468'; // fallback
    try {
      final db = FirebaseFirestore.instance;
      final doc = await db.collection('config').doc('app').get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        actualCurrentPin = data['adminPin'] as String? ?? '2468';
      }
    } catch (e) {
      // If we can't fetch, show error
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to verify current PIN: $e')),
      );
      return;
    }

    if (currentPin != actualCurrentPin) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Current PIN is incorrect')),
      );
      return;
    }

    // Validate new PIN
    if (newPin.length < 4) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New PIN must be at least 4 characters')),
      );
      return;
    }

    if (newPin != confirmPin) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New PIN and confirmation do not match')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final db = FirebaseFirestore.instance;
      await db.collection('config').doc('app').set({
        'adminPin': newPin,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Clear the cache so the new PIN takes effect
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('admin_pin');
      await prefs.remove('admin_pin_ttl_hours');
      await prefs.remove('admin_pin_fetched_at');

      setState(() {
        _currentPinController.clear();
        _newPinController.clear();
        _confirmPinController.clear();
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Admin PIN changed successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to change PIN: $e')),
      );
    } finally {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin PIN')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin PIN'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _changePin,
              child: const Text('Change PIN'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Change Admin PIN',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _currentPinController,
            decoration: const InputDecoration(
              labelText: 'Current PIN',
              hintText: 'Enter current admin PIN',
            ),
            obscureText: true,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _newPinController,
            decoration: const InputDecoration(
              labelText: 'New PIN',
              hintText: 'Enter new admin PIN (at least 4 characters)',
            ),
            obscureText: true,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _confirmPinController,
            decoration: const InputDecoration(
              labelText: 'Confirm New PIN',
              hintText: 'Re-enter new admin PIN',
            ),
            obscureText: true,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info, color: Colors.blue),
                    SizedBox(width: 8),
                    Text(
                      'Security Note',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  'Changing the admin PIN will require all users to enter the new PIN the next time they access admin features. The PIN is stored securely in Firestore.',
                  style: TextStyle(color: Colors.blue, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}