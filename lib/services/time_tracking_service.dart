import 'package:cloud_firestore/cloud_firestore.dart';

class TimeTrackingService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Future<TimeTrackingConfig> getConfig() async {
    try {
      final doc = await _db.collection('config').doc('timeTracking').get();
      if (doc.exists) {
        final data = doc.data()!;
        return TimeTrackingConfig(
          enabled: data['enabled'] as bool? ?? false,
          url: data['url'] as String? ?? '',
        );
      }
      return const TimeTrackingConfig(enabled: false, url: '');
    } catch (e) {
      return const TimeTrackingConfig(enabled: false, url: '');
    }
  }
}

class TimeTrackingConfig {
  final bool enabled;
  final String url;

  const TimeTrackingConfig({
    required this.enabled,
    required this.url,
  });

  bool get isValid => enabled && url.trim().isNotEmpty;
}