// utils/audit.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'operator_store.dart'; // wherever OperatorStore lives

class Audit {
  static Map<String, dynamic> created() {
    final user = FirebaseAuth.instance.currentUser; // accessed lazily
    final op = OperatorStore.name.value;
    final now = FieldValue.serverTimestamp();

    return {
      if (op != null && op.trim().isNotEmpty) 'operatorName': op.trim(),
      'createdBy': user?.uid,
      'createdAt': now,
      'updatedAt': now,
    };
  }

  static Map<String, dynamic> updated() {
    final user = FirebaseAuth.instance.currentUser;
    return {
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': user?.uid,
    };
  }
}
