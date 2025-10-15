class CartLine {
  final String itemId;
  final String itemName;
  final String baseUnit;
  final String? lotId;        // optional, if using lots
  final String? lotCode;      // the human-readable lot code (e.g., "2509-001")
  final num initialQty;
  final num? endQty;          // null until closing

  CartLine({
    required this.itemId,
    required this.itemName,
    required this.baseUnit,
    this.lotId,
    this.lotCode,
    required this.initialQty,
    this.endQty,
  });

  CartLine copyWith({
    String? itemId,
    String? itemName,
    String? baseUnit,
    String? lotId,
    String? lotCode,
    num? initialQty,
    num? endQty,
  }) {
    return CartLine(
      itemId: itemId ?? this.itemId,
      itemName: itemName ?? this.itemName,
      baseUnit: baseUnit ?? this.baseUnit,
      lotId: lotId ?? this.lotId,
      lotCode: lotCode ?? this.lotCode,
      initialQty: initialQty ?? this.initialQty,
      endQty: endQty ?? this.endQty,
    );
  }

  num get usedQty => (endQty == null) ? 0 : (initialQty - (endQty ?? 0)).clamp(0, double.infinity);

  Map<String, dynamic> toMap() => {
    'itemId': itemId,
    'itemName': itemName,
    'baseUnit': baseUnit,
    'lotId': lotId,
    'lotCode': lotCode,
    'initialQty': initialQty,
    'endQty': endQty,
  };

  static CartLine fromMap(Map<String, dynamic> m) => CartLine(
    itemId: m['itemId'] as String,
    itemName: (m['itemName'] ?? 'Unnamed') as String,
    baseUnit: (m['baseUnit'] ?? 'each') as String,
    lotId: m['lotId'] as String?,
    lotCode: m['lotCode'] as String?,
    initialQty: (m['initialQty'] ?? 0) as num,
    endQty: m['endQty'] as num?,
  );
}
