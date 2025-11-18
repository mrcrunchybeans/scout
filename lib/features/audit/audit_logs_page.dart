// lib/features/audit/audit_logs_page.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AuditLogsPage extends StatelessWidget {
  const AuditLogsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit Logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () => _showFilterDialog(context),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('audit_logs')
            .orderBy('createdAt', descending: true)
            .limit(100)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(
              child: Text('No audit logs found'),
            );
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;

              return _AuditLogTile(
                type: data['type'] as String? ?? 'Unknown',
                operatorName: data['operatorName'] as String?,
                createdAt: data['createdAt'] as Timestamp?,
                details: data['data'] as Map<String, dynamic>? ?? {},
              );
            },
          );
        },
      ),
    );
  }

  void _showFilterDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Theme(
        data: Theme.of(context),
        child: AlertDialog(
          title: const Text('Filter Options'),
          content: const Text('Filtering options will be implemented here.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuditLogTile extends StatelessWidget {
  final String type;
  final String? operatorName;
  final Timestamp? createdAt;
  final Map<String, dynamic> details;

  const _AuditLogTile({
    required this.type,
    required this.operatorName,
    required this.createdAt,
    required this.details,
  });

  @override
  Widget build(BuildContext context) {
    final dateTime = createdAt?.toDate();
    final formattedDate = dateTime != null
        ? DateFormat('MMM dd, yyyy • HH:mm').format(dateTime)
        : 'Unknown time';

    final icon = _getIconForType(type);
    final color = _getColorForType(type);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.2),
          child: Icon(icon, color: color),
        ),
        title: Text(
          _formatType(type),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'By: ${operatorName ?? 'Unknown'} • $formattedDate',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              _formatDetails(details),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        onTap: () => _showDetailsDialog(context),
      ),
    );
  }

  IconData _getIconForType(String type) {
    if (type.startsWith('item.')) return Icons.inventory;
    if (type.startsWith('lot.')) return Icons.warehouse;
    if (type.startsWith('session.')) return Icons.shopping_cart;
    if (type.startsWith('user.')) return Icons.person;
    return Icons.history;
  }

  Color _getColorForType(String type) {
    if (type.contains('create')) return Colors.green;
    if (type.contains('delete')) return Colors.red;
    if (type.contains('update') || type.contains('edit')) return Colors.blue;
    if (type.contains('archive')) return Colors.orange;
    return Colors.grey;
  }

  String _formatType(String type) {
    return type.split('.').map((part) {
      // Capitalize first letter
      if (part.isEmpty) return part;
      return part[0].toUpperCase() + part.substring(1);
    }).join(' • ');
  }

  String _formatDetails(Map<String, dynamic> details) {
    final parts = <String>[];

    // Add key information based on the type
    if (details.containsKey('itemId')) {
      parts.add('Item: ${details['itemId'].toString().substring(0, 8)}...');
    }
    if (details.containsKey('lotId')) {
      parts.add('Lot: ${details['lotId'].toString().substring(0, 8)}...');
    }
    if (details.containsKey('qtyUsed') || details.containsKey('qtyRemaining')) {
      final qty = details['qtyUsed'] ?? details['qtyRemaining'];
      if (qty != null) parts.add('Qty: $qty');
    }
    if (details.containsKey('lotCode')) {
      parts.add('Code: ${details['lotCode']}');
    }

    return parts.isNotEmpty ? parts.join(' • ') : 'No details';
  }

  void _showDetailsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Theme(
        data: Theme.of(context),
        child: AlertDialog(
          title: Text(_formatType(type)),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Operator: ${operatorName ?? 'Unknown'}'),
                Text('Time: ${createdAt?.toDate().toString() ?? 'Unknown'}'),
                const Divider(),
                const Text('Details:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...details.entries.map((entry) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('${entry.key}: ${entry.value}'),
                )),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
