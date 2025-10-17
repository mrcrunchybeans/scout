import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// Debug page to inspect dashboard_stats document and item flags
class DebugDashboardStatsPage extends StatelessWidget {
  const DebugDashboardStatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Dashboard Stats'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Dashboard Stats Document
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Dashboard Stats Document',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    StreamBuilder<DocumentSnapshot>(
                      stream: db.collection('meta').doc('dashboard_stats').snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Text('Error: ${snapshot.error}');
                        }
                        
                        if (!snapshot.hasData) {
                          return const CircularProgressIndicator();
                        }
                        
                        final doc = snapshot.data!;
                        if (!doc.exists) {
                          return const Text(
                            'Document does not exist!',
                            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                          );
                        }
                        
                        final data = doc.data() as Map<String, dynamic>?;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Exists: ${doc.exists}'),
                            const SizedBox(height: 8),
                            Text('Raw Data: $data'),
                            const SizedBox(height: 8),
                            if (data != null) ...[
                              Text('low: ${data['low']}'),
                              Text('expiring: ${data['expiring']}'),
                              Text('stale: ${data['stale']}'),
                              Text('expired: ${data['expired']}'),
                              Text('updatedAt: ${data['updatedAt']}'),
                              Text('lastRecalculatedAt: ${data['lastRecalculatedAt']}'),
                            ],
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Items with Flags
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Items with Flags (not archived)',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    StreamBuilder<QuerySnapshot>(
                      stream: db.collection('items')
                        .where('archived', isEqualTo: false)
                        .limit(20)
                        .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Text('Error: ${snapshot.error}');
                        }
                        
                        if (!snapshot.hasData) {
                          return const CircularProgressIndicator();
                        }
                        
                        final items = snapshot.data!.docs;
                        
                        int lowCount = 0;
                        int expiringCount = 0;
                        int staleCount = 0;
                        int expiredCount = 0;
                        
                        for (final doc in items) {
                          final data = doc.data() as Map<String, dynamic>;
                          if (data['flagLow'] == true) lowCount++;
                          if (data['flagExpiringSoon'] == true) expiringCount++;
                          if (data['flagStale'] == true) staleCount++;
                          if (data['flagExpired'] == true) expiredCount++;
                        }
                        
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Total items (not archived, first 20): ${items.length}'),
                            Text('Items with flagLow: $lowCount'),
                            Text('Items with flagExpiringSoon: $expiringCount'),
                            Text('Items with flagStale: $staleCount'),
                            Text('Items with flagExpired: $expiredCount'),
                            const SizedBox(height: 16),
                            const Text('Sample Items:', style: TextStyle(fontWeight: FontWeight.bold)),
                            ...items.take(5).map((doc) {
                              final data = doc.data() as Map<String, dynamic>;
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${doc.id}: ${data['name'] ?? 'Unnamed'}'),
                                    Text('  flagLow: ${data['flagLow']}'),
                                    Text('  flagExpiringSoon: ${data['flagExpiringSoon']}'),
                                    Text('  flagStale: ${data['flagStale']}'),
                                    Text('  flagExpired: ${data['flagExpired']}'),
                                    Text('  archived: ${data['archived']}'),
                                    const Divider(),
                                  ],
                                ),
                              );
                            }).toList(),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Action Buttons
            ElevatedButton(
              onPressed: () async {
                try {
                  final callable = FirebaseFunctions.instance.httpsCallable('recalcDashboardStatsManual');
                  await callable.call();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Dashboard stats recalculated successfully!')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              },
              child: const Text('Recalculate Dashboard Stats'),
            ),
          ],
        ),
      ),
    );
  }
}
