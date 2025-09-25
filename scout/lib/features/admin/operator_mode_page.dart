import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class OperatorModePage extends StatefulWidget {
  const OperatorModePage({super.key});

  @override
  State<OperatorModePage> createState() => _OperatorModePageState();
}

class _OperatorModePageState extends State<OperatorModePage> {
  String _operatorMode = 'prompt'; // Default to current behavior
  String _defaultOperatorName = '';
  List<String> _operatorList = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final db = FirebaseFirestore.instance;
      final doc = await db.collection('config').doc('app').get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _operatorMode = data['operatorMode'] as String? ?? 'prompt';
          _defaultOperatorName = data['defaultOperatorName'] as String? ?? '';
          _operatorList = List<String>.from(data['operatorList'] as List<dynamic>? ?? []);
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load config: $e')),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveConfig() async {
    setState(() => _saving = true);
    try {
      final db = FirebaseFirestore.instance;
      await db.collection('config').doc('app').set({
        'operatorMode': _operatorMode,
        'defaultOperatorName': _defaultOperatorName,
        'operatorList': _operatorList,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Operator mode configuration saved')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save config: $e')),
      );
    } finally {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Operator Mode')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Operator Mode'),
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
              onPressed: _saveConfig,
              child: const Text('Save'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'How should operator names be collected?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Column(
            children: [
              RadioMenuButton<String>(
                value: 'prompt',
                groupValue: _operatorMode,
                onChanged: (value) => setState(() => _operatorMode = value!),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Always prompt'),
                    Text('Ask for operator name each time the app is opened', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              RadioMenuButton<String>(
                value: 'default',
                groupValue: _operatorMode,
                onChanged: (value) => setState(() => _operatorMode = value!),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Use default name'),
                    Text('Use a predefined operator name for all operations', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              RadioMenuButton<String>(
                value: 'list',
                groupValue: _operatorMode,
                onChanged: (value) => setState(() => _operatorMode = value!),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Select from list'),
                    Text('Choose from a predefined list of operators', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              RadioMenuButton<String>(
                value: 'disabled',
                groupValue: _operatorMode,
                onChanged: (value) => setState(() => _operatorMode = value!),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Disabled'),
                    Text('Don\'t track operator names', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_operatorMode == 'default') ...[
            const Text(
              'Default Operator Name',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Default operator name',
                hintText: 'e.g. SCOUT System',
              ),
              controller: TextEditingController(text: _defaultOperatorName),
              onChanged: (value) => _defaultOperatorName = value,
            ),
          ],
          if (_operatorMode == 'list') ...[
            const Text(
              'Operator List',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ..._operatorList.map((operator) => ListTile(
              title: Text(operator),
              trailing: IconButton(
                icon: const Icon(Icons.delete),
                onPressed: () => setState(() => _operatorList.remove(operator)),
              ),
            )),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Add operator'),
              onTap: _addOperator,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _addOperator() async {
    final controller = TextEditingController();
    final operator = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Operator'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Operator name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (operator != null && operator.isNotEmpty && !_operatorList.contains(operator)) {
      setState(() => _operatorList.add(operator));
    }
  }
}