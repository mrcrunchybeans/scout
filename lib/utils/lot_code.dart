import 'package:cloud_firestore/cloud_firestore.dart';

/// Returns the standard month prefix (YYMM) for the provided [referenceDate] or now.
String lotCodeMonthPrefix({DateTime? referenceDate}) {
  final now = referenceDate ?? DateTime.now();
  final yy = (now.year % 100).toString().padLeft(2, '0');
  final mm = now.month.toString().padLeft(2, '0');
  return '$yy$mm';
}

/// Returns a preview lot code for UI placeholders (defaults to `YYMM-001`).
String previewLotCode({DateTime? referenceDate}) {
  return '${lotCodeMonthPrefix(referenceDate: referenceDate)}-001';
}

/// Generates the next lot code for the given [itemId] by inspecting existing lots.
///
/// Lot codes follow the pattern `YYMM-XXX`, where `XXX` is a zero-padded sequence
/// scoped per item per month.
Future<String> generateNextLotCode({
  required String itemId,
  FirebaseFirestore? firestore,
  DateTime? referenceDate,
}) async {
  final db = firestore ?? FirebaseFirestore.instance;
  final monthPrefix = lotCodeMonthPrefix(referenceDate: referenceDate);

  final lotsQuery = await db
      .collection('items')
      .doc(itemId)
      .collection('lots')
      .where('lotCode', isGreaterThanOrEqualTo: monthPrefix)
      .where('lotCode', isLessThan: '${monthPrefix}Z')
      .orderBy('lotCode', descending: true)
      .limit(1)
      .get();

  var nextNumber = 1;
  if (lotsQuery.docs.isNotEmpty) {
    final data = lotsQuery.docs.first.data();
    final lastLotCode = data['lotCode'] as String?;
    if (lastLotCode != null && lastLotCode.startsWith(monthPrefix)) {
      final suffix = lastLotCode.replaceFirst(monthPrefix, '').replaceAll('-', '');
      final numericPart = suffix.replaceAll(RegExp(r'[^0-9]'), '');
      final currentNumber = int.tryParse(numericPart) ?? 0;
      nextNumber = currentNumber + 1;
    }
  }

  final formattedNumber = nextNumber.toString().padLeft(3, '0');
  return '$monthPrefix-$formattedNumber';
}
