import 'package:cloud_firestore/cloud_firestore.dart';

/// Manually count items and update dashboard_stats from the client
/// Use this to bypass any Cloud Function issues
Future<Map<String, int>> manuallyFixDashboardStats() async {
  final db = FirebaseFirestore.instance;
  
  print('Starting manual dashboard stats fix...');
  
  // Get ALL items first to see what we have
  final snapshot = await db.collection('items').get();
  
  print('Found ${snapshot.docs.length} total items');
  
  // Check archived status
  int archivedCount = 0;
  int notArchivedCount = 0;
  int missingArchivedField = 0;
  
  for (final doc in snapshot.docs) {
    final data = doc.data();
    final archived = data['archived'];
    if (archived == true) {
      archivedCount++;
    } else if (archived == false) {
      notArchivedCount++;
    } else {
      missingArchivedField++;
      print('Item ${doc.id} has archived=${archived}');
    }
  }
  
  print('Archived: $archivedCount, Not archived: $notArchivedCount, Missing/null: $missingArchivedField');
  
  int lowCount = 0;
  int expiringCount = 0;
  int staleCount = 0;
  int expiredCount = 0;
  
  // Now count items with flags (only where archived != true)
  for (final doc in snapshot.docs) {
    final data = doc.data();
    final id = doc.id;
    final archived = data['archived'];
    
    // Skip if archived is explicitly true
    if (archived == true) continue;
    
    if (data['flagLow'] == true) {
      lowCount++;
      print('$id has flagLow');
    }
    if (data['flagExpiringSoon'] == true) {
      expiringCount++;
      print('$id has flagExpiringSoon');
    }
    if (data['flagStale'] == true) {
      staleCount++;
      print('$id has flagStale');
    }
    if (data['flagExpired'] == true) {
      expiredCount++;
      print('$id has flagExpired');
    }
  }
  
  final counts = {
    'low': lowCount,
    'expiring': expiringCount,
    'stale': staleCount,
    'expired': expiredCount,
  };
  
  print('Counts: $counts');
  
  // Update dashboard_stats document
  await db.collection('meta').doc('dashboard_stats').set({
    ...counts,
    'updatedAt': FieldValue.serverTimestamp(),
    'lastRecalculatedAt': FieldValue.serverTimestamp(),
    'manuallyFixed': true,
  }, SetOptions(merge: true));
  
  print('Dashboard stats updated successfully!');
  
  return counts;
}
